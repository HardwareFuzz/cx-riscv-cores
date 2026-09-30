# TLBroadcast D tracker source reuse can match multiple responses

- Record ID: `ROCKET-TLBROADCAST_D_TRACKER_SOURCE_REUSE`
- Core: Rocket Chip
- Source repository: [chipsalliance/rocket-chip](https://github.com/chipsalliance/rocket-chip)
- Scope: shared TLBroadcast tracker and source-ID coherence response selection
- Record kind: canonical upstream TileLink RTL fix
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: exact affected parent and direct fix, the tracker state transition, and the shared coherent-client boundary are all established
- Affected parent: [0a3e7c9a](https://github.com/chipsalliance/rocket-chip/commit/0a3e7c9a12e93be03ffd92ef9775da0a120d0f4e)
- Direct fix: [ef63230b](https://github.com/chipsalliance/rocket-chip/commit/ef63230bdff7413acbb3e61e78941ce14b297bc0), “TLBroadcast: fix bug where multiple trackers could match a response (#1690)”
- Pull request: [#1690](https://github.com/chipsalliance/rocket-chip/pull/1690)
- Canonical upstream master: [55bcad0f](https://github.com/chipsalliance/rocket-chip/commit/55bcad0f59436de98ea510334121de8546b9e9d7)
- Retrieved: 2026-09-10

## Failure mechanism

At the affected parent, TLBroadcast selected every tracker that was both
non-idle and carrying the current D-channel source:

```scala
val d_trackerOH =
  Vec(trackers.map { t => !t.idle && t.source === d_normal.bits.source }).asUInt
```

The tracker remained non-idle until both its D response and its E-channel
GrantAck had completed. Its state was effectively:

```scala
val got_e  = RegInit(Bool(true))
val sent_d = RegInit(Bool(true))
val idle   = got_e && sent_d

when (io.d_last) { sent_d := Bool(true) }
when (io.e_last) { got_e := Bool(true) }
```

After the tracker sent its D response, it could therefore remain non-idle
while waiting for E/GrantAck. A new request could legally reuse the same
source ID during that interval. The old `d_trackerOH` then became multi-hot:
the old tracker still matched by `!idle`, and the new tracker matched the
reused source. One D response consequently selected more than one tracker;
`OHToUInt(d_trackerOH)` received an ambiguous selection, and response
bookkeeping could update the wrong tracker or multiple trackers.

## Necessary multi-client trigger

1. A shared TLBroadcast coherence manager tracks an outstanding transaction
   for one probe-capable cache client.
2. That transaction completes its D-channel response while its E-channel
   GrantAck remains outstanding, leaving its tracker non-idle.
3. A second coherent client or the same master issues a new request that
   reuses the outstanding source ID.
4. The shared manager receives a D response for the reused source while both
   trackers satisfy the affected match predicate.
5. The resulting multi-hot selection makes the response routing and tracker
   completion state inconsistent at the shared coherence boundary.

This requires concurrent tracker state at a shared coherent fabric boundary;
a standalone single-client transaction with no source reuse cannot create the
two-tracker match.

## Canonical fix and closure

The direct upstream fix adds an explicit D-response obligation to each
tracker. Selection is based on that obligation rather than on overall
transaction idleness:

```scala
val d_trackerOH =
  Vec(trackers.map { t => t.need_d && t.source === d_normal.bits.source }).asUInt

io.need_d := !sent_d
```

Once a tracker has sent its D response, `need_d` is cleared even if the
tracker remains occupied while waiting for E/GrantAck. A reused source ID
therefore cannot make the completed tracker match a later D response. The
fixed source is retained at canonical upstream master [Broadcast.scala](https://github.com/chipsalliance/rocket-chip/blob/55bcad0f59436de98ea510334121de8546b9e9d7/src/main/scala/tilelink/Broadcast.scala).

The shared boundary is present in the canonical multicore construction:
TLBroadcast enumerates all probe-capable clients and maintains trackers for
the shared coherence manager. [BankedCoherenceParams.scala](https://github.com/chipsalliance/rocket-chip/blob/55bcad0f59436de98ea510334121de8546b9e9d7/src/main/scala/subsystem/BankedCoherenceParams.scala)
instantiates the TLBroadcast node as part of the banked coherent TileLink
fabric. The direct fix is an ancestor of canonical master
`55bcad0f59436de98ea510334121de8546b9e9d7`, providing the complete history
from the affected RTL to the retained repair.

## Distinct boundary

This record is distinct from
`ROCKET-TLBROADCAST_MULTIBEAT_TRACKER_HOLD`: its affected parent predates the
`need_d` correction and its failure is simultaneous matching of a completed-D
tracker with a newly allocated tracker. The multibeat record starts from the
later state that already contains `need_d` and addresses selection stability
across the beats of one D response.
