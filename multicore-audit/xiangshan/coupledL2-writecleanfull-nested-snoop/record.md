# CoupledL2 could mishandle a nested snoop during WriteCleanFull

- Record ID: `XIANGSHAN-COUPLEDL2-WRITECLEANFULL_NESTED_SNOOP`
- Core: XiangShan / CoupledL2 (XSCache)
- Record kind: canonical upstream CoupledL2 CHI WriteCleanFull/nested-snoop fix
- Source repository: [OpenXiangShan/CoupledL2](https://github.com/OpenXiangShan/CoupledL2)
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact `releaseToB` admission and metadata-write changes in merged PR #295
- Scope: shared CHI CMO WriteCleanFull and nested snoop metadata
- Status: fixed in upstream history
- Evidence level: A
- Observed configuration: a directory-hit local CMO-derived WriteCleanFull, before its CMO response completes, overlapping a remote RN-F snoop
- Affected revision: `442f4a749857b15a879acc94896675eb2a92019a`
- Fixed revision: `6c33ef0d0c9586cee702df3e07c608cd8bd9d1f3`

## Failure mechanism

The affected paths are `src/main/scala/coupledL2/tl2chi/RXSNP.scala` and
`MSHR.scala`. In the pre-fix RXSNP admission mask, a replacement MSHR was
excluded when it represented a `releaseToB` operation:

```scala
(!s.bits.dirHit || (!s.bits.s_cmoresp && !s.bits.releaseToB)) &&
  s.bits.metaState =/= INVALID && RegNext(s.bits.w_replResp) &&
  s.bits.w_rprobeacklast && !s.bits.w_releaseack
```

For the CMO path, `releaseToB` denotes the WriteCleanFull derived from
`req_cboClean`. The old `releaseToB` exclusion matters only when the MSHR is a
directory hit and `s_cmoresp` is false: the `!s.bits.dirHit` alternative
already admits a directory-miss case. At the same time the old ProbeAck
request unconditionally disabled metadata writes for a nested release:

```scala
mp_probeack.metaWen := !req.snpHitRelease
```

Thus a remote snoop that arrived during the directory-hit
WriteCleanFull/nested-release window was excluded by the wrong
`releaseToB` condition, and the ProbeAck could not apply the required
metadata update even when the nested release was specifically a
to-B/WriteCleanFull operation. The response and metadata state could diverge
from the CMO's ownership transition.

## Two-client trigger

1. RN-F A executes a CMO clean on line X whose CoupledL2 directory lookup is
   a hit, causing a WriteCleanFull with `s_cmoresp` still false.
2. RN-F B issues a CHI snoop for X while A's replacement response and
   ProbeAck handling are in flight.
3. The old `releaseToB` exclusion blocks the nested snoop in this
   directory-hit case, and the old `metaWen` gate suppresses the required
   metadata update for the to-B response.

The remote snoop from RN-F B is required to create the nested event; a local
CMO alone cannot trigger this defect.

## Canonical fix

[6c33ef0](https://github.com/OpenXiangShan/CoupledL2/commit/6c33ef0d0c9586cee702df3e07c608cd8bd9d1f3), merged as [PR #295](https://github.com/OpenXiangShan/CoupledL2/pull/295), removes `!s.bits.releaseToB` from nested-snoop admission, propagates `snpHitReleaseToB`, and changes the metadata write gate to:

```scala
mp_probeack.metaWen := !req.snpHitRelease || req.snpHitReleaseToB
```

The fix is reachable from canonical CoupledL2 `origin/master`.

This is separate from the SnpStashX record: WriteCleanFull is a CMO
to-B/nested-snoop admission and metadata-write defect, not a SnpStashX
invalidating-state side effect.

## Source evidence

- Pre-fix RXSNP/MSHR paths: [`RXSNP.scala`](https://github.com/OpenXiangShan/CoupledL2/blob/442f4a749857b15a879acc94896675eb2a92019a/src/main/scala/coupledL2/tl2chi/RXSNP.scala) and [`MSHR.scala`](https://github.com/OpenXiangShan/CoupledL2/blob/442f4a749857b15a879acc94896675eb2a92019a/src/main/scala/coupledL2/tl2chi/MSHR.scala)
- Fix: [6c33ef0](https://github.com/OpenXiangShan/CoupledL2/commit/6c33ef0d0c9586cee702df3e07c608cd8bd9d1f3)
- Upstream closure: [CoupledL2 PR #295](https://github.com/OpenXiangShan/CoupledL2/pull/295)
