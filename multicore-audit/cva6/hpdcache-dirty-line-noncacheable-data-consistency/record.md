# CVA6 HPDcache dirty-line/non-cacheable access could use stale memory data

- Record ID: `CVA6-HPDCACHE-DIRTY-LINE-NONCACHEABLE-DATA-CONSISTENCY`
- Core: CVA6
- Source repository: [openhwgroup/cv-hpdcache](https://github.com/openhwgroup/cv-hpdcache)
- Scope: shared HPDcache write-back requester path in the exact CVA6
  `cv64a6_imafdc_sv39_hpdcache_wb` consumer configuration
- Record kind: canonical upstream HPDcache/CVA6 SystemVerilog RTL fix
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact CVA6 dependency lock, the affected and
  fixed HPDcache RTL, the reachable dirty-line/non-cacheable trigger, and the
  merged HPDcache and CVA6 integration closures
- Affected CVA6 snapshot: [778c1a15](https://github.com/openhwgroup/cva6/commit/778c1a156456738d7e5b65737583ce8d43ae22a5)
- Affected HPDcache revision: [acf97c95](https://github.com/openhwgroup/cv-hpdcache/commit/acf97c95f2b0bf895143ed5559b04629a474548d), locked by that CVA6 snapshot
- Affected file: [`rtl/src/hpdcache_ctrl_pe.sv`](https://github.com/openhwgroup/cv-hpdcache/blob/acf97c95f2b0bf895143ed5559b04629a474548d/rtl/src/hpdcache_ctrl_pe.sv)
- Fixed HPDcache revision: [e5f66714](https://github.com/openhwgroup/cv-hpdcache/commit/e5f6671483ba84916638c2c2e2c155187e29bc4c)
- Canonical fix: [HPDcache PR #135](https://github.com/openhwgroup/cv-hpdcache/pull/135), merged as `e5f66714`
- CVA6 integration closure: [cfb85e7a](https://github.com/openhwgroup/cva6/commit/cfb85e7aeea3f9de345167f5819e3230bd313156), [CVA6 PR #3293](https://github.com/openhwgroup/cva6/pull/3293)
- Retrieved: 2026-09-10

## Failure mechanism

The CVA6 snapshot explicitly selects the `HPDCACHE_WB` data-cache type in
`cv64a6_imafdc_sv39_hpdcache_wb_config_pkg.sv`. Its
`core/cache_subsystem/hpdcache` gitlink is exactly
`acf97c95f2b0bf895143ed5559b04629a474548d`, so the consumer and dependency
revisions are identified together. The HPDcache is shared by independent
requester classes in this configuration, including load, accelerator-load,
store/AMO, PTW, CMO, and prefetch paths.

At the affected HPDcache revision, `hpdcache_ctrl.sv` forms
`st1_req_is_uncacheable` from `~cfg_enable_i |
st1_req.req.pma.uncacheable`. In `hpdcache_ctrl_pe.sv`, stage 0 suppresses the
directory read when `st0_req_is_uncacheable_i` is true. The stage-1
uncacheable branch can then produce `uc_req_valid_o` after pending
transactions clear without checking `cachedir_hit_i` or
`st1_dir_hit_dirty_i`. That path only drains the write buffer; it does not
flush a dirty write-back line already held in the directory and data array.

The same revision can create such a dirty line through the write-back store
path, which asserts `st2_mshr_alloc_wback_o` and
`st2_mshr_alloc_dirty_o`, or through the corresponding dirty directory update
on a hit. A later uncacheable access to that line therefore bypasses the
dirty cache copy and can read an older value from the next memory level.

## Necessary shared-requester trigger

This is a shared-cache, multi-requester failure. It does not require a claim
that the reproducing transaction uses two hart IDs; the exact CVA6 consumer
routes independent requester classes through one HPDcache instance.

1. In the exact `HPDCACHE_WB` configuration, a store or AMO requester writes a
   cached address `A`, leaving the corresponding HPDcache line dirty.
2. Software takes the reachable CVA6 `CSR_DCACHE = 12'h7C1` path to disable
   the data cache. That path changes HPDcache `cfg_enable_i`; it does not
   flush the dirty line.
3. A separate load requester accesses the same address `A`. With
   `~cfg_enable_i`, the request is classified as uncacheable.
4. At the affected revision, the uncacheable path skips the dirty directory
   line and reads lower-level memory, which can still contain the old value.

The trigger is specific to a write-back HPDcache with a dirty line and a
subsequent non-cacheable access. A cache configuration without that shared
write-back state does not establish this record's mechanism.

## Canonical fix and closure

The direct child fix [e5f66714](https://github.com/openhwgroup/cv-hpdcache/commit/e5f6671483ba84916638c2c2e2c155187e29bc4c)
has direct parent `acf97c95f2b0bf895143ed5559b04629a474548d`. It removes the
stage-0 exclusion that prevented uncacheable requests from reading the
directory. Stage 1 then distinguishes a directory miss, a clean hit, and a
dirty hit for an uncacheable request: a miss proceeds to the uncacheable
handler, a clean hit is invalidated first, and a dirty hit allocates a dirty
line flush, clears the relevant directory state, writes the line back, and
replays the uncacheable request after completion.

The CVA6 integration commit [cfb85e7a](https://github.com/openhwgroup/cva6/commit/cfb85e7aeea3f9de345167f5819e3230bd313156)
updates the HPDcache gitlink from `acf97c95f2b0bf895143ed5559b04629a474548d`
to `e5f6671483ba84916638c2c2e2c155187e29bc4c`. HPDcache issue [#133](https://github.com/openhwgroup/cv-hpdcache/issues/133)
identifies the dirty-line/non-cacheable data-consistency defect, and PR
[#135](https://github.com/openhwgroup/cv-hpdcache/pull/135) merges the RTL
fix and directed dirty-hit, clean-hit, miss, and mixed-traffic tests. CVA6 PR
[#3293](https://github.com/openhwgroup/cva6/pull/3293) closes the consumer
integration update.

## Source evidence

- [CVA6 locked consumer snapshot](https://github.com/openhwgroup/cva6/commit/778c1a156456738d7e5b65737583ce8d43ae22a5)
- [CVA6 HPDCACHE_WB configuration](https://github.com/openhwgroup/cva6/blob/778c1a156456738d7e5b65737583ce8d43ae22a5/core/include/cv64a6_imafdc_sv39_hpdcache_wb_config_pkg.sv)
- [Affected `hpdcache_ctrl.sv`](https://github.com/openhwgroup/cv-hpdcache/blob/acf97c95f2b0bf895143ed5559b04629a474548d/rtl/src/hpdcache_ctrl.sv)
- [Affected `hpdcache_ctrl_pe.sv`](https://github.com/openhwgroup/cv-hpdcache/blob/acf97c95f2b0bf895143ed5559b04629a474548d/rtl/src/hpdcache_ctrl_pe.sv)
- [Fixed `hpdcache_ctrl_pe.sv`](https://github.com/openhwgroup/cv-hpdcache/blob/e5f6671483ba84916638c2c2e2c155187e29bc4c/rtl/src/hpdcache_ctrl_pe.sv)
- [Exact affected-to-fixed comparison](https://github.com/openhwgroup/cv-hpdcache/compare/acf97c95f2b0bf895143ed5559b04629a474548d...e5f6671483ba84916638c2c2e2c155187e29bc4c)
- [HPDcache issue #133](https://github.com/openhwgroup/cv-hpdcache/issues/133)
- [HPDcache PR #135](https://github.com/openhwgroup/cv-hpdcache/pull/135)
- [CVA6 integration commit](https://github.com/openhwgroup/cva6/commit/cfb85e7aeea3f9de345167f5819e3230bd313156)
- [CVA6 PR #3293](https://github.com/openhwgroup/cva6/pull/3293)

## Duplicate boundary

This record concerns a dirty write-back line followed by a non-cacheable
access in the shared HPDcache requester path. It is distinct from the
existing [HPDcache fence.i record](../hpdcache-wb-fence-i-coherence/record.md),
which concerns ordering between a write-back data path and instruction-fetch
coherence at `fence.i`, not the dirty-line/non-cacheable transition.
