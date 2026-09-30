# XiangShan

Canonical upstream: [OpenXiangShan/XiangShan](https://github.com/OpenXiangShan/XiangShan).
The 27 records below are confirmed upstream CoupledL2/XSCache, CHI, and
inter-hart ordering fixes.

## CoupledL2 and CHI

- [coupledL2-probe-tot-nested-release-state](coupledL2-probe-tot-nested-release-state/record.md)
- [coupledL2-missed-forward-snoop-nested-writeback](coupledL2-missed-forward-snoop-nested-writeback/record.md)
- [coupledL2-snpstash-nested-state-update](coupledL2-snpstash-nested-state-update/record.md)
- [coupledL2-writecleanfull-nested-snoop](coupledL2-writecleanfull-nested-snoop/record.md)
- [coupledL2-probeack-mshr-meta-state](coupledL2-probeack-mshr-meta-state/record.md)
- [coupledL2-nestable-directory-miss-forward-state](coupledL2-nestable-directory-miss-forward-state/record.md)
- [coupledL2-snpquery-nested-evict-state](coupledL2-snpquery-nested-evict-state/record.md)
- [coupledL2-rxsnp-cmo-blocking-race](coupledL2-rxsnp-cmo-blocking-race/record.md)
- [coupledL2-writeback-retry-cbwrdata](coupledL2-writeback-retry-cbwrdata/record.md)
- [coupledL2-writeevict-nested-snoop](coupledL2-writeevict-nested-snoop/record.md)
- [coupledL2-snponce-writeback-nesting](coupledL2-snponce-writeback-nesting/record.md)
- [coupledL2-tl2tl-probe-releaseack-conflict](coupledL2-tl2tl-probe-releaseack-conflict/record.md)
- [coupledL2-snprepfwded-self-nesting](coupledL2-snprepfwded-self-nesting/record.md)
- [coupledL2-release-retry-opcode-immutability](coupledL2-release-retry-opcode-immutability/record.md)
- [coupledL2-writecleanfull-snponce-uc-state](coupledL2-writecleanfull-snponce-uc-state/record.md)
- [coupledL2-tl2tl-grantdata-dstorage](coupledL2-tl2tl-grantdata-dstorage/record.md)
- [coupledL2-snponce-trunk-dirty](coupledL2-snponce-trunk-dirty/record.md)
- [coupledL2-compack-datasep-ordering](coupledL2-compack-datasep-ordering/record.md)
- [coupledL2-snpunique-fwd-illegal-dct-resp](coupledL2-snpunique-fwd-illegal-dct-resp/record.md)
- [coupledL2-snppreferunique-fwd-classification](coupledL2-snppreferunique-fwd-classification/record.md)
- [coupledL2-cbo-inval-releasebuffer-data](coupledL2-cbo-inval-releasebuffer-data/record.md)
- [coupledL2-snpstash-trunk-stale-data](coupledL2-snpstash-trunk-stale-data/record.md)

## openLLC refill data paths

- [openllc-stash-refill-bypass-refillbuf-leak](openllc-stash-refill-bypass-refillbuf-leak/record.md)
  — a same-line MemUnit bypass could leave a `StashOnceShared` RefillUnit
  entry waiting forever for data.
- [coupledL2-rxsnp-replacement-releasebuf-race](coupledL2-rxsnp-replacement-releasebuf-race/record.md)
  — replacement-snoop admission could read the ReleaseBuffer before the
  refill wrote the newest victim data.

The records are limited to exact historical XSCache fixes for
nested release/snoop, ProbeAck metadata, and CMO/RXSNP ordering. The
XSCache review excluded the remaining
single-request, routing-only, arbitration/performance, and error-propagation
changes.

## Top-level multicore identity and interrupt routing

- [mhartid-nonunique](mhartid-nonunique/record.md)
- [clint-per-hart-state-alias](clint-per-hart-state-alias/record.md)

## L1 cache and inter-hart ordering

- [intercore-mip-csr-ordering](intercore-mip-csr-ordering/record.md)

The MIP record includes the equivalent v3 fix for the current v3 baseline.
The XiangShan, XSCache, ChiselAIA, and difftest source trees were not
modified.
