# openc910: fmax.d 对单个 SNaN 操作数错误返回规范 QNaN（应返回非 NaN 操作数）

> Status: **upstream-inherent（T-Head 原厂 RTL 缺陷，未在本 fork 修复）**。
> Dated 2026-08-11。由 HardwareFuzz riscv_fuzz_test diff-spike 矩阵复现（rv64_openc910 case_03 pass_002，#180，单指令可稳定复现）。
> 影响：openc910-vs-spike 差分测试的 fmax.d/fmin.d 写入值误报——**openc910 真实缺陷**，非 fuzz 框架/解析误报。

---

## 概述

RISC-V F/D 扩展的 `fmax.d`（maxNum 语义，riscv-spec §13.3）要求：**只有一个操作数是 NaN 时，结果必须是另一个（非 NaN）操作数**；只有两个都是 NaN 时才返回规范 QNaN。Spike 的 `riscv-isa-sim/riscv/insns/fmax_d.h` 正是这样实现的：

```c
bool greater = f64_lt_quiet(FRS2_D, FRS1_D) || (f64_eq(FRS2_D, FRS1_D) && (FRS2_D.v & F64_SIGN));
if (isNaNF64UI(FRS1_D.v) && isNaNF64UI(FRS2_D.v))
  WRITE_FRD_D(f64(defaultNaNF64UI));
else
  WRITE_FRD_D((greater || isNaNF64UI(FRS2_D.v) ? FRS1_D : FRS2_D));
```

openc910 的 FPU 把 fmax.d 解码到 FADD 单元（pipe7），其 maxNum 结果选择逻辑在 `vfalu/rtl/ct_fadd_double_dp.v` 中把 **单个 SNaN 也当作规范 NaN 输入**，从而错误返回规范 QNaN，违反 maxNum 规范。

## 复现

- 来源：`artifacts/diff_spike_execfix_20260810_new/fresh_all_50_lowp12_rerun5/rv64_openc910/case_03/` pass_002，#180，`fmax.d f19, f18, f20`。
- 输入：f18=0x3ff0000000000000（=1.0），f20=0xfff7ffffffffffff（SNaN，最高有效位 1 + 尾数非 0）。
- 观测（openc910 原始 trace，pipe7 写回总线直接采样）：

```
fdispatch cycle=6519 hart=0 iid=0 rd=f19 fpreg=8
commit    cycle=6522 hart=0 pc=0x00000008f8 iid=0
fpregwrite cycle=6525 hart=0 fpreg=8 value=0x7ff8000000000000   <- openc910: 规范 QNaN
```

- spike 同一指令写 `f19=0x3ff0000000000000`（=1.0，非 NaN 操作数）。
- 单指令复现稳定：`single_instruction_diff_003/` 中 openc910 写 0x7ff8000000000000、spike 写 0x3ff0000000000000。

## 根因（决定性证据）

`cores/openc910/C910_RTL_FACTORY/gen_rtl/vfalu/rtl/ct_fadd_double_dp.v`（约 2343-2368）maxNum 结果选择：

```verilog
if(ex2_src0_is_snan || ex2_src1_is_snan ||
   ex2_src0_is_qnan && ex2_src1_is_qnan)
  ex2_max_nm_result[63:0] = {64{ex2_double}} & {ex2_qnan_s, {11{1'b1}}, ex2_qnan_f[51:0]} | ...; // 规范 QNaN
else if(ex2_src0_is_0 && ex2_src1_is_0) ...                    // ±0
else if(ex2_src0_is_qnan) ex2_max_nm_result = src1;            // 单 QNaN -> 返回另一操作数
else if(ex2_src1_is_qnan) ex2_max_nm_result = src0;            // 单 QNaN -> 返回另一操作数
else if(ex2_sign ^ ex2_src_change) ...                          // 数值比较
else ...                                                         // 数值比较
```

关键缺陷在第一个分支：**只要任一个操作数是 SNaN（即使另一个是普通数值），就取规范 QNaN**。RTL 把 SNaN 当"必须产出 NaN"处理，而 maxNum 规范要求单 NaN 时返回非 NaN 操作数。本例 f20=SNaN、f18=1.0，正确结果应为 1.0（spike），openc910 却返回 0x7ff8000000000000。

（注意：`minNum`/`maxNum` 的 IEEE 754-2019 版本与 RISC-V 的 maxNum 语义有差异；RISC-V 明确采用"单 NaN 返回非 NaN 操作数"的 maxNum 语义，见 spec §13.3 及 spike 参考实现。）

## 修复

T-Head 原厂 RTL 缺陷（`gen_rtl` 为上游生成代码，Apache 2.0 许可），**本 fork 未改动**（改 gen_rtl 需重新生成 RTL 并重编译 Verilator 二进制）。正确修复方向：把第一个分支改为仅当**两个操作数都是 NaN（含 SNaN/QNaN）**时才返回规范 QNaN，单 SNaN 走 QNaN 分支之后逻辑（返回另一操作数）：

```verilog
// 建议：仅双 NaN 返回规范 QNaN；单 SNaN 应像单 QNaN 一样返回非 NaN 操作数
if((ex2_src0_is_snan || ex2_src1_is_snan ||
    ex2_src0_is_qnan || ex2_src1_is_qnan) &&
   (ex2_src0_is_snan || ex2_src0_is_qnan) &&
   (ex2_src1_is_snan || ex2_src1_is_qnan))
  ... // 规范 QNaN
```

若按 T-Head 默认 dqnan（denormal/quiet NaN）收敛策略，则至少需保证单 SNaN 时把 SNaN 静默化（quiet 化）后作为非 NaN 处理并返回另一操作数——这与 spike 完全一致。

## 对 diff-fuzz 的意义

这是 openc910 与 spike 在 maxNum 上**真实的架构性分歧**（openc910 对单 SNaN 错误返回规范 QNaN），不是 fuzz 框架误报。trace 插桩（`smart_run/logical/tb/tb_verilator.v:1180-1184`）直接采样 FPU 写回总线 `vfpu_idu_ex5_pipe7_wb_vreg_fr_data`，忠实反映 RTL。任何 fuzz 测试中 fmax/fmin 恰好遇到 SNaN 单操作数，都会造成 fp 寄存器写入值差异被误报。修复 RTL 并重编译后该差异将从矩阵消失。

## 附录：关键信号位置

- `ct_fadd_double_dp.v`：`ex2_src0_is_snan`/`ex2_src1_is_snan`（:1433/1439）、`ex2_max_nm_result`（:140）、maxNum 选择逻辑（:2343-2368）
- `ct_idu_rf_pipe7_decd.v`：fmax.d 解码到 FADD pipe7（FMAXD func）
- Spike 参考：`riscv-isa-sim/riscv/insns/fmax_d.h`（maxNum，单 NaN 返回另一操作数）
- 插桩：`tb_verilator.v:1180-1184`（pipe7 fpregwrite，采样 `vfpu_idu_ex5_pipe7_wb_vreg_fr_data`）
- 复现：`artifacts/diff_spike_execfix_20260810_new/fresh_all_50_lowp12_rerun5/rv64_openc910/case_03/spike_openc910_rv64/rv64_case_000_w00_1786430441_100214046/pass_002/`
