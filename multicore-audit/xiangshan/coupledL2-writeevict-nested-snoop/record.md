# CoupledL2 mishandled nested snoops during `WriteEvict*`

- Record ID: `XIANGSHAN-COUPLEDL2_WRITEEVICT_NESTED_SNOOP`
- Core: XiangShan / CoupledL2
- Scope: shared CHI `WriteEvictFull`/`WriteEvictOrEvict` and peer-snoop nesting
- Record kind: canonical upstream CoupledL2 CHI RTL fix
- Source repository: [OpenXiangShan/CoupledL2](https://github.com/OpenXiangShan/CoupledL2)
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the CHI opcode semantics, the exact MSHR/MainPipe correction, and merged CoupledL2 PR #327
- Status: fixed in upstream history
- Evidence level: A
- Observed configuration: at least two RN-F clients sharing the CoupledL2 home node
- Affected revision: `87cf9850feb88be5fb869984bba252bc9df69657`
- Fixed revision: `fbeb03ae88aa52d1b8d7dff0201b42eb24fb1f16`

## Failure mechanism

The affected implementation treated only a dirty-data nested release as a
nested writeback. Its `hitWriteBack` predicate was:

```scala
val hitWriteBack = req.snpHitRelease && req.snpHitReleaseWithData
```

That classification omitted clean-data `WriteEvictFull` and
`WriteEvictOrEvict`. Unlike `Evict`, those CHI opcodes do not have a silent
eviction path: their initial state cannot be treated as invalid before the
WriteData/Comp response completes. When a peer snoop nested during the
transaction, the old path could consequently use the wrong response state,
`PassDirty` behavior, forwarding decision, or directory transition.

## Two-client trigger

1. RN-F A starts a clean-data `WriteEvictFull` or `WriteEvictOrEvict` for a
   replacement line and has not completed its WriteData/Comp sequence.
2. RN-F B requests or snoops the same line. The shared home node sends the
   nested snoop to RN-F A.
3. The affected MSHR classifies the nested operation like an ordinary
   `Evict`/non-writeback case, even though `WriteEvict*` must retain its
   writeback semantics until completion.
4. The resulting snoop response and cache-state transition can carry the
   wrong state or dirty/forwarding information.

The shared CoupledL2 topology has separate RN-F clients and a peer-directory
snoop path. Without RN-F B there is no nested remote snoop; without RN-F A
there is no in-flight `WriteEvict*` transaction. Two independent clients are
therefore required for the recorded nested-snoop defect.

## Fix

PR #327 separates dirty `WriteBackFull` from clean `WriteEvict*`, introduces a
`hitWriteEvict`/`hitWriteX` classification, and applies it to the response
state, forwarding, replacement-data, and `PassDirty` logic. It also enumerates
the CHI forwarding opcodes explicitly instead of relying on a broad numeric
range. The corrected path keeps `WriteEvictFull` and `WriteEvictOrEvict` in the
nested-writeback handling required by their protocol semantics.

This is distinct from the existing plain-`Evict` nested-release record and
from the existing `WriteCleanFull` CMO nested-snoop record: the affected
opcodes, state rules, and fix predicates are different.

## Source evidence

- Pre-fix MSHR: [`src/main/scala/coupledL2/tl2chi/MSHR.scala`](https://github.com/OpenXiangShan/CoupledL2/blob/87cf9850feb88be5fb869984bba252bc9df69657/src/main/scala/coupledL2/tl2chi/MSHR.scala)
- Fix: [fbeb03ae](https://github.com/OpenXiangShan/CoupledL2/commit/fbeb03ae88aa52d1b8d7dff0201b42eb24fb1f16)
- Upstream closure: [CoupledL2 PR #327](https://github.com/OpenXiangShan/CoupledL2/pull/327)
