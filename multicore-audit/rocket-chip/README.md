# Rocket Chip

Canonical upstream: [chipsalliance/rocket-chip](https://github.com/chipsalliance/rocket-chip).
The eighteen records below are confirmed historical upstream fixes for
multi-hart interrupts, shared TileLink/atomic paths, Debug, and DCache
coherence behavior.

- [clint-msip-stride](clint-msip-stride/record.md)
- [dcache-lrsc-probe-progress](dcache-lrsc-probe-progress/record.md)
- [dcache-grant-probe-livelock](dcache-grant-probe-livelock/record.md)
- [dcache-lrsc-probe-admission](dcache-lrsc-probe-admission/record.md)
- [dcache-releaseack-probe](dcache-releaseack-probe/record.md)
- [dcache-releaseack-acquire-probeack](dcache-releaseack-acquire-probeack/record.md)
- [dm-hartarray-mask-32plus](dm-hartarray-mask-32plus/record.md)
- [dm-exttrigger-haltgroup](dm-exttrigger-haltgroup/record.md)
- [tlbroadcast-d-tracker-source-reuse](tlbroadcast-d-tracker-source-reuse/record.md)
- [tlbroadcast-multibeat-tracker-hold](tlbroadcast-multibeat-tracker-hold/record.md)
- [tlbroadcast-probeackdata-completion](tlbroadcast-probeackdata-completion/record.md)
- [tlatomic-automata-zero-latency-ack](tlatomic-automata-zero-latency-ack/record.md)
- [tlatomic-automata-get-error-merge](tlatomic-automata-get-error-merge/record.md)
- [core-amo-aq-rl-fence-direction](core-amo-aq-rl-fence-direction/record.md)
- [tlfragmenter-source-reuse](tlfragmenter-source-reuse/record.md)
- [dcache-acquire-before-release-queue](dcache-acquire-before-release-queue/record.md)
- [interrupt-crossing-sync-reset](interrupt-crossing-sync-reset/record.md)
- [plic-meip-seip-flat-order](plic-meip-seip-flat-order/record.md)

The fixed records are historical. The audit did not modify the Rocket Chip
submodule or run a full generated-system regression.
