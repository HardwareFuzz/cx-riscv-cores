# CompAck could be sent before the first DataSepResp beat

- Record ID: `XIANGSHAN-COUPLEDL2-COMPACK-DATASEP-ORDERING`
- Core: XiangShan
- Source repository: [OpenXiangShan/CoupledL2](https://github.com/OpenXiangShan/CoupledL2)
- Scope: shared CHI CompAck and separated-data response ordering
- Record kind: canonical upstream CoupledL2 CHI RTL fix
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact PR base, the active state-condition diff, the cross-RN ordering trigger, and merged upstream PR
- Affected base: [940467b5](https://github.com/OpenXiangShan/CoupledL2/commit/940467b53db4caaacd62c970de92f3db726c4bda)
- Fixed revision: [75008b1c](https://github.com/OpenXiangShan/CoupledL2/commit/75008b1c5557df8d29a51b8a3c422afab5561844)
- Canonical fix: [CoupledL2 PR #253](https://github.com/OpenXiangShan/CoupledL2/pull/253), merged upstream
- Retrieved: 2026-09-10

## Failure mechanism

In the affected `src/main/scala/coupledL2/tl2chi/MSHR.scala`, the transmit
valid for CompAck used `!s_compack && state.w_grant`. That allowed CompAck
after `RespSepData` had been observed but before the first `DataSepResp`
data beat had arrived. The receiver could consequently observe the
completion acknowledgement before the data stream had established the
required ordering point.

The fix changes the condition to
`!s_compack && state.w_grantfirst && state.w_grant`, requiring the first
data beat as well as the grant state before CompAck is emitted.

## Necessary multi-client trigger

PR #253 ties the ordering requirement to a transaction from one RN and a
subsequent snoop or related transaction from a different RN. The early
CompAck permits the shared HN-F/RN-F fabric to expose the wrong relative
order when those independent coherent clients overlap on the relevant
address. Without a second RN-F, there is no cross-client transaction whose
ordering can be violated.

## Canonical fix and closure

Merged commit [75008b1c](https://github.com/OpenXiangShan/CoupledL2/commit/75008b1c5557df8d29a51b8a3c422afab5561844)
adds the `w_grantfirst` requirement to the CompAck valid condition. PR #253
is closed and merged; its exact base is
`940467b53db4caaacd62c970de92f3db726c4bda` and its merge commit is
`75008b1c5557df8d29a51b8a3c422afab5561844`.

Source evidence:

- [affected `tl2chi/MSHR.scala`](https://github.com/OpenXiangShan/CoupledL2/blob/940467b53db4caaacd62c970de92f3db726c4bda/src/main/scala/coupledL2/tl2chi/MSHR.scala)
- [fixed `tl2chi/MSHR.scala`](https://github.com/OpenXiangShan/CoupledL2/blob/75008b1c5557df8d29a51b8a3c422afab5561844/src/main/scala/coupledL2/tl2chi/MSHR.scala)
- [PR #253](https://github.com/OpenXiangShan/CoupledL2/pull/253)

## Duplicate boundary

No retained XiangShan record covers CompAck/DataSepResp ordering. The
existing MSHR response-state records concern different state transitions and
do not assert this first-data-beat ordering requirement.
