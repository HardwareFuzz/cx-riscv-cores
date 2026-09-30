# BOOM writeback dropped the final C-channel beat under backpressure

- Record ID: `BOOM-WB_LAST_C_BEAT_LOST`
- Core: BOOM
- Source repository: [riscv-boom/riscv-boom](https://github.com/riscv-boom/riscv-boom)
- Scope: shared L1 TileLink C-channel writeback and dirty Probe response
- Record kind: canonical upstream Chisel/RTL coherence fix
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Affected parent: [3b6f11af](https://github.com/riscv-boom/riscv-boom/commit/3b6f11af603a0d21ab83dd0b8df8f2413ed7df9d)
- Direct fix: [d182b07e](https://github.com/riscv-boom/riscv-boom/commit/d182b07e6db1b38d5585628f882fb04310ee8368), `[dcache] Fix BoomWritebackUnit not sending all wb beats`
- Canonical closure: [BOOM PR #275](https://github.com/riscv-boom/riscv-boom/pull/275), merged as [ac28f02d](https://github.com/riscv-boom/riscv-boom/commit/ac28f02dafc5cfa284bb83e1c0c7d2b99c20a92a)
- Confirmation: exact parent/fix RTL diff and the merged PR history establish the failure and its upstream repair
- Retrieved: 2026-09-10

## Failure mechanism

At the affected parent, `BoomWritebackUnit` in
[`src/main/scala/lsu/dcache.scala`](https://github.com/riscv-boom/riscv-boom/blob/3b6f11af603a0d21ab83dd0b8df8f2413ed7df9d/src/main/scala/lsu/dcache.scala)
emits one TileLink C-channel beat from `io.release` for each refill row. In
the `s_active` state, the unit advances `data_req_cnt` only after a release
handshake:

```scala
when (io.release.fire()) {
  data_req_cnt := data_req_cnt + 1.U
}
```

However, the parent leaves `s_active` as soon as the counter reaches the
last-beat value, without requiring that the current release handshake has
occurred:

```scala
when (data_req_cnt === (refillCycles-1).U) {
  state := Mux(io.mem_grant || !req.voluntary, s_invalid, s_grant)
}
```

At `data_req_cnt === refillCycles-1`, `io.release.valid` describes the final
`ReleaseData` or dirty `ProbeAckData` beat. If the shared TileLink C channel
holds `io.release.ready` low for that cycle, `io.release.fire()` is false.
The old state transition nevertheless executes. For a dirty Probe response,
the non-voluntary request takes the unit to `s_invalid`; the unit therefore
withdraws the unaccepted final beat on the next cycle instead of retaining it
in `s_active` for a retry. The counter is not advanced, but the state that
would have retried that counter value has already been abandoned.

The C-channel message is consequently truncated at the shared coherence
boundary. The peer or coherence manager does not receive the complete dirty
line response, so the Probe transaction cannot complete as a valid
multi-beat coherence response and the associated data/ownership transfer is
left incomplete.

## Necessary multi-client trigger

The concrete trigger uses two coherent BOOM L1 clients or harts attached to a
shared TileLink network:

1. Hart A holds a dirty cache line `X`.
2. Hart B performs a coherent access that requires Hart A to relinquish or
   report `X`. The coherence manager sends a real TileLink B-channel Probe to
   Hart A.
3. Hart A's Probe path creates a dirty writeback request for the line. The
   `BoomWritebackUnit` begins the multi-beat C-channel `ProbeAckData` transfer
   through `io.release`.
4. On the cycle carrying the final beat, the shared manager or interconnect
   applies legal C-channel ready/valid backpressure: `io.release.valid` is
   asserted, but `io.release.ready` is deasserted, so the beat is not
   accepted.
5. The parent still observes `data_req_cnt === refillCycles-1` and changes
   state. The final beat disappears when `io.release.valid` is cleared in the
   new state, leaving the peer's dirty-line Probe response incomplete.

The peer-generated Probe and dirty-line transfer are necessary to exercise
this writeback path. A local data-cache request that does not cause a
coherent Probe does not enter this dirty Probe-response sequence.

## Canonical fix and closure

The direct child fix
[`d182b07e`](https://github.com/riscv-boom/riscv-boom/commit/d182b07e6db1b38d5585628f882fb04310ee8368)
changes the final-beat transition to require the actual C-channel
handshake:

```scala
when ((data_req_cnt === (refillCycles-1).U) && io.release.fire()) {
  state := Mux(io.mem_grant || !req.voluntary, s_invalid, s_grant)
}
```

With this guard, a final beat that is backpressured leaves the unit in
`s_active`; `io.release.valid` remains asserted for the same counter value
until the TileLink handshake occurs. Only after the final beat is accepted
can the unit move to `s_invalid` or wait in `s_grant` as required by the
request type.

The fix is included in [BOOM PR #275](https://github.com/riscv-boom/riscv-boom/pull/275),
which was merged into the canonical upstream history as
[ac28f02d](https://github.com/riscv-boom/riscv-boom/commit/ac28f02dafc5cfa284bb83e1c0c7d2b99c20a92a).
The direct fix is an ancestor of that merge, and the merge retains the
corrected `BoomWritebackUnit` behavior in the upstream BOOM source.

This record is distinct from the six existing BOOM records:

- `BOOM-LR_RESERVATION_PROBE_ADMISSION` concerns LR/SC reservation state
  gating Probe admission.
- `BOOM-PREFETCH_MSHR_PROBE_CLEAR` concerns clearing a matching prefetch
  MSHR after a Probe.
- `BOOM-PROBE_NACK_LRSC_RESERVATION` concerns LR/SC reservation updates
  after a Probe-induced nack.
- `BOOM-MSHR_PROBER_META_READ_CONFLICT` concerns a live MSHR metadata read
  colliding with Probe handling.
- `BOOM-PROBER_INVALID_MSHR_READY` concerns stale request-index metadata in
  an invalid MSHR blocking ProbeUnit readiness.
- `BOOM-LDLD_SNOOP_PNR_BLOCK` concerns same-address load ordering after an
  externally observed coherent snoop.

The present record concerns only the `BoomWritebackUnit` final-beat state
transition and loss of an unaccepted TileLink C-channel beat under legal
backpressure.
