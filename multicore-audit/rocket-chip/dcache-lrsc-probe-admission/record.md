# Stage-2 LR could continue blocking a DCache Probe

- Record ID: `ROCKET-DCACHE_LRSC_PROBE_ADMISSION`
- Core: Rocket Chip
- Source repository: [chipsalliance/rocket-chip](https://github.com/chipsalliance/rocket-chip)
- Scope: shared TileLink DCache LR/SC and Probe admission
- Record kind: canonical upstream DCache coherence/liveness fix
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact post-backoff base, the independent stage-2 LR predicate, the cross-hart Probe trigger, and merged PR #1624
- Affected parent: [504972bf](https://github.com/chipsalliance/rocket-chip/commit/504972bf699e48972b2b74a3bf18b76b5ba17e20)
- Fixed revision: [587badd5](https://github.com/chipsalliance/rocket-chip/commit/587badd5261ac6a2824f9d70fafc26f60020fb33), with PR follow-up [c89de4ed](https://github.com/chipsalliance/rocket-chip/commit/c89de4ed0f29601469ce04be3192909fdf8fab2f)
- Canonical fix: [Rocket Chip PR #1624](https://github.com/chipsalliance/rocket-chip/pull/1624), merged as [cf29601a](https://github.com/chipsalliance/rocket-chip/commit/cf29601a9896de44deae4332bd817dc1e155c7ff)
- Retrieved: 2026-09-10

## Failure mechanism

The affected parent already contained the earlier LR/SC countdown backoff:

```scala
val lrscValid = lrscCount > lrscBackoff
```

However, Probe admission still had a separate unconditional stage-2 LR
term:

```scala
val block_probe =
  releaseInFlight ||
  grantInProgress ||
  blockProbeAfterGrantCount > 0 ||
  lrscValid ||
  (s2_valid && s2_lr)
```

Thus an LR in stage 2 could hold `tl_out.b.ready` low even during the
countdown interval in which `lrscValid` was already false. Repeated LR
traffic could keep the Probe from being accepted and prevent a peer's
coherence transaction from completing.

## Necessary multi-client trigger

1. Hart A executes repeated LR operations or a tight LR/SC loop.
2. Hart B performs a conflicting store or cache upgrade.
3. The coherence manager sends a Probe to Hart A.
4. The stage-2 LR term in the affected DCache blocks B-channel admission,
   and repeated LR traffic can sustain the block.
5. The coherent transaction from Hart B cannot complete until the Probe is
   accepted.

The decisive event is the Probe from an independent coherent client. This is
not merely a local LR/SC result calculation.

## Canonical fix and closure

PR #1624 removes the independent stage-2 LR block from `block_probe` and
uses the accepted Probe (`s1_probe`) to clear the reservation. It also
ensures LR/SC state is killed only for the valid, non-killed stage-2 cases:

```scala
val block_probe =
  releaseInFlight ||
  grantInProgress ||
  blockProbeAfterGrantCount > 0 ||
  lrscValid
```

The fix is based on the already-present backoff behavior, so it is a later
omission rather than a duplicate of the earlier countdown correction. The
functional fix commit and its follow-up are merged through PR #1624 at
`cf29601a9896de44deae4332bd817dc1e155c7ff`.

Source evidence:

- [affected `DCache.scala`](https://github.com/chipsalliance/rocket-chip/blob/504972bf699e48972b2b74a3bf18b76b5ba17e20/src/main/scala/rocket/DCache.scala)
- [fixed `DCache.scala`](https://github.com/chipsalliance/rocket-chip/blob/c89de4ed0f29601469ce04be3192909fdf8fab2f/src/main/scala/rocket/DCache.scala)
- [PR #1624](https://github.com/chipsalliance/rocket-chip/pull/1624)

## Duplicate boundary

`ROCKET-DCACHE_LRSC_PROBE_PROGRESS` covers the earlier defect in which the
reservation countdown itself blocked Probe progress. This record starts
from a later base that contains that backoff and covers the remaining
stage-2 LR admission term.
