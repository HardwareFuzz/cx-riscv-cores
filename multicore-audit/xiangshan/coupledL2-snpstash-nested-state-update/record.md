# CoupledL2 could apply an invalidating nested-writeback effect to SnpStashX

- Record ID: `XIANGSHAN-COUPLEDL2-SNPSTASH_NESTED_STATE_UPDATE`
- Core: XiangShan / CoupledL2 (XSCache)
- Record kind: canonical upstream CoupledL2 CHI nested-snoop state fix
- Source repository: [OpenXiangShan/CoupledL2](https://github.com/OpenXiangShan/CoupledL2)
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact nested metadata propagation and `SnpStashX` invalidation exclusion in merged PR #308
- Scope: shared CHI nested snoop, MSHR metadata, and cache-state transitions
- Status: fixed in upstream history
- Evidence level: A
- Observed configuration: one RN-F replacement/writeback MSHR nested by a SnpStashX from another RN-F
- Affected revision: `13110382c868d1761ee2bb63afae5fcb1207c940`
- Fixed revision: `46c1844a80837f63dc3caf4f5ad5928466543428`

## Failure mechanism

The affected paths are `src/main/scala/coupledL2/tl2chi/MainPipe.scala`,
`MSHR.scala`, and `RXSNP.scala`. Before the repair, a nested writeback from
any snoop could be marked as an invalidating effect:

```scala
io.nestedwb.b_inv_dirty := task_s3.valid && task_s3.bits.fromB &&
  source_req_s3.snpHitRelease
```

There was no `!isSnpStashX(...)` exclusion. In addition, the nested MSHR's
actual `meta.state` and `meta.dirty` were not passed through the nested-snoop
task; the response-state calculation could therefore use MainPipe metadata
instead of the nested MSHR metadata. A SnpStashX, whose cache-line state is
supposed to remain unchanged while the nested writeback is handled, could
therefore take the generic invalidating/dirty transition and return a state
that did not describe the nested MSHR line.

## Two-client trigger

1. RN-F A has an active replacement or writeback MSHR for line X.
2. RN-F B sends a SnpStashX for X while RN-F A's replacement response and
   nested writeback are being handled.
3. The old RXSNP/MainPipe path sets `snpHitRelease` and unconditionally
   permits `b_inv_dirty`; because the nested MSHR metadata is not exported,
   the SnpStashX response can use the wrong state/dirty information and
   alter the line as if the snoop were invalidating.

The second RN-F's SnpStashX is necessary: without a remote nested snoop there
is no `snpHitRelease`/`nestedwb` event and no cross-client state transition.

## Canonical fix

[46c1844](https://github.com/OpenXiangShan/CoupledL2/commit/46c1844a80837f63dc3caf4f5ad5928466543428), merged as [PR #308](https://github.com/OpenXiangShan/CoupledL2/pull/308), makes the nested MSHR export `metaState` and `metaDirty`, uses those fields for the SnpStashX response state, and changes the invalidating side effect to exclude SnpStashX:

```scala
io.nestedwb.b_inv_dirty := task_s3.valid && task_s3.bits.fromB &&
  source_req_s3.snpHitRelease && !isSnpStashX(req_s3.chiOpcode.get)
```

It also prevents `respPassDirty` from treating SnpStashX as an ordinary
dirty-forwarding snoop. The fix is reachable from canonical CoupledL2
`origin/master`.

This is distinct from the later ProbeAck metadata record: this defect is the
SnpStashX-specific nested state/invalidating side effect, while the later
record covers ProbeAck/ProbeAckData updates to a live MSHR.

## Source evidence

- Pre-fix MainPipe path: [`MainPipe.scala`](https://github.com/OpenXiangShan/CoupledL2/blob/13110382c868d1761ee2bb63afae5fcb1207c940/src/main/scala/coupledL2/tl2chi/MainPipe.scala)
- Fix: [46c1844](https://github.com/OpenXiangShan/CoupledL2/commit/46c1844a80837f63dc3caf4f5ad5928466543428)
- Upstream closure: [CoupledL2 PR #308](https://github.com/OpenXiangShan/CoupledL2/pull/308)
