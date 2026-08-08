# CX Trace V2：跨 RISC-V 核心的周期与指令终结规范

## 1. 目的

CX Trace V2 为 `cx-riscv-cores` 中不同流水线、不同发射宽度和不同 hart 数量的核心定义统一的周期口径。规范的主要用途是计算 ROI 周期、IPC/CPI 和后端驻留延迟；Verilator 的宿主机 wall-clock 时间不属于本规范。

本规范区分两类指标：

- 主要性能指标：ROI 周期、retired architectural instruction 数、IPC/CPI；
- 诊断指标：单条动态指令从后端分配到架构提交或精确异常的驻留时间。

单条指令的平均驻留时间不能代替 IPC/CPI，因为多个 OoO 指令的驻留区间可以重叠。

## 2. 周期域

- `cycle=0` 仅用于 reset 有效期间；
- reset 释放后的第一个有效 CPU 参考时钟上升沿为 `cycle=1`；
- 在一个上升沿观察到的 allocation、commit、trap、writeback 或 memory 事件都记录该上升沿的 cycle；
- counter 为 64 位；
- 双核或多核实例共享同一个顶层参考时钟周期域；
- counter 不受 `mcountinhibit` 影响，不使用宿主机时间；
- 所有区间都是闭区间，`span=end_cycle-start_cycle+1`。

实现可以保留核心原有 counter，但必须用断言或测试证明它符合上述定义。双核实现优先使用一个共享 counter。

## 3. 动态指令身份

每个 hart 独立维护：

- `token`：在 backend allocation 时分配的 64 位唯一 ID。错误路径指令可以消耗 token，因此 terminal trace 中允许缺号；
- `term_seq`：第一条 architectural terminal record 为 0，此后每次 terminal event 递增，包括 normal commit 和 synchronous precise trap，必须连续；
- `instret_seq`：第一条 `retired=1` record 为 0，此后仅在 retired instruction 上递增，应能和 `minstret` 交叉验证。

PC、ROB index、scoreboard index、OpenC iid 或内部 uop ID 都不能代替 `token`。这些内部 ID 可以作为额外字段输出。

## 4. 开始事件

主时间字段的开始语义固定为：

```text
start_kind=backend_alloc
start_cycle=指令第一次被后端正式接收并获得可追踪 token 的周期
```

映射规则：

- 顺序核：ID/decode 指令正式进入执行流水线；
- scoreboard 核：scoreboard entry allocation；
- ROB/OoO 核：rename/dispatch 成功 enqueue ROB；
- replay：必须复用第一次 allocation 的 token 和 start cycle；
- macro/split instruction：使用原始 architectural instruction 的第一个 uop allocation；
- fetch、首次看到 PC、issue、writeback 都不是 V2 主 start。

指令可以在控制流推测下获得 token。被 squash 的 token 不产生 architectural terminal record。

## 5. 结束事件

正常指令：

```text
end_kind=arch_commit
retired=1
end_cycle=architectural commit/retire 周期
```

同步异常：

```text
end_kind=precise_trap
retired=0
end_cycle=导致异常的指令在精确异常边界终结的周期
```

中断没有对应 allocation token，必须使用独立的 `event=interrupt`。不得构造伪指令，也不得增加 `instret_seq`。

store 的主 end 是 store commit，不是 store buffer drain、cache write 或总线可见。长延迟 load/div/FPU/RoCC/vector 指令的主 end 是 architectural retire；较晚的物理寄存器写回使用辅助事件。

## 6. architectural instruction 与 uop

- compressed instruction 是一条 architectural instruction；
- CVA6 Zcmp、OpenC906 split instruction 等扩展产生的多个内部 uop，只生成一条主 terminal record；
- 一条指令的多个寄存器写或内存副作用不能生成多条主 terminal record；
- 多提交核心在同一周期生成多条记录，并使用 `commit_slot` 表示从老到新的顺序；
- retired 计数按 architectural instruction，而不是 uop。

## 7. 主记录格式

实现可以继续输出 legacy 行，但必须额外输出或可无歧义转换为以下记录：

```text
CXTRACE v=2 event=inst_terminal core=<name> hart=<h> token=<token> \
  term_seq=<seq> instret_seq=<seq> commit_slot=<slot> \
  pc=<pc> insn=<architectural-insn> insn_len=<2|4> \
  start_cycle=<alloc> end_cycle=<terminal> span=<inclusive-span> \
  start_kind=backend_alloc end_kind=<arch_commit|precise_trap> \
  retired=<0|1> trap=<0|1> cause=<cause> priv=<mode>
```

`cause` 使用统一的无歧义编码：普通 architectural commit 必须写
`cause=none`；只有 precise synchronous trap 才写数值异常 cause（十进制或
`0x` 前缀十六进制）。不能用 `cause=0` 表示“无异常”，因为 RISC-V cause 0
本身表示 instruction-address-misaligned。interrupt 的 cause 仍只出现在独立的
`event=interrupt` 记录中。

实现可以额外输出 `start_valid=1`，用于暴露内部 metadata-valid 位；一旦输出该
字段，其值必须为 `1`，`start_valid=0` 是硬错误。没有显式输出该字段的实现仍必须
通过非零 `start_cycle`、动态 token 和 RTL assertion 证明 allocation metadata
存在，不能在 host 端用 `start=end` 补造缺失的开始事件。

目标寄存器和内存字段可以附加在同一行。未知但可在 host 端从 ELF 恢复的 `insn` 必须注明来源，不能根据最近一次相同 PC 猜测动态身份。

辅助记录：

```text
CXTRACE v=2 event=writeback hart=<h> token=<token> cycle=<cycle> ...
CXTRACE v=2 event=memory_req hart=<h> token=<token> cycle=<cycle> ...
CXTRACE v=2 event=memory_resp hart=<h> token=<token> cycle=<cycle> ...
CXTRACE v=2 event=store_visible hart=<h> token=<token> cycle=<cycle> ...
CXTRACE v=2 event=interrupt hart=<h> cycle=<cycle> cause=<cause>
CXTRACE v=2 event=squash hart=<h> token=<token> cycle=<cycle> ...
```

辅助记录不能修改主记录的 `end_cycle`。

## 8. 运行头

每次 trace 至少提供：

```text
trace_version=2
cycle_domain=core_ref_clk
cycle_base=first_post_reset_posedge_is_1
interval=inclusive
start_kind=backend_alloc
end_kind=arch_commit_or_precise_trap
core=<name>
harts=<count>
isa=<isa>
build_config=<config>
```

header 的固定值必须逐项匹配本节和第 2 节的定义。同一次运行中的重复 header 必须
一致；`core` 必须与 terminal/interrupt record 一致，`harts` 必须覆盖且只能覆盖该
发布产物的 hart 编号。字段名不能重复，64 位 token/sequence/cycle 不能溢出，
`priv` 只允许 RISC-V 的 U/S/M 编码 `0/1/3`。

## 9. ROI

每 hart 使用两个普通、可提交的 marker 指令，并从 ELF 符号表获取其 PC：

```asm
cx_roi_begin_hN:
    addi x0, x0, 0
    # payload
cx_roi_end_hN:
    addi x0, x0, 0
```

定义：

```text
roi_start_cycle = begin marker.start_cycle
roi_end_cycle   = end marker.end_cycle
roi_cycles      = roi_end_cycle - roi_start_cycle + 1
```

marker 本身不进入 retired/useful instruction 分母。双核在 marker 前使用统一 ready/release barrier，不能把固定 hart stagger 计入 ROI。

集成层可以在 begin marker 前发射一条固定宽度的 framework guard NOP，用于把核心模板的 testcase 标签与全局 marker 符号分配到不同地址；该 guard 必须位于 ROI 外，且不得占用 payload 的 source instruction identity。

报告至少包含每 hart ROI cycles、retired、IPC/CPI，以及共享周期域下的 aggregate IPC。`mcycle/minstret` 可以作为交叉验证，但不能替代 trace ROI。

## 10. 强制验证

每个发布核心必须证明：

1. 每个主记录满足 `1 <= start_cycle <= end_cycle` 和 inclusive span；
2. token 每 hart 唯一，term_seq 连续，instret_seq 只在 retired 时递增；
3. 每 hart 按 term_seq 观察到的 `end_cycle` 单调不减，同周期记录的 commit_slot
   从 0 连续递增；
4. 正常 retired 数与 `minstret` 一致；
5. 同 PC 循环产生多条不同 token 的记录；
6. 错误路径没有 terminal record；
7. trap 能回溯到原 start，interrupt 不伪装成指令；
8. macro/split instruction 只生成一条主记录；
9. store visibility 和晚到 writeback 不延长主 end；
10. ROB/scoreboard/iid 回绕不会读取陈旧 metadata；
11. trace on/off 不改变架构结果和模拟周期数；
12. 1c/2c 使用相同字段语义且双核 hart 不串线；
13. 缺少 start metadata 必须显式报错，不能静默伪造 `start=end`。
