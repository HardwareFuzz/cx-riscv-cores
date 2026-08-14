# openc910: f32/f16 源操作数读取缺 NaN-box 检查（未合法 box 值被当普通数值）

> 分类：**新 bug 新修复**（riscv_fuzz_test 未记录，fuzz bugs 目录无 openc910）

> Status: **upstream-inherent（T-Head 原厂 RTL 缺陷）。本 fork 已修复、重编译并 replay/单指令验证通过（2026-08-12）**。
> Dated 2026-08-12。由 HardwareFuzz riscv_fuzz_test diff-spike 矩阵复现（rv64_openc910 rerun8 case_02，#92，`fmin.s f17, f20, f16` 单指令可稳定复现），单指令复现 + 全用例 replay 验证通过。
> 影响：openc910-vs-spike 差分测试的 f32/f16 窄精度指令写值误报——**openc910 真实缺陷**，非 fuzz 框架/解析误报。spike 参考侧行为正确（符合 RISC-V spec NaN Boxing）。

## 概述

RISC-V F/D 扩展的 NaN-boxing 规则（spec "D" 扩展章节 "NaN Boxing of Narrower Values"）：**除 transfer 指令（fmv.*/load）外，所有窄精度（n<FLEN）浮点运算读取寄存器时检查其是否被正确 NaN-boxed（高 FLEN−n 位全 1）；若未正确 box，该输入视为 n-bit canonical NaN**（f32: 0x7fc00000，f16: 0x7e00）。写侧规则：窄精度运算写回时必须把高位置全 1（NaN-box）。

Spike 参考实现（`riscv-isa-sim/riscv/decode_macros.h` L273-283）对每个窄精度源做 unbox 检查：

```c
#define isBoxedF32(r) (isBoxedF64(r) && ((uint32_t)((r.v[0] >> 32) + 1) == 0))
#define unboxF32(r)   (isBoxedF32(r) ? (uint32_t)r.v[0] : defaultNaNF32UI)  // 0x7fc00000
#define isBoxedF64(r) ((r.v[1] + 1) == 0)
```

openc910 的 FPU **写侧严格 NaN-box（正确），但读侧完全没有检查**：窄精度源操作数直接取 64 位寄存器值低部分（`fadd_scalar_dp.v`/`fcnvt_scalar_dp.v`/`fspu_dp.v`/`vfdsu_scalar_dp.v` 中 `assign src = dp_*_srcf*[63:0]`）。当寄存器高位置了非全 1 值（如测试框架用 64 位随机值 `0xaaaaaaaa_3f800000` 表示"1.0f 未 box"），openc910 把它当普通 1.0f 参与 minNum/maxNum，而 spike 按 spec 视为 canonical QNaN。

## 复现

- 来源：`artifacts/diff_spike_execfix_20260810_new/fresh_all_50_lowp12_rerun8/rv64_openc910/case_02/`，全局索引 248，`fmin.s f17, f20, f16`。
- 输入（single_instruction_diff_001 复现，`fld f16, 0(x16)` 从内存载入 64 位随机值）：
  - f16 = 0xaaaaaaaa_3f800000（低 32 位 = 1.0f，但高 32 位非全 1 → **未合法 NaN-box**）
  - f20 = 0xffffffff_ff800001（-SNaN，合法 box）
- openc910（旧二进制）写 `f17 = 0xffffffff_3f800000`（把未 box 的 f16 当 1.0f，minNum 返回非 NaN 操作数）——**违反 NaN-boxing**；
- spike 写 `f17 = 0xffffffff_7fc00000`（未 box 源视为 canonical QNaN → 双 NaN → QNaN）——**符合 spec**。

同族 f16 案例：`fmin.h`（rerun8 case_05 未落地，但单指令验证覆盖），`f16=0xaaaaaaaa_aaaa0001` 高 48 位非全 1 → canonical half QNaN 0x7e00。

## 根因（决定性证据）

四个窄精度源读取点均直通 64 位寄存器值，无 NaN-box 检测：

- `vfalu/rtl/ct_fadd_scalar_dp.v` L222-223：`assign fadd_ctrl_src0[63:0] = dp_vfalu_ex1_pipex_srcf0[63:0];`（fadd/fsub/fmul? 见下/fmin/fmax/fcvt.cmp/half 全系列，f32 与 f16 共用 double 数据通路）
- `vfalu/rtl/ct_fcnvt_scalar_dp.v` L239-240：`assign ex1_src0[63:0] = dp_vfalu_ex1_pipex_srcf0[63:0];`（fcvt 系列源）
- `vfalu/rtl/ct_fspu_dp.v` L164-165：`assign ex1_pipex_src0[63:0] = dp_vfalu_ex1_pipex_srcf0[63:0];`（fsgnj/fclass/fmv 系列源，其中 fmv 为 transfer 不检查、fsgnj/fclass 需检查）
- `vfdsu/rtl/ct_vfdsu_scalar_dp.v` L194-195：`assign ex1_src0[63:0] = dp_vfdsu_ex1_pipex_srcf0[63:0];`（fdiv/fsqrt 源）

整个 `C910_RTL_FACTORY/gen_rtl/` 无任何 NaN-box 检查逻辑（`grep -rn nan_box` 为空）。

## 修复（2026-08-12）

在四个源读取点各插入组合 NaN-box 检查（只读侧，写侧严格 box 正确未动）：

- 判定：f32 合法 box = `srcf[63:32] == 32'hffffffff`；f16 合法 box = `srcf[63:16] == 48'hffffffffffff`；f64 直通。
- 未合法 box 时源替换为 canonical NaN：f32 → `{32'hffffffff, 32'h7fc00000}`，f16 → `{48'hffffffffffff, 16'h7e00}`（保持 NaN-boxed 写格式）。
- 精度选择：
  - fadd/fcnvt/vfdsu：用组合 `func[16]`(double)/`func[15]`(single)/`!single&&!double`(half) 判定（vfdsu 用 `idu_vfpu_rf_pipex_func` 组合位，因为其 ex1_single 是时序 flop，不能同拍门控源）。
  - fspu：`func[6]`(fsgnj)/`func[18]`(fclass) 触发，`func[5]`(fmv) 排除（transfer 指令不检查）。
- 覆盖文件（均在 `C910_RTL_FACTORY/gen_rtl/`）：
  - `vfalu/rtl/ct_fadd_scalar_dp.v`（fadd/fsub/fmin/fmax/fcvt.cmp 全系列 + f16）
  - `vfalu/rtl/ct_fcnvt_scalar_dp.v`（fcvt.* 源）
  - `vfalu/rtl/ct_fspu_dp.v`（fsgnj.s/.h + fclass.s/.h，fmv.* 除外）
  - `vfdsu/rtl/ct_vfdsu_scalar_dp.v`（fdiv/fsqrt f32/f16）

## 验证

- **单指令对拍**（新 Vtop vs spike `--isa=rv64imafdc_zfh --log-commits`，10 用例程序，全数一致）：
  - `fmin.s` 未 box 源 → 0xffffffff_7fc00000（=spike）✓；合法 box → 0xffffffff_3f800000（1.0f）✓
  - `fmin.d` SNaN+1.0 → 0x3ff0000000000000（1.0）✓（f64 不受影响）
  - `fmin.h` 未 box 源 → 0xffffffff_ffff7e00（=spike）✓；合法 box → 0xffffffff_ffff3c00（1.0h）✓
  - `fadd.s`/`fmul.s` 常规合法 box 值 → 逐位不变（3.0f/6.0f）✓（无回归）
  - `fcvt.s.d`/`fsgnj.s` 常规值 → 逐位不变 ✓
  - `fsgnj.s` 未 box rs1 → 0xffffffff_7fc00000（=spike）✓
- **replay case_02**（全量 1129 指令用例，新 Vtop）：pass_000 中 fmin.s 写 `0xffffffff_7fc00000` 与 spike 一致，`report_01_write_diff` 不再含该差异。
- **emulator md5**：`smart_run/work/obj_dir/Vtop` 786ca8b0 → **1fd5b277**（`--clean` 强制重编，2026-08-12 12:52）。已部署到 `cx-riscv-cores/artifacts/openc910_rv64fd_1c`（插件经 `CX_RISCV_CORES_OPENC910_RV64FD_1C` 读取）与 `riscv_fuzz_test/dist/docker-binary/cx-riscv-cores/artifacts/openc910_rv64fd_1c`；旧版备份为 `*.bak_pre_nanboxfix`。

## 对 diff-fuzz 的意义

这是 openc910 与 spike 在 NaN-boxing 上**真实的架构性分歧**（openc910 读侧不检查、把未合法 box 的窄精度源当普通数值），不是 fuzz 框架误报。diff 框架 normalize 层（`crates/riscv-fuzz-diff/src/normalize.rs` `canonicalize_nan_write_values_for_diff`）只合并 NaN sign/payload 差异，不会掩盖"NaN vs 非 NaN"分叉，故该差异被正确检出。测试框架用 64 位随机立即数初始化 FPR/内存，会产生大量未合法 box 的 f32/f16 值，任何窄精度指令（fmin/fmax/fadd/fsgnj/fclass/fcvt/fdiv…）读到都会误报。修复 RTL 并重编译后该差异从矩阵消失。

## 附录：关键信号位置

- `ct_fadd_scalar_dp.v`：源直通 L222-223（改后替换为 `fadd_src*_nanboxed`），精度 `ex1_single=func[15]`/`ex1_double=func[16]`，half = `!single && !double`
- `ct_fcnvt_scalar_dp.v`：源直通 L239-240，精度 `ex1_src_single`/`ex1_src_l16`
- `ct_fspu_dp.v`：源直通 L164-165，`ex1_op_fsgnj*=func[6]`、`ex1_op_class=func[18]`、`ex1_op_fmvfx/fmvxf=func[5]`
- `ct_vfdsu_scalar_dp.v`：源直通 L194-195，精度用组合 `idu_vfpu_rf_pipex_func[15]/[16]`
- Spike 参考：`riscv-isa-sim/riscv/decode_macros.h` L269-276（isBoxed/unbox）、`riscv/insns/fmin_s.h` 等（minNum/maxNum 逻辑本身 f32/f64 一致且正确，分歧仅在源读取）
- 复现：`artifacts/diff_spike_execfix_20260810_new/fresh_all_50_lowp12_rerun8/rv64_openc910/case_02/spike_openc910_rv64/rv64_case_000_w00_1786501882_140389860/pass_000/`
- 单指令对拍程序：`/tmp/fmin_test/test.S`（10 用例，spike 期望值已记录）
