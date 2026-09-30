# Ibex SecureIbex lockstep delay state survived repeated reset

- Record ID: `IBEX-LOCKSTEP_RESET_STALE_DELAYED_INPUTS`
- Core: Ibex
- Source repository: [lowRISC/ibex](https://github.com/lowRISC/ibex)
- Scope: SecureIbex lockstep multi-execution
- Record kind: canonical upstream RTL fix with reset regression
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by issue #1368's concrete failing seed/assertion and the upstream reset-state fix
- Affected parent: [2ce6653c](https://github.com/lowRISC/ibex/commit/2ce6653c65dad0987ff56631694f4f814a14a2b6)
- Affected revisions: descendants of `2ce6653c` before `f3b163af3534c0f8ac83b68e8cf702f42bcf0c87`
- Fixed revision: `f3b163af3534c0f8ac83b68e8cf702f42bcf0c87`, included in the
  audited `3250d99482f1963891ef1cf19356eeaeeaa71d30`
- Retrieved: 2026-09-09

## Symptom

After repeated reset, delayed lockstep inputs and instruction/data-cache
responses could retain values from the previous run. When execution resumed,
the shadow core could consume a spurious memory response, register-file input,
interrupt, debug request, or fetch-control value and diverge from the primary
core. Issue #1368 reports a `NoMemResponseWithoutPendingAccess` assertion in
`riscv_reset_test`, including seed `26328`.

## Trigger

Enable `SecureIbex=1`, exercise the primary and delayed shadow instances, and
apply the reset sequence repeatedly such that the delay pipeline does not see
a normal clock edge while reset is asserted. Release reset and inspect the
first requests and responses seen by the shadow instance.

## Root cause

Before the fix, the `shadow_inputs_q`, `shadow_tag_rdata_q`, and
`shadow_data_rdata_q` delay state used an `always_ff @(posedge clk_i)` block
without an asynchronous reset. The state that aligns the second execution
instance with the primary was therefore not cleared between runs.

## Fix and verification

The fix adds `or negedge rst_ni` and clears all delayed inputs and cache
responses during reset. The current RTL keeps the reset in both the
multi-cycle (`LockstepOffset > 1`) and single-cycle (`LockstepOffset == 1`)
delay branches. Re-run issue #1368's reset test with seed `26328` on the
pre-fix parent and fixed revision; this audit did not independently rerun the
seed or capture a waveform.

## Source evidence

- Upstream issue [#1368](https://github.com/lowRISC/ibex/issues/1368).
- Fix commit [f3b163af](https://github.com/lowRISC/ibex/commit/f3b163af3534c0f8ac83b68e8cf702f42bcf0c87).
- Pre-fix parent
  [2ce6653c](https://github.com/lowRISC/ibex/commit/2ce6653c65dad0987ff56631694f4f814a14a2b6).
- Current delay implementation in
  [`rtl/ibex_lockstep.sv`](https://github.com/lowRISC/ibex/blob/3250d99482f1963891ef1cf19356eeaeeaa71d30/rtl/ibex_lockstep.sv).

This is a confirmed SecureIbex multi-execution issue. The stale state belongs
to the SecureIbex primary/shadow pair rather than to two independently
addressable SMP harts.
