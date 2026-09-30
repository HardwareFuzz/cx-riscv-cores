# SnpOnce ProbeAckData could lose dirty state on a TRUNK line

- Record ID: `XIANGSHAN-COUPLEDL2-SNPONCE-TRUNK-DIRTY`
- Core: XiangShan
- Source repository: [OpenXiangShan/CoupledL2](https://github.com/OpenXiangShan/CoupledL2)
- Scope: shared CHI SnpOnce ProbeAckData and directory dirty-state tracking
- Record kind: canonical upstream CoupledL2 CHI RTL fix
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact PR base, the active metadata diff, the peer-RN-F snoop trigger, and merged upstream PR
- Affected base: [c6944071](https://github.com/OpenXiangShan/CoupledL2/commit/c69440711494fae6e55d0f62d1b1353f91d842e5)
- Fixed revision: [9e841f3e](https://github.com/OpenXiangShan/CoupledL2/commit/9e841f3e6c83a08f18c7f9ed800de97eb3432230)
- Canonical fix: [CoupledL2 PR #187](https://github.com/OpenXiangShan/CoupledL2/pull/187), merged upstream
- Retrieved: 2026-09-10

## Failure mechanism

At the affected base, `src/main/scala/coupledL2/tl2chi/MSHR.scala` did not
inherit the dirty indication from a dirty Probe-toT response when the
request was a `SnpOnce` transaction and the CoupledL2 directory line was
otherwise clean. The returned data could therefore be installed or tracked
as clean even though the snooped upstream DCache had supplied dirty data.
Later replacement or eviction could treat the newest copy as clean and
discard the dirty-state information.

The fix adds the `isSnpOnceX(req_chiOpcode) && probeDirty` case to the
`mp_probeack.meta.dirty` update, preserving the dirty metadata carried by
the SnpOnce ProbeAckData response.

## Necessary multi-client trigger

`SnpOnce` is an HN-F B-channel snoop sent to an RN-F. The concrete sequence
requires a coherent requester on one path to cause the HN-F snoop and a
different RN-F's upstream DCache to own the dirty copy that answers with
ProbeAckData TtoT. A single isolated client with no peer coherence request
does not generate this snoop and dirty-state transfer.

## Canonical fix and closure

The merged fix [9e841f3e](https://github.com/OpenXiangShan/CoupledL2/commit/9e841f3e6c83a08f18c7f9ed800de97eb3432230)
adds the SnpOnce/dirty response condition to the MSHR ProbeAck metadata
update. PR #187 is closed and merged; its exact reported base is
`c69440711494fae6e55d0f62d1b1353f91d842e5` and its merge commit is
`9e841f3e6c83a08f18c7f9ed800de97eb3432230`.

Source evidence:

- [affected `tl2chi/MSHR.scala`](https://github.com/OpenXiangShan/CoupledL2/blob/c69440711494fae6e55d0f62d1b1353f91d842e5/src/main/scala/coupledL2/tl2chi/MSHR.scala)
- [fixed `tl2chi/MSHR.scala`](https://github.com/OpenXiangShan/CoupledL2/blob/9e841f3e6c83a08f18c7f9ed800de97eb3432230/src/main/scala/coupledL2/tl2chi/MSHR.scala)
- [PR #187](https://github.com/OpenXiangShan/CoupledL2/pull/187)

## Duplicate boundary

This is distinct from `XIANGSHAN-COUPLEDL2_SNPONCE_WRITEBACK_NESTING`,
which concerns in-flight writeback nesting. It is also distinct from the
generic ProbeAck MSHR metadata record: this record is specifically the
ordinary SnpOnce-on-TRUNK dirty-state inheritance case.
