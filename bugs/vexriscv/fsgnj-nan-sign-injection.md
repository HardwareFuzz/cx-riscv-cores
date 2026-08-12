# VexRiscv: fsgnj/fsgnjn/fsgnjx 跳过 NaN rs1 的符号位注入（上游 bug）

> Status: **fixed in our fork** (`cx-build` branch, cores/VexRiscv), verified against a rebuilt
> Verilator simulator (A/B) and full re-diff.
> Dated 2026-08-12。由 HardwareFuzz riscv_fuzz_test diff-spike 矩阵复现（rerun7 rv32_vex case_01 等）。
> 影响：vex-vs-spike 差分测试的 fsgnj* 寄存器写误报 —— **vex 真实缺陷**（违反 RISC-V spec 位级定义），
> 非 fuzz 框架误报。
> 归属：**上游 VexRiscv 原始 bug**（`git blame` 显示为 Dolu1990 2021 年提交，
> 当前 cx-build 分支与上游 master 该处代码完全一致），非用户 fork 改动。已在 fork 修复。

---

## 概述

RISC-V spec 定义 `fsgnj.s/d`、`fsgnjn.s/d`、`fsgnjx.s/d` 为**纯位级符号位操作**：
结果 = `{新符号位, rs1 的指数+尾数}`，其中 fsgnj→取 rs2 符号位、fsgnjn→取 ~rs2 符号位、
fsgnjx→取 rs1⊕rs2 符号位。该操作**不做任何 NaN 检测、不做 NaN-box 解盒**——即使 rs1 是 NaN，
也必须按位替换符号位。

VexRiscv 的 `FpuCore.scala`（`shortPip` 区）对 SGNJ 用 `when(!input.rs1.isNan)` 守卫符号注入，
导致 rs1 为 NaN 时符号位不被替换，结果 = rs1 原样；且对 boxed 单精度 rs1（读为 double NaN 的
NaN-box 模式）会额外把结果格式改成 FLOAT 并回写 rs1 的 float 符号位，双双违反 spec。

## 复现（rerun7 rv32_vex case_01，#534 全局 754）

`fsgnjn.d f18, f15, f19`，上文 `f15=0xffffffff00000000`（NaN-boxed +0.0f，读为 double -Infinity /
boxed 位型），`f19=0xffffffffbf800000`：

- **spike（正确）**：`f18=0x7fffffff00000000`。64 位操作数按位处理：rs1 bit63=1、
  fsgnjn 用 ~rs2 bit63=0 → 结果符号位=0，尾数保留 NaN-box 的 0xFFFFFFFFxxxxxxxx 上字。
- **vex（pre-fix）**：`f18=0xffffffff00000000`（rs1 原样，符号位未注入、NaN-box 上字被丢）。

观测探针（`single_instruction_diff_001/observation_probe`）确认两核心真实状态不一致：
spike `0x7fffffff` vs vex `0xffffffff`（f18 high word），非框架误报。

历史上 87 个 write-diff 扫描中发现 10 个 fsgnj* 真 bug（fsgnj.s/fsgnjn.s/fsgnj.d/fsgnjn.d 等，含 NaN 输入）。

## 根因

`src/main/scala/vexriscv/ip/fpu/FpuCore.scala`（上游 Dolu1990 2021-02-16 commit f180ba2fc，
与上游 master 一致）：

```scala
is(FpuOpcode.SGNJ){
  when(!input.rs1.isNan) {              // ← 错误守卫：rs1 为 NaN 时跳过符号注入
    rfOutput.value.sign := sgnjResult
  }
  if(p.withDouble) when(input.rs1Boxed && input.format === FpuFormat.DOUBLE){
    rfOutput.value.sign := input.rs1.sign   // ← 错误：把已注入的符号回退为 rs1 的 float 符号
    rfOutput.format := FpuFormat.FLOAT      // ← 错误：把结果当 boxed float 编码，丢 NaN-box 上字
  }
}
```

两个缺陷叠加，对 boxed 单精度 rs1 的 `fsgnj*_d` 必现：`when(!isNan)` 对 -Infinity recode 不拦
（isNan=false 通过），但随后 boxed 分支把符号回退并改成 FLOAT 编码 → 输出 = boxed float 原样
（0xFFFFFFFFxxxxxxxx），符号位完全按 float（bit31）而非 64 位（bit63）处理。

纯 NaN（如 fsgnj.s 输入 0x7FC00000）时，`when(!isNan)` 直接把注入跳过，输出 = rs1 原样。

## 修复（fork 内）

`FpuCore.scala` 两处：

1. **符号位无条件注入**：删除 `when(!input.rs1.isNan)` 守卫，`rfOutput.value.sign := sgnjResult`
   无条件执行（fsgnj* 是纯位操作，不检查 NaN）。
2. **boxed rs1 的 64 位重建（保持格式 DOUBLE）**：原
   `when(input.rs1Boxed && format==DOUBLE)` 分支把 `sign := input.rs1.sign`（回退已注入符号）+
   `format := FpuFormat.FLOAT`（把结果当 boxed float 编码）——对 fsgnj.d 读 boxed 单精度 rs1 的
   场合，把 64 位 NaN-box 操作错误地改成 32 位 float 操作（符号按 bit31 而非 bit63，NaN-box 上字
   被解盒丢掉）。修复改为**保持 DOUBLE 格式**、把结果重建为 64 位 NaN-box 模式：
   `exp=0x7FF`、`mantissa=0xFFFFF ## float32(rs1)`（recoded 下 `0xFFFFF ## sign ## f32.exp ## f32.man`
   ，53 位 writeFloating 布局为 bits52..1）。double 写回路径对该 NaN 按位产出
   `{sgnjResult} 11111111111 0xFFFFFFFF ## float32(rs1)`——正是 spec 期望的
   `{新符号}FFFFFFFF ## float32(rs1)`。
3. **配套**：`sgnjRs1Sign` 在 `(rs1Boxed && format==DOUBLE)` 时置 1（NaN-box 的 bit63 即符号），
   使 fsgnjx 对 boxed rs1 的符号异或也正确（fsgnj/fsgnjn 的 rs2 侧本就有同款处理）。
4. **boxed NaN 的 f32 指数还原**（第二轮修正）：boxed 分支重建用的 `f32.exp`
   （=`input.rs1.exponent - (exponentOne-127)`）对**普通/零** boxed float 能正确还原 raw f32 指数，
   但对 **NaN/Inf** boxed float 是错的——load recode 的 `setNan`/`setInfinity` 把 recoded 指数重写
   为 0x87A/0x879（special 编码），`f32.exp` 因此变成 0xFA/0xF9 而非 raw 的 0xFF。NaN/Inf 的
   IEEE f32 指数恒为 0xFF，故在 boxed 分支里对 NaN/Inf 强制 `f32ExpCorrected := 0xFF`。
5. **重建位布局 = 53 位 mantissa 的 [52:1]**：52 位拼接 `C = 0xFFFFF ## sign ## exp ## man`
   必须以 `@@U"0"` 放到 `writeFloating` mantissa 的 bit52..1（bit0=0）——`roundBack`
   用 `mantissa[52:1]` 作为 52 位尾数（bit52 是前导位），因此 double 写回的 `manBase = C`，
   加上 NaN 的 `| 1<<51`（非 canonical），精确产出 `{newSign} 0xFFFFFFFF ## float32(rs1)`。
   曾误以为 `@@U"0"` 是冗余并改成 `resize(53)`（C 落在 bit51..0），导致 boxed 重建整体右移一位、
   写回变成 `0x7fffffff80000000`（fsgnjn.d）等垃圾值——`@@U"0"` 必须保留。

```scala
// 1. sgnjRs1Sign boxed 覆盖（fsgnjx 需要）
if(p.withDouble){
  sgnjRs1Sign setWhen(input.rs1Boxed && input.format === FpuFormat.DOUBLE)
  sgnjRs2Sign setWhen(input.rs2Boxed && input.format === FpuFormat.DOUBLE)
}
// 2. SGNJ 分支
is(FpuOpcode.SGNJ){
  rfOutput.value.sign := sgnjResult          // 无条件注入
  if(p.withDouble) when(input.rs1Boxed && input.format === FpuFormat.DOUBLE){
    // 重建 NaN-box 模式：exp=0x7FF, mantissa=0xFFFFF ## float32(rs1)
    val f32ExpCorrected = CombInit(f32.exp)
    val f32ManCorrected = CombInit(f32.man)
    when(input.rs1.isNan || input.rs1.isInfinity){ f32ExpCorrected := 0xFF }
    // boxed f32 SUBNORMAL（IEEE exp8=0 且 man23!=0）：load recode 会把它归一化——
    // 尾数左移 msbPos 位、recoded 指数置为 exponentOne-149+msbPos（范围 [1898,1920]），
    // 原始 f32 字段不再直接可见。用与 STORE/FMV 相同的 mod-64 反归一化恢复 raw 尾数：
    //   man23 = ((1 ## mantissa) >> (1950 - exp))[22:0]
    //（隐式前导 1 提供 bit msbPos，移位后的 52 位字段提供其余低位）。
    when(!input.rs1.special && input.rs1.exponent <= U(exponentOne-127) && input.rs1.exponent >= U(exponentOne-149)){
      f32ExpCorrected := 0
      f32ManCorrected := (((U(1, 1 bits) @@ input.rs1.mantissa) >> (U(exponentOne-97) - input.rs1.exponent))(22 downto 0)).resized
    }
    rfOutput.value.setNan
    rfOutput.value.exponent(11 downto 3) := 0
    rfOutput.value.mantissa := (U(0xFFFFF, 20 bits) ## input.rs1.sign ## f32ExpCorrected ## f32ManCorrected).asUInt @@ U"0"
  }
}
```

`.s`（单精度）与 `.d`（双精度）路径均覆盖：`.s` 走无条件 `sign := sgnjResult`（NaN 也注入，
boxed 分支不触发）；`.d` 的 boxed 分支重建 64 位 NaN-box 模式。

> 修复过程中踩坑记录：
> 1. 曾尝试**删除 boxed 分支**（只留无条件符号注入 + 依赖 double 写回按位保留 NaN-box 上字）。
>    对 boxed rs1 该方案错误——recode 会把 boxed float 解盒为 float 再右移 29 位到 double mantissa
>    高位，double 写回输出 `{sign} exp man>>29<<29`（高位 mantissa 仍在但**不是** NaN，exp 为 boxed
>    单精度的指数而非 0x7FF），产生 0x36a… 等非 NaN 垃圾值。必须显式重建 NaN-box。
> 2. 重建的 f32 指数必须还原（见上第 4 点）：若直接用 `f32.exp`，boxed NaN 会得到
>    `0xffffffff7d400000` 而非 `0xffffffff7fc00000`（f32exp=0xFA 误当 0xFF）。
> 3. `@@U"0"` 位布局必须保留（见上第 5 点）：`roundBack` 以 `mantissa[52:1]` 为尾数，去掉
>    `@@U"0"`（`resize(53)` 使 C 落 bit51..0）会让 boxed 重建整体右移一位、写回变成
>    `0x7fffffff80000000` 等垃圾值。曾误判其为冗余，实际是必须的。
> 4. **boxed f32 SUBNORMAL 的字段丢失**（第三轮修正，本文件再更新）：load recode 对 boxed 次正规
>    （IEEE exp8=0 且 man23!=0）走归一化 FSM——尾数左移 `shift.by`（=msbPos）位、recoded 指数置
>    `exponentOne-149+msbPos`，使 `f32.exp = exp-1920` 与 `f32.man = mantissa[51:29]` 对次正规全错
>    （单 bit 次正规 0x00000001 的 RF 尾数甚至整个移出 52 位字段，`f32.man=0`、`f32.exp=0xEA`）。
>    必须在 boxed 分支里用与 STORE/FMV 相同的 mod-64 反归一化恢复 raw 尾数。曾以「fsw/fld 往返
>    能还原 0x00000001」误判 RF 无损，实际 STORE 走 `recodedResult`（不经 roundBack），而 SGNJ
>    走 recoded→roundBack，二者路径不同。

## 修复验证（fork 内）

- 重建：`./build.sh --isa rv32fd --cores 1` → `artifacts/vexriscv_rv32fd_1c`
  （前轮 md5 `27fe0f1d…`；subnormal 修复后 md5 `7bbd357c…`，mtime 更新）。
- **单元级 A/B**：`/tmp/vex_unit2/test6.elf` 9 个隔离用例（fsgnj/fsgnjn/fsgnjx × .d/.s，
  boxed 次正规 0x00000001/0x00000004/0x00000005/0x00010000/0x007FFFFF、boxed +0.0、
  boxed NaN 0x7FC00000）——vex 输出与 spike（`--isa=rv32imafdc --log-commits`）逐位一致
  （如 `fsgnj.d` boxed 0x00000001 → 0x7fffffff00000001；`fsgnj.s` boxed 0x00000003 → 0x80000003）。
  先前 5-case 全新 diff 暴露的 case_02 #236 / case_05 #890 fsgnjn.d 均修复。
- 重放原始 testcase（rerun7 case_01 #534 差异所在 pass）→ fsgnjn.d 写差异消失；
  剩余 1 个 write-diff 为既有良性 fsgnjx.s 状态级联（dedup family `WRFAM-8669cda3debeaec2`，
  两核心各自输入不同、各自按 spec 正确计算，非真缺陷，修复前重放即已存在）。
- 5 case 全新 diff（rv32_vex.toml + timeout 600 overlay，seed 815000005..815000009，
  concurrency 2）→ 剩余 3 个 fsgnj* write-diff 全部**单独复现验证为良性**：
  - case_01 `fsgnjx.d f19,f19,f17`（boxed +Inf rs1）：单指令复现（test7）vex=spike=0x7fffffff7f800000；
    差异为历史级联（起点 #10），真实状态各自按 spec 正确。
  - case_02 `fsgnj.s f20,f20,f17`（boxed SNaN）：单指令复现（test8）vex=spike=0xff800001；
    报告自身标注「真实状态一致，差异仅存在于日志/解析记录」。
  - case_03 `fsgnj.d f13,f17,f14`（boxed NaN rs1）：单指令复现（test8）vex=spike=0xffffffff7fc00000；
    报告上下文 0x7fed929e 与 0x7fc00000 均为合法 boxed NaN，单指令下两核心逐位一致，差异为历史级联。

相关：`artifacts/diff_spike_execfix_20260810_new/fresh_all_50_lowp12_rerun7_vex_fixed/`；
subnormal 修复后的 5-case 全新 diff 见 `/tmp/vex_5case_subfix/`（5/5 CLI OK）。
