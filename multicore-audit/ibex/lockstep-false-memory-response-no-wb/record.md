# SecureIbex without a writeback stage could consume an unsolicited memory response

- Record ID: `IBEX-LOCKSTEP_FALSE_MEMORY_RESPONSE_NO_WB`
- Core: Ibex
- Scope: SecureIbex primary/shadow shared external memory-response path
- Record kind: canonical upstream lockstep RTL security fix
- Source repository: [lowRISC/ibex](https://github.com/lowRISC/ibex)
- Source issue: [#2144 — False memory response can break the multiply state machine](https://github.com/lowRISC/ibex/issues/2144)
- Fix PR: [#2166 — Guard against false memory responses for secure configurations](https://github.com/lowRISC/ibex/pull/2166)
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the no-writeback-stage response-consumption RTL,
  the explicit issue #2144 runtime effect, and merged PR #2166
- Status: fixed in upstream history
- Evidence level: A
- Observed configuration: `SecureIbex=1` and `WritebackStage=0`, with the
  primary and delayed shadow execution instances
- Affected parent revision: `b94364ab5808833bfab228f9c35d7852795866fd`
- Fixing/merged revision: `5977d4e3a0433e96d43a9225bae941a216ecac8e`

## Failure mechanism

In the affected load/store unit, external response signals were treated as a
transaction response whenever the LSU state was `IDLE`:

```systemverilog
assign lsu_resp_valid_o =
    (data_rvalid_i | pmp_err_q) & (ls_fsm_cs == IDLE);

assign lsu_rdata_valid_o =
    (ls_fsm_cs == IDLE) & data_rvalid_i & ~data_or_pmp_err &
    ~data_we_q & ~data_intg_err;
```

In `ibex_core`, the latter output was connected directly to the LSU register
write enable. Without a writeback stage, `ibex_wb_stage` bypasses the write
signals from ID and the LSU, so an unsolicited `data_rvalid_i` could assert
the load-data write path even though no load response was outstanding. The
current ID-stage destination and `data_rdata_i` could then be committed as an
incorrect register-file write. An unsolicited bus error was likewise exposed
as a load/store response and could terminate an unrelated multiply operation.

The issue #2144 reproducer reports the concrete multiply consequence: an
unsolicited memory error response interrupted `MULH`, and the following
multiply used residual state from the previous operation, producing an
incorrect result and exposing operand-dependent information.

## Two-instance trigger and impact

1. Configure SecureIbex with `WritebackStage=0`, so the primary and delayed
   shadow instances use the ID/EX response path.
2. Run an instruction stream in which the data interface has no response
   outstanding; a multiply is a direct example for the error-response path.
3. Inject `data_rvalid_i`, `data_rdata_i`, or `data_err_i` at the external
   response interface.
4. The primary consumes the false response. The same memory-response bundle is
   buffered by the lockstep path and delivered to the delayed shadow, which
   consumes the corresponding false event after its delay.
5. Both execution instances can therefore accept the response in lockstep,
   while the intended comparison sees no independent external response and
   does not expose the injected event.

The no-writeback-stage limitation is essential. With `WritebackStage=1`, the
separate writeback-stage qualification is the distinct path covered by
`IBEX-LOCKSTEP_DATA_RVALID_FI_WINDOW`; this record covers the ID/EX response
consumption, no-writeback register write, and multiply-state error path in
`WritebackStage=0` secure configurations. The primary and shadow are not
independently addressable SMP harts.

## Fix and upstream closure

PR #2166 adds `expecting_load_resp_id` and `expecting_store_resp_id` from the
ID stage. In secure configurations, LSU data writes and load/store errors are
qualified by an outstanding writeback response or the corresponding ID/EX
expectation:

```systemverilog
assign lsu_load_err  = lsu_load_err_raw  &
                       (outstanding_load_wb | expecting_load_resp_id);
assign lsu_store_err = lsu_store_err_raw &
                       (outstanding_store_wb | expecting_store_resp_id);
assign rf_we_lsu     = lsu_rdata_valid &
                       (outstanding_load_wb | expecting_load_resp_id);
```

For `WritebackStage=0`, the expectation signals are asserted only for the
appropriate ID-stage load or store cycles. A response with no matching
instruction is no longer consumed in the secure path. Non-secure
configurations intentionally retain the original bus-protocol assumption;
the recorded fixed scope is `SecureIbex=1`.

## Source evidence

- Pre-fix LSU response path: [`rtl/ibex_load_store_unit.sv`](https://github.com/lowRISC/ibex/blob/b94364ab5808833bfab228f9c35d7852795866fd/rtl/ibex_load_store_unit.sv)
- Pre-fix no-writeback connections: [`rtl/ibex_core.sv`](https://github.com/lowRISC/ibex/blob/b94364ab5808833bfab228f9c35d7852795866fd/rtl/ibex_core.sv)
- Fix: [5977d4e3](https://github.com/lowRISC/ibex/commit/5977d4e3a0433e96d43a9225bae941a216ecac8e)
- Runtime report: [Ibex issue #2144](https://github.com/lowRISC/ibex/issues/2144)
- Upstream closure: [Ibex PR #2166](https://github.com/lowRISC/ibex/pull/2166)
