# BOOM Probe interaction left a matching prefetch MSHR uncleared

- Record ID: `BOOM-PREFETCH_MSHR_PROBE_CLEAR`
- Core: BOOM
- Scope: shared L1 coherence Probe handling and prefetch MSHR state
- Record kind: canonical upstream Chisel/RTL fix
- Source repository: [riscv-boom/riscv-boom](https://github.com/riscv-boom/riscv-boom)
- Affected parent: [3b32b972](https://github.com/riscv-boom/riscv-boom/commit/3b32b972fbd8c26b39863b91c2ac8a7fea6cb05d)
- Fix commit: [bd20e75c](https://github.com/riscv-boom/riscv-boom/commit/bd20e75cb06c1b64dbaaf902f56e42652e83661f), `[mshrs] Fix probe interaction with prefetching mshrs`
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact parent/child MSHR clear condition and the retained canonical v4 equivalent
- Affected revisions: BOOM MSHR revisions before `bd20e75c`
- Retrieved: 2026-09-10

## Failure mechanism

In the affected MSHR file, a completed prefetch could remain in
`s_prefetch`. The parent cleared a prefetch MSHR on a request/index conflict
only when the incoming tag did not match:

```scala
mshr.io.clear_prefetch := io.clear_all ||
  ((req.valid || req_is_probe) &&
   idx_matches(req_idx)(i) &&
   cacheable &&
   !tag_match(req_idx))
```

For a Probe to the same prefetched line, the index matched and the prefetch
tag also matched, so `!tag_match(req_idx)` was false. The MSHR stayed in
`s_prefetch` while the Probe path waited for the MSHR's readiness. The
finding recorded here is limited to this Probe-specific clear omission. The
same commit also adds primary-request handling while in `s_prefetch`; that
separate primary-request reuse behavior can be exercised by one client and
is not included in this record. The Probe-specific result was a
Probe/prefetch state-machine wait rather than completion of the incoming
coherence action.

The upstream fix adds a Probe-specific clear alternative:

```scala
mshr.io.clear_prefetch :=
  ((io.clear_all && !req.valid) ||
   (req.valid && idx_matches(req_idx)(i) && cacheable &&
    !tag_match(req_idx)) ||
   (req_is_probe && idx_matches(req_idx)(i)))
```

The same commit also factors the primary-request handler and makes it
available in `s_prefetch`; that portion is intentionally outside this
record because it does not require a second client. The recorded change is
the actual Probe-specific state transition, not a benchmark or trace
adjustment.

## Two-client trigger

Use two coherent BOOM harts/clients sharing the TileLink network.

1. Hart A issues a prefetch that fills an MSHR and leaves it in the
   `s_prefetch` state instead of committing the line to ordinary metadata.
2. Hart B requests a coherence transition for the same line, causing an
   incoming TileLink B-channel Probe to hart A. The Probe is accepted by the
   prober and reaches the MSHR arbitration as `req_is_probe`.
3. The parent sees the same MSHR index and matching prefetch tag. Because the
   old clear condition required `!tag_match(req_idx)`, it does not clear the
   prefetch MSHR. The MSHR remains unavailable for the Probe, and the
   coherence transaction can be held indefinitely by the readiness loop.
4. The fix clears the matching prefetch MSHR specifically for a Probe, after
   which the MSHR reports readiness and the Probe can complete.

The external Probe from the second coherent client is necessary. A local
prefetch alone does not set `req_is_probe` and cannot exercise this
Probe/prefetch interaction.

## Source and deduplication evidence

The parent and fix modify [`src/main/scala/lsu/mshrs.scala`](https://github.com/riscv-boom/riscv-boom/blob/3b32b972fbd8c26b39863b91c2ac8a7fea6cb05d/src/main/scala/lsu/mshrs.scala).
The current canonical v4 implementation retains the Probe-specific clear
path in [`v4/lsu/mshrs.scala`](https://github.com/riscv-boom/riscv-boom/blob/58ef2720eae13be26b3008c02b5a74ce29c61c44/src/main/scala/v4/lsu/mshrs.scala).

This record is distinct from:

- the separate prefetch permission-upgrade path
  upgrade racing with a Probe;
- `BOOM-PROBER_INVALID_MSHR_READY`, which covers stale index state in an
  already invalid MSHR;
- `BOOM-MSHR_PROBER_META_READ_CONFLICT`, which covers live MSHR metadata
  arbitration.

No new simulation is claimed; the canonical parent/fix diff and retained
upstream implementation are the confirmation evidence.
