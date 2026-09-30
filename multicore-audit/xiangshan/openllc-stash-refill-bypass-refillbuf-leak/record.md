# StashOnceShared refill bypass could leak a RefillBuf entry

- Record ID: `XIANGSHAN-OPENLLC-STASH-REFILL-BYPASS-REFILLBUF-LEAK`
- Core: XiangShan
- Source repository: [OpenXiangShan/XSCache](https://github.com/OpenXiangShan/XSCache)
- Scope: shared openLLC StashOnceShared refill, MemUnit bypass, and RefillUnit
- Record kind: canonical upstream XSCache openLLC RTL fix
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact affected parent, complete bypass/refill dataflow, direct repair, and merged canonical closure
- Affected base: [b7211c6c](https://github.com/OpenXiangShan/XSCache/commit/b7211c6c398bc188641a1fc256bbf082a6756bef)
- Fixed revision: [237e18fa](https://github.com/OpenXiangShan/XSCache/commit/237e18fa204534e8ea5cabc2b5ee2101d85de6a8)
- Direct repair: [8dc36e35](https://github.com/OpenXiangShan/XSCache/commit/8dc36e35a00b844f4f452d39baa330c18fd46d33)
- Canonical fix: [XSCache PR #25](https://github.com/OpenXiangShan/XSCache/pull/25), merged with the equivalent core repair in `237e18fa`
- Retrieved: 2026-09-10

## Failure mechanism

In the affected [`MainPipe.scala`](https://github.com/OpenXiangShan/XSCache/blob/b7211c6c398bc188641a1fc256bbf082a6756bef/src/main/scala/openLLC/MainPipe.scala), a `StashOnceShared` miss that is neither a self-hit nor a client hit sets:

```scala
val stashMissRead_s4 = stashOnceShared_s4 && !self_hit_s4 && !clients_hit_s4
val stashMissRefill_s4 = stashMissRead_s4
```

That path allocates a RefillUnit entry, allocates a ResponseUnit entry, and
sends a `ReadNoSnp` request to MemUnit. The RefillUnit entry starts with
`w_datRsp` clear because it still needs the cacheline data.

The affected [`MemUnit.scala`](https://github.com/OpenXiangShan/XSCache/blob/b7211c6c398bc188641a1fc256bbf082a6756bef/src/main/scala/openLLC/MemUnit.scala) detects a same-line conflict between a read and a pending write:

```scala
def sameAddr(a: Task, b: Task): Bool =
  Cat(a.tag, a.set) === Cat(b.tag, b.set)

def conflict(r: Task, w: Task): Bool =
  sameAddr(r, w) &&
  r.chiOpcode === ReadNoSnp &&
  w.chiOpcode === WriteNoSnpFull
```

When the conflict is present, MemUnit returns the pending write's data as
registered `bypassData` and does not allocate a normal memory-read entry or
send a downstream read that would produce RXDAT.

The affected [`ResponseUnit.scala`](https://github.com/OpenXiangShan/XSCache/blob/b7211c6c398bc188641a1fc256bbf082a6756bef/src/main/scala/openLLC/ResponseUnit.scala) already consumes `MemUnit.bypassData`. The affected [`RefillUnit.scala`](https://github.com/OpenXiangShan/XSCache/blob/b7211c6c398bc188641a1fc256bbf082a6756bef/src/main/scala/openLLC/RefillUnit.scala) has no bypass-data input or update path, and the affected [`Slice.scala`](https://github.com/OpenXiangShan/XSCache/blob/b7211c6c398bc188641a1fc256bbf082a6756bef/src/main/scala/openLLC/Slice.scala) connects the bypass only to ResponseUnit. RefillUnit can receive data only from the ordinary upstream or downstream RXDAT paths.

## Necessary shared-cache trigger

The failure requires two concurrent activities in the shared openLLC:

1. A pending same-line `WriteNoSnpFull` leaves a MemUnit write entry.
2. A `StashOnceShared` miss allocates its refill and response work and issues
   the same-line `ReadNoSnp`.

MemUnit then satisfies the read through its internal bypass. ResponseUnit
consumes the returned beats, but RefillUnit receives neither those beats nor
downstream RXDAT.

## Confirmed consequence

The RefillUnit entry remains valid with `w_datRsp` unset. Its issue condition
requires the data-response state, while the ordinary cancellation path
explicitly excludes `StashOnceShared` entries. The entry therefore remains in
the RefillBuf and can reach the existing assertion:

```scala
assert(t < timeoutThreshold.U, "RefillBuf Leak(id: %d)", i.U)
```

The confirmed consequences are a `RefillBuf Leak` assertion when the check is
enabled, or persistent RefillBuf occupancy that blocks later shared-LLC
refills when it is not. The `StashOnceShared` refill itself cannot complete
through the missing data path.

## Canonical fix and closure

The direct repair [`8dc36e35`](https://github.com/OpenXiangShan/XSCache/commit/8dc36e35a00b844f4f452d39baa330c18fd46d33), titled
`fix(openLLC): complete stash refill from MemUnit bypass data`, adds a
`bypassData` input to RefillUnit, connects MemUnit's bypass in Slice, matches
the beats by transaction ID, updates the refill data and beat-valid state,
and sets `w_datRsp` only when all required beats have arrived. It also checks
that data sources are not mixed for one refill transaction.

The direct repair commit is a branch-only commit rather than an ancestor of
canonical XSCache master. Its core change was subsequently included in the
merged [XSCache PR #25](https://github.com/OpenXiangShan/XSCache/pull/25),
whose canonical commit is
[`237e18fa`](https://github.com/OpenXiangShan/XSCache/commit/237e18fa204534e8ea5cabc2b5ee2101d85de6a8). The canonical commit body names
`fix(openLLC): complete stash refill from MemUnit bypass data`, and its source
contains the RefillUnit bypass input/update path and the Slice connection. It
is an ancestor of canonical XSCache master
[`dfd3edcf`](https://github.com/OpenXiangShan/XSCache/commit/dfd3edcf42b772e2a21178579b93bafc956f99b8). This provides fixed-history
closure for the exact mechanism while preserving the distinction between
the branch repair SHA and the merged canonical commit object.

Source evidence:

- [affected `MainPipe.scala`](https://github.com/OpenXiangShan/XSCache/blob/b7211c6c398bc188641a1fc256bbf082a6756bef/src/main/scala/openLLC/MainPipe.scala)
- [affected `MemUnit.scala`](https://github.com/OpenXiangShan/XSCache/blob/b7211c6c398bc188641a1fc256bbf082a6756bef/src/main/scala/openLLC/MemUnit.scala)
- [affected `ResponseUnit.scala`](https://github.com/OpenXiangShan/XSCache/blob/b7211c6c398bc188641a1fc256bbf082a6756bef/src/main/scala/openLLC/ResponseUnit.scala)
- [affected `RefillUnit.scala`](https://github.com/OpenXiangShan/XSCache/blob/b7211c6c398bc188641a1fc256bbf082a6756bef/src/main/scala/openLLC/RefillUnit.scala)
- [affected `Slice.scala`](https://github.com/OpenXiangShan/XSCache/blob/b7211c6c398bc188641a1fc256bbf082a6756bef/src/main/scala/openLLC/Slice.scala)
- [direct repair `8dc36e35`](https://github.com/OpenXiangShan/XSCache/commit/8dc36e35a00b844f4f452d39baa330c18fd46d33)
- [merged PR #25](https://github.com/OpenXiangShan/XSCache/pull/25)
- [canonical fixed commit `237e18fa`](https://github.com/OpenXiangShan/XSCache/commit/237e18fa204534e8ea5cabc2b5ee2101d85de6a8)

## Duplicate boundary

This is distinct from the existing CoupledL2 `SnpStash` records, which cover
CHI `SnpStashX` snoop/state behavior. This record is an openLLC
`StashOnceShared` refill-data path: the defect is the missing
`MemUnit.bypassData` consumer in RefillUnit, and the consequence is a
RefillBuf leak. No existing XiangShan record covers this combination.
