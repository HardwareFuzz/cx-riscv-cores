# Halt-group extTrigger handling mixed hart indices and all-halted state

- Record ID: `ROCKET-DM_EXTTRIGGER_HALTGROUP`
- Core: Rocket Chip
- Source repository: [chipsalliance/rocket-chip](https://github.com/chipsalliance/rocket-chip)
- Scope: multi-hart Debug Module halt-group and external-trigger state
- Record kind: canonical upstream Debug Module RTL fix
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact PR base/fix/merge ancestry, both halt-group RTL defects, and concrete multi-hart trigger sequences
- Affected parent: [f517abbf](https://github.com/chipsalliance/rocket-chip/commit/f517abbf41abb65cea37421d3559f9739efd00a9)
- Fixed revision: [c79658c9](https://github.com/chipsalliance/rocket-chip/commit/c79658c9ad58e4022ae4c93486125bd1f94c702b)
- Canonical fix: [Rocket Chip PR #3748](https://github.com/chipsalliance/rocket-chip/pull/3748), merged as [1d470ef7](https://github.com/chipsalliance/rocket-chip/commit/1d470ef75d7550deb48e8697b465d820056bb976)
- Retrieved: 2026-09-10

## Failure mechanism

PR #3748 fixes two related halt-group defects in the Debug Module.

First, the affected firing logic indexed `haltedBitRegs` by the raw hart ID:

```scala
hgHartFiring(hg) :=
  hartHaltedWrEn &
  ~haltedBitRegs(hartHaltedId) &
  (hgParticipateHart(
    hartSelFuncs.hartIdToHartSel(hartHaltedId)) === hg.U)
```

The halted-bit storage was written using the mapped selection index from
`hartSelFuncs.hartIdToHartSel(hartHaltedId)`. With a non-identity hart-ID
mapping, the read and write indices referred to different harts, so halt
group firing could be missed or spuriously generated.

Second, the halt-group FSM accepted an external trigger after every
participating hart was already halted:

```scala
}.elsewhen (
  ~hgFired(hg) &
  (hgHartFiring(hg) | hgTrigFiring(hg))
) {
  hgFired(hg) := true.B
}
```

The missing `~hgHartsAllHalted(hg)` guard allowed a new extTrigger to
re-enter group-fired processing after the halt operation had completed.

## Necessary multi-hart trigger

For the index defect:

1. Configure multiple harts with a non-identity hart-ID-to-selection map.
2. Place the mapped harts in a halt group.
3. An external debugger halts a hart and writes its raw hart ID to the
   Debug ROM `HALTED` register.
4. The affected logic checks the wrong dense halted-bit entry and produces
   the wrong group-firing result.

For the all-halted defect:

1. Configure at least two harts in one halt group with an external trigger.
2. Set the halted bits for all participating harts.
3. A new edge arrives through `trigInReq`.
4. The affected FSM still sees `hgTrigFiring(hg)` and can mark the group
   fired even though no participating hart remains running.

Both failures require the Debug Module's multi-hart halt-group state. The
raw index failure additionally requires a non-identity mapping.

## Canonical fix and closure

The fix uses the same mapped index for the halted-bit test:

```scala
~haltedBitRegs(
  hartSelFuncs.hartIdToHartSel(hartHaltedId)
)
```

and prevents a group from firing on a new trigger after all of its harts
have halted:

```scala
}.elsewhen (
  ~hgFired(hg) &
  ~hgHartsAllHalted(hg) &
  (hgHartFiring(hg) | hgTrigFiring(hg))
) {
  hgFired(hg) := true.B
}
```

The PR fix commit `c79658c9...` is the direct child of the exact PR base
`f517abbf...`. The canonical merge later used the advanced master-side
parent `5c18d6e7...` and the fixed PR-side parent, producing merge commit
`1d470ef75d7550deb48e8697b465d820056bb976`.

Source evidence:

- [affected `Debug.scala`](https://github.com/chipsalliance/rocket-chip/blob/f517abbf41abb65cea37421d3559f9739efd00a9/src/main/scala/devices/debug/Debug.scala)
- [fixed `Debug.scala`](https://github.com/chipsalliance/rocket-chip/blob/c79658c9ad58e4022ae4c93486125bd1f94c702b/src/main/scala/devices/debug/Debug.scala)
- [PR #3748](https://github.com/chipsalliance/rocket-chip/pull/3748)

## Duplicate boundary

This is distinct from `ROCKET-DM_HARTARRAY_MASK_32PLUS`, which covers
compile-time HAWINDOW mask arithmetic. It is also distinct from CVA6's
Debug request-width truncation and from Rocket's CLINT MSIP address stride.
