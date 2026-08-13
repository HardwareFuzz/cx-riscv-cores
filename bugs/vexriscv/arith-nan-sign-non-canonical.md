# VexRiscv: 算术指令（fdiv/fmul/fadd/fsqrt/fminmax）NaN 结果符号非 canonical（上游 bug）

> Status: **confirmed spec violation（上游 VexRiscv 原始 bug）— 已修复**（fork `cx-build`
> cb7a0576「canonical NaN must carry positive sign」，2026-08-12），Verilator 重编后同 seed
> 20-case 重跑 0 写差异（`rerun_20_vex_fcvtfix_20260813`，fcvt 修复后残留差异不再复现）。
> 下方「修复（建议，fork 内）」原为建议稿，现由 cb7a0576 **逐条实施**，见「修复实施」。
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

## 修复实施（fork，cb7a0576，已发布）

fork 提交 `cb7a0576`（canxin121，2026-08-12）在**全部 5 个结果 NaN 强制分支**各加一行
`sign := False`，与本文件建议逐条对应。**未改 `setNanQuiet`**（接口层保持不动，符合建议）：

| 通路 | 建议条目 | cb7a0576 落点（FpuCore.scala） |
|---|---|---|
| fmin/fmax both-NaN | 5 | `when(minMaxSelectNanQuiet){ rfOutput.value.sign := False; … }`（L897） |
| fmul/fma | 2 | `when(forceNan){ output.sign := False; … }`（L1069） |
| fdiv | 1 | `when(forceNan){ output.value.sign := False; … }`（L1182） |
| fsqrt | 4 | `when(negative){…}` 与 `when(input.rs1.isNan){…}` 两分支各加（L1232/L1235） |
| fadd/fsub | 3 | `when(forceNan){ output.value.sign := False; … }`（L1607） |

diff 摘要（`git show cb7a0576`）：

```scala
when(minMaxSelectNanQuiet){
+  rfOutput.value.sign := False  // both-NaN fmin/fmax -> canonical NaN (positive sign)
   rfOutput.value.setNanQuiet
}
when(forceNan) {          // fmul/fma、fdiv、fadd/fsub 各一处
+  output.sign := False   // canonical NaN requires positive sign (spec norm:F_canonical_NaN)
   output.setNanQuiet
   ...
}
when(negative){           // fsqrt
+  output.value.sign := False
   output.value.setNanQuiet
   ...
}
when(input.rs1.isNan){    // fsqrt
+  output.value.sign := False
   output.value.setNanQuiet
   ...
}
```

后续 `dbf40ff3`（fsgnj*_d boxed 重建）只调整了 fsgnj 路径的符号/载荷处理，上述算术通路
（fdiv/fmul/fma/fadd/fsub/fsqrt/fminmax）的 `sign := False` 不受影响、全部保留。

## 修复验证（已实施，2026-08-12）

1. `./build.sh` 重建 vexriscv emulator（核对 emulator mtime/md5 已变）。
2. 同 seed 20-case 重跑（`rerun_20_vex_fcvtfix_20260813`，seed 823050000+i）：
   **20/20 exit=0，全部 `0 exception rounds, 0 write rounds`**；rerun10 case_01 的
   `fdiv.s` f13 写差异不再复现（fcvt 修复后该 case 其余差异亦消除）。
