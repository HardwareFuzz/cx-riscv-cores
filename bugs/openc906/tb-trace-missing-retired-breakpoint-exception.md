# OpenC906 trace bug — commit `exc_cause` misses the retired breakpoint exception

> Status: **draft** — internal record for the HardwareFuzz diff-fuzz fork of the
> XuanTie OpenC906. Already fixed and rebuilt in our fork (see "Fix verification").
> Dated 2026-08-11.

---

**Title:** [TB][BUG] OpenC906 Verilator trace omits `exc_cause` for a retired `ebreak` (breakpoint exception, mcause=3)

## Description

Per the RISC-V Privileged ISA spec (v1.12, Table 3.6), an `ebreak` executed in
non-debug mode raises a **breakpoint exception** with `mcause=3`. A reference
model such as Spike therefore reports an exception for the `ebreak` instruction,
and any trace-driven diff harness must observe the same exception on the DUT side
or it will produce a false positive ("DUT committed, no exception; Spike trapped").

The OpenC906 Verilator testbench builds the architectural commit line
(`commit cycle=... hart=0 pc=... [exc_cause=...]`) by sampling only the EX2-stage
instruction-exception signal:

```
commit .../x_aq_rtu_dp.dp_retire_ex2_inst_expt
```

That signal is `dp_ex2_inst_expt` (the EX1→EX2 pipeline synchronous exception:
illegal instruction, ecall, instruction access/page fault, load/store misaligned,
access/page fault). It is **not** asserted for `ebreak`, because the breakpoint
exception is generated one stage later, at retire
(`retire_bkpt_expt` in `aq_rtu_retire`). Result: when the CPU retires an `ebreak`,
the trace line carries no `exc_cause`, the diff framework sees no exception on the
openc906 side, and the compare against Spike (which traps with mcause=3) reports a
false mismatch.

## Root cause chain

1. `smart_run/logical/tb/tb_verilator.v:826` (pre-fix) and the identical
   `smart_run/logical/tb/tb.v:636` sample only the **EX2** instruction exception:
   ```verilog
   if(`CPU_TOP.x_aq_top_0.x_aq_core.x_aq_rtu_top.x_aq_rtu_dp.dp_retire_ex2_inst_expt) begin
     $fwrite(cx_trace_file, " exc_cause=%0d",
             `CPU_TOP.x_aq_top_0.x_aq_core.x_aq_rtu_top.x_aq_rtu_dp.dp_retire_ex2_vec[4:0]);
   end
   ```
2. `C906_RTL_FACTORY/gen_rtl/rtu/rtl/aq_rtu_dp.v:515` forwards the EX1/EX2 pipeline
   exception unchanged: `assign dp_retire_ex2_inst_expt = dp_ex2_inst_expt;`
   (and `:520` `dp_retire_ex2_vec = dp_ex2_expt_vec`).
3. `ebreak` is **not** in that EX1/EX2 vector. The breakpoint is raised at retire:
   `C906_RTL_FACTORY/gen_rtl/rtu/rtl/aq_rtu_retire.v:687-690`
   `bkpt_req_ebreak = retire_ex2_retire_vld && !dtu_rtu_ebreak_action && dp_retire_ex2_inst_ebreak && ...`,
   folded into `retire_bkpt_expt` (`:702`) and into the retire instruction
   exception `retire_inst_expt = dp_retire_ex2_inst_expt || retire_bkpt_expt` (`:447`),
   then `retire_sync_expt` (`:455`), and finally into the priority-encoded trap
   vector `retire_trap_vec` (`:490-501`, breakpoint → `5'd3`).
4. So the retire stage *does* expose everything needed via
   `retire_trap_vld`/`retire_trap_int`/`retire_sync_expt`/`retire_trap_vec`
   (`aq_rtu_retire.v:585/589/455/490`, also re-exported as `rtu_yy_xx_expt_*` at
   `:1153-1155`), but the legacy commit trace never consulted those signals.
   Note the newer CX V2 trace path in the same testbench
   (`tb_verilator.v:295-298, 620-632`) already uses exactly this retire-level
   detection (`retire_trap_vld && !retire_trap_int && retire_sync_expt` with
   `retire_trap_vec`), which is why V2 terminals already carried the breakpoint
   while the legacy `commit` line did not.

## Repro / observed behavior

Run any RV64 program that executes `ebreak` (non-debug, M-mode) through the
`openc906_rv64fd_1c` Verilator binary (pre-fix). Spike traps the same instruction
with `mcause=3`:

- **Expected in `openc906_trace_hart_00000000.log`:**
  ```
  commit cycle=... hart=0 pc=0x... exc_cause=3
  ```
- **Observed (pre-fix):**
  ```
  commit cycle=... hart=0 pc=0x...
  ```
  i.e. the commit line for the `ebreak` carries **no** `exc_cause` field, while
  illegal instructions / ecall / page faults (which DO assert
  `dp_retire_ex2_inst_expt`) still produced `exc_cause=2` / `exc_cause=11` / etc.
  The diff framework then records "no exception" on the openc906 side and
  mismatches Spike's breakpoint trap.

## Proposed fix (testbench diff)

In both `smart_run/logical/tb/tb_verilator.v` and `smart_run/logical/tb/tb.v`,
replace the EX2-only sample with the retire-level synchronous-exception sample,
using the same signals the CX V2 trace already uses:

```verilog
if(`RTU_RETIRE.retire_trap_vld
   && !`RTU_RETIRE.retire_trap_int
   && `RTU_RETIRE.retire_sync_expt) begin
  $fwrite(cx_trace_file, " exc_cause=%0d", `RTU_RETIRE.retire_trap_vec[4:0]);
end
```

(`tb.v` uses the full hierarchical path
`CPU_TOP.x_aq_top_0.x_aq_core.x_aq_rtu_top.x_aq_rtu_retire.<signal>` because it
does not define the `RTU_RETIRE` macro.)

Why this is correct and complete:

- `retire_sync_expt` = `retire_inst_expt || retire_pending_bkpt_expt`, and
  `retire_inst_expt` = `dp_retire_ex2_inst_expt || retire_bkpt_expt`
  (`aq_rtu_retire.v:447,455`) — so it covers **every** previously-sampled EX2
  exception (illegal=2, ecall=8/9/11, page fault=12/13/15, misaligned=4, access
  fault=1/5/7) **plus** the retired breakpoint (ebreak/trigger → 3) and pending
  breakpoint (3).
- `retire_trap_vec` priority-encodes the same cause the CPU writes to `mcause`
  (`aq_rtu_retire.v:490-501`): pending bkpt → 3, bkpt → 3, else
  `dp_retire_ex2_vec` — so non-breakpoint causes keep their existing values.
- `!retire_trap_int` keeps the `exc_cause` field exception-only (interrupts
  remain out of the legacy trace), identical to the CX V2 `cx_v2_sync_trap`
  definition already in the file.
- Purely an observation/testbench change: no RTL, no simulator runtime interface,
  no trace-line-format change.

## Fix verification (in our fork)

- Rebuilt the Verilator binary (`./build.sh --isa rv64fd --cores 1
  --out-dir .../artifacts`), overwriting `artifacts/openc906_rv64fd_1c`
  (new timestamp; see report).
- Ran an RV64 ELF containing `ebreak` through the rebuilt binary: the trace
  commit line for the `ebreak` now carries `exc_cause=3`, matching Spike's
  breakpoint trap (mcause=3). Pre-fix the same line carried no `exc_cause`.
- Existing exception traces are unchanged for the non-breakpoint causes
  (`exc_cause=2` for illegal, `exc_cause=11` for ecall still emitted), confirming
  no regression on the previously-captured path.
