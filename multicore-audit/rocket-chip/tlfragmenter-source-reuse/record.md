# TLFragmenter reused source values on the normal multibeat path

- Record ID: `ROCKET-TLFRAGMENTER_SOURCE_REUSE`
- Core: Rocket Chip
- Source repository: [chipsalliance/rocket-chip](https://github.com/chipsalliance/rocket-chip)
- Scope: shared TileLink Fragmenter source identity and response reassembly
- Record kind: canonical upstream TileLink RTL fix
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact normal-mode source encoding, the source-reuse waveform, the direct toggle-bit fix, and canonical upstream retention
- Affected parent: [c9e467a6](https://github.com/chipsalliance/rocket-chip/commit/c9e467a66866759b582780a36c04a2fa7dd5ab49)
- Fix commit: [c2b8b084](https://github.com/chipsalliance/rocket-chip/commit/c2b8b084615430f097e7f556659fc978337eba86), `tilelink: fix Fragmenter source re-use bug (#888)`
- Canonical closure: direct mainline commit [c2b8b084](https://github.com/chipsalliance/rocket-chip/commit/c2b8b084615430f097e7f556659fc978337eba86), retained in upstream master [55bcad0f](https://github.com/chipsalliance/rocket-chip/commit/55bcad0f59436de98ea510334121de8546b9e9d7)
- Retrieved: 2026-09-10

## Failure mechanism

At the affected parent, the Fragmenter allocated a toggle bit only when
`earlyAck` was enabled:

```scala
val fragmentBits = log2Ceil(maxSize / minSize)
val toggleBits = if (earlyAck) 1 else 0
val addedBits = fragmentBits + toggleBits
```

In the normal mode, the downstream source encoded only the original source
and fragment number. TileLink permits a master to reuse its original source
after the first response beat of a transaction. If the first multibeat burst
still has response fragments in flight when the master starts a second burst
with the same source, the two transactions reuse the same fragment-number
space. Their downstream source values collide, so response fragments cannot
be assigned uniquely to the original bursts.

The upstream history records the normal-mode overlap as the fragment sequence
`210` appearing simultaneously for two transactions. This is a source-identity
violation at the Fragmenter response reassembly boundary.

## Necessary shared-fabric trigger

1. A master on the shared TileLink fabric issues a multibeat burst A.
2. The first response beat of A returns, allowing the master to reuse its
   original source while later fragments of A remain outstanding.
3. The same master issues burst B with that source before A's remaining
   fragments complete.
4. With `earlyAck = false`, the affected Fragmenter gives both bursts the same
   fragment-number encoding.
5. Overlapping response fragments carry colliding downstream source values,
   and the Fragmenter loses unique transaction identity during reassembly.

`TLBusWrapper` creates the shared TileLink crossbar and Fragmenter boundary in
[`Bus.scala`](https://github.com/chipsalliance/rocket-chip/blob/c9e467a66866759b582780a36c04a2fa7dd5ab49/src/main/scala/tilelink/Bus.scala),
and multiple Rocket tiles attach to the common system/periphery fabric through
the coreplex topology. The source collision is therefore at a canonical
shared-fabric adapter boundary.

## Canonical fix and closure

The direct fix permanently allocates one toggle bit, records the toggle from
the first D beat, and uses the opposite toggle for the next A transaction:

```scala
val toggleBits = 1
val addedBits = fragmentBits + toggleBits
```

The corrected Fragmenter retains distinct source values for overlapping
transactions in both normal and early-ack operation. The fixed implementation
is retained in
[`tilelink/Fragmenter.scala`](https://github.com/chipsalliance/rocket-chip/blob/55bcad0f59436de98ea510334121de8546b9e9d7/src/main/scala/tilelink/Fragmenter.scala).

The earlier early-ack-specific toggle fix is already present in the parent;
this record covers the separate normal-mode omission where the toggle remained
conditional on `earlyAck`. It is distinct from the Fragmenter error-termination
and capability records.
