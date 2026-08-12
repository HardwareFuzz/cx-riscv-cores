# openc906: fmax/fmin 对单个 SNaN 操作数错误返回规范 QNaN（应返回非 NaN 操作数）

> Status: **upstream-inherent（T-Head 原厂 RTL 缺陷）。本 fork 已修复、重编译并 replay 验证通过（2026-08-12）**。
> Dated 2026-08-12。由 HardwareFuzz riscv_fuzz_test diff-spike 矩阵复现（rv64_openc906 rerun8 case_01 pass_000 / case_03 pass_000），并通过探针验证两核心真实状态不一致（非 fuzz 框架误报）。
> 影响：openc906-vs-spike 差分测试的 fmax.d/fmin.d（及 fmax.s/fmin.s）写入值误报——**openc906 真实缺陷**。
>
> 与已记录的 openc910 `fmax-d-snan-canonical-nan.md`（bugs/openc910/）为**同一族 bug**：T-Head C9xx 系 FPU（vfalu/FADD 单元）的 maxNum/minNum 特殊值逻辑把单个 SNaN 当"必须产出 NaN"，违反 RISC-V maxNum 语义。

---

## 概述

RISC-V F/D 扩展的 `fmax.*`/`fmin.*`（maxNum/minNum 语义，riscv-spec §13.3）要求：**只有一个操作数是 NaN 时，结果必须是另一个（非 NaN）操作数**；只有两个都是 NaN 时才返回规范 QNaN。Spike 的 `riscv-isa-sim/riscv/insns/fmax_d.h` 正是这样实现（`f64_lt_quiet`/`f64_eq` 静默比较 + `isNaNF64UI` 判双 NaN → `defaultNaNF64UI`）。

openc906 的 FPU 把 fmax/fmin 解码到 FALU/FADD 单元（`aq_idu_id_decd.v` → `EU_FALU`），其 maxNum/minNum 的 NaN 特殊值结果选择在 `vfalu/rtl/aq_fadd_double_special.v` 中把**单个 SNaN 也当作"必须产出 NaN"**，从而错误返回规范 QNaN（`0x7ff8000000000000`）。

## 复现（rerun8 全新发现，探针确认真实状态不一致）

来源：`artifacts/diff_spike_execfix_20260810_new/fresh_all_50_lowp12_rerun8/rv64_openc906/`

- case_01 pass_000 `fmax.d f16, f13, f20`：f13=`0x7ff2aaaaaaaaaaaa`（SNaN，指数全 1 + 尾数 0x2aa... bit51=0）、f20=`0x3ff0000000000000`（=1.0）。
  - openc906 写 f16=`0x7ff8000000000000`（规范 QNaN）；spike 写 f16=`0x3ff0000000000000`（=1.0）。
- case_03 pass_000 `fmin.d f18, f15, f20`：f15=`0x7ff2aaaaaaaaaaaa`（SNaN）、f20=`0x1`。
  - openc906 写 f18=`0x7ff8000000000000`；spike 写 f18=`0x1`。

两例均：**单个 SNaN + 普通数值 → openc906 错返回规范 QNaN，spike 返回非 NaN 操作数**。单指令复现 + 探针观测均确认状态差异真实。

## 根因（决定性证据）

`cores/openc906/C906_RTL_FACTORY/gen_rtl/vfalu/rtl/aq_fadd_double_special.v`（约 335-358）max/min 的 NaN 特殊值选择 `ex2_special_sel_1_a`：

```verilog
if(ex2_src0_snan && cp0_vpu_xx_dqnan)
  ex2_special_sel_1_a[8:0] = {4'b0, 1'b1, 4'b0};  // qnan_src0
else if(ex2_src1_snan && cp0_vpu_xx_dqnan)
  ex2_special_sel_1_a[8:0] = {3'b0, 1'b1, 5'b0};  // qnan_src1
else if(ex2_src0_qnan && ex2_src1_qnan && !ex2_src0_cnan && cp0_vpu_xx_dqnan)
  ex2_special_sel_1_a[8:0] = {4'b0, 1'b1, 4'b0};  // qnan_src0
else if(ex2_src0_snan || ex2_src1_snan || ex2_src0_qnan && ex2_src1_qnan)
  ex2_special_sel_1_a[8:0] = {5'b0, 1'b1, 3'b0};  // cnan   <-- 缺陷分支
else if(ex2_src0_qnan)
  ex2_special_sel_1_a[8:0] = {1'b1, 1'b0, 7'b0};  // src1
else// if(ex2_src1_qnan)
  ex2_special_sel_1_a[8:0] = {1'b0, 1'b1, 7'b0};  // src0
```

关键缺陷在第 4 个分支：**只要任一个操作数是 SNaN（即使另一个是普通数值），就取 cnan（规范 QNaN）**。`cp0_vpu_xx_dqnan`（`fxcr_dqnan`，复位默认 0，仅自定义 FXCR CSR 可写）为 0 时，单个 SNaN 直接落入该分支 → 规范 QNaN。而 maxNum 规范要求单 NaN 返回非 NaN 操作数。本例 f13=SNaN、f20=1.0，正确结果应为 1.0（spike），openc906 却返回 `0x7ff8000000000000`。

（旁注：即使 `dqnan=1`，单个 SNaN 会走"qnan_src0/qnan_src1"分支返回静默化 SNaN，同样违反 maxNum；但该自定义模式默认关闭，fuzz 测试不触碰 FXCR。）

`ex2_special_sel_1`/`ex2_special_sel_2`（max/min 共用同一 NaN 选择）在 `ex2_src0_nan || ex2_src1_nan` 时取 `ex2_special_sel_1_a`，故本模块**一次修复覆盖 fmax.d/fmin.d/fmax.s/fmin.s**（及 rv64fd 未启用的 .h/.bh）。单精度/半精度与双精度共享同一 special 模块（`aq_fadd_double_special.v` 同时产出 `ex2_single0_special_data`/`ex2_half0_special_data`），无独立 single/half 版本。

## 修复

T-Head 原厂 RTL 缺陷（`gen_rtl` 为上游生成代码，Apache 2.0 许可，初始提交 bd92068 2021-10-19 原样引入，fork 从未改动）。**本 fork 已于 2026-08-12 直接修改 `gen_rtl` 并重编译 Verilator 二进制**（`gen_rtl` 为独立代码，无再生成步骤覆盖）。修复把"任何 SNaN → NaN 结果"改为**仅当两个操作数都是 NaN（QNaN 或 SNaN）时才返回 NaN（规范 QNaN，或 dqnan 模式下静默化操作数）**，单个 NaN（含 SNaN）与单 QNaN 一样返回另一操作数：

```verilog
always @( ex2_src0_snan
       or ex2_src1_snan
       or ex2_src0_qnan
       or ex2_src1_qnan
       or ex2_src0_cnan
       or ex2_src0_nan
       or ex2_src1_nan
       or cp0_vpu_xx_dqnan)
begin
if(ex2_src0_snan && ex2_src1_snan && cp0_vpu_xx_dqnan) // 双 SNaN + dqnan -> 静默 src0
  ex2_special_sel_1_a[8:0] = {4'b0, 1'b1, 4'b0};  // qnan_src0
else if(ex2_src0_snan && ex2_src1_qnan && cp0_vpu_xx_dqnan) // SNaN+QNaN + dqnan -> 静默 src0
  ex2_special_sel_1_a[8:0] = {4'b0, 1'b1, 4'b0};  // qnan_src0
else if(ex2_src0_qnan && ex2_src1_snan && cp0_vpu_xx_dqnan) // QNaN+SNaN + dqnan -> 静默 src1
  ex2_special_sel_1_a[8:0] = {3'b0, 1'b1, 5'b0};  // qnan_src1
else if(ex2_src0_qnan && ex2_src1_qnan && !ex2_src0_cnan && cp0_vpu_xx_dqnan) // 双 QNaN + dqnan -> 静默 src0
  ex2_special_sel_1_a[8:0] = {4'b0, 1'b1, 4'b0};  // qnan_src0
else if(ex2_src0_nan && ex2_src1_nan)         // 仅双 NaN（任意组合）-> 规范 QNaN
  ex2_special_sel_1_a[8:0] = {5'b0, 1'b1, 3'b0};  // cnan
else if(ex2_src0_nan)                          // 单侧 NaN（含 SNaN）-> src1
  ex2_special_sel_1_a[8:0] = {1'b1, 1'b0, 7'b0};  // src1
else                                           // 单侧 NaN（含 SNaN）-> src0
  ex2_special_sel_1_a[8:0] = {1'b0, 1'b1, 7'b0};  // src0
end
```

覆盖文件：`aq_fadd_double_special.v`（唯一 max/min NaN 选择点，覆盖全部精度）。`fmax.s/fmin.s` 与 `fmax.d/fmin.d` 共用同一 FADD 数据通路与 special 模块，一次修复全部覆盖。

## 单指令验证（修复后逐位一致，2026-08-12）

用受控单指令程序（`li`+`fmv.w.x`/`fmv.d.x` 正规 NaN-boxing 置数，mstatus.FS=on）在新 emulator（`artifacts/openc906_rv64fd_1c`，md5 `672e7f34d6335f2d47a195047ab63644`）与 `/opt/riscv/bin/spike --isa=rv64imafdc --log-commits` 上对拍，全部逐位一致：

| 指令 | 操作数 | openc906(修复后) | spike | |
|---|---|---|---|---|
| fmax.s | 1.0, SNaN(0x7faaaaaa) | 0xffffffff3f800000 | 0xffffffff3f800000 | 单 NaN → 非 NaN 操作数 ✓ |
| fmin.s | 1.0, SNaN | 0xffffffff3f800000 | 0xffffffff3f800000 | ✓ |
| fmax.s | 1.0, QNaN | 0xffffffff3f800000 | 0xffffffff3f800000 | ✓ |
| fmax.d | 1.0, SNaN(0x7ff2aaaaaaaaaaaa) | 0x3ff0000000000000 | 0x3ff0000000000000 | ✓ |
| fmin.d | 1.0, SNaN | 0x3ff0000000000000 | 0x3ff0000000000000 | ✓ |
| fmax.d | SNaN, QNaN | 0x7ff8000000000000 | 0x7ff8000000000000 | 双 NaN → 规范 QNaN ✓ |
| fmax.s | SNaN, QNaN | 0xffffffff7fc00000 | 0xffffffff7fc00000 | ✓ |

**单精度与双精度均已验证**。注意 NaN-boxing：非规范 box（上 32 位≠全 1，如 `0xaaaaaaaa7faaaaaa`）被两核一致地视为 NaN（双 NaN → QNaN），因此 rerun8 里那类非规范 box 的 fmax.s 行两边都写 QNaN、无 diff——不是回归，是两核对 NaN-boxing 的一致性行为。

## NaN-boxing（窄值 NaN 装箱）检查：上游已具备，逐位对拍验证通过（2026-08-12）

排查结论：**openc906 的 f32/f16 NaN-box 检查（RISC-V "NaN Boxing of Narrower Values"）上游原厂已实现且正确，无需也不应再加 RTL 修改**。与同族 openc910 不同（openc910 由另一 agent 排查），openc906 的源操作数类型分类器在**上游初始提交（git blame：Ziyi Hao 2021-10-19, `bd92068` "Initial commit"）就包含**这一检查。

### RTL 机制（检查已存在）

`vdsp/rtl/aq_vpu_srcv_type.v` 类型分类器对每个源操作数预先计算分类位，其中 cnan（canonical NaN / 装箱违规）正是 NaN-box 检查（与 spike `isBoxedF32`/`isBoxedF16` 语义逐位对应）：

```verilog
// f32 标量：上 32 位 ≠ 全 1 → cnan（装箱违规）；SIMD 走 src_high/src_vec 另一判据
assign src_single0_cnan  = (inst_simd) ? !(&src_high[47:16] || src_vec) : !(&src[63:32]);
// f16 标量：上 48 位 ≠ 全 1 → cnan
assign src_half0_cnan    = (inst_simd) ? !(&src_high[47:0]  || src_vec) : !(&src[63:16]);
// 装箱违规强制为规范 QNaN（= spike unboxF32/unboxF16 的 defaultNaNF32UI 0x7fc00000 / defaultNaNF16UI 0x7e00）
assign src_single0_qnan  = src_single0_expn_max && src_single0_frac_msb || src_single0_cnan;
assign src_half0_qnan    = src_half0_expn_max   && src_half0_frac_msb   || src_half0_cnan;
// 装箱违规同时从 inf/zero/norm 分类中剔除，避免被误判为合法数值
assign src_single0_inf   = src_single0_expn_max && src_single0_frac_zero && !src_single0_cnan;
assign src_single0_zero  = src_single0_expn_zero && src_single0_frac_zero && !src_single0_cnan;
```

分类位（SINGLE0_CNAN=位41、HALF0_CNAN=位27）随操作数值**同步流动**到全部 FP 单元（dispatch 前向 mux → VIQ 流水线寄存器 → `aq_vpu_group_unit` 纯直通 → 各单元），**无"前向值已更新而类型位陈旧"的泄漏**（`aq_fadd_scalar_dp.v` 中 "TBD, there will be the inner forward path" 注释处的类型位与数值同源 `ex1_srcv0`）。四个单元族全部以 cnan→qnan 门控特殊值路径：VFALU（`aq_fadd_double_special.v`/`aq_fspu_top.v`/`aq_fcnvt_scalar_dp.v`）、VFMAU（`aq_vfmau_special_judge_double.v` `ex1_cnan`）、VFDSU（`aq_fdsu_scalar_dp.v`）。单精度/半精度与双精度共用同一 special 模块，一次覆盖。

### 单指令逐位对拍（当前 emulator md5 672e7f34，与 spike `--isa=rv64imafdc_zfh --log-commits`）

4 组受控程序（非规范 box 源操作数 = 高 32/48 位清零，mstatus.FS=on），覆盖全部 FP 单元族与边界情形，**全部逐位一致**：

| 场景 | 指令 | openc906 | spike | |
|---|---|---|---|---|
| f32 非装箱（高32=0） | fmax.s/fmin.s/fadd.s/fmul.s/fdiv.s/fsqrt.s | 0xffffffff7fc00000（QNaN）或非 NaN 操作数 | 同 | ✓ |
| f32 非装箱 | fcvt.d.s/fcvt.s.d | 0x7ff8000000000000 / 0xffffffff3f800000 | 同 | ✓ |
| f32 非装箱 | fsgnj.s | 0xffffffff7fc00000（QNaN） | 同 | ✓ |
| f32 非装箱 | flt.s/fle.s/fleq/fclass.s | 0 / 0x200 | 同 | ✓ |
| f32 非装箱（含 SNaN/QNaN 位型） | fmadd.s/fmsub.s/fnmadd.s | 0xffffffff7fc00000（规范 QNaN，非 SNaN） | 同 | ✓ |
| f16 非装箱（高48=0） | flt.h/fclass.h/fsgnj.h/fcvt.s.h/fmul.h/fdiv.h | 0x200 / 0xffffffffffff7e00 | 同 | ✓ |
| 合法 box 对照（防回归） | fadd.s(1,2)/fmax.s/fmin.s/fmul.s/fadd.h/fmin.h | 3.0f/2.0f/1.0f/2.0f/2.0h/1.0h | 同 | ✓ |
| 边界：非装箱且低 32 位=S NaN 位型 0x7f800001 | fmax.s/fmin.s/fadd.s/fclass.s/fsgnj.s | 1.0/1.0/QNaN/0x200/QNaN | 同 | ✓ |
| 边界：非装箱且低 32 位=QNaN 载荷 0x7fc00001 | fmax.s/fadd.s/fclass.s | 1.0/0xffffffff7fc00000/0x200 | 同 | ✓ |
| 边界：非装箱且低 16 位=S NaN 位型 0x7e01（half） | fmax.h/fadd.h/fclass.h | 1.0h/0xffffffffffff7e00/0x200 | 同 | ✓ |

对拍程序（`/tmp/spike_min_test/nb{2,3,4}_s.S`，DirectElf 输入链 objcopy→srec→openc_srec2vmem→inst.pat/data.pat，emulator `+cx_trace=`），逐寄存器比对 `fpwrite`/`regwrite`（f0..f31 与整数比较结果 x17..x26）全部一致。**特别地，非装箱且低 32 位为 SNaN 位型的操作数被两核一致地规范化为 QNaN（0x7fc00000）而非当作 SNaN**——这正是"若缺检查会误分类"的判别场景，openc906 处理正确，且与本次已修复的单 SNaN maxNum 逻辑协同无回归（两者机制独立：NaN-box 在类型分类器、maxNum 在 special 模块）。

**结论：openc906 无需 NaN-box 的 RTL 修改**（该检查上游已实现且与 spike 逐位一致；修改只会引入风险）。本次仅针对同族 openc910 的同类检查缺口进行排查（另一 agent 并行负责）。

## 对 diff-fuzz 的意义

openc906 与 spike 在 maxNum/minNum 上**真实的架构性分歧**（openc906 对单 SNaN 错误返回规范 QNaN），不是 fuzz 框架误报。trace 插桩直接采样 FPU 写回总线，忠实反映 RTL。任何 fuzz 测试中 fmax/fmin 恰好遇到 SNaN 单操作数，都会造成 fp 寄存器写入值差异被误报。修复 RTL 并重编译后该差异从矩阵消失。

## 附录：关键信号位置

- `aq_fadd_double_special.v`：`ex2_src0_nan`/`ex2_src1_nan`（:270-271）、`ex2_special_sel_1_a` max/min NaN 选择（:335-358）、`ex2_nv_sel`（:280）、`fadd_ex2_float_nv`/`ex2_special_value_vld`（:547-554）
- `aq_fadd_double_dp.v`：`ex2_double_rslt = special_value_vld ? special_data : (op_sel ? sel_final_f : addsub)`（:288-290）
- `aq_idu_id_decd.v`：fmin.d/fmax.d/fmin.s/fmax.s 解码到 `EU_FALU`（FUNC_FMIND/FMAXD/FMINS/FMAXS，:2465-2473/:2640-2648）
- Spike 参考：`riscv-isa-sim/riscv/insns/fmax_d.h`（maxNum，单 NaN 返回另一操作数；`f64_lt_quiet`/`f64_eq` 不置 NV）
- 复现：`artifacts/diff_spike_execfix_20260810_new/fresh_all_50_lowp12_rerun8/rv64_openc906/case_01/.../pass_000/` 与 `case_03/.../pass_000/`
