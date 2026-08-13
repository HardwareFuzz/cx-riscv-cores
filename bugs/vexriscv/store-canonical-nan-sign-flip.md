# VexRiscv: STORE/FMV_X_W 在存储总线上翻转 canonical NaN 的符号位（上游 bug）

> Status: **confirmed spec violation（上游 VexRiscv 原始 bug）** — 已在 fork `cx-build` 分支修复
> （f6e64834），Verilator 重编后同 seed 20-case 重跑 0 写差异。
> Dated 2026-08-13。由 HardwareFuzz riscv_fuzz_test diff-spike 矩阵复现（fcvt 修复后的
> `rerun_20_vex_fcvtfix_20260813` rv32_vex case_20，root diff = `c.fswsp`；此前该差异被
> fcvt.d.s 符号差异掩盖）。
> 影响：vex-vs-spike 差分测试的 `fsw`/`c.fswsp`/`fmv.x.w` 内存/寄存器写差异 —— **vex 真实缺陷**
> （违反 RISC-V spec「bit-exact move」条文），非 fuzz 框架误报。
> 归属：**上游原厂**（`git blame`：Dolu1990 2021-02-10 commit `e97c2de83`；上游 master 该处与
> fork 修复前一致）。

---

## 概述

RISC-V spec 把 **STORE 与 FMV（位搬运）定义为 bit-exact move**：写入内存或通用寄存器的值必须与
源浮点寄存器**逐位一致**，不得修改任何位（包括 NaN 的符号位和 payload）。

VexRiscv `FpuCore.scala` 的存储数据通路里，`cononicalForced` 分支对**读出的 canonical NaN**执行：

```scala
when(cononicalForced){
  whenDouble(input.format){
    recodedResult(63) := False    // ← 强制把双精度 NaN 的符号位清 0
    recodedResult(51) := True
  }  {
    recodedResult(31) := False    // ← 强制把单精度 NaN 的符号位清 0
    recodedResult(22) := True
  }
}
```

即：寄存器里符号位=1 的 canonical NaN（如 `0xffc00000`）经 STORE/FMV_X_W 总线输出时**符号被清成
0**（`0x7fc00000`）。这违反 bit-exact move —— 浮点寄存器被当作「值」重写了符号位。

对照：spike 的 store/FMV 严格 bit-exact（`freg` 直接写内存/通用寄存器，不做任何 NaN 规范化）。
故该 diff 是**真实架构差异，违规方是 vex**。

## 复现（rerun_20_vex_fcvtfix_20260813 rv32_vex case_20，历史依赖复现）

`c.fswsp f20, 16(sp)`，上文 `f20=0xffffffffffc00000`（f32 = `0xffc00000` = 负 canonical QNaN）：

- **spike（正确，bit-exact）**：内存写入 word = `0x80=0x00, 0x81=0x00, 0x82=0xc0, 0x83=0xff`
  （即 `0xffc00000`，符号位=1 完整保留）
- **vex（pre-fix）**：内存写入 word = `0x80=0x00, 0x81=0x00, 0x82=0xc0, 0x83=0x7f`
  （即 `0x7fc00000`，**符号位被清 0**）

同一现象也会出现在 `fmv.x.w`（写通用寄存器）和直接 `fsw` 上。输入 `0xffffffffffc00000` 两核相同，
差异只在**存储总线上的符号位**。

> 提示：单指令 A/B 复现可能**不触发**此 bug —— 若 NaN 来自 `fld` 载入，load 通路走 `setNan`
> （清 canonical 位）→ 存储时不进 `cononicalForced`；只有 **fsgnj 等产生的 canonical NaN** 存储
> 才触发。判定请以全 trace / 同 seed 重放为准（参见记忆 [[project_vex_1c_float_record_noise]]）。

## 根因

`src/main/scala/vexriscv/ip/fpu/FpuCore.scala`（上游 Dolu1990 2021-02-10，git blame `e97c2de83`）。

`cononicalForced` 本意是把非 canonical 的 NaN 输出规范化（quiet 位、符号），但**该分支把 canonical
NaN 也一并命中了**——而 canonical NaN 是架构上合法的值，STORE/FMV 必须原样搬运。强制 `sign := False`
对**值驱动**的存储输出是越权改写。

## 修复（fork，f6e64834）

```scala
when(cononicalForced){
  whenDouble(input.format){
    // keep sign: STORE/FMV_X_W are bit-exact moves (spec norm); canonical
    // NaN sign must not be flipped on the store bus
    recodedResult(51) := True
  }  {
    recodedResult(22) := True
  }
}
```

**只删两行 `recodedResult(63)/(31) := False`，不要删整个块** —— `recodedResult(51)/(22) := True`
是 mantissaForced 先清掉 quiet 位后恢复 quiet bit 所必需的（参见
[[project_vex_1c_float_record_noise]] 的修复说明）。

## 修复验证

1. `./build.sh` 重建 vexriscv emulator（核对 emulator mtime/md5）。
2. 同 seed 20-case 重跑（seed 823050000+i，`rerun_20_vex_storefix_20260813`）：
   **20/20 exit=0，全部 `0 exception rounds, 0 write rounds`**；原 c.fswsp 差异 case_20 不再复现，
   fcvt.d.s 差异同样不复现（双修复后）。
