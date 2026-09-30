# TLBroadcast can change the selected tracker during a multibeat D response

- Record ID: `ROCKET-TLBROADCAST_MULTIBEAT_TRACKER_HOLD`
- Core: Rocket Chip
- Source repository: [chipsalliance/rocket-chip](https://github.com/chipsalliance/rocket-chip)
- Scope: shared TLBroadcast multibeat D-response tracker selection
- Record kind: canonical upstream TileLink RTL fix
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: exact affected parent and direct fix, the multibeat selection path, and the shared coherent-client boundary are all established
- Affected parent: [db1ff281](https://github.com/chipsalliance/rocket-chip/commit/db1ff2818b16bc915770e4a6c3f316fa53beb70d)
- Direct fix: [f4783b7a](https://github.com/chipsalliance/rocket-chip/commit/f4783b7ab2b86d7933b56d673f4a22514741fa3e), “TLBroadcast: fix bug when masters early re-use source ID”
- Canonical upstream master: [55bcad0f](https://github.com/chipsalliance/rocket-chip/commit/55bcad0f59436de98ea510334121de8546b9e9d7)
- Retrieved: 2026-09-10

## Failure mechanism

At the affected parent, TLBroadcast recomputed the tracker one-hot directly
from the current tracker state and the current D beat:

```scala
val d_trackerOH =
  VecInit(trackers.map { t =>
    t.need_d && t.source === d_normal.bits.source
  }).asUInt
```

The same live selection drove the D-channel sink and the completion signal
for each tracker. A multibeat D response could therefore begin with one
tracker selected and encounter a different set of matching trackers on a
later beat. If the master reused the source ID before the first response was
complete, a newly allocated tracker could match the same source while the
original tracker still needed later beats. Response routing and
`d_last`/completion bookkeeping then used an unstable selection, so a beat
could be associated with the wrong tracker or with more than one tracker.

## Necessary multi-client trigger

1. The shared coherence manager has at least two tracker-eligible,
   probe-capable cache clients or transactions in flight.
2. One transaction produces a multibeat D-channel response.
3. Before its final D beat, a master reuses the same source ID and the
   manager allocates another tracker for the new request.
4. On a later D beat, the old and new tracker state both satisfy
   `need_d && source === d_normal.bits.source`, while the affected RTL
   recomputes the selection instead of retaining the first-beat choice.
5. The selected tracker set can change across the response, making D sink
   routing and tracker completion inconsistent at the shared TileLink
   coherence boundary.

The trigger depends on concurrent source-bearing activity at the shared
multi-client fabric and on a response with more than one beat. A single
isolated one-beat response does not exercise the selection transition.

## Canonical fix and closure

The direct upstream fix derives first/last-beat information and holds the
tracker selection after the first beat:

```scala
val (d_first, d_last, _) = edgeIn.firstlast(d_normal)

val d_trackerOH =
  VecInit(trackers.map { t =>
    t.need_d && t.source === d_normal.bits.source
  }).asUInt holdUnless d_first
```

The held selection is then used consistently for the D sink and completion:

```scala
d_normal.bits.sink := OHToUInt(d_trackerOH)

(trackers zip d_trackerOH.asBools) foreach { case (tracker, select) =>
  tracker.d_last := select && d_normal.fire() && d_response && d_last
}
```

The fixed source is retained at canonical upstream master [Broadcast.scala](https://github.com/chipsalliance/rocket-chip/blob/55bcad0f59436de98ea510334121de8546b9e9d7/src/main/scala/tilelink/Broadcast.scala).
The direct fix is an ancestor of master
`55bcad0f59436de98ea510334121de8546b9e9d7`, closing the affected parent
history with the retained repair.

The shared multicore boundary is explicit in the canonical design:
TLBroadcast gathers all probe-capable clients for the coherence manager, and
[BankedCoherenceParams.scala](https://github.com/chipsalliance/rocket-chip/blob/55bcad0f59436de98ea510334121de8546b9e9d7/src/main/scala/subsystem/BankedCoherenceParams.scala)
connects that manager into the banked coherent TileLink fabric.

## Distinct boundary

This record is distinct from
`ROCKET-TLBROADCAST_D_TRACKER_SOURCE_REUSE`. The first record starts at the
earlier parent before `need_d` exists and covers multiple trackers matching a
D response after one tracker has already completed D. This record starts at
the later parent, which already uses `need_d`, and covers the separate
instability of live tracker selection across the beats of one multibeat
response.
