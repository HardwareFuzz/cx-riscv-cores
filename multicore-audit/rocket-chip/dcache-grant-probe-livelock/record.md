# DCache Grant/Probe arbitration could livelock

- Record ID: `ROCKET-DCACHE_GRANT_PROBE_LIVELOCK`
- Core: Rocket Chip
- Source repository: [chipsalliance/rocket-chip](https://github.com/chipsalliance/rocket-chip)
- Scope: shared TileLink DCache Grant and Probe progress
- Record kind: canonical upstream DCache coherence/liveness fix
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact parent/fix commit, the D/E/B-channel state interaction, the external coherent-client trigger, and canonical mainline closure
- Affected parent: [728569c7](https://github.com/chipsalliance/rocket-chip/commit/728569c71776b92c78aed70554abda1fc538abdc)
- Fixed revision: [cc9ec1d5](https://github.com/chipsalliance/rocket-chip/commit/cc9ec1d51a1359cd9f2d88e4183eedfa0d3ba020), `Send D$ grant acks early; accept release acks early`
- Canonical closure: direct mainline commit [cc9ec1d5](https://github.com/chipsalliance/rocket-chip/commit/cc9ec1d51a1359cd9f2d88e4183eedfa0d3ba020), retained in upstream `master`
- Retrieved: 2026-09-10

## Failure mechanism

The affected DCache did not coordinate cached D-channel Grants with the
E-channel GrantAck path and had no bounded post-Grant opportunity for the
processor-side request path. Incoming TileLink B-channel Probes could keep
being serviced while the local processor remained unable to advance through
its Grant path. The resulting repeated Probe-side arbitration could livelock
the cache/processor interface.

The upstream commit identifies the condition directly: the B-channel must
be blocked for a few cycles after a Grant so that the processor can issue at
least one request. The defect is a progress failure in the shared DCache
coherence state machine, not a latency-only change.

## Necessary multi-client trigger

1. Hart A has an outstanding cache request and receives a cached Grant or
   GrantData.
2. Independently, Hart B issues a miss, upgrade, or conflicting access.
3. The coherence manager presents a B-channel Probe to Hart A immediately
   after the Grant.
4. Repeated Probe traffic can keep selecting Probe-side work while Hart A's
   processor request cannot progress under the affected arbitration.
5. The missing fairness window leaves the shared transaction in livelock.

The B-channel Probe is caused by an independent coherent client. An isolated
single-client request stream does not create the cross-client Probe pressure
that exposes this progress failure.

## Canonical fix and closure

Commit [cc9ec1d5](https://github.com/chipsalliance/rocket-chip/commit/cc9ec1d51a1359cd9f2d88e4183eedfa0d3ba020)
removes the unnecessary processor-side GrantAck queue, sends the cached
GrantAck directly from the cached D response, and ties cached D acceptance
to E-channel readiness. It adds explicit progress state:

```scala
val grantInProgress = Reg(init = Bool(false))
val blockProbeAfterGrantCount = Reg(init = UInt(0))
```

The state is set while a cached Grant is consumed and loads a bounded
post-Grant Probe-blocking count after the final Grant beat. This gives the
processor a forward-progress window and prevents the livelock. The direct
mainline fix has exact parent
`728569c71776b92c78aed70554abda1fc538abdc`.

Source evidence:

- [affected `DCache.scala`](https://github.com/chipsalliance/rocket-chip/blob/728569c71776b92c78aed70554abda1fc538abdc/src/main/scala/rocket/DCache.scala)
- [fixed `DCache.scala`](https://github.com/chipsalliance/rocket-chip/blob/cc9ec1d51a1359cd9f2d88e4183eedfa0d3ba020/src/main/scala/rocket/DCache.scala)
- [fixed commit](https://github.com/chipsalliance/rocket-chip/commit/cc9ec1d51a1359cd9f2d88e4183eedfa0d3ba020)

## Duplicate boundary

This does not cover LR/SC reservation blocking, the pending-ReleaseAck
ordering window, or the later address-qualified ReleaseAck/Acquire checks.
Those are separate DCache states and fixes.
