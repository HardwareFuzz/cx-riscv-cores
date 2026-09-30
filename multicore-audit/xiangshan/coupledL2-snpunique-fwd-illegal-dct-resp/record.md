# SnpUniqueFwd could generate an illegal forwarded snoop response state

- Record ID: `XIANGSHAN-COUPLEDL2-SNPUNIQUEFWD-ILLEGAL-DCT-RESP`
- Core: XiangShan
- Source repository: [OpenXiangShan/CoupledL2](https://github.com/OpenXiangShan/CoupledL2)
- Scope: shared CHI SnpUniqueFwd forwarded snoop response/data path
- Record kind: canonical upstream CoupledL2 CHI RTL fix
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact PR base, the active MSHR and CHI-state RTL diff, the two-RN forward-snoop trigger, and merged upstream PR
- Affected base: [8c757005](https://github.com/OpenXiangShan/CoupledL2/commit/8c757005852daa382852a42466417f34c71daa53)
- Fixed revision: [f629e4f3](https://github.com/OpenXiangShan/CoupledL2/commit/f629e4f3688a4a7c92a8e69e3ea0634285ef7624)
- Canonical fix: [CoupledL2 PR #261](https://github.com/OpenXiangShan/CoupledL2/pull/261), merged upstream
- Retrieved: 2026-09-10

## Failure mechanism

At the affected base, `tl2chi/MSHR.scala` generated the response and
forward-state combination for the `SnpUniqueFwd` snoop path from incomplete
dirty/writeback classification. `tl2chi/chi/Message.scala` supplied the CHI
state encodings and `setPD`, but did not generate this transaction
combination or provide the later legality table.

The relevant pre-fix distinction is important: `mp_dct` emits a `CompData`
packet, while the problematic combination is emitted by the `mp_probeack`
snoop-response/data-forwarding path. In the latter path, the pre-fix MSHR
could allow `SnpUniqueFwd` to enter the `doRespData_retToSrc_fwd` handling and
derive `Resp = I_PD` from the `mp_probeack.resp` release-data condition and
`FwdState = UC` from the `SnpUniqueFwd` forwarding-state classification. It
could thus produce a `SnpRespDataFwded` response with `Resp = I_PD` and
`FwdState = UC`,
the `SnpRespData_I_PD_Fwded_UC` combination that CHI excludes for this
operation. The HN may discard the returned data; when the line has unique
permission but has not otherwise become dirty, that can leave the forwarded
dirty data unavailable to a later Evict.

## Necessary multi-client trigger

`SnpUniqueFwd` is a forward-snoop/data-transfer operation between coherent
clients. The concrete trigger is:

1. RN-A is the snoopee holding the line, and a distinct RN-B is the requester
   or forwarded-data destination.
2. HN-F sends `SnpUniqueFwd` toward RN-A and carries RN-B's destination in the
   forwarding fields.
3. The CoupledL2 MSHR emits the snoop response/data path for RN-A. Under the
   affected dirty/writeback classification, it can form the illegal
   `SnpRespDataFwded` state pair (`Resp = I_PD`, `FwdState = UC`), after which
   HN handling may discard the data.

A single RN-F cannot create this forwarded peer transaction or its response
state, so the failure is specific to the shared multi-client CHI path.

## Canonical fix and closure

Merged commit [f629e4f3](https://github.com/OpenXiangShan/CoupledL2/commit/f629e4f3688a4a7c92a8e69e3ea0634285ef7624)
reworks `hitDirty` and `hitDirtyOrWriteBack`, the SnpUniqueFwd response and
forward-state generation, and the `RetToSrc` data-response condition. It
removes `isSnpToNFwd` from the generic `RetToSrc` path, corrects the
forwarding-state classification, and establishes legal response/forward-state
tables in `Message.scala`. `MSHR.scala` adds assertions that check emitted
`Resp`/`FwdState` values against those tables, excluding the illegal
combination.
PR #261 is closed and merged; its exact base is
`8c757005852daa382852a42466417f34c71daa53` and its merge commit is
`f629e4f3688a4a7c92a8e69e3ea0634285ef7624`.

Source evidence:

- [affected `tl2chi/MSHR.scala`](https://github.com/OpenXiangShan/CoupledL2/blob/8c757005852daa382852a42466417f34c71daa53/src/main/scala/coupledL2/tl2chi/MSHR.scala)
- [affected `tl2chi/chi/Message.scala` state encodings](https://github.com/OpenXiangShan/CoupledL2/blob/8c757005852daa382852a42466417f34c71daa53/src/main/scala/coupledL2/tl2chi/chi/Message.scala)
- [fixed `tl2chi/MSHR.scala`](https://github.com/OpenXiangShan/CoupledL2/blob/f629e4f3688a4a7c92a8e69e3ea0634285ef7624/src/main/scala/coupledL2/tl2chi/MSHR.scala)
- [fixed `tl2chi/chi/Message.scala`](https://github.com/OpenXiangShan/CoupledL2/blob/f629e4f3688a4a7c92a8e69e3ea0634285ef7624/src/main/scala/coupledL2/tl2chi/chi/Message.scala)
- [PR #261](https://github.com/OpenXiangShan/CoupledL2/pull/261)

## Duplicate boundary

This is distinct from `XIANGSHAN-COUPLEDL2_SNPRESPFORWARDED_SELF_NESTING`.
That record concerns a forwarded response being matched to its own MSHR;
this record concerns the illegal SnpUniqueFwd snoop-response/forward-state
combination and the resulting forwarded-data loss.
