# TLBroadcast can complete ProbeAckData before its translated cleanup response

- Record ID: `ROCKET-TLBROADCAST_PROBEACKDATA_COMPLETION`
- Core: Rocket Chip
- Source repository: [chipsalliance/rocket-chip](https://github.com/chipsalliance/rocket-chip)
- Scope: shared TLBroadcast ProbeAckData completion and downstream cleanup ordering
- Record kind: canonical upstream TileLink RTL fix
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: exact affected parent and direct fix, the C-to-D completion dependency, and the shared coherent-client boundary are all established
- Affected parent: [3c9718ec](https://github.com/chipsalliance/rocket-chip/commit/3c9718ec8f148f55b7ee31f8f130f44d90c471d4)
- Direct fix: [fbfa15ef](https://github.com/chipsalliance/rocket-chip/commit/fbfa15efea7d682da88937c2882cf0583e6c3676), “TLBroadcast: support non-FIFO devices (#482)”
- Pull request: [#482](https://github.com/chipsalliance/rocket-chip/pull/482)
- Canonical upstream master: [55bcad0f](https://github.com/chipsalliance/rocket-chip/commit/55bcad0f59436de98ea510334121de8546b9e9d7)
- Retrieved: 2026-09-10

## Failure mechanism

At the affected parent, the C-channel completion counter treated plain
ProbeAck and dirty-data ProbeAckData as the same event:

```scala
val c_decrement = in.c.fire() && (c_probeack || c_probeackdata)
val c_last = edgeIn.last(in.c)

tracker.probeack :=
  c_decrement &&
  c_last &&
  tracker.line === (in.c.bits.address >> lineShift)
```

ProbeAckData also caused TLBroadcast to emit a downstream cleanup request
carrying the dirty data:

```scala
val put_what = Mux(c_releasedata, TRANSFORM_B, DROP)

putfull.valid :=
  in.c.valid &&
  (c_probeackdata || c_releasedata)

putfull.bits :=
  edgeOut.Put(
    Cat(put_what, in.c.bits.source),
    in.c.bits.address,
    in.c.bits.size,
    in.c.bits.data
  )._2
```

The old counter could therefore complete the probe obligation when the
ProbeAckData was accepted on C, before the translated `PutFull(DROP)` had
received its downstream D-channel `AccessAck`. The tracker could become
ready for the next operation while the dirty-data cleanup remained in
flight. With a non-FIFO manager, the next operation or response could pass
the still-outstanding cleanup, violating the ordering required by this
coherence conversion and exposing stale or incorrectly ordered data.

## Necessary multi-client trigger

1. A shared TLBroadcast coherence manager sends a Probe to one
   probe-capable cache client because another coherent client needs the
   cache line.
2. The probed cache returns a dirty `ProbeAckData` on the C channel.
3. TLBroadcast accepts that C beat and issues the translated downstream
   `PutFull(DROP)` cleanup transaction.
4. The downstream manager permits non-FIFO response ordering, so the D
   `AccessAck` for the cleanup is not required to precede the next tracked
   operation under the affected completion logic.
5. The tracker advances at C acceptance, allowing the next shared-coherence
   operation to proceed before the cleanup D response completes.

The trigger is inherently cross-client: the Probe originates from a shared
coherence transaction involving another cache client, and the dirty-data
response plus downstream cleanup cross the TLBroadcast manager boundary.
The fixed-history TLBroadcast configuration explicitly supports non-FIFO
devices with `fifoId = None`, so the ordering condition is part of the
canonical shared fabric.

## Canonical fix and closure

The direct upstream fix separates C-channel plain ProbeAck completion from
the D-channel completion of the translated cleanup:

```scala
tracker.probenack :=
  in.c.fire() &&
  c_probeack &&
  select

tracker.probedack := select && out.d.fire() && d_drop
```

The tracker decrements on either event and accounts for both when they occur
in the same cycle:

```scala
when (io.probenack || io.probedack) {
  count := count - Mux(
    io.probenack && io.probedack,
    UInt(2),
    UInt(1)
  )
}
```

Thus ProbeAckData does not complete the probe obligation merely when C is
accepted; its translated DROP transaction must also complete on D. The
fixed source remains in canonical upstream master [Broadcast.scala](https://github.com/chipsalliance/rocket-chip/blob/55bcad0f59436de98ea510334121de8546b9e9d7),
where the TLBroadcast parameters retain `fifoId = None` and the tracker
keeps the two completion paths separate.

The shared-coherence topology is explicit: TLBroadcast gathers all
probe-capable clients, and [BankedCoherenceParams.scala](https://github.com/chipsalliance/rocket-chip/blob/55bcad0f59436de98ea510334121de8546b9e9d7/src/main/scala/subsystem/BankedCoherenceParams.scala)
instantiates it in the banked coherent TileLink fabric. The direct fix is an
ancestor of canonical master
`55bcad0f59436de98ea510334121de8546b9e9d7`, closing the exact affected
history.

## Distinct boundary

This record is distinct from
`ROCKET-TLBROADCAST_D_TRACKER_SOURCE_REUSE` and
`ROCKET-TLBROADCAST_MULTIBEAT_TRACKER_HOLD`. Those records concern D-channel
source-to-tracker selection and multibeat selection stability. This record
concerns the separate completion dependency between a peer's C-channel
ProbeAckData and TLBroadcast's translated downstream D-channel cleanup
response.
