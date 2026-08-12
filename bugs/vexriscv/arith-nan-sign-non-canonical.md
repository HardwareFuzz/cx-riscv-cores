# VexRiscv: 算术指令（fdiv/fmul/fadd/fsqrt/fminmax）NaN 结果符号非 canonical（上游 bug）

> Status: **confirmed spec violation（上游 VexRiscv 原始 bug）** — fork 尚未改、未重建。
> Dated 2026-08-12。由 HardwareFuzz riscv_fuzz_test diff-spike 矩阵复现（rerun10 rv32_vex case_01，
> root diff = `fdiv.s f13, f17, f13, rdn`）。
> 影响：vex-vs-spike 差分测试的算术指令寄存器写差异 —— **vex 真实缺陷**（违反 RISC-V spec 的
> canonical NaN 规范条文），非 fuzz 框架误报。
> 背景：先前对该 diff 的判定为「RISC-V 规定算术 NaN 载荷（含符号）implementation-defined，正负皆合法」。
> 用户提出质疑（「正负都可以真的符合 riscv 规范吗？」），经 RISC-V 规范原文（本地 upstream 检出
> 2026-07-27 + 已定稿 IMFDQC-Ratification 镜像）复核：**该判定不成立**。spec 对算术指令的结果 NaN
> 明确要求 canonical NaN（单精度 = 正号 `0x7fc00000`），payload/符号传播仅是「非标准扩展」。
> 归属：**上游原厂**（`git blame`：Dolu1990 2021-02-25 commit `de09ed3fc`，当前 fork 该处与上游一致），
> 非用户 fork 改动。

---

## 概述

RISC-V 规范（未特权 F/D 扩展「NaN Generation and Propagation」，规范条文）明确：

> **norm:canonical_NaN**："Except when otherwise stated, if the result of a floating-point
> operation is NaN, it is *the canonical NaN*."

> **norm:F_canonical_NaN**："For single-precision floating-point, the canonical NaN has a
> **positive sign** and all significand bits clear except the MSB, the quiet bit. In other
> words, for single-precision floating-point, the canonical NaN corresponds to the pattern
> `0x7fc00000`."

> **NOTE（同章）**："Implementers are free to provide a NaN payload propagation scheme as a
> **non-standard extension enabled by a non-standard operating mode**. However, the canonical
> NaN scheme described above **must always be supported and should be the default mode**."

即：**算术指令（fadd/fsub/fmul/fdiv/fsqrt/fmadd/fnmadd/fmsub/fnmsub）结果若是 NaN，必须是
canonical NaN**（单精度 = 正号 `0x7fc00000`，双精度 = 正号 `0x7ff8000000000000`）。「结果 NaN
的符号/载荷随操作数」在规范里**不是**默认允许行为，payload 传播只是被限定为「非标准 operating
mode 下的非标准扩展」，且 canonical 方案「必须始终支持、应为默认」。fmin/fmax 的「单 NaN → 返回
非 NaN 操作数」是 spec 里仅有的显式例外，不适用于 fdiv/fmul/fadd/fsqrt。

VexRiscv `FpuCore.scala` 全部算术通路在结果 NaN 时**保留操作数派生的符号**（`setNanQuiet`
只改 special/exponent/mantissa 的 quiet 位，不碰 sign），与规范冲突：

| 指令通路 | NaN 结果符号 | FpuCore.scala |
|---|---|---|
| fmul / fma（norm 区） | `rs1.sign ^ rs2.sign` | L1062 + L1070-1072 |
| fdiv | `rs1.sign ^ rs2.sign` | L1159 + L1182-1184 |
| fadd / fsub | `xySign`（较大幅值操作数的符号，平手取 rs2） | L1594 + L1604-1605 |
| fsqrt | `rs1.sign` | L1219 + L1231-1238 |
| fmin/fmax（both-NaN） | 被选中操作数符号（rs1/rs2） | L886/L894 + L899-901 |

对照：spike（softfloat `defaultNaNF32UI = 0x7FC00000`，`s_propagateNaNF32UI.c` 固定返回 default
NaN）与 rocket（hardfloat `RoundAnyRawFNToRecFN.scala:249` `signOut = Mux(isNaNOut, false.B,
io.in.sign)`，NaN 时强制正号）都输出正 canonical NaN —— 符合规范。故该 diff 是**真实架构差异，
违规方是 vex**。

## 复现（rerun10 rv32_vex case_01）

`fdiv.s f13, f17, f13, rdn`：

- `f17 = 0xffffffff16453a7b`（合法 NaN-box，f32 = `0x16453a7b` = SNaN，**sign=0**）
- `f13 = 0xffffffffff800001`（合法 NaN-box，f32 = `0xff800001` = SNaN，**sign=1**）

两核输入完全相同，均为负/正混合 SNaN，输入本身无误。

- **spike（符合 spec）**：`f13 = 0xffffffff7fc00000`（f32 `0x7fc00000` = 正 canonical QNaN；
  softfloat `propagateNaNF32UI` 固定返回 `defaultNaNF32UI`）。
- **vex（违反 spec）**：`f13 = 0xffffffffffc00000`（f32 `0xffc00000` = 负 QNaN；
  sign = `rs1.sign ^ rs2.sign` = 0^1 = 1）。

规范要求 fdiv 的 NaN 结果必须是 canonical（正 `0x7fc00000`），vex 输出负 `0xffc00000` 非 canonical。

## 根因

`src/main/scala/vexriscv/ip/fpu/FpuCore.scala`（上游 Dolu1990 2021-02-25，git blame `de09ed3fc`）。

每个算术通路都**先无条件赋操作数派生符号，再做 NaN 强制**，而 `setNanQuiet`
（`Interface.scala:60`：`special := True; exponent := NAN; exponent(canonical bit) := True;
mantissa.msb := True`）**不改 sign**，于是 NaN 结果保留了操作数符号：

```scala
// fdiv（div 区，L1158-1184）
output.value.setNormal
output.value.sign := input.rs1.sign ^ input.rs2.sign   // ← 无条件赋符号
...
val forceNan = input.rs1.isNan || input.rs2.isNan || infinitynan
...
when(forceNan) {
  output.value.setNanQuiet                              // ← 只改 exp/man，sign 保留 0^1=1
  output.NV setWhen(...)
}
// fmul/fma（norm 区 L1061-1072）同构：output.sign := rs1.sign^rs2.sign；forceNan→setNanQuiet
// fadd/fsub（add 区 L1594,1604-1605）：output.value.sign := xySign；forceNan→setNanQuiet
// fsqrt（sqrt 区 L1219,1231-1238）：output.value.sign := rs1.sign；NaN/negative→setNanQuiet
// fmin/fmax both-NaN（L899-901）：minMaxSelectNanQuiet→setNanQuiet，sign=选中操作数
```

## spec 对照（原文）

- `norm:canonical_NaN`："Except when otherwise stated, if the result of a floating-point
  operation is NaN, it is the canonical NaN."（算术 NaN 结果 = canonical，无「implementation-
  defined 符号/载荷」的余地）
- `norm:F_canonical_NaN`：单精度 canonical NaN = `0x7fc00000`，**正号**。
- 同章 NOTE：payload 传播 = 非标准扩展、须非标准 operating mode；canonical 方案 must always
  be supported / should be the default。
- `norm:fmin-s_fmax-s_both_nan_input` / `norm:fmin-s_fmax-s_one_nan_input`：fmin/fmax 的
  one-NaN → 非 NaN 操作数、both-NaN → canonical，是仅有的显式例外；fdiv 无例外。
- IEEE 754-2019 §6.3 对生成 NaN 的符号是 unspecified（这正是「implementation-defined」直觉的
  来源），但 **RISC-V 用规范条文显式覆盖**为「canonical = 正号」，故该直觉不适用于 RISC-V。

证据：本地 upstream 检出 `/tmp/riscv-vector-overlap-audit.XqhW81/riscv-isa-manual/
src/unpriv/f-st-ext.adoc` L134-178（commit 4757308，2026-07-27，remote =
github.com/riscv/riscv-isa-manual）；已定稿镜像
five-embeddev.github.io/riscv-docs-html/riscv-user-isa-manual/IMFDQC-Ratification-20190305/f.html
同文；glibc bug build/29501 亦引用同句（"the canonical NaN has a positive sign ... 0x7fc00000"）。

## 修复（建议，fork 内）

在每个结果 NaN 强制分支显式清符号位。**不要改 `setNanQuiet`**：它同时被用于「静音输入操作数」
（L344/349/353 等非结果场景），接口层不该动 sign。

1. **fdiv**（L1182-1184）：
   ```scala
   when(forceNan) {
     output.value.sign := False          // ← 新增：canonical NaN 必须正号
     output.value.setNanQuiet
     output.NV setWhen(...)
   }
   ```
2. **fmul/fma**（L1070-1072）：同样在 `when(forceNan)` 内加 `output.sign := False`。
3. **fadd/fsub**（L1604-1605）：在 `when(forceNan)` 内加 `output.value.sign := False`。
4. **fsqrt**（L1231-1238）：两个 NaN 分支（`negative`、`input.rs1.isNan`）内加
   `output.value.sign := False`。
5. **fmin/fmax both-NaN**（L899-901）：`when(minMaxSelectNanQuiet)` 内加
   `rfOutput.value.sign := False`（spec：both-NaN → canonical）。

## 修复验证（建议流程，仿 fsgnj 流程）

1. `./build.sh` 重建 vexriscv emulator（**注意：改 FpuCore.scala 后必须重编 Verilator 并核对
   emulator mtime/md5，二进制不会自动更新**）。
2. 单指令 A/B：`fdiv.s` SNaN×SNaN、单 SNaN、0/0、inf/inf 等 → vex 输出应与 spike 一致为正
   `0x7fc00000`。
3. 重放 rerun10 rv32_vex case_01 → fdiv 写差异消失。
4. 5-case 全新 diff 复查，确认无新增回归（注意 NaN 符号修复可能连带消除/改变既有级联差异）。
