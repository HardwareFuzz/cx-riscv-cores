# CoupledL2 could nest a writeback after a missed forward snoop

- Record ID: `XIANGSHAN-COUPLEDL2-MISSED_FORWARD_SNOOP_NESTED_WRITEBACK`
- Core: XiangShan / CoupledL2 (XSCache)
- Record kind: canonical upstream CoupledL2 CHI nested-writeback fix
- Source repository: [OpenXiangShan/CoupledL2](https://github.com/OpenXiangShan/CoupledL2)
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact `req_mayRepl` correction and merged upstream PR #306
- Scope: shared CHI directory-miss and DCT forward-snoop handling
- Status: fixed in upstream history
- Evidence level: A
- Observed configuration: at least two RN-F clients, with a DCT forward snoop and an overlapping nested writeback
- Affected revision: `19ccf1ee2490e1ea4db2dd5177274231a1c7e676`
- Fixed revision: `c072c9ebe95cc4f5e0bdf9d3f1822290861660ce`

## Failure mechanism

The affected path is `src/main/scala/coupledL2/tl2chi/MSHR.scala`. The
pre-fix nested-writeback match was:

```scala
val nestedwb_match = req_valid && meta.state =/= INVALID &&
  dirResult.set === io.nestedwb.set &&
  dirResult.tag === io.nestedwb.tag &&
  (state.w_replResp && (state.s_cmoresp || dirResult.hit))
```

The condition assumed that an MSHR with `state.w_replResp` represented a
replacement-capable request. That is not true for a DCT forward snoop: the
DCT forward-snoop request can enter an MSHR and can receive multiple
separate responses even when the directory lookup is a miss. Consequently,
the old expression could match a nested writeback on a directory-miss
forward-snoop MSHR and apply nested writeback state/data transitions to a
request that must not own replacement/writeback behavior.

## Two-client trigger

Use two coherent RN-F clients sharing the CoupledL2:

1. RN-F A initiates a CHI operation that causes the DCT to issue a forward
   snoop; the forward-snoop request occupies an MSHR and has a directory
   miss for the relevant set/tag.
2. While that MSHR is in the old `w_replResp`-qualified window, RN-F B
   supplies or causes a nested writeback/snoop task for the same line.
3. The old `nestedwb_match` accepts the nested writeback even though the
   active request is a non-replacement DCT forward snoop and the directory
   misses. The resulting writeback bookkeeping can corrupt the MSHR's
   metadata or response sequencing.

The forward snoop and the nested coherence client are distinct inputs. The
incorrect match does not arise from a single, isolated request without a
second RN-F's overlapping snoop/writeback.

## Canonical fix

[c072c9e](https://github.com/OpenXiangShan/CoupledL2/commit/c072c9ebe95cc4f5e0bdf9d3f1822290861660ce), merged as [PR #306](https://github.com/OpenXiangShan/CoupledL2/pull/306), introduces:

```scala
val req_mayRepl = req_acquire || req_get || req_prefetch
```

and changes the match to require replacement eligibility or an actual
directory hit:

```scala
state.w_replResp &&
  (state.s_cmoresp || dirResult.hit) &&
  (req_mayRepl || dirResult.hit)
```

This preserves nested writeback for replacement-capable requests while
excluding a directory-miss DCT forward snoop. The fix is reachable from the
canonical CoupledL2 `origin/master`.

This is not the existing DCT directory-client overapproximation record: that
record concerns directory ownership bits, whereas this one is an erroneous
nested-writeback admission decision for a non-replacement MSHR.

## Source evidence

- Pre-fix path: [`MSHR.scala`](https://github.com/OpenXiangShan/CoupledL2/blob/19ccf1ee2490e1ea4db2dd5177274231a1c7e676/src/main/scala/coupledL2/tl2chi/MSHR.scala)
- Fix: [c072c9e](https://github.com/OpenXiangShan/CoupledL2/commit/c072c9ebe95cc4f5e0bdf9d3f1822290861660ce)
- Upstream closure: [CoupledL2 PR #306](https://github.com/OpenXiangShan/CoupledL2/pull/306)
