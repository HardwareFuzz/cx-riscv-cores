# VexRiscv: fsgnj*_d boxed 重建导致 boxed 标志与值分裂（fork 回归）

> Status: **fork regression（cb7a0576 fsgnj NaN-sign 修复引入）** — 非上游原始 bug。
> Dated 2026-08-12。由 HardwareFuzz riscv_fuzz_test diff-spike 矩阵复现（fresh_all_5_single
> rv32_vex case_02，root diff = `flt.s x13, f13, f14`，前序 `fsgnjx.d f13`）。
> 影响：vex-vs-spike 差分测试的**单精度读路径误判** —— vex 真实状态差异（违反 RISC-V 规范的
> 值驱动 NaN-box 解盒规则），非 fuzz 框架误报。
> 归属：**fork 自身回归**。上游原始 fsgnj*_d 对 boxed rs1 把 `format` 设为 `FpuFormat.FLOAT`
> （boxed 标志=true）；fork 修复（cb7a0576「canonical NaN must carry positive sign」）改为保持
> `FpuFormat.DOUBLE` 并按 64 位 NaN-box 位型重建，导致**寄存器文件的 boxed 标志（=写入格式）与
> 实际值（高 32 位全 1）分裂**。后续单精度指令读该寄存器时，vex 按 boxed 标志判定 NaN，而 spike
> 按值（高 32 位是否 0xFFFFFFFF）解盒，产生真实分歧。

---

## 概述

RISC-V 规范（F 扩展 NaN-boxing）定义**读单精度寄存器值**的规则是**值驱动**：

> 读 f32 时，若寄存器的**高 32 位为 0xFFFFFFFF**，则取低 32 位；否则将该值视为 canonical NaN。

spike 严格按此实现（`riscv/decode_macros.h`）：

```c
#define isBoxedF32(r) (isBoxedF64(r) && ((uint32_t)((r.v[0] >> 32) + 1) == 0))  // 高 32 == 0xFFFFFFFF
#define unboxF32(r) (isBoxedF32(r) ? (uint32_t)r.v[0] : defaultNaNF32UI)
```

VexRiscv 的 `FpuCore.scala` 用**写入格式**维护一个 boxed 标志：

```scala
port.data.boxed := input.format === FpuFormat.FLOAT   // 写回时：仅 FLOAT 指令置 boxed
```

正常情况下两者一致：float 指令写 boxed 值（高 32=0xFFFFFFFF）且 boxed=true；double 指令写 64 位
double（高 32 一般不是 0xFFFFFFFF）且 boxed=false。**fork 的 fsgnj*_d boxed 重建打破了这个不变量**：
以 `FpuFormat.DOUBLE` 写出一个**高 32 位恰为 0xFFFFFFFF** 的 64 位 NaN-box 位型（如
`0xFFFFFFFF00000000`），boxed 标志仍=false → 后续单精度读 f13 时
`format(FLOAT) ≠ boxed(false)` → `setNanQuiet` → 误判 NaN。

## 复现（fresh_all_5_single rv32_vex case_02，pass_001 history 起点 #470）

指令序列（candidate_470，vex 侧 program）：

```
fmv.w.x f13, x8   ; x8=0            -> f13 = 0xFFFFFFFF00000000 (boxed +0.0f)
fmv.w.x f14, x8   ; x8=0x052829b2   -> f14 = 0xFFFFFFFF052829B2 (boxed 极小正数)
...
fld f15, 0(x16)   ; trap (misaligned)，f15 保持 0x7FF8000000000000 (double NaN)
fsgnjx.d f13, f13, f15   ; 纯位操作：f13 = {bit63: 1^0} ## f13[62:0]
                         ;      = 0xFFFFFFFF00000000（作为 double 是 -Infinity，
                         ;        作为 boxed f32 是 boxed +0.0f）
...
flt.s x13, f13, f14
```

- **spike（正确，值驱动）**：flt.s 读 f13 → 高 32=0xFFFFFFFF → 解盒低 32 = 0x00000000 = +0.0f
  → `flt.s(+0.0, 0x052829b2)` = **1**。
- **vex（pre-fix，格式驱动）**：fsgnjx.d 写 f13 时 `boxed := (format==FLOAT)` = false →
  flt.s 读 f13 时 `format(FLOAT) ≠ boxed(false)` → `setNanQuiet` → NaN → `flt.s(NaN, ...)` = **0**。

观测探针确认两核心真实状态不一致（spike x13=0x1 vs vex x13=0x0），非框架误报。

对照组：同一 flt.s 在**无 fsgnjx.d 前序**的单指令程序里（f13 由 `fmv.w.x` 写入，boxed=true），
vex 输出 = spike = 1，正确。差异只在「fsgnjx.d 改写过的 freg 被后续单精度指令读取」时出现。

## 根因

1. **上游原始 fsgnjx.d 对 boxed rs1**（git show 06426567~1，上游 Dolu1990 代码）：

   ```scala
   is(FpuOpcode.SGNJ){
     when(!input.rs1.isNan) { rfOutput.value.sign := sgnjResult }
     if(p.withDouble) when(input.rs1Boxed && input.format === FpuFormat.DOUBLE){
       rfOutput.value.sign := input.rs1.sign
       rfOutput.format := FpuFormat.FLOAT        // ← 结果按 boxed float 编码
     }
   }
   ```

   此时结果 `format=FLOAT` → `boxed := true` → 后续单精度读正常（但代价是丢失 NaN-box 上字、
   符号按 bit31 处理——这正是 cb7a0576 要修的原 bug）。

2. **fork 修复（cb7a0576）**：boxed 分支改为「保持 `FpuFormat.DOUBLE` + 重建 64 位 NaN-box 位型」
   （`exp=0x7FF, mantissa=0xFFFFF ## float32(rs1)`），以产生
   `{newSign} 0xFFFFFFFF ## float32(rs1)`。值正确了，但 `format` 仍是 DOUBLE →
   `boxed := false` → **boxed 标志与值分裂**，后续单精度读误判 NaN。

3. 判定位置：`FpuCore.scala` writeback：

   ```scala
   port.data.boxed := input.format === FpuFormat.FLOAT
   ```

   与 read：

   ```scala
   elsewhen (s1.format === FpuFormat.FLOAT =/= rs(0).boxed) {
     output.rs1.setNanQuiet   // ← boxed=false + 请求 FLOAT → 误判 NaN
   }
   ```

## 修复（fork 内）

`shortPip` 的 SGNJ 分支按 `sgnjResult` 分流，两种产物都精确对应 spike 的逐位
`{sgnjResult} ## rs1[62:0]`：

```scala
is(FpuOpcode.SGNJ){
  rfOutput.value.sign := sgnjResult
  if(p.withDouble) when(input.rs1Boxed && input.format === FpuFormat.DOUBLE){
    when(sgnjResult){
      // sgn=1：结果仍是 NaN-box 位型 0xFFFFFFFF ## float32(rs1)（作为 double 是
      // -Infinity，但按 NaN-box 规则仍是 boxed float）。存 FLOAT recode：后续
      // 单精度读按 boxed 解盒低 32 位（spike 同），符号取 rs1.sign（bit31），
      // 因为 sgnjResult 是 NaN-box 的 bit63，不是 float32 的 bit31。
      rfOutput.format := FpuFormat.FLOAT
      rfOutput.value.sign := input.rs1.sign
    } otherwise {
      // sgn=0：结果 0x7FFFFFFF ## float32(rs1)，不再是 boxed（后续单精度读 = NaN），
      // 作为 double 是 NaN（exp=0x7FF，mantissa=0xFFFFF ## float32(rs1)）。
      // 用 06426567 的 NaN-box 重建编码该 double NaN。
      ...（f32Exp/f32Man 校正 + setNan + 0x7FFFFFFF 重建，见代码）...
    }
  }
}
```

writeback 的 boxed 判定**回退为上游原版（只看写入格式）**：

```scala
port.data.boxed := input.format === FpuFormat.FLOAT
```

为什么不能用「按值判定」（早期尝试，已回退）：`0xFFFFFFFF00000000` 既是 boxed float
位型又是**合法 double -Infinity**，且 double NaN 也常有高 32 位全 1
（如 `0xFFFFFFFFxxxxxxxx`）。按值判定会把**真 double**（如 fld 加载的 double NaN/
-Infinity）误标 boxed → 后续 `fsgnj.d` 对纯 double 输入误入 boxed 重建分支 → 垃圾值。
修复后 fsgnj*_d 不再产生「DOUBLE 格式 + NaN-box 位型」的混合产物，boxed 只看 format
即可与值保持一致。

## 修复验证（fork 内）

- 单元级 A/B（`/tmp/vex_unit2/test_boxedflag.S`，忠实复现 case_02 的 `fmv.w.x` 写 boxed
  float + `fld` 写 double NaN，并覆盖 sgn=1/sgn=0 双路径），vex 输出与 spike 逐位一致：

  | 用例 | 指令序列 | vex | spike 期望 |
  |---|---|---|---|
  | J | boxed +0.0f `fsgnjx.d`(+NaN) → `flt.s`(+1.0f) | x31=1 | 1 |
  | K | boxed +1.0f `fsgnjx.d`(+NaN) → `flt.s`(+1.0f) | x31=0 | 0 |
  | L | boxed +0.0f `fsgnjx.d`(−NaN) → `fsd` 位 | 0x7fffffff00000000 | 0x7FFFFFFF00000000 |
  | L | 同上 → `flt.s` | x31=0 | 0 |
  | M | `flt.d`(非 boxed NaN, boxed +1.0f) | 0 | 0 |
  | N | boxed −Inf `fsgnjn.d`(boxed +NaN) → `fsd` 位 | 0x7fffffffff800000 | 0x7FFFFFFF_FF800000 |
  | O | boxed +NaN → `fsw`（STORE 路径 f32 位型） | 0x7fc00000 | 0x7FC00000 |
  | P | `fmv.w.x` boxed +NaN `fsgnjx.d`(sgn=0) → `fsd` | 0x7fffffff7fc00000 | 0x7FFFFFFF_7FC00000 |
  | Q | `fld` boxed +NaN `fsgnjx.d`(sgn=0) → `fsd` | 0x7fffffff7fc00000 | 0x7FFFFFFF_7FC00000 |

- 重建：`./build.sh --isa rv32fd --cores 1` → `artifacts/vexriscv_rv32fd_1c`（核对 mtime/md5）。
- 5 case 全新 diff（rv32_vex.toml + timeout 600 overlay）→ vex 浮点写差异收敛。

## 连带修复：boxed rs2 的 bit63 符号 + rebuild 的 sign

首轮修复（sgn=1 透传 / sgn=0 重建）后重跑矩阵，case_02 又暴露 `fsgnjn.d f15, f15, f16`
（f15=0xffffffffff800000 boxed −Inf, f16=0xffffffff7fc00000 boxed +NaN）真实状态不一致，
spike=0x7fffffffff800000 vs vex 保持原样。两个连带 bug：

1. **boxed rs2 的符号位**：06426567 用 `sgnjRs2Sign setWhen(recode.sign)` 取 boxed rs2
   的符号——recode 是 float recode（sign = float32 的 bit31），且 read 区 NaN-box 检查还把
   rs2 的 sign 清 0。而 NaN-box 上字 0xFFFFFFFF 的 bit63 恒为 1。改为
   `when(boxed && DOUBLE){ sgnjRs2Sign := True }`（rs1 同理），匹配 spike 直接读 bit63。
2. **rebuild 的 sign**：重建分支的 bit63 必须 = `sgnjResult`（spike 的 fsgnj 只动 bit63），
   float32 完整位型（含其自身 sign）落在低 32 位。若用 rs1.sign 覆盖 bit63，boxed −Inf
   （float32 sign=1）会输出 0xFFFFFFFF##float32 原样，fsgnjn.d 不翻转。首次 A/B 的 L 用例
   （boxed +0.0f，float32 sign=0）恰好掩盖了它。

## 连带修复：算术 recode 的 boxed NaN/Inf payload canonicalize

case_03 的 `fsgnjx.d f17, f17, f13` 又暴露真实不一致：f17=0xffffffff7fc00000（boxed +NaN）
由 **fnmsub.s（长算术流水线）** 写出，其 recode 的 `mantissa[51:29]` 携带 recoded NaN 载荷
（0x710602）而非原始 f32 payload（0x7FC00000）。rebuild 原样复制 0x710602 进 fsgnj.d 结果
（0x7fffffff7ff10602）vs spike 的 bit-exact 0x7fffffff7fc00000。writeback 的 IEEE 视图
（fregWriteData）对 NaN/Inf 做了 canonicalize（NaN → man|0x400000，canonical→0x400000；
Inf → man=0），rebuild 也必须一致：NaN payload 置 quiet 位（canonical 用 0x400000），Inf
mantissa 清零。注意 OR 用原始切片 `f32.man`，不能 `CombInit(f32ManCorrected)`（会把整棵
赋值树拷入自身 → 组合逻辑环）。

相关：`artifacts/diff_spike_execfix_20260810_new/fresh_all_5_single_lowp45/rv32_vex/case_02/`；
根因分析见 `docs/sc-reservation-outcome-divergence.md` 的 flt.s 姊妹篇
（本文件即该分析的落地）。
