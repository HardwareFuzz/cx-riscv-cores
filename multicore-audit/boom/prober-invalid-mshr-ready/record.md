# BOOM stale metadata in an invalid MSHR prevented ProbeUnit progress

- Record ID: `BOOM-PROBER_INVALID_MSHR_READY`
- Core: BOOM
- Scope: shared L1 coherence Probe progress at the MSHR rendezvous
- Record kind: canonical upstream Chisel/RTL fix
- Source repository: [riscv-boom/riscv-boom](https://github.com/riscv-boom/riscv-boom)
- Affected parent: [3e17d246](https://github.com/riscv-boom/riscv-boom/commit/3e17d246f5b89e5d18f23c021ad391c9f85ad427)
- Fix commit: [4b9f9f53](https://github.com/riscv-boom/riscv-boom/commit/4b9f9f53dfba4eaa819fc193de6386159a997a78), `[lsu] Fix bug with prober`
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact parent/child `probe_rdy` diff and the retained canonical v4 equivalent
- Affected revisions: BOOM MSHR revisions before `4b9f9f53`
- Retrieved: 2026-09-10

## Failure mechanism

In the affected `src/main/scala/lsu/dcache.scala`, each `BoomMSHR` retained
its request register after returning to `s_invalid`. The index comparison was
computed from that retained request:

```scala
val req_idx   = req.addr(untagBits-1, blockOffBits)
val idx_match = req_idx === io.req.addr(untagBits-1, blockOffBits)
```

The parent then advertised Probe readiness solely as:

```scala
io.probe_rdy := !idx_match
io.idx_match := (state =/= s_invalid) && idx_match
```

Thus an invalid/empty MSHR could still carry the index of its previous
request and deassert `probe_rdy` when a new incoming Probe used that index.
`BoomMSHRFile` conservatively combines all MSHR readiness signals into its
global `io.probe_rdy`, which is supplied to the coherence prober as its MSHR
rendezvous condition. In the parent, the B-channel can initially handshake
with an idle ProbeUnit; once the unit reaches its MSHR-request state, the
stale invalid MSHR leaves the unit waiting in that state and prevents the
ProbeAck from completing. The occupied/stalled prober can then hold later
Probe traffic at the B-channel. The defect is therefore a ProbeUnit
progress/liveness failure, rather than a direct combinational B-channel
ready failure.

The upstream fix changes the child condition to:

```scala
io.probe_rdy := (state === s_invalid) || !idx_match
```

An invalid MSHR is now always available for Probe handling, independent of
the stale request index. The fix is a state qualification of the actual
coherence admission signal, not merely a cleanup of an unused register.

## Two-client trigger

Use two coherent BOOM clients/harts sharing the TileLink network.

1. Hart A allocates an MSHR for a miss, then lets that MSHR complete and
   return to `s_invalid`; its old request index remains in the MSHR register.
2. Hart B accesses a line whose address has the same cache index, causing the
   coherence manager to send an incoming TileLink B-channel Probe to hart A.
3. The old invalid MSHR reports `probe_rdy = 0` because its stale index
   matches the Probe index. The ProbeUnit may first accept the B-channel
   request, then reaches its MSHR rendezvous and waits because the aggregate
   `mshr_rdy` is low; it cannot complete the ProbeAck, and later Probe
   traffic can be backpressured.
4. After the fix, the invalid MSHR reports ready and the ProbeUnit can
   complete the real Probe.

The incoming Probe from the second coherent client is necessary. A local
single-hart LSU request does not create a TileLink B-channel Probe, so it
cannot reproduce this Probe-admission failure by itself.

## Source and deduplication evidence

The parent and fix both modify [`src/main/scala/lsu/dcache.scala`](https://github.com/riscv-boom/riscv-boom/blob/3e17d246f5b89e5d18f23c021ad391c9f85ad427/src/main/scala/lsu/dcache.scala).
The current canonical v4 implementation retains the invalid-state
qualification in [`v4/lsu/mshrs.scala`](https://github.com/riscv-boom/riscv-boom/blob/58ef2720eae13be26b3008c02b5a74ce29c61c44/src/main/scala/v4/lsu/mshrs.scala).

This is distinct from the existing `BOOM-MSHR_PROBER_META_READ_CONFLICT`: that
record concerns a live MSHR metadata access colliding with the prober, while
this record concerns a stale index in an already invalid MSHR incorrectly
blocking Probe admission. It is also distinct from
`BOOM-PROBE_NACK_LRSC_RESERVATION`, which concerns LR/SC bookkeeping after a
Probe-induced pipeline nack.

No new simulation is claimed; the canonical parent/fix diff and retained
upstream implementation are the confirmation evidence.
