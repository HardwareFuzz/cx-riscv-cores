# SecureIbex could write back a false load response to both lockstep instances

- Record ID: `IBEX-LOCKSTEP_DATA_RVALID_FI_WINDOW`
- Core: Ibex
- Scope: SecureIbex primary/shadow shared memory-response path
- Record kind: canonical upstream lockstep RTL security fix
- Source repository: [lowRISC/ibex](https://github.com/lowRISC/ibex)
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the pre-fix write-enable path, the merged FI-hardening fix, and upstream PR #1968
- Status: fixed in upstream history
- Evidence level: A
- Observed configuration: SecureIbex with the writeback stage and its delayed shadow execution instance
- Affected revision: `ec32fb1a6460d8512f9192a84d5fc395502c13f5`
- Fixed revision: `590d196e620376c9888546fa947f3b7bb81af956`

## Failure mechanism

SecureIbex executes a primary instance and a delayed shadow instance, while
the interconnect response is shared by the two instances. In the affected
writeback stage, the LSU register-file write enable was passed through
whenever `rf_we_lsu_i` was asserted:

```systemverilog
assign rf_wdata_wb_mux_we[1] = rf_we_lsu_i;
```

That enable is derived from the memory response-valid path. A fault or glitch
on `data_rvalid_i` at the interconnect boundary could therefore make a
non-load write back the current `data_rdata_i` when its integrity bits happened
to be accepted. Because the injected response was on the shared path, both
the main and delayed shadow instances could receive the same false event; the
lockstep comparison consequently had no independent response to expose it.

## Two-instance trigger

1. Use the SecureIbex primary and delayed shadow execution instances with the
   writeback stage enabled.
2. Run a non-load or otherwise no-outstanding-load writeback.
3. Inject the documented interconnect-level `data_rvalid_i` fault while the
   data and integrity inputs are accepted.
4. The affected path permits the LSU write-enable to write the shared current
   data into the register file of both aligned execution instances.

The primary/shadow pair is essential to this recorded failure: the shared
response fault is specifically dangerous because it affects both instances
equally and can evade their comparison. This is a SecureIbex multi-execution
record, not a claim about two independently addressable SMP harts.

## Fix and upstream closure

The fix adds `outstanding_load_wb_o` to the LSU write-enable qualification:

```systemverilog
assign rf_wdata_wb_mux_we[1] = outstanding_load_wb_o & rf_we_lsu_i;
```

An LSU response can consequently write the register file through this path
only while the writeback stage is actually waiting for a load response. The
upstream commit explicitly identifies an interconnect-level glitch and the
equal effect on main and shadow cores. Later Ibex logic added a broader secure
configuration response guard; this record retains the original, distinct
writeback-stage fix and its historical affected revision.

## Source evidence

- Pre-fix writeback source: [`rtl/ibex_wb_stage.sv`](https://github.com/lowRISC/ibex/blob/ec32fb1a6460d8512f9192a84d5fc395502c13f5/rtl/ibex_wb_stage.sv)
- Fix: [590d196e](https://github.com/lowRISC/ibex/commit/590d196e620376c9888546fa947f3b7bb81af956)
- Upstream closure: [Ibex PR #1968](https://github.com/lowRISC/ibex/pull/1968)
