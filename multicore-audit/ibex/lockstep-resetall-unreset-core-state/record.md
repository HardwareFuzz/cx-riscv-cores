# SecureIbex lockstep left core-internal state unreset

- Record ID: `IBEX-LOCKSTEP_RESETALL_UNRESET_CORE_STATE`
- Core: Ibex
- Source repository: [lowRISC/ibex](https://github.com/lowRISC/ibex)
- Scope: SecureIbex primary/shadow core reset convergence
- Record kind: canonical upstream lockstep RTL reset fix
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact unreset core-state paths, the upstream commit rationale, and the merged canonical history
- Affected parent: [44777dc1](https://github.com/lowRISC/ibex/commit/44777dc16dbe4f1929fff16e416e4ec441fac8ec)
- Fixed revision: [a1902004](https://github.com/lowRISC/ibex/commit/a1902004f9400ec91e404a1cc1071f45ddc73bc5), `Add ResetAll parameter`
- Canonical fix status: merged in upstream `master`
- Retrieved: 2026-09-10

## Failure mechanism

SecureIbex runs a primary `ibex_core` and a delayed shadow `ibex_core`.
Before the fix, `ibex_top` did not enable or propagate a `ResetAll` mode, so
many registers inside each execution instance used clock-only sequential
blocks. For example, the pre-fix fetch FIFO address and data state were:

```systemverilog
always_ff @(posedge clk_i) begin
  if (instr_addr_en) begin
    instr_addr_q <= instr_addr_d;
  end
end

for (genvar i = 0; i < DEPTH; i++) begin : g_fifo_regs
  always_ff @(posedge clk_i) begin
    if (entry_en[i]) begin
      rdata_q[i] <= rdata_d[i];
      err_q[i]   <= err_d[i];
    end
  end
end
```

The IF/ID pipeline, I-cache prefetch/lookup/fill/skid state,
`ibex_prefetch_buffer` address state, and writeback metadata had the same
clock-only reset structure. The shadow execution instance is released with
the lockstep offset, so these unreset internal registers were not guaranteed
to have a common value when primary and shadow began executing. A stale or
unknown instruction/data/pipeline value could consequently create a
spurious lockstep mismatch or an X-valued alert.

## Necessary two-instance trigger

1. Instantiate SecureIbex so that `u_ibex_core` (primary) and the delayed
   shadow core both execute the same program.
2. Apply reset while the two instances have different clock/reset-release
   timing, or repeat reset after internal FIFO/cache/pipeline state has been
   populated.
3. Release reset. In the parent revision, core-internal state such as a
   fetch FIFO entry or IF/ID register is not reset in either instance, while
   the shadow starts at the lockstep offset. The two execution instances can
   therefore start from different or unknown internal values and raise a
   false lockstep failure.

The primary/shadow relationship is necessary for this finding: without the
second execution instance and delayed lockstep comparison there is no common
starting-state guarantee to violate. This is not a claim about an ordinary
single-hart Ibex reset bug.

## Canonical fix and deduplication

The fix sets `ResetAll` from the lockstep configuration and propagates it
through both core instances:

```systemverilog
localparam bit ResetAll = Lockstep;
```

The affected FIFO, IF, I-cache, prefetch, and writeback registers gain a
reset branch of the form:

```systemverilog
always_ff @(posedge clk_i or negedge rst_ni) begin
  if (!rst_ni) begin
    ...
  end else if (...) begin
    ...
  end
end
```

The upstream commit explicitly states that resetting all core registers is
required to guarantee a common starting point for lockstep and prevent
spurious lockstep failure alerts.

This is distinct from `IBEX-LOCKSTEP_RESET_STALE_DELAYED_INPUTS`. That
existing record covers the lockstep wrapper's `shadow_inputs_q`,
`shadow_tag_rdata_q`, and `shadow_data_rdata_q` delay arrays. This record
covers the unreset state inside each primary/shadow IF, FIFO, I-cache,
prefetch, and WB instance; the two fixes touch different state layers.

## Source evidence

- Pre-fix FIFO path: [`rtl/ibex_fetch_fifo.sv`](https://github.com/lowRISC/ibex/blob/44777dc16dbe4f1929fff16e416e4ec441fac8ec/rtl/ibex_fetch_fifo.sv)
- Pre-fix IF path: [`rtl/ibex_if_stage.sv`](https://github.com/lowRISC/ibex/blob/44777dc16dbe4f1929fff16e416e4ec441fac8ec/rtl/ibex_if_stage.sv)
- Complete fix: [a1902004](https://github.com/lowRISC/ibex/commit/a1902004f9400ec91e404a1cc1071f45ddc73bc5)
- Canonical branch head used for the audit: [3250d994](https://github.com/lowRISC/ibex/commit/3250d99482f1963891ef1cf19356eeaeeaa71d30)
