# BOOM

Canonical upstream: [riscv-boom/riscv-boom](https://github.com/riscv-boom/riscv-boom).
Ten historical upstream fixes meet the confirmed-only multicore criteria:

- [probe-nack-lrsc-reservation](probe-nack-lrsc-reservation/record.md) — a
  Probe-nacked request could still update or clear LR/SC reservation state.
- [prober-invalid-mshr-ready](prober-invalid-mshr-ready/record.md) — stale
  request-index state in an invalid MSHR could stall ProbeUnit progress.
- [lr-reservation-probe-admission](lr-reservation-probe-admission/record.md)
  — a live LR reservation did not gate TileLink Probe admission.
- [prefetch-mshr-probe-clear](prefetch-mshr-probe-clear/record.md) — a
  matching prefetch MSHR could remain uncleared when a Probe arrived.
- [mshr-prober-meta-read-conflict](mshr-prober-meta-read-conflict/record.md)
  — a live MSHR metadata read could conflict with same-index Probe admission.
- [ldld-snoop-pnr-block](ldld-snoop-pnr-block/record.md) — an incomplete
  older load could let a coherent snoop drive the younger same-address load
  into the PNR ordering-failure path.
- [wb-last-c-beat-lost](wb-last-c-beat-lost/record.md) — writeback could
  withdraw the final dirty ReleaseData or ProbeAckData beat under C-channel
  backpressure.
- [wb-early-release-ack-not-latched](wb-early-release-ack-not-latched/record.md)
  — an early ReleaseAck could be lost before a multi-beat Release completed.
- [mshr-reused-before-grantack-e](mshr-reused-before-grantack-e/record.md) —
  an MSHR could be reused before its queued GrantAck E-channel handshake.
- [probeack-wrong-source-id](probeack-wrong-source-id/record.md) — dirty
  ProbeAckData used a source ID that did not echo the incoming Probe source.

Unresolved workload hangs, SimTSI integration behavior, and coherence traces
without a confirmed root cause are not included. The BOOM submodule was not
modified.
