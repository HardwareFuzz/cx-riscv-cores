# RISC-V confirmed-only multi-hart / multi-core HDL audit

This directory is the final confirmed-only deliverable for the multicore
audit, retrieved on 2026-09-11. It contains 78 independent records across
ten RISC-V core families. Each record has one precise pre-fix HDL/RTL
mechanism, a concrete multi-hart, multi-core, shared-fabric, or multi-instance
trigger, and authoritative upstream evidence or an independently reproduced
failure.

Only files named record.md are deliverables. The index in
[records.tsv](records.tsv) is generated from those records, and every indexed
path exists. Historical records describe a fixed defect in an earlier
revision; they do not imply that the current checkout is still broken.

## Inclusion rule

A record is included only when all of the following are established:

- the affected implementation and the failure mechanism are identifiable;
- the failure concerns multiple harts, cores, coherent clients, a shared
  interconnect/cache, per-hart resource routing, or multiple execution
  instances;
- the trigger is concrete rather than a general suspicion; and
- an upstream fix, an authoritative issue/PR with a closed mechanism, or an
  independent runtime differential confirms the result.

Materials that do not meet every condition are not part of this directory.
No core submodule was modified while preparing these records.

## Counts

| Core | Confirmed records | Boundary |
| --- | ---: | --- |
| BOOM | 10 | upstream coherence, LR/SC, Probe, MSHR, writeback, and LSU ordering |
| CVA6 | 10 | upstream AXI/HPDcache paths, atomics, CLINT, and Debug Module |
| Ibex | 12 | SecureIbex lockstep multi-execution |
| Kronos | 0 | canonical implementation is single-core |
| OpenC906 | 0 | audited artifacts expose a single core |
| OpenC910 | 0 | no qualifying canonical confirmed record |
| PicoRV32 | 0 | no qualifying canonical multi-hart record |
| Rocket Chip | 18 | upstream multi-hart interrupt, Debug, atomic, bus, and DCache paths |
| VexRiscv | 1 | upstream four-core SMP DataCache invalidation path |
| XiangShan | 27 | upstream CoupledL2, CHI, openLLC, and inter-hart paths |
| Total | 78 | |

Ibex is counted under the broad multi-core HDL scope because SecureIbex
instantiates a primary and a delayed shadow execution instance. Those twelve
records are explicitly not claims about two independently addressable SMP
harts. No qualifying ordinary SMP record was established for Ibex.

No qualifying canonical multi-hart record was established for PicoRV32. The
canonical core is a single-instance RV32 implementation without a coherence
or interrupt fabric. XiangShan's TL2TL record is explicitly historical
because the current CHI path has been restructured.

## Core conclusions

- [BOOM](boom/README.md): ten confirmed upstream historical fixes.
- [CVA6](cva6/README.md): ten confirmed upstream historical fixes.
- [Ibex](ibex/README.md): twelve confirmed SecureIbex multi-execution records;
  no independently addressable SMP record was established.
- [Kronos](kronos/README.md): no confirmed multi-core record.
- [OpenC906](openc906/README.md): no confirmed multi-core record.
- [OpenC910](openc910/README.md): no confirmed canonical multi-hart record.
- [PicoRV32](picorv32/README.md): no qualifying canonical multi-hart record.
- [Rocket Chip](rocket-chip/README.md): eighteen confirmed upstream records.
- [VexRiscv](vexriscv/README.md): one confirmed upstream four-core SMP
  DataCache invalidation fix.
- [XiangShan](xiangshan/README.md): 27 confirmed upstream records.
