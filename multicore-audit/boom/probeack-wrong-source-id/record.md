# BOOM dirty ProbeAckData used the wrong TileLink source ID

- Record ID: `BOOM-PROBEACK_WRONG_SOURCE_ID`
- Core: BOOM
- Scope: shared L1 TileLink ProbeAckData source identity
- Record kind: canonical upstream Chisel/RTL coherence response fix
- Source repository: [riscv-boom/riscv-boom](https://github.com/riscv-boom/riscv-boom)
- Affected parent: [5b68d590](https://github.com/riscv-boom/riscv-boom/commit/5b68d590d87c4a8c4c60793060b9eb28e08565c4)
- Direct fix: [c5ec95fd](https://github.com/riscv-boom/riscv-boom/commit/c5ec95fd1bf29f94df84dfd625dced212392898f)
- Pull request: [BOOM PR #275](https://github.com/riscv-boom/riscv-boom/pull/275), merged as [ac28f02d](https://github.com/riscv-boom/riscv-boom/commit/ac28f02dafc5cfa284bb83e1c0c7d2b99c20a92a)
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact parent/fix source change and its retained canonical BOOM v4 implementation
- Affected source: [`src/main/scala/lsu/dcache.scala`](https://github.com/riscv-boom/riscv-boom/blob/5b68d590d87c4a8c4c60793060b9eb28e08565c4/src/main/scala/lsu/dcache.scala)
- Retrieved: 2026-09-10

## Failure mechanism

The affected BOOM v4 DCache has a `BoomProbeUnit` that receives a
peer-generated TileLink B-channel Probe. The probe request's source is
copied into the writeback request sent to `BoomWritebackUnit`:

```scala
io.wb_req.bits.source := req.source
```

At the affected parent, `BoomWritebackUnit` instead constructed the dirty
probe response with the fixed internal value `cfg.nMSHRs`:

```scala
val id = cfg.nMSHRs
val probeResponse = edge.ProbeAck(
  fromSource = id.U,
  toAddress = r_address,
  lgSize = lgCacheBlockBytes.U,
  reportPermissions = req.param,
  data = wb_buffer(data_req_cnt))
```

The `edge.ProbeAck` helper places `fromSource` in the TileLink C-channel
response source field. For a response to a B-channel Probe, that field must
echo the source of the Probe that caused the response. `cfg.nMSHRs` is a
fixed local DCache identifier used by the voluntary-release path; it is not
the source carried by the peer's Probe. Consequently, a dirty-line
`ProbeAckData` emitted by the parent can carry a source ID unrelated to the
outstanding Probe transaction.

This is a malformed coherence response at the shared L1 TileLink boundary.
A coherence manager that matches the C-channel response against the
outstanding B-channel source can reject the response as having an invalid
source or associate it with a different outstanding probe transaction. In
either case, the manager cannot correctly retire the Probe and preserve the
coherence transaction's response identity.

## Necessary multi-client trigger

The triggering transaction requires two coherent clients or harts sharing
the TileLink coherence manager and L1 interconnect:

1. Hart A holds a cache line in a dirty state after modifying it.
2. A peer client, Hart B, needs the line, so the coherence manager sends a
   legal B-channel Probe to Hart A. Let the Probe source be `s`, with
   `s != cfg.nMSHRs`.
3. Hart A accepts the Probe. Its `BoomProbeUnit` forwards `s` in
   `WritebackReq.source` to `BoomWritebackUnit`.
4. Because Hart A's line is dirty, the writeback unit emits a C-channel
   `ProbeAckData`. TileLink requires its C-channel source to echo `s`.
5. At the affected parent, the response is built with `fromSource =
   cfg.nMSHRs`, so its source is not `s`. The shared coherence manager can
   therefore reject the response or match it to the wrong outstanding
   transaction instead of completing Hart B's Probe correctly.

The peer-generated B-channel Probe and the dirty line are both necessary:
the former supplies the source that must be echoed, and the latter selects
the `ProbeAckData` writeback path. A local access without a peer Probe does
not exercise this source-correlation failure.

## Canonical fix and closure

The direct child [c5ec95fd](https://github.com/riscv-boom/riscv-boom/commit/c5ec95fd1bf29f94df84dfd625dced212392898f)
changes the dirty probe response construction to use the source propagated
from the Probe request:

```scala
val probeResponse = edge.ProbeAck(
  fromSource = req.source,
  toAddress = r_address,
  lgSize = lgCacheBlockBytes.U,
  reportPermissions = req.param,
  data = wb_buffer(data_req_cnt))
```

The fix is the direct source-level correction for the malformed response:
the C-channel `ProbeAckData` now carries the original B-channel Probe source,
while the fixed `cfg.nMSHRs` identifier remains separate for the voluntary
Release path. [BOOM PR #275](https://github.com/riscv-boom/riscv-boom/pull/275)
merged this correction as [ac28f02d](https://github.com/riscv-boom/riscv-boom/commit/ac28f02dafc5cfa284bb83e1c0c7d2b99c20a92a).
The corrected implementation remains in the canonical BOOM v4 DCache
source at [`src/main/scala/lsu/dcache.scala`](https://github.com/riscv-boom/riscv-boom/blob/master/src/main/scala/lsu/dcache.scala).

This record is distinct from every existing BOOM record. The existing
records cover `BOOM-LR_RESERVATION_PROBE_ADMISSION`,
`BOOM-PREFETCH_MSHR_PROBE_CLEAR`, `BOOM-PROBE_NACK_LRSC_RESERVATION`,
`BOOM-LDLD_SNOOP_PNR_BLOCK`, `BOOM-PROBER_INVALID_MSHR_READY`, and
`BOOM-MSHR_PROBER_META_READ_CONFLICT`. None addresses the source identity
of a dirty C-channel `ProbeAckData` or the required echo of a peer B-channel
Probe source. This record therefore documents a separate malformed
coherence-response path with its own direct upstream fix.
