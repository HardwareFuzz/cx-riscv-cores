# CVA6

Canonical upstream: [openhwgroup/cva6](https://github.com/openhwgroup/cva6).
Ten confirmed multi-hart/shared-memory or shared-cache records are included:

- [multihart-debug-req-width](multihart-debug-req-width/record.md) — the
  Debug Module truncated high-hart halt requests and mis-sized command status.
- [multicore-clint-timer-irq](multicore-clint-timer-irq/record.md) — CLINT
  compared a packed multi-core timer array as one value and emitted one IRQ.
- [axi-riscv-atomic-burst-reservation-invalidation](axi-riscv-atomic-burst-reservation-invalidation/record.md)
  — a write burst cleared only its base address in the shared reservation table.
- [axi-riscv-atomic-inflight-lr-sc-ordering](axi-riscv-atomic-inflight-lr-sc-ordering/record.md)
  — an exclusive LR could pass an overlapping write that was still in flight.
- [multihart-clint-msip-stride](multihart-clint-msip-stride/record.md) — the
  CLINT used the wrong per-hart stride and address bit for MSIP/IPI access.
- [std-cache-axi-wvalid-awready-deadlock](std-cache-axi-wvalid-awready-deadlock/record.md)
  — AW backpressure could deadlock W propagation in the shared standard-cache
  AXI fabric.
- [std-cache-axi-w-fifo-aw-order](std-cache-axi-w-fifo-aw-order/record.md)
  — the shared AXI W-source FIFO could retain a completed AW source.
- [hpdcache-wb-fence-i-coherence](hpdcache-wb-fence-i-coherence/record.md)
  — HPDcache write-back could race fence.i instruction fetch.
- [hpdcache-dirty-line-noncacheable-data-consistency](hpdcache-dirty-line-noncacheable-data-consistency/record.md)
  — a dirty write-back line could be bypassed by a later non-cacheable access.
- [hpdcache-cmo-flush-dirty-clear](hpdcache-cmo-flush-dirty-clear/record.md)
  — flush-only writeback could leave the HPDcache directory dirty bit set.

The ten records use canonical upstream CVA6/HPDcache and PULP dependency history. The two AXI atomics records use the canonical PULP dependency history that is
vendored by CVA6, including the merged burst invalidation fix and the closed
in-flight ordering issue. Fork-only DTM, trace, AXI-mux, PLIC, and private
cache integration observations are outside the final set. The HPDcache
dirty-line record is limited to the exact `HPDCACHE_WB` consumer lock and does
not claim that this CVA6 snapshot implements Svpbmt. No CVA6 source was
modified.
