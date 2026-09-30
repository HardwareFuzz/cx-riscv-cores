# HPDcache flush-only writeback could retain the directory dirty bit

- Record ID: `CVA6-HPDCACHE-CMO-FLUSH-DIRTY-CLEAR`
- Core: CVA6
- Source repository: [openhwgroup/cv-hpdcache](https://github.com/openhwgroup/cv-hpdcache)
- Scope: shared-memory software coherence, CBO.CLEAN, and HPDcache directory state
- Record kind: canonical upstream HPDcache SystemVerilog RTL fix
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact parent/fix chain, the flush and directory RTL paths, the CVA6 CBO mapping, and merged HPDcache PR #56
- Affected parent: [d300e522](https://github.com/openhwgroup/cv-hpdcache/commit/d300e5224dd2f93abde9be3eb08621443fdcd954)
- Fixed revision: [04de808](https://github.com/openhwgroup/cv-hpdcache/commit/04de80896981527c34fbbd35d7b1ef787a082d7c)
- Canonical fix: [HPDcache PR #56](https://github.com/openhwgroup/cv-hpdcache/pull/56), merged upstream
- Retrieved: 2026-09-10

## Failure mechanism

At the affected parent, HPDcache distinguished flush-only operations from
flush-invalidate operations with `cmoh_flush_req_inval_q`. For `flush by
nline` and `flush all`, the CMO state machine explicitly kept that flag low:

```systemverilog
cmoh_flush_req_inval_d = 1'b0;
```

The directory output, however, was driven only for the invalidate case:

```systemverilog
dir_inval_o = cmoh_flush_req_inval_q & ...;
```

The flush machinery still selected dirty lines, read their data, wrote the
whole line to lower memory, and waited for the memory write response. The
missing directory update meant that a successful flush-only operation left
the directory state unchanged: the line could remain valid with its old tag
and `dirty=1` even though the dirty data had already been written back.

Affected source paths:

- [parent `hpdcache_cmo.sv`](https://github.com/openhwgroup/cv-hpdcache/blob/d300e5224dd2f93abde9be3eb08621443fdcd954/rtl/src/hpdcache_cmo.sv)
- [parent `hpdcache_memctrl.sv`](https://github.com/openhwgroup/cv-hpdcache/blob/d300e5224dd2f93abde9be3eb08621443fdcd954/rtl/src/hpdcache_memctrl.sv)
- [parent `hpdcache_flush.sv`](https://github.com/openhwgroup/cv-hpdcache/blob/d300e5224dd2f93abde9be3eb08621443fdcd954/rtl/src/hpdcache_flush.sv)

## Necessary shared-memory trigger

The CVA6 HPDcache adapter maps the architectural operation as follows:

```text
CBO.CLEAN  -> HPDCACHE_REQ_CMO_FLUSH_NLINE
CBO.FLUSH  -> HPDCACHE_REQ_CMO_FLUSH_INVAL_NLINE
CBO.INVAL  -> HPDCACHE_REQ_CMO_INVAL_NLINE
```

Thus the affected flush-only path is reachable through the CVA6 CBO
interface. A concrete shared-memory sequence is:

1. Hart A writes a shared line in its write-back HPDcache, producing value
   `A1` and a directory `dirty=1` state.
2. Hart A executes `CBO.CLEAN`; the parent writes `A1` to shared lower memory.
3. Because the flush is not an invalidate and the parent has no directory
   update for it, Hart A's line remains valid and marked dirty.
4. Hart B or a DMA agent publishes a newer value `B2` for the same shared
   line in lower memory.
5. Hart A later replaces or cleans its still-valid stale line. The retained
   dirty state permits the old `A1` line to be written back again, overwriting
   the newer shared value `B2`.

HPDcache is a software-maintained coherence cache rather than a hardware
snoop-coherent cache. Its CMO and fence interface is intended to let multiple
harts or DMA agents coordinate access to shared memory. The stale directory
state therefore has a concrete multi-agent consequence; it is not only an
isolated local CMO bookkeeping discrepancy.

## Confirmed consequence

After a successful flush-only writeback, the directory's dirty state can
disagree with lower memory. In the shared-memory sequence above, a later
operation can treat the stale line as dirty and write it back over a newer
value published by another hart or DMA agent. This is a software-coherence
failure caused by the HPDcache RTL's directory state not tracking its own
completed writeback.

## Canonical fix and closure

The direct fix [`04de808`](https://github.com/openhwgroup/cv-hpdcache/commit/04de80896981527c34fbbd35d7b1ef787a082d7c), titled
`cmo: fix flush operation that shall clear the dirty bit in directory`, adds
a complete directory-update path for CMO operations. For flush-only work it
preserves the valid/tag/write-back identity while forcing `dirty=0`; for
flush-invalidate it invalidates the entry. The fix updates the directory
control and memory-control paths rather than merely changing a test or
software mapping.

The exact upstream chain is parent
`d300e5224dd2f93abde9be3eb08621443fdcd954` to fix
`04de80896981527c34fbbd35d7b1ef787a082d7c`. [HPDcache PR #56](https://github.com/openhwgroup/cv-hpdcache/pull/56) contains that one-commit RTL repair and is merged upstream. The repaired directory update remains in the fixed source:

- [fixed `hpdcache_cmo.sv`](https://github.com/openhwgroup/cv-hpdcache/blob/04de80896981527c34fbbd35d7b1ef787a082d7c/rtl/src/hpdcache_cmo.sv)
- [fixed `hpdcache_memctrl.sv`](https://github.com/openhwgroup/cv-hpdcache/blob/04de80896981527c34fbbd35d7b1ef787a082d7c/rtl/src/hpdcache_memctrl.sv)
- [CVA6 adapter CBO mapping](https://github.com/openhwgroup/cva6/blob/b4d678f12010da00fbdbcdb512ac284bc9041213/core/cache_subsystem/cva6_hpdcache_if_adapter.sv)
- [HPDcache PR #56](https://github.com/openhwgroup/cv-hpdcache/pull/56)

## Duplicate boundary

The existing CVA6 records cover other HPDcache writeback, fence, AXI, and
atomic paths. They do not cover the flush-only distinction between writing a
dirty line back and clearing its directory dirty bit. This record is also
distinct from a single-request directory bookkeeping issue: its consequence
requires the software-maintained shared-memory/coherence interaction with a
second hart or DMA agent.
