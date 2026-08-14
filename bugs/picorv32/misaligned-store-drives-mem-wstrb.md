# PicoRV32: misaligned store 仍驱动 mem_wstrb（应 trap 且不发写使能）（上游 bug）

> 分类：**旧 bug 新修复**（riscv_fuzz_test `bugs/picorv32/2` 已记录，完全重复）

> Status: **confirmed spec violation（上游 YosysHQ/picorv32 原始 bug）** — 已在 fork `cx-build`
> 分支修复（000efde，父仓库 bump ac94ce6，2026-05-11），当前发布子模块指针 e12010c 已含。
> Dated 2026-08-13（审计归档；修复于 2026-05-11）。由 HardwareFuzz riscv_fuzz_test diff-spike
> 矩阵于修复当时（2026-05）复现；当前 20-case 矩阵（fresh_all_20_single_20260813 rv32_picorv32）
> 已 20/20 干净、0 write rounds，无复发。
> 归属：**上游原厂**。`git show upstream/main:picorv32.v` 的写数据总线仍为
> `mem_wstrb <= mem_la_wstrb & {4{mem_la_write}}`（无 misaligned 保护），fork 修复是新增
> `store_misaligned` 门控，非上游已有行为。

---

## 概述

RISC-V 对 misaligned 访存的异常语义：`CATCH_MISALIGN`（PicoRV32 的 misaligned trap 开关）开启时，
misaligned 的 load/store 必须进入 trap 路径，**不得真正写内存、不得向总线发出写使能**。

PicoRV32 上游写数据总线把 `mem_la_wstrb` 原样透传：

```verilog
// 上游 YosysHQ/picorv32 picorv32.v:576
mem_wstrb <= mem_la_wstrb & {4{mem_la_write}};
```

没有 misaligned 保护。当一条 misaligned store（如 `sw` 到非 4 字节对齐地址）进入 memory 阶段时，
即使 trap 逻辑随后把 `cpu_state` 转走，`mem_wstrb` 已把写使能透传到总线（latched_store 仍保持），
产生一个**实际的内存写或总线写使能**——违反「misaligned trap 不得写内存」，并与 spike 分歧。

## 根因

上游 `picorv32.v` 的 memory 写使能生成不感知 `store_misaligned`：

```verilog
// 上游 :576（无任何 misaligned 门控）
mem_wstrb <= mem_la_wstrb & {4{mem_la_write}};
```

对照上游的 MISALIGNED trap 分支（:1923 起）只在 `cpu_state` 上转 trap，没有同时清零
`mem_wstrb`/`latched_store`，因此写使能在 trap 判定后仍可发射。

（注：fork 内部早期有数个实验分支分别尝试补齐——`origin/bug` 的 `fc69431`/`3a77012`
（2025-10-19/20，「fix bug 1/2」，latched_* 清零 + wstrb 门控雏形）、`picorv32_origin2` 的
`a3ac56c`（AXI-Lite wstrb 保护）、`9e3f911`（misaligned load trap 抑制写回）——均未合并到
`cx-build` 发布线；最终发布实现是 000efde 统一整合：新增 `store_misaligned` 信号并用它门控
`mem_wstrb`，同时对 staged store 修正 misaligned 检查地址。）

## 修复（fork，000efde，已发布）

`picorv32.v`：

```verilog
wire [31:0] mem_write_addr = reg_op1 + decoded_imm;
wire [31:0] mem_store_addr_check = mem_do_wdata ? reg_op1 : mem_write_addr;
wire store_misaligned = CATCH_MISALIGN && resetn &&
        ((instr_sw && |mem_store_addr_check[1:0]) ||
         (instr_sh && mem_store_addr_check[0]));
...
// write 总线门控
mem_wstrb <= (store_misaligned ? 4'b0000 : mem_la_wstrb) & {4{mem_la_write}};
```

- misaligned store 命中时把 `mem_wstrb` 清 0，不发写使能，与 trap 语义一致。
- staged store（`mem_do_wdata`）场景用 `reg_op1`（存地址）而非 `mem_write_addr` 检查，避免
  检查到错误的地址。

## 对 diff-fuzz 的意义

misaligned store 在 spike（正确 trap、不写内存）与上游 PicoRV32（发出总线写使能）之间产生
真实的 mem 写差异。修复后该差异从矩阵消失；当前 20-case 矩阵 rv32_picorv32 全 0 write rounds。

## 附录：上游对照位置

- 上游（YosysHQ/picorv32 `upstream/main`）`picorv32.v:576`：`mem_wstrb <= mem_la_wstrb & {4{mem_la_write}}`（无保护）
- 上游 `picorv32.v:1923`：MISALIGNED WORD trap 分支（只转 cpu_state，不清 wstrb）
- fork 修复：`cx-build` HEAD `e12010c`，`picorv32.v:603`（wstrb 门控）、`:1439`（store_misaligned）
- 父仓库 bump：`ac94ce6`（2026-05-11，cores/picorv32 → 000efde）
