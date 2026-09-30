# Ibex

Canonical upstream: [lowRISC/ibex](https://github.com/lowRISC/ibex).
The confirmed records in this directory cover SecureIbex multi-execution:

- [lockstep-csr-config-propagation](lockstep-csr-config-propagation/record.md)
  — configured identity CSRs were not propagated to the shadow core.
- [lockstep-reset-stale-delayed-inputs](lockstep-reset-stale-delayed-inputs/record.md)
  — delayed shadow inputs and cache responses were not reset.
- [lockstep-resetall-unreset-core-state](lockstep-resetall-unreset-core-state/record.md)
  — core-internal IF, FIFO, I-cache, prefetch, and WB state was not reset for
  the lockstep pair.
- [lockstep-enable-fi-hardening](lockstep-enable-fi-hardening/record.md) — a
  single-bit lockstep-enable fault could disable comparison.
- [lockstep-memory-ecc-not-replicated](lockstep-memory-ecc-not-replicated/record.md)
  — memory integrity checking and generation were shared outside the two
  execution instances.
- [lockstep-data-rvalid-fi-window](lockstep-data-rvalid-fi-window/record.md)
  — a shared false response-valid event could write data back to both
  lockstep instances.
- [lockstep-fpga-counter-reset-mismatch](lockstep-fpga-counter-reset-mismatch/record.md)
  — non-DSP FPGA counters used the wrong reset style and diverged across the
  lockstep pair.
- [lockstep-rf-write-enable-glitch](lockstep-rf-write-enable-glitch/record.md)
  — a decoded register-file write-enable fault could corrupt common state
  without an independent shadow observation.
- [lockstep-rf-read-mux-fi](lockstep-rf-read-mux-fi/record.md) — a
  synthesized register-file read MUX fault could feed the same wrong word to
  primary and shadow.
- [lockstep-false-memory-response-no-wb](lockstep-false-memory-response-no-wb/record.md)
  — a false memory response could enter the ID/EX path without a writeback
  stage.
- [lockstep-core-busy-clock-gating](lockstep-core-busy-clock-gating/record.md)
  — a low glitch on primary busy could stop the shared clock before the
  delayed shadow comparison.
- [lockstep-offset-one-elaboration](lockstep-offset-one-elaboration/record.md)
  — the one-cycle lockstep offset could not elaborate because of zero-width
  counter state and incompatible cache-response port shapes.
These twelve records concern primary/shadow SecureIbex instances, not
independently addressable SMP harts. No qualifying ordinary SMP Ibex record
was established, and no Ibex source was modified.
