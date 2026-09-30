# Rocket Core reversed the acquire and release ordering of AMOs

- Record ID: `ROCKET-CORE_AMO_AQ_RL_FENCE_DIRECTION`
- Core: Rocket Chip
- Source repository: [chipsalliance/rocket-chip](https://github.com/chipsalliance/rocket-chip)
- Scope: shared-memory AMO acquire/release ordering across Rocket harts
- Record kind: canonical upstream RocketCore RTL memory-ordering fix
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact `aq`/`rl` predicates, the architectural fence direction, the direct fix, and the merged upstream PR
- Affected parent: [95294bbd](https://github.com/chipsalliance/rocket-chip/commit/95294bbdcb00c3d61c4aa531850e27f97e1b727a)
- Fix commit: [eb6e192e](https://github.com/chipsalliance/rocket-chip/commit/eb6e192ec0a9e4e1341f5c876c17feecf585cc4b), `Fix mapping of acquire/release AMOs to fence operations`
- Canonical closure: [merge a48dd575](https://github.com/chipsalliance/rocket-chip/commit/a48dd575b23aa4b82368f19beaaf19e2d4bf1e3e), retained in upstream master [55bcad0f](https://github.com/chipsalliance/rocket-chip/commit/55bcad0f59436de98ea510334121de8546b9e9d7)
- Retrieved: 2026-09-10

## Failure mechanism

At the affected parent, the RocketCore instruction-ordering predicates
exchanged the `aq` and `rl` conditions:

```scala
val id_fence_next =
  id_ctrl.fence || id_ctrl.amo && id_amo_rl

val id_do_fence = Wire(init =
  id_rocc_busy && id_ctrl.fence ||
  id_mem_busy && (
    id_ctrl.amo && id_amo_aq ||
    id_ctrl.fence_i ||
    id_reg_fence && (id_ctrl.mem || id_ctrl.rocc)))
```

The required architectural directions are `AMO.aq` as `AMO; FENCE` and
`AMO.rl` as `FENCE; AMO`. The affected predicates implemented the opposite
directions. A release AMO therefore did not order preceding shared-memory
stores before the AMO, and an acquire AMO did not order following shared-memory
loads after the AMO.

## Necessary multi-hart trigger

1. Hart A performs a shared-memory store followed by an `AMO.rl` operation.
2. The affected RocketCore ordering logic places the fence in the wrong
   direction, allowing the earlier store to remain unordered with respect to
   the AMO as observed by another hart.
3. Conversely, a following load after `AMO.aq` can pass the intended acquire
   point and observe data without the required ordering.
4. A second Rocket hart or another shared-memory observer sees the resulting
   ordering violation through the common coherent memory system.

The upstream fix explicitly limits the manifestation to cacheable accesses
using the nonblocking DCache and to weakly ordered I/O regions; blocking DCache
accesses, the data scratchpad, and strongly ordered I/O are excluded. The
nonblocking L1 configuration is a built-in Rocket configuration, and the
multi-tile coreplex connects each tile to the shared system fabric in
[`RocketCoreplex.scala`](https://github.com/chipsalliance/rocket-chip/blob/95294bbdcb00c3d61c4aa531850e27f97e1b727a/src/main/scala/coreplex/RocketCoreplex.scala).

## Canonical fix and closure

The direct fix restores the architectural directions:

```scala
val id_fence_next =
  id_ctrl.fence || id_ctrl.amo && id_amo_aq

val id_do_fence = Wire(init =
  id_rocc_busy && id_ctrl.fence ||
  id_mem_busy && (
    id_ctrl.amo && id_amo_rl ||
    id_ctrl.fence_i ||
    id_reg_fence && (id_ctrl.mem || id_ctrl.rocc)))
```

The corrected predicates remain in
[`rocket/RocketCore.scala`](https://github.com/chipsalliance/rocket-chip/blob/55bcad0f59436de98ea510334121de8546b9e9d7/src/main/scala/rocket/RocketCore.scala).
This record is distinct from the Rocket DCache coherence records: it is an
instruction-ordering defect in `RocketCore.scala`, not a Probe, Grant, Release,
or reservation-admission state defect.
