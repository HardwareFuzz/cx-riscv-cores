# VexRiscv invalidation read-during-write hazard could misapply a stale way mask

- Record ID: `VEXRISCV-INVALIDATION_READ_DURING_WRITE_HAZARD`
- Core: VexRiscv
- Source repository: [SpinalHDL/VexRiscv](https://github.com/SpinalHDL/VexRiscv)
- Scope: four-core SMP DataCache invalidation and write/read ordering
- Record kind: canonical upstream SMP cache RTL fix
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact affected parent, the changed DataCache pipeline, the four-core shared BMB invalidation path, the committed SMP consistency regression, and the upstream merge closure
- Affected parent: [8e8b64fe](https://github.com/SpinalHDL/VexRiscv/commit/8e8b64feaaf0d3c93aab6c61d33be08260c4c60c)
- Fixed revision: [b389878d](https://github.com/SpinalHDL/VexRiscv/commit/b389878d2323002d6619981a5a82cc4581cf2715), `Add smp consistency check, fix VexRiscv invalidation read during write hazard logic`
- Canonical closure: upstream merge [f6931784](https://github.com/SpinalHDL/VexRiscv/commit/f6931784a5d3e1ac8dd1252e5f4728bc5b6e82ca), `Merge branch 'smp' into dev`, whose merged SMP branch contains the fixed revision
- Retrieved: 2026-09-10

## Failure mechanism

At the exact affected parent, `src/main/scala/vexriscv/ip/DataCache.scala`
implements invalidation as a pipelined tag read. The `s0` stage accepts an
invalidation request and starts `tagsInvReadCmd`; `s1` computes the matching
ways from the tag response; and `s2` applies the matching-way mask to the tag
write and to a same-line CPU-read hazard. The pre-fix code then carried the
mask back into the next invalidation-read stage with:

```scala
s1.invalidations := RegNext((input.valid && input.enable) ? wayHits | 0)
```

That register was not qualified by acceptance of the corresponding `s0`
request and did not verify that the delayed mask belonged to the same cache
line as that request. With a peer invalidation and a local cache write/read
pipeline overlapping, a prior tag-read result could therefore be applied as
the `invalidations` mask for a later request. The mask is consumed in `s1` by
the `wayHits` calculation (`... && way.tagsInvReadRsp.valid) &
~invalidations`, so the stale association can hide a valid way or otherwise
misalign invalidation and data/tag activity. This is the concrete
read-during-write hazard named by the upstream fix, not a generic cache
ordering concern.

The affected source is visible at the
[pre-fix DataCache invalidation pipeline](https://github.com/SpinalHDL/VexRiscv/blob/8e8b64feaaf0d3c93aab6c61d33be08260c4c60c/src/main/scala/vexriscv/ip/DataCache.scala#L874-L927).

## Necessary multi-core trigger

The fixed commit exercises the actual shared-client configuration rather than
an isolated DataCache:

1. `VexRiscvSmpClusterGen.vexRiscvCluster(4)` creates four VexRiscv CPU
   configurations.
2. The cluster connects their data buses through a shared `BmbArbiter`, then
   through `BmbExclusiveMonitor` and `BmbInvalidateMonitor`. A peer hart's
   write consequently produces an invalidation that can arrive while another
   hart is reading or writing the same cache line.
3. The committed raw SMP image uses multiple `mhartid`-selected harts,
   LR/SC barriers, and a same-line `sw; fence w,r; lw` consistency check. Hart
   A writes `666` to one shared test word and reads Hart B's word; Hart B does
   the symmetric operation.
4. The test reports both observed values. The harness treats `(0, 0)` as
   `simFailure`, which is the observable consistency failure that the fixed
   invalidation timing must prevent.

The relevant fixed harness explicitly instantiates the shared monitors and
four CPUs in
[`VexRiscvSmpCluster.scala`](https://github.com/SpinalHDL/VexRiscv/blob/b389878d2323002d6619981a5a82cc4581cf2715/src/main/scala/vexriscv/demo/smp/VexRiscvSmpCluster.scala#L20-L112).
The two-hart interaction and its failing `(0,0)` condition are in the
[committed SMP regression](https://github.com/SpinalHDL/VexRiscv/blob/b389878d2323002d6619981a5a82cc4581cf2715/src/test/cpp/raw/smp/src/crt.S#L61-L147).

## Canonical fix

The upstream change replaces the unqualified `RegNext` with an accepted,
same-line-qualified pipeline transfer:

```scala
s1.invalidations := RegNextWhen(
  (input.valid && input.enable &&
    input.address(lineRange) === s0.input.address(lineRange)) ? wayHits | 0,
  s0.input.ready
)
```

The invalidation mask is now captured only when the corresponding `s0`
request is accepted, and only when the `s2` result is for that request's
cache line. A peer invalidation therefore cannot be reused by a later line or
by an unaccepted pipeline slot. The same fixed revision updates the SMP
DataCache/DBus interface so the four-core cluster uses the external
exclusive/invalidation monitors that provide the shared-client ordering path.

The exact fixed RTL is visible at the
[post-fix DataCache invalidation pipeline](https://github.com/SpinalHDL/VexRiscv/blob/b389878d2323002d6619981a5a82cc4581cf2715/src/main/scala/vexriscv/ip/DataCache.scala#L890-L943).
The commit also adds the monitor-backed SMP consistency instrumentation and
the raw image used by the regression; these changes are part of the same
upstream fix commit rather than a downstream reproduction.

## Upstream closure and duplicate boundary

The fixed revision's direct parent is exactly `8e8b64feaaf0d3c93aab6c61d33be08260c4c60c`.
The upstream merge commit `f6931784a5d3e1ac8dd1252e5f4728bc5b6e82ca` merges
the `smp` branch into `dev` and retains the DataCache fix, the four-core
shared-monitor topology, and the consistency regression. The commit message
and changed RTL identify the defect as an invalidation read-during-write
hazard; the complete evidence chain is supplied by the upstream history and
its merged test and RTL changes.

This record is limited to the `DataCache.scala` invalidation-mask timing and
its SMP consistency closure. It does not claim that the separate FPU, hart-ID,
or refill-invalidation changes in other VexRiscv histories are confirmed
multicore failures.
