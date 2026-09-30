# VexRiscv

Canonical upstream: [SpinalHDL/VexRiscv](https://github.com/SpinalHDL/VexRiscv).
One VexRiscv record met the exact-parent evidence gate for this
confirmed-only deliverable:

- [invalidation-read-during-write-hazard](invalidation-read-during-write-hazard/record.md)

The record is limited to the upstream four-core SMP DataCache invalidation
hazard and its merged consistency regression. Hart-ID, FPU, debug, CSR, and
refill-invalidation changes that do not establish the same complete
multicore failure-and-fix chain are not included. No VexRiscv source was
modified.
