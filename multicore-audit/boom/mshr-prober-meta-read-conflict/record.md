# BOOM MSHR metadata-read and Probe admission could conflict at one set

- Record ID: `BOOM-MSHR_PROBER_META_READ_CONFLICT`
- Core: BOOM
- Source repository: [riscv-boom/riscv-boom](https://github.com/riscv-boom/riscv-boom)
- Scope: shared L1 coherence Probe and MSHR metadata-read admission
- Record kind: canonical upstream Chisel/RTL coherence progress fix
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact parent/fix ancestry, the live MSHR and ProbeUnit RTL, the shared metadata-read arbiter, the concrete same-index peer Probe trigger, and the merged PR closure
- Affected parent: [397992d5](https://github.com/riscv-boom/riscv-boom/commit/397992d535d14d38658e8503a5ededa3430bb352)
- Fix chain: [35a6070c](https://github.com/riscv-boom/riscv-boom/commit/35a6070cd75e98a7b16e2c6ef4616bb700143500) and [12dcbbce](https://github.com/riscv-boom/riscv-boom/commit/12dcbbce19bf9fd79b7be68ee16f30a070c989b5)
- Canonical closure: [BOOM PR #420](https://github.com/riscv-boom/riscv-boom/pull/420), merged as [c9fa26de](https://github.com/riscv-boom/riscv-boom/commit/c9fa26ded445bc722578d9650ba80ee0053d1a05)
- Retrieved: 2026-09-10

## Failure mechanism

At the affected parent, a `BoomMSHR` actively issued a metadata read in
`s_meta_read`:

```scala
} .elsewhen (state === s_meta_read) {
  io.meta_read.valid := true.B
  io.meta_read.bits.idx := req_idx
  io.meta_read.bits.tag := req_tag
  io.meta_read.bits.way_en := req.way_en
  when (io.meta_read.fire()) {
    state := s_meta_resp_1
  }
}
```

The same MSHR advertised Probe readiness with a state set that omitted
`s_meta_read`:

```scala
val meta_hazard = RegInit(0.U(2.W))
when (meta_hazard =/= 0.U) { meta_hazard := meta_hazard + 1.U }
when (io.meta_write.fire()) { meta_hazard := 1.U }

io.probe_rdy :=
  (meta_hazard === 0.U &&
   state.isOneOf(s_invalid, s_refill_req, s_refill_resp))
```

The MSHR file rejects an incoming Probe when its index matches an MSHR that
reports not-ready:

```scala
when (!mshr.io.probe_rdy &&
      idx_matches(w)(i) &&
      io.req_is_probe(w)) {
  io.probe_rdy := false.B
}
```

This creates a deterministic same-index admission conflict: while the MSHR
is in `s_meta_read`, it can request the shared metadata arbiter, but the
matching external Probe is denied at the MSHR rendezvous even when
`meta_hazard` is clear. The DCache uses one metadata-read arbiter for the
MSHR and ProbeUnit paths, including the MSHR at input 3 and the prober at
input 1. An active Probe consequently cannot complete its MSHR rendezvous;
the ProbeUnit retries its metadata sequence and holds later B-channel Probe
traffic at the coherence boundary. The proven result is a deterministic
retry/backpressure progress conflict for the stated state and index window;
it is not a claim that every schedule produces an unconditional permanent
deadlock.

The affected sources are [`lsu/mshrs.scala`](https://github.com/riscv-boom/riscv-boom/blob/397992d535d14d38658e8503a5ededa3430bb352/src/main/scala/lsu/mshrs.scala)
and [`lsu/dcache.scala`](https://github.com/riscv-boom/riscv-boom/blob/397992d535d14d38658e8503a5ededa3430bb352/src/main/scala/lsu/dcache.scala).

## Necessary multi-client trigger

The trigger uses two coherent BOOM clients sharing the TileLink network:

1. Hart A holds line `X` and also has an active MSHR for a different line
   `Y` with the same cache index but a different tag.
2. Hart A's MSHR for `Y` reaches `s_meta_read`, where its metadata-read
   request is valid.
3. Hart B performs a store or permission upgrade to `X`. The coherence
   manager sends a real TileLink B-channel Probe for `X` to Hart A.
4. Hart A's DCache passes the B-channel request to the ProbeUnit. At the
   Probe/MHSR rendezvous, the index of `X` matches the active MSHR for `Y`.
5. Because that MSHR is in the omitted `s_meta_read` readiness state,
   `mshr.io.probe_rdy` is false. The ProbeUnit cannot advance to its response
   state and retries, while its active request backpressures later Probe
   traffic.

The same-index/different-tag construction is necessary because the parent
conflict check is index-based at this point. The incoming B-channel Probe is
also necessary: a local single-hart metadata read does not create the
coherence request that enters the rejected Probe path.

The DCache's external Probe connection is explicit:

```scala
prober.io.req.valid := tl_out.b.valid && !lrsc_valid
tl_out.b.ready      := prober.io.req.ready && !lrsc_valid
prober.io.mshr_rdy  := mshrs.io.probe_rdy
```

## Canonical fix and closure

The fix branch first adds the ProbeUnit-idle input and includes `s_meta_read`
in the MSHR readiness set:

```scala
io.probe_rdy :=
  (meta_hazard === 0.U &&
   state.isOneOf(
     s_invalid,
     s_refill_req,
     s_refill_resp,
     s_drain_rpq_loads,
     s_meta_read))
```

It also holds the MSHR metadata read while the ProbeUnit is active:

```scala
} .elsewhen (state === s_meta_read) {
  io.meta_read.valid := io.prober_idle
  ...
}
```

The DCache drives that input from the ProbeUnit's ready state:

```scala
mshrs.io.prober_idle := prober.io.req.ready && !lrsc_valid
```

The later canonical refinement [7b43a907](https://github.com/riscv-boom/riscv-boom/commit/7b43a907f8b1ff0445817339b47314806a3256a7),
`[mshr] MSHRS should not wait on prober when not to same set`, makes the
serialization index-aware. The current canonical master retains the refined
protocol:

```scala
val prober_state = Input(Valid(UInt(coreMaxAddrBits.W)))

io.probe_rdy :=
  (meta_hazard === 0.U &&
   (state.isOneOf(
      s_invalid,
      s_refill_req,
      s_refill_resp,
      s_drain_rpq_loads) ||
    (state === s_meta_read && grantack.valid)))

io.meta_read.valid :=
  !io.prober_state.valid ||
  !grantack.valid ||
  (io.prober_state.bits(untagBits-1,blockOffBits) =/= req_idx)
```

The current DCache connects the active Probe state to each MSHR, and the
current ProbeUnit exports the active Probe address. This confirms that the
merged closure preserves the corrected same-set protocol rather than merely
changing an unused readiness flag.

The exact fix is retained in upstream PR #420. Its ancestry is:

```text
397992d535d14d38658e8503a5ededa3430bb352
  -> 35a6070cd75e98a7b16e2c6ef4616bb700143500
  -> 12dcbbce19bf9fd79b7be68ee16f30a070c989b5
  -> c9fa26ded445bc722578d9650ba80ee0053d1a05 (PR merge)
```

The retained record is distinct from `BOOM-PROBER_INVALID_MSHR_READY`:
that record covers a stale index in an already invalid MSHR, whereas this
record covers a live MSHR in `s_meta_read` and its shared metadata-read/Probe
progress conflict. It is also distinct from the LR/SC and prefetch Probe
records, which use different admission and reservation conditions.
