# CoupledL2 could change a Release opcode when retrying

- Record ID: `XIANGSHAN-COUPLEDL2_RELEASE_RETRY_OPCODE_IMMUTABILITY`
- Core: XiangShan / XSCache
- Source repository: [OpenXiangShan/XSCache](https://github.com/OpenXiangShan/XSCache)
- Record kind: canonical XSCache CHI Release retry-state fix
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact Release opcode recomputation and the merged XSCache PR #328
- Scope: shared CHI replacement Release retry protocol
- Status: fixed in upstream history
- Evidence level: A
- Observed configuration: at least two independent RN-F clients, with one replacement Release retried after a peer snoop changes its metadata
- Parent revision: `fbeb03ae88aa52d1b8d7dff0201b42eb24fb1f16`
- Fixed revision: `49b142b64ff5daa2550deca7617d288dcfefe52f`

## Failure mechanism

The parent revision already contains the earlier `WriteEvict*` nested-snoop
correction. Its replacement Release path can receive `RetryAck`, wait for a
credit response, and issue the same transaction again. Before this fix, the
retry's `oa.opcode` was recomputed from the current metadata:

```scala
(release_valid2 && isWriteCleanFull)    -> WriteCleanFull
(release_valid2 && isWriteBackFull)     -> WriteBackFull
(release_valid2 && isWriteEvictFull)    -> WriteEvictFull
(release_valid2 && isWriteEvictOrEvict) -> WriteEvictOrEvict
(release_valid2 && isEvict)             -> Evict
```

Nested snooping can change the metadata between the first Release and its
retry. The retry could consequently use a different CHI Release opcode from
the transaction that was first issued, along with inconsistent retry
attributes such as `LikelyShared` and `ExpCompAck`.

## Runtime trigger

1. RN-F A starts a replacement Release and the first request is accepted.
2. The Release is retried after `RetryAck` while the MSHR waits for the
   required credit response.
3. Between the first issue and the retry, RN-F B requests the same line and
   causes a nested snoop to RN-F A.
4. The snoop changes A's metadata. In the parent revision, the retry derives a
   new opcode and related CHI attributes from that changed metadata rather than
   preserving the original Release transaction.

RN-F A supplies the retried replacement, and RN-F B supplies the peer snoop
that changes the retry-time metadata. Both independent clients are necessary
for this nested retry window.

## Fix

PR #328 adds `req_released_chiOpcode` and captures the opcode when the first
Release is accepted:

```scala
when (release_valid2) {
  oa.opcode := req_released_chiOpcode
}
```

The retry-specific `LikelyShared` and `ExpCompAck` decisions are likewise
derived from the captured opcode. The Release transaction keeps its original
CHI type across nested snooping and retry.

## Distinction from other records

This record fixes immutability of the Release opcode and its correlated retry
attributes. It is distinct from PR #199, which fixes stale `s_cbwrdata` data
selection after nested metadata changes. Those records have a similar retry
window but different protocol fields and different fixes.

## Source evidence

- Pre-fix path: [`MSHR.scala`](https://github.com/OpenXiangShan/XSCache/blob/fbeb03ae88aa52d1b8d7dff0201b42eb24fb1f16/src/main/scala/coupledL2/tl2chi/MSHR.scala)
- Fix: [49b142b](https://github.com/OpenXiangShan/XSCache/commit/49b142b64ff5daa2550deca7617d288dcfefe52f)
- Upstream closure: [XSCache PR #328](https://github.com/OpenXiangShan/XSCache/pull/328)
- Relevant diff: latch the first Release opcode and use it for retry-time CHI attributes.
