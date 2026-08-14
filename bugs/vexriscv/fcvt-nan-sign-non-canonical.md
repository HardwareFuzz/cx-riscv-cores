# VexRiscv: FCVT (F32→F64) 的 NaN 结果符号非 canonical（上游 bug）

> 分类：**新 bug 新修复**（riscv_fuzz_test 未记录）

> Status: **confirmed spec violation（上游 VexRiscv 原始 bug）** — 已在 fork `cx-build` 分支修复
> （ae225728），Verilator 重编后同 seed 20-case 重跑 0 写差异。
> Dated 2026-08-13。由 HardwareFuzz riscv_fuzz_test diff-spike 矩阵复现（fresh_all_20_single_20260813
> rv32_vex case_16/case_20，root diff = `fcvt.d.s`）。
> 影响：vex-vs-spike 差分测试的 `fcvt.d.s` 寄存器写差异 —— **vex 真实缺陷**（违反 RISC-V spec 的
> canonical NaN 规范条文），非 fuzz 框架误报。
> 归属：**上游原厂**（`git blame`：Dolu1990 2021-02-11 commit `9a25a1287` 引入该分支；上游 master
> 该处与 fork 修复前一致）。

---

## 概述

RISC-V 规范（未特权 F/D 扩展「NaN Generation and Propagation」）要求转换指令产生 NaN 时输出
**canonical NaN**（正号，单精度 `0x7fc00000`、双精度 `0x7ff8000000000000`），与算术指令同：

> **norm:canonical_NaN**："Except when otherwise stated, if the result of a floating-point
> operation is NaN, it is *the canonical NaN*."
> **norm:F_canonical_NaN**："For single-precision floating-point, the canonical NaN has a
> **positive sign** and all significand bits clear except the MSB, the quiet bit … `0x7fc00000`."

VexRiscv `FpuCore.scala` 的 `FCVT_X_X`（F32→F64）分支用 `setNanQuiet` 处理 NaN 输入，但
`setNanQuiet` 只改 special/exponent/mantissa 的 quiet 位、**不碰 sign** —— 于是 fcvt.d.s 把
**输入 float NaN 的符号位原样带进双精度结果**，输出负号 `0xfff8000000000000` 而非规范的
`0x7ff8000000000000`。

对照：spike（softfloat `s_propagateNaNF32UI`/`defaultNaNF64UI` 固定返回正 default NaN）输出正
canonical NaN —— 符合规范。故该 diff 是**真实架构差异，违规方是 vex**。

## 复现（fresh_all_20_single_20260813 rv32_vex）

**case_16**（单指令复现）：
- 上文：`f13=0xffffffffffffffff`（NaN-box 位型，f32 = `0xffffffff` = 负 QNaN）
- spike：`fcvt.d.s f13, f13` → `f13=0x7ff8000000000000`（正 canonical NaN）
- vex：`fcvt.d.s f13, f13` → `f13=0xfff8000000000000`（**负** NaN，符号位 = 输入 float 的 bit31=1）

**case_20**（单指令复现）：
- `fcvt.d.s f20, f13`，f13=`0xffffffffffffffff` → spike `f20=0x7ff8000000000000` vs vex
  `f20=0xfff8000000000000`

两核输入完全相同，输入本身无误。差异只在**结果 NaN 的符号位**。

## 根因

`src/main/scala/vexriscv/ip/fpu/FpuCore.scala`（上游 Dolu1990 2021-02-11，git blame `9a25a1287`）。

```scala
if(p.withDouble) is(FpuOpcode.FCVT_X_X){
  rfOutput.format := ((input.format === FpuFormat.FLOAT) ? FpuFormat.DOUBLE | FpuFormat.FLOAT)
  when(input.rs1.isNan){
    rfOutput.value.setNanQuiet        // ← 只改 exp/man，sign 保留输入 float 的符号
  }
}
```

`setNanQuiet`（`Interface.scala:60`：`special := True; exponent := NAN; exponent(canonical bit) := True;
mantissa.msb := True`）不改 sign，所以 F32→F64 的 NaN 输入符号（bit31）被搬进结果的 bit63。

**注意**：前一个上游 bug 修复（cb7a0576「canonical NaN must carry positive sign」）覆盖了算术通路
fadd/fsub/fmul/fdiv/fma/fsqrt/fsgnj*/fminmax both-NaN 的强制 NaN 符号，**但漏掉了 FCVT_X_X 分支**。
本修复（ae225728）补上这一处。

## 修复（fork，ae225728）

```scala
when(input.rs1.isNan){
  rfOutput.value.sign := False  // canonical NaN requires positive sign (spec norm:F_canonical_NaN)
  rfOutput.value.setNanQuiet
}
```

## 修复验证

1. `./build.sh` 重建 vexriscv emulator（**改 FpuCore.scala 后必须重编 Verilator 并核对 emulator
   mtime/md5**）。
2. 同 seed 20-case 重跑（seed 823050000+i，`rerun_20_vex_storefix_20260813`）：
   **20/20 exit=0，全部 `0 exception rounds, 0 write rounds`**；原 fcvt 差异 case_16/case_20 不再复现。
