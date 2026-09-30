# CVA6 AXI LR/SC adapter failed to clear reservations covered by a write burst

- Record ID: `CVA6-AXI-RISCV-ATOMIC-BURST-RESERVATION-INVALIDATION`
- Core: CVA6 / vendored PULP AXI atomics
- Scope: shared AXI exclusive monitor and reservation invalidation
- Record kind: canonical merged upstream PULP AXI SystemVerilog RTL fix for the CVA6-vendored dependency; the CVA6 snapshot remains pre-fix
- Source repositories: [openhwgroup/cva6](https://github.com/openhwgroup/cva6) and [pulp-platform/axi_riscv_atomics](https://github.com/pulp-platform/axi_riscv_atomics)
- CVA6 vendoring commit: [59f73d27](https://github.com/openhwgroup/cva6/commit/59f73d27e5840fa5f00d416708e22cee1188da34)
- CVA6 vendor lock: `vendor/pulp-platform_axi_riscv_atomics.lock.hjson` pins `550881f12e22dfae405612fc1df6368f4c003e68`
- Affected upstream source: [550881f1](https://github.com/pulp-platform/axi_riscv_atomics/commit/550881f12e22dfae405612fc1df6368f4c003e68)
- Original fix PR: [#26](https://github.com/pulp-platform/axi_riscv_atomics/pull/26), merged as [2ad7a9fd](https://github.com/pulp-platform/axi_riscv_atomics/commit/2ad7a9fd7794788ff85bb76ba9ab4b73a1caf980)
- Original reservation fix: [05700f6c](https://github.com/pulp-platform/axi_riscv_atomics/commit/05700f6cef0d52ae9a908e45c2fb407b1693e1fb)
- Follow-up length correction: [427f84de](https://github.com/pulp-platform/axi_riscv_atomics/commit/427f84ded79c10ae4a4c1496311554e0fb4eae5f), merged as [424697e9](https://github.com/pulp-platform/axi_riscv_atomics/commit/424697e916867f87cdeeef429729760adc50e197)
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the vendored lock revision, exact pre-fix RTL, the merged burst fix, and its merged invalidation-length correction
- Retrieved: 2026-09-10

## Failure mechanism

The CVA6 vendor lock file
`vendor/pulp-platform_axi_riscv_atomics.lock.hjson` selected the PULP
`axi_riscv_atomics` source at
`550881f12e22dfae405612fc1df6368f4c003e68`. In that revision,
`axi_riscv_lrsc.sv` saved only the AXI write address:

```systemverilog
if (slv_aw_valid_i && slv_aw_ready_o) begin
    w_addr_d = slv_aw_addr_i;
    w_id_d   = slv_aw_id_i;
end
```

At the final write-data beat it requested one reservation-table clear at
that saved base address:

```systemverilog
if (slv_w_valid_i && slv_w_ready_o && slv_w_last_i) begin
    wr_clr_addr = w_addr_q;
    wr_clr_req  = 1'b1;
end
```

The old `axi_res_tbl` compared each stored reservation against that single
`clr_addr_i`; it did not iterate over the addresses covered by an AXI burst
or account for a write wider than the reservation granularity. Consequently,
a write burst that touched several reservation granules invalidated only its
base address.

PR #26 adds an `AW_BURST` state, computes the number of granules affected by
`AWSIZE` and `AWLEN`, and walks the reservation-table clear address across
the transaction. PR #31 then fixes the `clr_len_q` off-by-one: the walker
terminates after clearing the last intended covered granule and prevents one
extra clear beyond the burst. The latter is included here as part of the
complete closure of the same reservation-invalidation defect.

## Two-client trigger

Use two independent AXI clients/harts behind the shared atomic adapter, with
a 64-bit AXI data bus and 8-byte-aligned incrementing beats. In this example
`AWSIZE = 3`; `AXI_ADDR_LSB = 3` is only the later fix's internal granularity
representation and is not a parameter of the pre-fix `550881f` HDL. Let `X`
be an 8-byte-aligned address in the exclusively accessible range.

1. Client B issues an exclusive LR at `X`; the reservation table stores `X`
   for B's AXI ID.
2. Client A issues a normal incrementing write burst with
   `AWADDR = X - 8`, `AWLEN = 1`, and `AWSIZE = 3`. Its two data beats cover
   `X - 8` and `X`.
3. The old adapter accepts both W beats but, on `WLAST`, asks the reservation
   table to clear only `X - 8`, the saved AW base address. B's reservation at
   `X` remains present.
4. Client B issues its SC at `X`. The old exclusive monitor can report a
   successful reservation check and allow the SC, although client A's burst
   has written the same reservation granule.

This requires two independent clients: one creates the reservation and the
other performs the invalidating burst. A single client can issue the burst,
but cannot produce the cross-client LR/SC invalidation race represented by
this record.

## Source and deduplication evidence

The CVA6 vendorized RTL is [`vendor/pulp-platform/axi_riscv_atomics/src/axi_riscv_lrsc.sv`](https://github.com/openhwgroup/cva6/blob/59f73d27e5840fa5f00d416708e22cee1188da34/vendor/pulp-platform/axi_riscv_atomics/src/axi_riscv_lrsc.sv), selected by `vendor/pulp-platform_axi_riscv_atomics.lock.hjson` at the pre-fix `550881f` revision; CVA6 does not claim to have imported the later PULP fix in that snapshot.
The upstream historical source and fixes are linked above. The final merged
PR #31 is important because its `clr_len_q` correction completes the
multi-beat coverage promised by PR #26.

This record is distinct from existing CVA6 records:

- `CVA6-AXI-RISCV-ATOMIC-INFLIGHT-LR-SC-ORDERING` concerns ordering an LR
  against an independent write that remains in flight;
- this record concerns reservation-table invalidation for a normal
  multi-beat write and uses the PULP atomic adapter history.

No new simulation is claimed; the exact upstream RTL fixes and merged PRs
are the confirmation evidence.
