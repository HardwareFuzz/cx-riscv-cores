# Kronos: accesses to unimplemented CSRs silently return 0 / are ignored instead of raising an illegal-instruction exception

> Status: **fixed in our fork** (cx-build / cx-2hart-build branches), verified against a rebuilt Verilator simulator.
> Dated 2026-08-11. Root-caused, fixed, and verified locally; no upstream PR posted yet.
> Affects the HardwareFuzz RISC-V diff-fuzz framework: Kronos is diffed against Spike, which
> traps (mcause=2) on any access to a CSR it does not implement — Kronos did not, producing
> false positives.

---

**Title:** [BUG] Kronos does not raise an illegal-instruction exception (mcause=2) for accesses to unimplemented CSRs; reads silently return 0 and writes are silently dropped

## Description

Per the RISC-V Privileged Architecture spec (v1.11, §2.1 "Control and Status Registers"), "any
read or write of a CSR that does not exist in the implementation must raise an illegal instruction
exception." Equivalently, the base ISA spec's Zicsr chapter requires `CSRRW/CSRRS/CSRRC` (and their
immediate forms) to raise an illegal-instruction exception (mcause=2) when the addressed CSR is not
implemented.

Kronos instead:

- decodes **every** CSR instruction as valid regardless of the CSR address field `IR[31:20]`, and
- in the CSR unit, a read of an unhandled CSR address falls through the `case(addr)` with no
  `default` arm, leaving `csr_rd_data = '0` (a silent read of zero), and a write to an unhandled
  address falls through the write `case(addr)` with no `default`, silently discarding the write.

Consequence for diff-fuzz: the HardwareFuzz framework compares Kronos against Spike. Spike traps
with mcause=2 on `csrr/csrw` of a CSR it does not implement, whereas Kronos commits the instruction
retired and writes back 0 (or no-ops the write). The two cores therefore diverge on the same
program: Spike reports a precise trap, Kronos reports a retired instruction with `rd=0` — a false
positive that the framework surfaces as an instruction-count / trap mismatch.

## Root cause chain

All in `cores/kronos` (submodule branch `cx-build` at `ff50f36`; the dual-core `cx-2hart-build`
branch shares the same defect).

1. `rtl/core/kronos_ID.sv` lines 326-338 — the `INSTR_SYS` decoder arm. For `funct3` 001 (CSRRW),
   010 (CSRRS), 011 (CSRRC), 101 (CSRRWI), 110 (CSRRSI), 111 (CSRRCI) it unconditionally sets
   `csr = 1'b1; instr_valid = 1'b1;`. No check is made on the CSR address `IR[31:20]`, so every
   CSR instruction is accepted, including ones whose address is not implemented.
2. `rtl/core/kronos_csr.sv` lines 185-219 — the read `always_comb` block. `csr_rd_data` is
   initialized to `'0` and the `case(addr)` covers only the 12 implemented CSRs
   (MSTATUS/MIE/MTVEC/MSCRATCH/MEPC/MCAUSE/MTVAL/MIP/MCYCLE/MINSTRET/MCYCLEH/MINSTRETH) with no
   `default` arm. Any other address keeps `csr_rd_data = 0` → silent read of 0.
3. `rtl/core/kronos_csr.sv` lines 247-285 — the write `always_ff` block. The `case(addr)` on
   `csr_wr_en` has no `default` arm either, so writes to unimplemented CSRs are silently ignored
   (and the sequencer still returns `csr_rdy` normally at `WRITE`, line 123, so the instruction is
   retired as if it succeeded).
4. `rtl/core/kronos_EX.sv` line 543 — `exception` is assembled from `decode.illegal` (plus
   misaligned access flags). Since the decoder never flags CSR instructions as illegal, none of
   them reach the `decode.illegal` → `ILLEGAL_INSTR` trap path (lines 552-554, which set
   `trap_cause = {28'b0, ILLEGAL_INSTR}` and `trap_value = decode.ir`).

There is no separate signal from the CSR unit back to the execute/decode stage to report an unknown
CSR address; the CSR unit has no trap output at all.

## Repro / observed behavior

Before the fix, on the rebuilt Verilator simulator:

- `csrr a0, 0xC00` (or any unimplemented address such as 0x7FF) executes, writes `a0 = 0`, and the
  instruction is retired — the CX trace logs an `inst_terminal` with `retired=1 trap=0`, no `[TRAP]`
  line, no exception.
- `csrw 0x7FF, a5` executes, discards the write, and is retired the same way.
- Spike, run on the same program, raises a precise trap with `mcause=0x2` (`cause=0x2`), and the
  framework's cross-core comparison reports the divergence.

## Proposed fix

Gate CSR decode on the set of CSRs actually implemented by `kronos_csr`, so that any other CSR
address marks the instruction illegal and reuses the existing illegal-instruction trap path
(mcause=2, mtval=instruction word).

`rtl/core/kronos_ID.sv` — add a combinational CSR-address validity check and use it in the CSR
decode arms:

```systemverilog
// CSR address validity - only the CSRs implemented by kronos_csr (see
// kronos_types.sv) are legal. Per the RISC-V privileged spec, an access to a
// CSR that does not exist in the implementation MUST raise an
// illegal-instruction exception (mcause=2). Without this gate, an access to an
// unimplemented CSR silently reads 0 / ignores the write instead of trapping.
always_comb begin
  csr_addr_ok = 1'b0;
  unique case (IR[31:20])
    MSTATUS,
    MIE,
    MTVEC,
    MSCRATCH,
    MEPC,
    MCAUSE,
    MTVAL,
    MIP,
    MCYCLE,
    MINSTRET,
    MCYCLEH,
    MINSTRETH: csr_addr_ok = 1'b1;
    default  : csr_addr_ok = 1'b0;
  endcase // IR[31:20]
end
```

and in `INSTR_SYS` (was lines 326-338):

```systemverilog
3'b001,       // CSRRW
3'b010,       // CSRRS
3'b011: begin // CSRRC
  op1 = rs1_data;
  csr = 1'b1;
  instr_valid = csr_addr_ok;   // was: 1'b1
end
3'b101,       // CSRRWI
3'b110,       // CSRRSI
3'b111: begin // CSRRCI
  csr = 1'b1;
  instr_valid = csr_addr_ok;   // was: 1'b1
end
```

The legal set is derived from the `case(addr)` arms in `kronos_csr.sv`, so it stays exactly in sync
with what the CSR unit can service. On the dual-core branch (`cx-2hart-build`), `MHARTID` (0xF14) is
also implemented and must be added to the list above (the dual-hart boot template reads `mhartid`).

Notes:
- The CSR address is a static field of the instruction (`IR[31:20]`), so the check belongs in the
  decoder (ID stage). The existing `illegal` consolidation
  (`assign illegal = CATCH_ILLEGAL_INSTR ? (~instr_valid | illegal_opcode) : 1'b0;`, `kronos_ID.sv`
  line 349) then propagates it through `decode.illegal` to the existing mcause=2 trap path in
  `kronos_EX.sv` — no new exception plumbing was required.
- Implemented CSRs are unaffected: mstatus/mie/mtvec/mscratch/mepc/mcause/mtval/mip/mcycle/minstret/
  mcycleh/minstreth (and mhartid on the dual-core branch) still read/write exactly as before.

## Fix verification (in our fork)

Rebuilt the Verilator simulator from the fixed RTL
(`./build.sh --isa rv32 --cores 1` and `--cores 2`), then ran a minimal ELF whose first instruction
is `csrr a0, 0x7FF` (an unimplemented CSR) followed by `ebreak`:

- **Pre-fix:** the `csrr` was retired (CX trace `retired=1 trap=0`, no `[TRAP]`), i.e. silent
  zero-read.
- **Post-fix:** the same `csrr` produces a precise trap — CX trace
  `[TRAP] ... exception=1 irq=0 cause=0x2` (`mcause=2`, illegal instruction), matching Spike, and
  `mtval` carries the offending instruction word (`0x7ff0f73`).
- Regression: the framework's own boot/trap scaffolding (`csrw mtvec, ...`, `csrr mepc/mcause/mtval`,
  and the dual-hart `csrr mhartid`) still executes and retires normally, and CSR writes to the
  implemented CSRs (e.g. `csrw mstatus, ...`) still take effect.

Artifacts rebuilt in the framework's repo artifact dir
(`/home/canxin/Git/riscv_research/cx-riscv-cores/artifacts/`):
- `kronos_rv32_1c` (single-core, from `cx-build`)
- `kronos_rv32_2c` (dual-core, from `cx-2hart-build`)

## Interaction with the diff-fuzz framework (Spike comparison)

Empirically tabulated with a single probe ELF (per-CSR `csrr`, trap handler
advancing `mepc`) run on Spike (`spike --isa=RV32I_ZICSR_ZIFENCEI -l`, the exact
binary the framework invokes via `CX_RISCV_CORES_SPIKE`) and on both rebuilt
Kronos simulators:

| CSR                  | Spike          | Kronos pre-fix  | Kronos post-fix |
|----------------------|----------------|-----------------|-----------------|
| mstatus/mie/mscratch/mepc/mcause/mtval/mip/mcycle/minstret/mcycleh/minstreth | OK | OK (implemented) | OK (implemented) |
| mhartid (0xF14)      | OK             | OK (reads 0)    | OK (2c) / trap (1c) |
| mcyclecfg (0x321)    | **trap**       | OK (reads 0)    | **trap**        |
| mtinst (0x34A)       | **trap**       | OK (reads 0)    | **trap**        |
| mtval2 (0x34B)       | **trap**       | OK (reads 0)    | **trap**        |
| misa (0x301)         | OK (0x40140100)| OK (reads 0)    | **trap**        |
| mcounteren/menvcfg/mcountinhibit | OK (reads 0) | OK (reads 0) | **trap** |
| mhpmcounter3-31 / mhpmcounter3-31h | OK (reads 0) | OK (reads 0) | **trap** |
| mvendorid/marchid/mimpid | OK        | OK (reads 0)    | **trap**        |

So the fix eliminates the original false positives (mcyclecfg/mtinst/mtval2 —
Spike traps, Kronos previously did not) but also makes Kronos trap on a second
set of CSRs that Spike *accepts* (mhpmcounter3-31 and their high halves,
mcountinhibit, mcounteren, menvcfg, misa, mvendorid/marchid/mimpid, and mhartid
on the single-core build). Those new divergences are **not** a Kronos defect:
per the privileged spec an implementation that does not implement those CSRs
MUST trap, and Spike is a superset core that implements more. They are a
generator-scoping gap: the kronos profile advertises only I/Zicsr/Zifencei, but
`riscv-instruction`'s CSR `enabled_values()` (csr.rs) does not gate on
`defined_by_extensions`, so the generator emits machine-mode CSR operands
outside Kronos's implemented set. Follow-up (framework side): restrict the
kronos profile's CSR-operand domain to the implemented CSRs, or advertise the
CSR surface in the kronos plugin metadata. The RTL fix itself is spec-correct
and should stand.
