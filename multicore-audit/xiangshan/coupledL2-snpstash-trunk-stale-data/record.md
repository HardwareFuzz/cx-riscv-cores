# SnpStash on a TRUNK line could skip the required upstream Probe-toT

- Record ID: `XIANGSHAN-COUPLEDL2-SNPSTASH-TRUNK-STALE-DATA`
- Core: XiangShan
- Source repository: [OpenXiangShan/CoupledL2](https://github.com/OpenXiangShan/CoupledL2)
- Scope: shared CHI SnpStash snoop and TRUNK-line data selection
- Record kind: canonical upstream CoupledL2 CHI RTL fix
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact PR base, the active Probe condition diff, the cross-client stale-copy trigger, and merged upstream PR
- Affected base: [1d118c6a](https://github.com/OpenXiangShan/CoupledL2/commit/1d118c6a73886c7c0230fadc4cdf3fe60b95d019)
- Fixed revision: [463d9f5e](https://github.com/OpenXiangShan/CoupledL2/commit/463d9f5eeba5032b68cb6a60d4438c689644b8a1)
- Canonical fix: [CoupledL2 PR #326](https://github.com/OpenXiangShan/CoupledL2/pull/326), merged upstream
- Retrieved: 2026-09-10

## Failure mechanism

At the affected base, `src/main/scala/coupledL2/tl2chi/MainPipe.scala`
issued the relevant Probe-toT only when
`isSnpOnceX(req_s3.chiOpcode.get) || isSnpQuery(req_s3.chiOpcode.get)` was
true. The condition omitted
`|| isSnpStashX(req_s3.chiOpcode.get)`. When the CoupledL2 directory line was
in TRUNK and an upstream RN-F cache held the newest copy, the stash flow could
therefore proceed without consulting that upstream cache.

`SnpStash` is a no-data response path in this logic (`neverRespData` includes
`isSnpStashX`), so the precise failure is the missing Probe-toT and the
resulting use/selection of an unrefreshed L2 copy by the downstream stash
flow. This record does not claim that SnpStash itself returns a direct
`SnpRespData` beat containing stale data.

The fix extends the condition with `|| isSnpStashX(req_s3.chiOpcode.get)`;
that helper covers `SnpStashUnique` and `SnpStashShared`, so the upstream
hierarchy is probed before the stash operation proceeds with the line state.

## Necessary multi-client trigger

`SnpStash` is an HN-F snoop sent to a target RN-F. The concrete failure
requires a stash/requesting coherent client and a different RN-F's cache
hierarchy holding the newer dirty L1 copy, while the shared L2 directory
reports TRUNK:

1. RN-B initiates a stash/coherent operation that causes HN-F to send
   `SnpStashUnique` or `SnpStashShared`.
2. RN-A's upstream hierarchy holds the newer copy, while CoupledL2 reports a
   directory hit in TRUNK with clients.
3. Before the fix, `isSnpStashX(req_s3.chiOpcode.get)` is absent from
   `need_pprobe_s3_b_snpStable`, so no Probe-toT is issued to RN-A.
4. The stash flow proceeds without obtaining the latest copy required for
   the operation; any stale-copy consequence is downstream selection/use of
   the unrefreshed L2 copy, not a direct SnpStash data response.

A single isolated L2 without the peer stash request and upstream RN-F cannot
enter this snoop/data-selection sequence.

## Canonical fix and closure

Merged commit [463d9f5e](https://github.com/OpenXiangShan/CoupledL2/commit/463d9f5eeba5032b68cb6a60d4438c689644b8a1)
extends `need_pprobe_s3_b_snpStable` from
`isSnpOnceX(...) || isSnpQuery(...)` to
`isSnpOnceX(...) || isSnpQuery(...) || isSnpStashX(...)`; the last helper
covers `SnpStashUnique` and `SnpStashShared`. PR #326 is closed and merged; its exact base is
`1d118c6a73886c7c0230fadc4cdf3fe60b95d019` and its merge commit is
`463d9f5eeba5032b68cb6a60d4438c689644b8a1`.

Source evidence:

- [affected `tl2chi/MainPipe.scala`](https://github.com/OpenXiangShan/CoupledL2/blob/1d118c6a73886c7c0230fadc4cdf3fe60b95d019/src/main/scala/coupledL2/tl2chi/MainPipe.scala)
- [fixed `tl2chi/MainPipe.scala`](https://github.com/OpenXiangShan/CoupledL2/blob/463d9f5eeba5032b68cb6a60d4438c689644b8a1/src/main/scala/coupledL2/tl2chi/MainPipe.scala)
- [PR #326](https://github.com/OpenXiangShan/CoupledL2/pull/326)

## Duplicate boundary

This is distinct from `XIANGSHAN-COUPLEDL2-SNPSTASH_NESTED_STATE_UPDATE`,
which covers a nested writeback causing an invalidating SnpStashX state
update. The present record covers the TRUNK-state omission of Probe-toT and
the resulting unrefreshed-copy selection in the downstream stash flow.
