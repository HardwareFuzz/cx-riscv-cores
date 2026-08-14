# Upstream issue draft — CVA6 RVFI: LR/SC report nonzero `mem_wmask`

> 分类：**新 bug 新修复**（riscv_fuzz_test 未记录）

> Status: **draft** — review, then post to https://github.com/openhwgroup/cva6/issues
> Body below is in English and ready to paste. Remove this header before publishing.
> Dated 2026-08-10; already fixed and verified in our fork (see "Fix verification" at the end).

---

**Title:** [RVFI][BUG] LR/SC instructions report nonzero `mem_wmask` in the RVFI trace

## Description

Per the RISC-V RVFI contract (riscv-formal), a load-reserved (`lr.w`/`lr.d`) is a **pure read** — it
must never report a memory write — and a failed store-conditional (`sc.w`/`sc.d`) does **not** write
memory either. In both cases `mem_wmask` must be `0`.

CVA6 currently reports a nonzero `mem_wmask` for both:

- `lr.w/lr.d` → a bogus all-zero memory write is logged, and
- a failing `sc.w/sc.d` → a bogus write is logged even though no memory was modified.

## Root cause chain

1. `core/decoder.sv` (OpcodeAmo, `8ef28596d`) classifies **every** AMO — including LR — as
   `fu = STORE`.
2. `core/cva6_rvfi.sv` derives the masks directly from that classification:
   `lsu_wmask = (lsu_ctrl_fu == STORE) ? lsu_ctrl_be : '0;`
3. `core/cva6_rvfi.sv` packs `mem_wmask <= mem_q[...].lsu_wmask` unconditionally, with no AMO
   special-casing.
4. `corev_apu/tb/rvfi_tracer.sv` (since #3131) prints the write whenever `mem_wmask != 0`, so the
   bogus mask becomes a visible bogus memory write in `trace_rvfi_hart_*.dasm`.

Note this is the same decoder root cause behind #2455 (LR.D misaligned → Store misaligned) and #3394
(LR.W page fault → Store/AMO page fault), but observed here on the **trace path** rather than the
exception path.

## Repro / observed behavior

`lr.w x13, (x5)` with `x5 = 0x8fffffb8`, memory `[0xbc..0xbf] = 0xabe57a0e`:

- **Expected (Spike):**
  ```
  3 0x00000000800004be (0x1002a6af) x13 0xabe57a0e mem 0x8fffffb8 0xf
  ```
  read mask only, no write.
- **Observed (CVA6, pre-fix):** a write mask is reported and the tracer prints
  `mem 0x8fffffb8 0x00000000` — i.e. a fake zeroing write to the LR address, which difftest tools
  against Spike misreport as a real store.

## Proposed fix (patch sketch)

In `core/cva6_rvfi.sv`, route the mem masks through per-op helpers at the packing site
(`rvfi_instr_o[i].mem_wmask` / `mem_rmask`):

```systemverilog
function automatic logic is_amo_lr_op(input fu_op amo_op);
  return (amo_op == AMO_LRW) || (amo_op == AMO_LRD);
endfunction

function automatic logic is_amo_sc_op(input fu_op amo_op);
  return (amo_op == AMO_SCW) || (amo_op == AMO_SCD);
endfunction

function automatic logic [(CVA6Cfg.XLEN/8)-1:0] rvfi_mem_rmask_for_op(
    input fu_op amo_op,
    input logic [(CVA6Cfg.XLEN/8)-1:0] lsu_rmask_in,
    input logic [(CVA6Cfg.XLEN/8)-1:0] lsu_wmask_in
);
  if (is_amo_lr_op(amo_op)) begin
    return lsu_wmask_in;          // LR: report the byte-enables as the read mask
  end
  if (is_amo_sc_op(amo_op)) begin
    return '0;                    // SC: no read either
  end
  return lsu_rmask_in;
endfunction

function automatic logic [(CVA6Cfg.XLEN/8)-1:0] rvfi_mem_wmask_for_op(
    input fu_op amo_op,
    input logic [(CVA6Cfg.XLEN/8)-1:0] lsu_wmask_in,
    input logic [CVA6Cfg.XLEN-1:0] rd_wdata_in
);
  if (is_amo_lr_op(amo_op)) begin
    return '0;                    // LR is a pure read: never a write
  end
  if (is_amo_sc_op(amo_op)) begin
    return (rd_wdata_in == '0) ? lsu_wmask_in : '0;  // write only when SC succeeds
  end
  return lsu_wmask_in;
endfunction
```

## Open question for maintainers: SC-success detection

The sketch above infers SC success from `rd_wdata == '0` (SC writes `0` to rd on success).
That is an *heuristic*; if the LSU exposes a dedicated success signal (e.g. inside the load-store
unit / dcache AMO response), it would be a cleaner criterion. Please confirm the right signal before
adopting this patch.

## Fix verification (in our fork)

We applied this fix on the `HardwareFuzz/cva6` `cx-build` branch and re-verified against real
Verilator RVFI traces:

- pre-fix: `lr.w.aq x13,(x5)` produced a fake `mem 0x8fffffb8 0x00000000` write line;
- post-fix: the same instruction reports only the read mask (`mem 0x8fffffb8 0xf`), `x13` keeps its
  loaded value, and the bogus-write count for plain `lr.w` drops to zero.

Related: #2455, #3338, #3394, #3131.
