# CBO inval could omit dirty data from the ReleaseBuffer

- Record ID: `XIANGSHAN-COUPLEDL2-CBOINVAL-RELEASEBUFFER-DATA`
- Core: XiangShan
- Source repository: [OpenXiangShan/CoupledL2](https://github.com/OpenXiangShan/CoupledL2)
- Scope: shared CHI CBO inval, derived Evict, and ReleaseBuffer data path
- Record kind: canonical upstream CoupledL2 CHI RTL fix
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact PR base, the active MainPipe condition diff, the peer-RN nested-snoop trigger, and merged upstream PR
- Affected base: [0050f039](https://github.com/OpenXiangShan/CoupledL2/commit/0050f0399198a1315bd11bc11b2501e74545dd74)
- Fixed revision: [dc18bd74](https://github.com/OpenXiangShan/CoupledL2/commit/dc18bd7460df76f4b1eb2b8e0b0e6faecd510241)
- Canonical fix: [CoupledL2 PR #300](https://github.com/OpenXiangShan/CoupledL2/pull/300), merged upstream
- Retrieved: 2026-09-10

## Failure mechanism

In the affected `src/main/scala/coupledL2/tl2chi/MainPipe.scala`,
`need_data_cmo` was derived from `cmo_cbo_retention_s3`. That condition
covered CBO clean/flush but not CBO inval. An Evict derived from CBO inval
could consequently enter MainPipe without the data-preservation indication
needed to save a dirty line into the ReleaseBuffer, allowing the newest data
to be lost when the transaction was nested or retried.

The fix changes the condition to use `cmo_cbo_s3`, covering the CBO inval
case as well as the existing CMO CBO handling.

## Necessary multi-client trigger

PR #300 documents the transaction as a CBO inval-derived Evict that can be
nested by a snoop from another RN. The sequence therefore requires the CMO
requesting client and an independent coherent RN-F generating the peer snoop
while the Evict is in flight. The shared CHI path can also carry the data
through multiple RNs/DCTs; that peer activity is absent from an isolated
single-client request.

## Canonical fix and closure

Merged commit [dc18bd74](https://github.com/OpenXiangShan/CoupledL2/commit/dc18bd7460df76f4b1eb2b8e0b0e6faecd510241)
changes `need_data_cmo` from `cmo_cbo_retention_s3` to `cmo_cbo_s3`, so a
CBO inval-derived Evict preserves dirty data in the ReleaseBuffer. PR #300
is closed and merged; its exact base is
`0050f0399198a1315bd11bc11b2501e74545dd74` and its merge commit is
`dc18bd7460df76f4b1eb2b8e0b0e6faecd510241`.

Source evidence:

- [affected `tl2chi/MainPipe.scala`](https://github.com/OpenXiangShan/CoupledL2/blob/0050f0399198a1315bd11bc11b2501e74545dd74/src/main/scala/coupledL2/tl2chi/MainPipe.scala)
- [fixed `tl2chi/MainPipe.scala`](https://github.com/OpenXiangShan/CoupledL2/blob/dc18bd7460df76f4b1eb2b8e0b0e6faecd510241/src/main/scala/coupledL2/tl2chi/MainPipe.scala)
- [PR #300](https://github.com/OpenXiangShan/CoupledL2/pull/300)

## Duplicate boundary

This is distinct from the retained WriteCleanFull nested-snoop record,
which covers its own CMO-to-B nested-admission and metadata gate. It is also
distinct from the WriteEvict records: this condition is the CBO inval
classification that determines whether dirty data is preserved in the
ReleaseBuffer.
