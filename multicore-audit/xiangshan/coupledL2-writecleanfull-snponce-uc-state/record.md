# CoupledL2 could turn a clean UC state into SC on nested `WriteCleanFull`

- Record ID: `XIANGSHAN-COUPLEDL2_WRITECLEANFULL_SNPONCE_UC_STATE`
- Core: XiangShan / XSCache
- Source repository: [OpenXiangShan/XSCache](https://github.com/OpenXiangShan/XSCache)
- Record kind: canonical XSCache CHI nested-state correction
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact UC-to-SC predicate correction and merged XSCache PR #392
- Scope: shared CHI `WriteCleanFull` and nested `SnpOnce*` state
- Status: fixed in upstream history
- Evidence level: A
- Observed configuration: one RN-F performs a CMO-derived `WriteCleanFull` while another RN-F requests the same line and causes a nested `SnpOnce` or `SnpOnceFwd`
- Parent revision: `7d4002766542951ed3bd908644b89a31da039e4b`
- Fixed revision: `de2bcf974420cb497b6c82900cba6e6fdba316b9`

## Failure mechanism

The affected path is `src/main/scala/coupledL2/tl2chi/MainPipe.scala`. In the
parent revision, the `SnpOnce`/`SnpOnceFwd` nested `WriteCleanFull` handling
changed the response cache state whenever `snpHitReleaseToClean` was true:

```scala
when (isSnpOnceX(req_s3.chiOpcode.get)) {
  when (req_s3.snpHitReleaseToClean) {
    respCacheState := SC
  }
}
```

That predicate did not distinguish a dirty `UD` state from a clean `UC`
state. A clean `WriteCleanFull` nesting event could therefore be reported as
`SC`, changing the CHI permission/state result even though no dirty ownership
existed to justify the transition.

## Runtime trigger

1. RN-F A performs a CMO operation that creates a `WriteCleanFull` for a line
   whose directory state is clean `UC`.
2. Before A's CMO transaction finishes, RN-F B requests the same line.
3. The home node sends `SnpOnce` or `SnpOnceFwd` to RN-F A, nesting the snoop
   in the `WriteCleanFull` operation.
4. The parent path unconditionally converts the clean response state from
   `UC` to `SC`, exposing the wrong state to the CHI response path.

The CMO/writeback client and the peer request client are both necessary: the
first creates the nested `WriteCleanFull`, and the second creates the remote
snoop that exercises the state transition.

## Fix

PR #392 restricts the transition to a dirty nested metadata state:

```scala
when (req_s3.snpHitReleaseToClean && nestable_meta_s3.dirty) {
  respCacheState := SC
}
```

Only the dirty `UD` to `SC` transition remains; a clean `UC` state stays `UC`.

## Distinction from other records

This is a response-state error in nested `SnpOnce*` handling of clean
`WriteCleanFull`. It is distinct from PR #295, which fixed nested-snoop
admission and `metaWen` for `WriteCleanFull`, and from PR #309, which fixed
`SnpOnce*` nesting of replacement writebacks and clean `Release` state.

## Source evidence

- Pre-fix path: [`MainPipe.scala`](https://github.com/OpenXiangShan/XSCache/blob/7d4002766542951ed3bd908644b89a31da039e4b/src/main/scala/coupledL2/tl2chi/MainPipe.scala)
- Fix: [de2bcf9](https://github.com/OpenXiangShan/XSCache/commit/de2bcf974420cb497b6c82900cba6e6fdba316b9)
- Upstream closure: [XSCache PR #392](https://github.com/OpenXiangShan/XSCache/pull/392)
- Relevant diff: require `nestable_meta_s3.dirty` before returning `SC`.
