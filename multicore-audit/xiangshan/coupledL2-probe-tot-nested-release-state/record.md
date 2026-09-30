# CoupledL2 could write DataStorage with stale state after a nested Probe-toT/Release

- Record ID: `XIANGSHAN-COUPLEDL2-PROBE_TOT_NESTED_RELEASE_STATE`
- Core: XiangShan / CoupledL2 (XSCache)
- Record kind: canonical upstream CoupledL2 CHI nested-release fix
- Source repository: [OpenXiangShan/CoupledL2](https://github.com/OpenXiangShan/CoupledL2)
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the canonical two-commit fix chain, merged CoupledL2 PR #305, and its exact MSHR data/metadata gating changes
- Scope: shared CHI cache DataStorage and nested snoop/release state
- Status: fixed in upstream history
- Evidence level: A
- Observed configuration: multiple RN-Fs sharing one HN-F, with a local ReleaseData and a remote Probe-toT overlapping in one MSHR
- Affected revision: `d4cfb8ac790455d16208ef2b369027a61f308b10` and its descendants before the two repairs below
- Fixed revisions: `b9b7cfe12dcb93628e8e9cd2685f15b05cbea43f` and `19ccf1ee2490e1ea4db2dd5177274231a1c7e676`

## Failure mechanism

The affected path is `src/main/scala/coupledL2/tl2chi/MSHR.scala`. Before the
repair, a ProbeAck task was allowed to write DataStorage whenever the Probe
was not to-N and the temporary `probeDirty` bit was set:

```scala
mp_probeack.dsWen := !snpToN && probeDirty
```

That condition did not require the MSHR to retain any valid client metadata.
In the nested Probe-toT/Release sequence, the response path could still carry
`probeDirty` after the latest line data was unavailable in the ReleaseBuffer
and the MSHR had no valid client owner. The old `dsWen` condition could then
commit an invalid or stale DataStorage write. The same nested-writeback
`c_set_dirty` path only set the line dirty; it did not clear `meta.clients` or
make the resulting metadata state `TIP`, leaving the ownership metadata
inconsistent with the nested writeback.

This is a concrete state/data ordering defect: the cache could perform a
DataStorage write based on a transient Probe result in a state with no valid
client metadata, rather than only writing data when a valid owner/data source
remained.

## Two-client trigger

Use two coherent CHI RN-F clients connected to the same CoupledL2 HN-F:

1. RN-F A has or is replacing a line and starts a local ReleaseData/nested
   writeback for that line.
2. RN-F B issues a Probe-toT for the same line, making the CoupledL2 MSHR
   process a nested Probe while the Release is in flight.
3. The nested Probe-toT/Release state leaves the old `mp_probeack` path with
   `probeDirty` asserted even though the latest data is not available in the
   ReleaseBuffer and no valid `meta.clients` owner remains.
4. The pre-fix condition above still enables the DataStorage write. In the
   nested dirty-writeback path, the old `c_set_dirty` update also leaves the
   client vector and CHI state unchanged instead of clearing it and setting
   `TIP`.

The remote Probe from RN-F B is necessary to create the ProbeAck/nested
state interaction; a single isolated RN-F cannot exercise this coherence
ordering window.

## Canonical fix and deduplication

The canonical repair is a consecutive two-commit chain:

- [b9b7cfe](https://github.com/OpenXiangShan/CoupledL2/commit/b9b7cfe12dcb93628e8e9cd2685f15b05cbea43f) changes the gate to
  `!snpToN && probeDirty && meta.clients.orR` and clears `meta.clients` on
  the nested dirty writeback path.
- [19ccf1e](https://github.com/OpenXiangShan/CoupledL2/commit/19ccf1ee2490e1ea4db2dd5177274231a1c7e676) additionally sets
  `meta.state := TIP` for that nested dirty writeback.

Both commits are reachable from the canonical CoupledL2 `origin/master`.
They are recorded as one defect because the second commit closes the
remaining metadata-state half of the same Probe-toT/nested-Release failure;
they are one combined record.

The two commits are the merged [CoupledL2 PR #305](https://github.com/OpenXiangShan/CoupledL2/pull/305) fix chain.

This record is distinct from the existing XiangShan records for RXSNP
replacement/refill timing and ProbeAck writeback beat tracking: those do not
cover the `mp_probeack.dsWen` client-vector gate and nested Release metadata
transition described here.

## Source evidence

- Pre-fix path: [`MSHR.scala`](https://github.com/OpenXiangShan/CoupledL2/blob/d4cfb8ac790455d16208ef2b369027a61f308b10/src/main/scala/coupledL2/tl2chi/MSHR.scala)
- First repair: [b9b7cfe](https://github.com/OpenXiangShan/CoupledL2/commit/b9b7cfe12dcb93628e8e9cd2685f15b05cbea43f)
- Completion of the metadata repair: [19ccf1e](https://github.com/OpenXiangShan/CoupledL2/commit/19ccf1ee2490e1ea4db2dd5177274231a1c7e676)
- Upstream closure: [CoupledL2 PR #305](https://github.com/OpenXiangShan/CoupledL2/pull/305)
