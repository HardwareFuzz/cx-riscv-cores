# BOOM Probe-induced `s2_nack_hit` could still change LR/SC reservation state

- Record ID: `BOOM-PROBE_NACK_LRSC_RESERVATION`
- Core: BOOM
- Scope: shared L1 cache coherence Probe nack and LR/SC reservation bookkeeping
- Record kind: canonical upstream Chisel/RTL fix
- Source repository: [riscv-boom/riscv-boom](https://github.com/riscv-boom/riscv-boom)
- Initial defect parent: [9b834ac9](https://github.com/riscv-boom/riscv-boom/commit/9b834ac9d56562e2d1692280dd140383334aae4d)
- Intermediate fix: [6bd83ac7](https://github.com/riscv-boom/riscv-boom/commit/6bd83ac7d692daec4a0a984686cdb375d737e546)
- Residual-defect parent: [bcfbf3f2](https://github.com/riscv-boom/riscv-boom/commit/bcfbf3f22693432593d37bc6a77b2214766af71d)
- Complete fix: [693166e8](https://github.com/riscv-boom/riscv-boom/commit/693166e86f282e3bb19f07cbb5c52cb325d3ccbd)
- Fix PR: [#275](https://github.com/riscv-boom/riscv-boom/pull/275), merged as [ac28f02d](https://github.com/riscv-boom/riscv-boom/commit/ac28f02dafc5cfa284bb83e1c0c7d2b99c20a92a)
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the canonical parent/intermediate/final diff chain and the merged upstream PR
- Affected revisions: the residual parent `bcfbf3f2` after the earlier LR/SC-classification repair and before `693166e8`
- Retrieved: 2026-09-10

## Failure mechanism

The affected path is `src/main/scala/lsu/dcache.scala`. BOOM pipelines a
load/store request through DCache stages `s1` and `s2`. An incoming coherence
Probe can make the request be nacked in `s2` through `s2_nack_hit`:

```scala
val s2_nack_hit = RegNext(s1_nack) // nack because of incoming probe
val s2_nack     = (s2_nack_miss || s2_nack_hit || s2_nack_victim) && !s2_is_replay
```

The initial parent also had a separate LR/SC-classification defect: a
Probe-nacked operation could still be classified as `s2_lr` or `s2_sc`.
That first-stage defect was fixed by `6bd83ac7`, which added
`!RegNext(s1_nack)` to the operation tests. The finding recorded here is the
residual defect in the direct parent `bcfbf3f2`, after that classification
repair. Its LR/SC reservation bookkeeping was still guarded by hit/miss
conditions but not by the Probe-induced `s2_nack_hit`:

```scala
when ((s2_valid && s2_hit) ||
      (s2_is_replay && s2_req.uop.mem_cmd =/= M_FLUSH_ALL)) {
  when (s2_lr) {
    lrsc_count := (lrscCycles - 1).U
    lrsc_addr  := s2_req.addr >> blockOffBits
  }
  when (lrsc_count > 0.U) { lrsc_count := 0.U }
}
when (s2_valid && !s2_hit && s2_lrsc_addr_match) {
  lrsc_count := 0.U
}
```

The remaining defect was that the bookkeeping conditions could still execute
for a Probe-nacked hit or matching miss. The complete repair introduced a
single `s2_nack` wire and added `!s2_nack` to both reservation update/clear
conditions. For this record, the relevant component is
`s2_nack_hit = RegNext(s1_nack)`, the nack caused by the incoming Probe. This
closes the residual path:

- a Probe-induced nacked hit cannot clear an existing reservation;
- a Probe-induced matching miss cannot clear an existing reservation;
- the normal response path remains suppressed by the same nack.

The final parent-to-fix diff is visible in the [canonical DCache fix
commit](https://github.com/riscv-boom/riscv-boom/commit/693166e86f282e3bb19f07cbb5c52cb325d3ccbd).

## Two-hart trigger

Configure at least two coherent BOOM clients/harts sharing the DCache's
TileLink coherence network:

1. Hart A issues an LR or SC for a line resident in its BOOM DCache.
2. Hart B writes or upgrades the same line, causing the coherence manager to
   send an incoming Probe to hart A.
3. Arrange the Probe and hart A's DCache request to overlap at the `s1`/`s2`
   boundary. The Probe sets `s1_nack`, and the corresponding request reaches
   `s2` with `s2_nack_hit`/`s2_nack` asserted.
4. In the residual parent, the request is nacked to the LSU, but the
   reservation bookkeeping is not consistently nacked. The
   Probe-induced `s2_nack_hit` can still enter a matching hit/miss clear path
   and remove an existing reservation even though the operation did not
   complete. A later SC from hart A consequently observes reservation state
   that does not correspond to the completed LR/SC history.

The trigger requires a coherent second client to generate the incoming Probe;
the same-cycle Probe/request interaction is absent from a single isolated
client. The bug is in the shared-cache multi-client interaction, not merely in
the existence of the LR/SC instruction.

## Upstream closure and deduplication

PR #275 merged the complete repair after the earlier `6bd83ac7` change. This
record is distinct from the existing BOOM records:

- `BOOM-MSHR_PROBER_META_READ_CONFLICT` concerns MSHR metadata arbitration against
  the prober, not LR/SC reservation updates after a nack.
- the separate prefetch permission-upgrade path concerns prefetch permission upgrades
  racing with Probe handling.
- the per-hart interrupt connection-order path concerns interrupt connection order.

No new simulation is claimed here; the exact canonical fix chain is the
confirmation evidence.

## Source evidence

- Pre-fix and final path: [`src/main/scala/lsu/dcache.scala`](https://github.com/riscv-boom/riscv-boom/blob/bcfbf3f22693432593d37bc6a77b2214766af71d/src/main/scala/lsu/dcache.scala)
- Initial Probe/LRSC repair: [6bd83ac7](https://github.com/riscv-boom/riscv-boom/commit/6bd83ac7d692daec4a0a984686cdb375d737e546)
- Complete reservation-nack repair: [693166e8](https://github.com/riscv-boom/riscv-boom/commit/693166e86f282e3bb19f07cbb5c52cb325d3ccbd)
- Merged upstream closure: [PR #275 / ac28f02d](https://github.com/riscv-boom/riscv-boom/pull/275)
