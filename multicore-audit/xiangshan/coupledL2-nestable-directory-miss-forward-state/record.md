# CoupledL2 treated an INVALID nested line as a directory hit

- Record ID: `XIANGSHAN-COUPLEDL2-NESTABLE_DIRECTORY_MISS_FORWARD_STATE`
- Core: XiangShan / CoupledL2 (XSCache)
- Record kind: canonical upstream CoupledL2 CHI nested-directory forwarding fix
- Source repository: [OpenXiangShan/CoupledL2](https://github.com/OpenXiangShan/CoupledL2)
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact directory-hit correction and merged PR #374
- Scope: shared CHI multiple-nesting response/forwarding state
- Status: fixed in upstream history
- Evidence level: A
- Observed configuration: two or more RN-F snoops nested around a replacement/writeback MSHR
- Affected revision: `7cddc57befd8a90e6beb429e45d0cb94df8b2cfd`
- Fixed revision: `38306873ea21e235aa35f2fb062c1243548688d0`

## Failure mechanism

The affected path is `src/main/scala/coupledL2/tl2chi/MainPipe.scala`. The
pre-fix nested-directory result unconditionally claimed a hit:

```scala
nestable_dirResult_s3.hit := true.B
nestable_dirResult_s3.meta := req_s3.snpHitReleaseMeta
```

The metadata came from a nested MSHR and could already be `INVALID` after an
earlier snoop. Nevertheless, `hit := true.B` drove the downstream CHI
forwarding decision (`canFwd`) down the directory-hit path. A later nested
snoop could therefore be answered as though the invalid nested line still
had a directory entry/forwarding owner, producing the wrong SnpResp state
or forwarding behavior.

## Multi-client trigger

The canonical sequence is:

1. RN-F A sends a WriteBackFull/replacement operation.
2. RN-F B sends SnpUnique; its nested state becomes `INVALID`, and the
   response includes the invalidating/forwarded data transition.
3. Before the replacement MSHR is gone, RN-F C sends SnpUniqueFwd for the
   same line. The old `nestable_dirResult_s3.hit := true.B` makes this second
   nested request use directory-hit forwarding even though the nested state
   is invalid.

At least two independent coherent clients are required (and the fully
described sequence uses three): one client creates the replacement/nesting
state and another supplies the subsequent snoop. A single RN-F cannot create
the multiple-nesting observation.

## Canonical fix

[3830687](https://github.com/OpenXiangShan/CoupledL2/commit/38306873ea21e235aa35f2fb062c1243548688d0), merged as [PR #374](https://github.com/OpenXiangShan/CoupledL2/pull/374), changes the assignment to:

```scala
nestable_dirResult_s3.hit := req_s3.snpHitReleaseMeta.state =/= INVALID
```

An invalid nested metadata state is consequently treated as a directory
miss, so subsequent nested forwarding uses the correct miss response path.
The fix is reachable from canonical CoupledL2 `origin/master`.

## Source evidence

- Pre-fix path: [`MainPipe.scala`](https://github.com/OpenXiangShan/CoupledL2/blob/7cddc57befd8a90e6beb429e45d0cb94df8b2cfd/src/main/scala/coupledL2/tl2chi/MainPipe.scala)
- Fix: [3830687](https://github.com/OpenXiangShan/CoupledL2/commit/38306873ea21e235aa35f2fb062c1243548688d0)
- Upstream closure: [CoupledL2 PR #374](https://github.com/OpenXiangShan/CoupledL2/pull/374)
