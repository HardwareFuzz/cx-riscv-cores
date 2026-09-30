# TL2TL GrantData could be accepted without updating DataStorage

- Record ID: `XIANGSHAN-COUPLEDL2-TL2TL-GRANTDATA-DSTORAGE`
- Core: XiangShan
- Source repository: [OpenXiangShan/CoupledL2](https://github.com/OpenXiangShan/CoupledL2)
- Scope: shared TL2TL client-L2 directory and GrantData path
- Record kind: canonical upstream CoupledL2 CHI/TL2TL RTL fix
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact PR base, active RTL diff, required two-client sequence, and merged upstream PR
- Affected base: [7c206290](https://github.com/OpenXiangShan/CoupledL2/commit/7c2062903b9a1afda5bb1191081e2fc38b1ccc1e)
- Fixed revision: [8afd89fc](https://github.com/OpenXiangShan/CoupledL2/commit/8afd89fcd9726f1dbeefb4b2953741cdf809b8e1)
- Canonical fix: [CoupledL2 PR #166](https://github.com/OpenXiangShan/CoupledL2/pull/166), merged upstream
- Retrieved: 2026-09-10

## Failure mechanism

In the affected `src/main/scala/coupledL2/tl2tl/MSHR.scala`, the
DataStorage write enable for a TL2TL GrantData response was additionally
gated by the old directory-hit and dirty-state result. In the relevant
sequence, the MSHR could receive GrantData even though that old directory
result indicated a hit with no dirty data. The response completed, but
`DataStorage` was not written with the returned line.

The fix changes the `mp_grant.dsWen` condition from a form requiring
`(!dirResult.hit || gotDirty) && gotGrantData` to the GrantData condition
that directly tracks receipt of the data. This preserves the returned line
when the directory result is stale relative to the concurrent TL2TL
transactions.

## Necessary multi-client trigger

The reproducer described by PR #166 uses two independent client L2s sending
`AcquireBlock BToT` for the same block. One L2 is probed while the other
receives data returned from L3. This creates the directory-conflict and
delayed-GrantData sequence in which `gotGrantData` is true while the old
directory result has `hit=true` and `gotDirty=false`.

With only one isolated client L2 there is no peer acquisition and probe
ordering to create this conflicting directory state. The defect therefore
concerns the shared coherent TL2TL fabric and its independent RN/client
traffic, not a local single-request datapath.

## Canonical fix and closure

The merged change in [8afd89fc](https://github.com/OpenXiangShan/CoupledL2/commit/8afd89fcd9726f1dbeefb4b2953741cdf809b8e1)
removes the stale directory/dirty gating from the GrantData DataStorage
write decision while retaining the requirement that GrantData has arrived.
PR #166 is closed and merged, with merge commit
`8afd89fcd9726f1dbeefb4b2953741cdf809b8e1`; its exact reported base is the
affected revision `7c2062903b9a1afda5bb1191081e2fc38b1ccc1e`.

Source evidence:

- [affected `tl2tl/MSHR.scala`](https://github.com/OpenXiangShan/CoupledL2/blob/7c2062903b9a1afda5bb1191081e2fc38b1ccc1e/src/main/scala/coupledL2/tl2tl/MSHR.scala)
- [fixed `tl2tl/MSHR.scala`](https://github.com/OpenXiangShan/CoupledL2/blob/8afd89fcd9726f1dbeefb4b2953741cdf809b8e1/src/main/scala/coupledL2/tl2tl/MSHR.scala)
- [PR #166](https://github.com/OpenXiangShan/CoupledL2/pull/166)

## Duplicate boundary

This is distinct from `XIANGSHAN-COUPLEDL2_TL2TL_PROBE_RELEASEACK_CONFLICT`,
which covers same-address Probe admission while ReleaseAck is outstanding.
The present record covers a GrantData response that was received but failed
to commit to DataStorage because of stale directory gating.
