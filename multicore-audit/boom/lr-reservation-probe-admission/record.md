# BOOM valid LR reservation did not block coherence Probe admission

- Record ID: `BOOM-LR_RESERVATION_PROBE_ADMISSION`
- Core: BOOM
- Scope: shared L1 LR/SC reservation and coherence Probe ordering
- Record kind: canonical upstream Chisel/RTL fix
- Source repository: [riscv-boom/riscv-boom](https://github.com/riscv-boom/riscv-boom)
- Affected parent: [79c92b56](https://github.com/riscv-boom/riscv-boom/commit/79c92b56be1c644c4da31b6f3d9cc5b1a58683ec)
- Fix commit: [33991593](https://github.com/riscv-boom/riscv-boom/commit/339915933e9db799f3f03964e3cd65fc89c21f17), `[dcache] LR reservation should block prober`
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact parent/child TileLink B-channel gate and the retained canonical v4 implementation
- Affected revisions: BOOM DCache revisions before `33991593`
- Retrieved: 2026-09-10

## Failure mechanism

BOOM represents a live LR reservation with `lrsc_valid`, derived from the
reservation counter. In the affected DCache, incoming TileLink B-channel
Probes were admitted without considering that state:

```scala
prober.io.req.valid := tl_out.b.valid
tl_out.b.ready      := prober.io.req.ready
```

The prober can update the same cache metadata and ownership state used by the
LR/SC path. The parent therefore allowed an external coherence action to
enter while the LR reservation window was still active. The fix gates both
sides of the ready/valid handshake:

```scala
prober.io.req.valid := tl_out.b.valid && !lrsc_valid
tl_out.b.ready      := prober.io.req.ready && !lrsc_valid
```

Gating both signals is important: the incoming Probe is not accepted by the
TileLink interface and cannot be partially consumed by the prober while the
reservation is live.

## Two-client trigger

Use two coherent BOOM harts/clients sharing the DCache coherence network.

1. Hart A executes an LR and establishes a reservation, leaving
   `lrsc_valid = 1` for the reservation window.
2. Hart B requests write permission or another ownership transition for the
   same cache line. The coherence manager sends a Probe to hart A.
3. In the parent, `tl_out.b.valid` and `prober.io.req.ready` can complete the
   Probe handshake even though hart A's LR reservation is still valid. The
   Probe can then race the local LR/SC metadata/ownership path; the external
   coherence transaction is no longer ordered behind the reservation window.
4. The fix holds the Probe at the TileLink boundary until `lrsc_valid` is
   false, so it cannot overtake the LR/SC reservation protocol.

The second coherent client is necessary to generate the incoming Probe. A
single hart can set `lrsc_valid`, but it cannot create the external B-channel
coherence transaction that exposes the missing admission gate.

## Source and deduplication evidence

The parent and fix modify [`src/main/scala/lsu/dcache.scala`](https://github.com/riscv-boom/riscv-boom/blob/79c92b56be1c644c4da31b6f3d9cc5b1a58683ec/src/main/scala/lsu/dcache.scala).
The current canonical v4 source retains the equivalent gate in [`v4/lsu/dcache.scala`](https://github.com/riscv-boom/riscv-boom/blob/58ef2720eae13be26b3008c02b5a74ce29c61c44/src/main/scala/v4/lsu/dcache.scala).

This is distinct from:

- `BOOM-PROBE_NACK_LRSC_RESERVATION`, which filters LR/SC reservation
  bookkeeping after a Probe has already caused a local pipeline nack;
- `BOOM-MSHR_PROBER_META_READ_CONFLICT`, which serializes live MSHR metadata
  access against the prober;
- the separate prefetch permission-upgrade path
  upgrade rather than the `lrsc_valid` Probe-admission gate.

No new simulation is claimed; the canonical parent/fix diff and retained
upstream implementation are the confirmation evidence.
