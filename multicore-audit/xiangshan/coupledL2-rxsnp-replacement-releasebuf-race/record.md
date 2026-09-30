# RXSNP could read replacement data before the ReleaseBuffer write

- Record ID: `XIANGSHAN-COUPLEDL2-RXSNP-REPLACEMENT-RELEASEBUF-RACE`
- Core: XiangShan
- Source repository: [OpenXiangShan/XSCache](https://github.com/OpenXiangShan/XSCache)
- Scope: shared CHI RXSNP, MSHR replacement, and ReleaseBuffer data ordering
- Record kind: canonical upstream XSCache CHI RTL fix
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact parent/fix commits, the documented pipeline timing, the ReleaseBuffer data path, and canonical master ancestry
- Affected base: [0fa991ae](https://github.com/OpenXiangShan/XSCache/commit/0fa991aef56e57bed3dbc0c29411343a8071c3a8)
- Fixed revision: [23adbaea](https://github.com/OpenXiangShan/XSCache/commit/23adbaea68b077737df88a78d26bd3474bc9ad25)
- Canonical fix: [XSCache commit 23adbaea](https://github.com/OpenXiangShan/XSCache/commit/23adbaea68b077737df88a78d26bd3474bc9ad25), retained in canonical master
- Retrieved: 2026-09-10

## Failure mechanism

In the affected [`RXSNP.scala`](https://github.com/OpenXiangShan/XSCache/blob/0fa991aef56e57bed3dbc0c29411343a8071c3a8/src/main/scala/coupledL2/tl2chi/RXSNP.scala), both replacement-snoop admission masks used the current `w_replResp` state directly:

```scala
val replaceBlockSnpMask = VecInit(io.msInfo.map(s =>
  s.valid &&
  s.bits.set === task.set &&
  s.bits.metaTag === task.tag &&
  !s.bits.dirHit &&
  isValid(s.bits.metaState) &&
  s.bits.w_replResp &&
  (!s.bits.w_rprobeacklast || s.bits.w_releaseack) &&
  !s.bits.willFree
)).asUInt

val replaceNestSnpMask = VecInit(io.msInfo.map(s =>
  s.valid &&
  s.bits.set === task.set &&
  s.bits.metaTag === task.tag &&
  !s.bits.dirHit &&
  s.bits.metaState =/= INVALID &&
  s.bits.w_replResp &&
  s.bits.w_rprobeacklast &&
  !s.bits.w_releaseack
)).asUInt
```

The RXSNP task bundle derives `snpHitRelease` and
`snpHitReleaseWithData` from these masks. That admission decision allows the
incoming snoop to leave the RXSNP queue and enter the snoop pipeline.

In the same affected revision, [`MSHR.scala`](https://github.com/OpenXiangShan/XSCache/blob/0fa991aef56e57bed3dbc0c29411343a8071c3a8/src/main/scala/coupledL2/tl2chi/MSHR.scala) sets `state.w_replResp` when the replacement response is accepted, and exports it through `io.msInfo`. Replacement data is written to the ReleaseBuffer later by the stage-5 write path in [`MainPipe.scala`](https://github.com/OpenXiangShan/XSCache/blob/0fa991aef56e57bed3dbc0c29411343a8071c3a8/src/main/scala/coupledL2/tl2chi/MainPipe.scala). The snoop-side ReleaseBuffer read is issued earlier in the request arbitration path and is consumed by the snoop response data path.

## Necessary multi-client trigger

The upstream fix describes the concrete sequence:

1. A refill for cacheline X selects cacheline Y as its victim.
2. The MSHR sets `w_replResp` when the replacement response is accepted.
3. An independent incoming CHI snoop for Y is dequeued from RXSNP because the current state already satisfies the replacement mask.
4. The snoop pipeline reads Y from the ReleaseBuffer at its stage 2.
5. The refill pipeline writes the newest Y data into the ReleaseBuffer only at stage 5.

The required activities are therefore a local refill/replacement transaction
and an independent coherent peer sending the same-line snoop. Without the
peer snoop, the replacement transaction does not exercise this admission and
ReleaseBuffer read-before-write ordering window.

## Confirmed consequence

The snoop can observe the old victim data from the ReleaseBuffer instead of
the newest replacement data. That stale line can be used to form the snoop
response or forwarded data returned to the CHI peer. The confirmed failure is
incorrect coherent data visibility during replacement; this record does not
claim a broader permanent-memory-loss consequence.

## Canonical fix and closure

The direct fix [`23adbaea`](https://github.com/OpenXiangShan/XSCache/commit/23adbaea68b077737df88a78d26bd3474bc9ad25), titled
`fix(RXSNP): fix bug for race condition on nested snoop`, changes the
replacement timing predicates so the first cycle in which `w_replResp`
becomes visible remains blocked. The relevant changes are:

```scala
s.bits.w_replResp &&
(!s.bits.w_rprobeacklast ||
 s.bits.w_releaseack ||
 !RegNext(s.bits.w_replResp))
```

and:

```scala
RegNext(s.bits.w_replResp) &&
s.bits.w_rprobeacklast &&
!s.bits.w_releaseack
```

This delays nested replacement-snoop admission by the cycle needed to align
the ReleaseBuffer read with the replacement data write. The fix commit is an
ancestor of canonical XSCache master
[`dfd3edcf`](https://github.com/OpenXiangShan/XSCache/commit/dfd3edcf42b772e2a21178579b93bafc956f99b8), and the fixed RXSNP gating remains in that canonical revision. No linked issue or PR was needed for the closure: the exact fix commit and its canonical ancestry provide the historical closure.

Source evidence:

- [affected `RXSNP.scala`](https://github.com/OpenXiangShan/XSCache/blob/0fa991aef56e57bed3dbc0c29411343a8071c3a8/src/main/scala/coupledL2/tl2chi/RXSNP.scala)
- [affected `MSHR.scala`](https://github.com/OpenXiangShan/XSCache/blob/0fa991aef56e57bed3dbc0c29411343a8071c3a8/src/main/scala/coupledL2/tl2chi/MSHR.scala)
- [affected `MainPipe.scala`](https://github.com/OpenXiangShan/XSCache/blob/0fa991aef56e57bed3dbc0c29411343a8071c3a8/src/main/scala/coupledL2/tl2chi/MainPipe.scala)
- [fixed `RXSNP.scala`](https://github.com/OpenXiangShan/XSCache/blob/23adbaea68b077737df88a78d26bd3474bc9ad25/src/main/scala/coupledL2/tl2chi/RXSNP.scala)
- [canonical master](https://github.com/OpenXiangShan/XSCache/commit/dfd3edcf42b772e2a21178579b93bafc956f99b8)

## Duplicate boundary

This is distinct from the existing
[`coupledL2-rxsnp-cmo-blocking-race`](../coupledL2-rxsnp-cmo-blocking-race/record.md),
which gates RXSNP around CMO `rprobe`/`cmometaw` work. It is also distinct
from the CBO ReleaseBuffer record, which covers omission of dirty-data
preservation for a CBO-inval-derived Evict. This record covers the
replacement-specific `w_replResp` admission cycle and the resulting
ReleaseBuffer read-before-write race.
