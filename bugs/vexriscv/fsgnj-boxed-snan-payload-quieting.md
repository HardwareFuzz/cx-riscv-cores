# VexRiscv: fsgnj*_d boxed 重建对 transfer 载入的 SNaN payload 静音化（fork 回归，已修复）

> Status: **confirmed spec violation（fork 回归）— 已修复**（fork `cx-build` 674ebd97
> 「fsgnj*_d boxed rebuild must copy SNaN payload verbatim」，2026-08-13；`cx-2hart-build`
> 47669ad0 同步）。由 HardwareFuzz riscv_fuzz_test diff-spike 单核矩阵（fresh 20-case，
> rv32_vex case_19）复现。影响：vex-vs-spike 差分测试的 fsgnj*.d 寄存器写差异 ——
> **vex 真实缺陷**（fsgnj 是 spec 位级操作，SPIKE 逐位复制，vex 把 SNaN 静音化），
> 非 fuzz 框架误报。
> 归属：**fork 回归**（引入于 fork `dbf40ff3`，非上游 VexRiscv）。

---

## 概述

RISC-V 规范对 fsgnj/fsgnjn/fsgnjx 的定义是**纯位级符号操作**：结果 = `{sgnjResult} ## rs1[62:0]`
（双精度），**不做 NaN 检测、不解 NaN-box、不修改 payload**。因此对 boxed SNaN 输入
（高 32 位全 1 的 NaN-box 单精度，quiet bit=0），spike 原样保留 SNaN payload。

fork `dbf40ff3`（2026-08-12，fsgnj*_d boxed 重建的 sgnjResult 分流修复）在 boxed 重建的
「非 canonical NaN」分支强制 `f32ManCorrected := f32.man | 0x400000`（OR quiet bit），
把 transfer 载入的 boxed SNaN 静音化 → 违反 spec。

## 复现（fresh 单核矩阵 rv32_vex case_19）

`fsgnjx.d f17, f19, f17`（单指令复现，spike vs vex）：

- `f17 = 0xffffffffa9b68a26`（boxed 单精度，非 NaN，正常数）
- `f19 = 0xffffffffffaaaaaa`（boxed 单精度 **SNaN**：f32 = 0xffaaaaaa，quiet bit=0，sign=1）
  —— 由 `fld` 载入（load 路径 `setNan`，canonical bit=0 → `isCanonical=false`）

两核输入完全相同。

- **spike（符合 spec）**：`f17 = 0x7fffffffffaaaaaa`（`{sgnjResult} ## rs1[62:0]`，
  sgnjResult = sign(rs1) ^ sign(rs2) = 0^1 = 1 → bit63=1；f32 payload 原样 `0xffaaaaaa`，
  仍是 SNaN）
- **vex（违反 spec）**：`f17 = 0x7fffffffffeaaaaa`（f32 低 23 位 `0x6aaaaa` = `0x2aaaaa | 0x400000`，
  quiet bit 被强制置位 → SNaN 变 QNaN）

观测探针确认真实状态不一致（spike 0xffaaaaaa vs vex 0xffeaaaaa 低字），非框架误报。

## 根因

`src/main/scala/vexriscv/ip/fpu/FpuCore.scala`，fsgnj 通路 boxed 重建的「sgnjResult=0」分支
（L961-967，fork dbf40ff3 引入，后经 cb7a0576/后续调整）：

```scala
} elsewhen(input.rs1.isNan){
  when(input.rs1.isCanonical){
    f32ManCorrected := U((BigInt(1) << 22), 23 bits)      // canonical NaN -> 0x400000
  } otherwise {
    f32ManCorrected := (f32.man | U((BigInt(1) << 22), 23 bits)).resized  // ← 强制 OR quiet bit
  }
}
```

canonicalize 的**本意**只针对**算术 recode** 产物（如 fnmsub.s 走长流水线的 recoded NaN：
`f32.man` 不是原始 IEEE 载荷，而是 recoded mantissa 的高位切片，直接复制会偏离 spike 的
`0x7FFFFFFF ## float32(rs1)`——case_03 复现）。但该分支对**transfer 载入**的 boxed NaN
（fld/fmv.w.x/flw，load 路径 `setNan` → canonical bit=0）同样命中，而这类 NaN 的 `f32.man`
**就是原始 IEEE 载荷**，必须逐位保留（spike fsgnj 位级复制）。静音化在这里是过度应用。

算术路径的 NaN 结果恒 canonical（算术通路 `setNanQuiet` → canonical bit=1），所以
`isCanonical=false` 的非 canonical 分支**只可能**由 transfer 载入的 SNaN/QNaN 命中，
静音化在此分支无合法用途。

## 修复（fork 674ebd97 / 47669ad0，已发布）

非 canonical 分支改为**逐位复制** `f32.man`，仅当低 23 位为 0（防御性覆盖不存在的算术
非 canonical NaN recode）才静音：

```scala
} elsewhen(input.rs1.isNan){
  when(input.rs1.isCanonical){
    f32ManCorrected := U((BigInt(1) << 22), 23 bits)
  } otherwise {
    // fsgnj/fsgnjn/fsgnjx are pure bit-level sign manipulations (spec):
    // copy the SNaN/QNaN payload verbatim. Transfer-loaded boxed NaNs keep
    // their raw IEEE payload in f32.man; quieting them is a spec violation.
    when(f32.man === 0){
      f32ManCorrected := U((BigInt(1) << 22), 23 bits)
    } otherwise {
      f32ManCorrected := f32.man
    }
  }
}
```

未动 `isCanonical` 分支（算术 canonical NaN → 0x400000 不变，case_03 fnmsub.s 不受影响）。

## 验证

1. 单指令复现（case_19 single_instruction_diff_001 testcase）用新 1c 二进制
   （md5 f97b3a89）replay：fsgnjx.d 后 f17 = `0x7fffffffffaaaaaa` == spike；
   0 write rounds，0 exception rounds（原 diff 完全消除）。
2. 同 seed 20-case 回归（`rerun_20_vex_fsgnjxfix_20260813`，seed 823050000+i）：
   **20/20 exit=0，18/20 完全干净（0 exception, 0 write）**；case_19 不再复现；
   case_15/17 的 1 exception round 为已知 CSR 噪声（csrrci/csrrwi/csrrw machine CSR
   异常行为差异，与 fsgnj 无关）。

## 关联

- 与 [[fsgnj-boxed-flag-regression.md]]（dbf40ff3 修复的 boxed 标志/值分裂）同一修复链；
  dbf40ff3 修好一个 fork 回归的同时在此引入新回归（canonicalize 过度应用）。
- 与 [[arith-nan-sign-non-canonical.md]]（cb7a0576 修的算术 NaN 符号上游 bug）不同问题。
- 本 bug 是 fork 代码引入的回归，非上游 VexRiscv 问题。
