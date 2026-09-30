# CVA6 AXI LR/SC adapter allowed an LR to pass an in-flight overlapping write

- Record ID: `CVA6-AXI-RISCV-ATOMIC-INFLIGHT-LR-SC-ORDERING`
- Core: CVA6 / vendored PULP AXI atomics
- Scope: shared AXI exclusive monitor ordering between independent clients
- Record kind: canonical upstream AXI SystemVerilog RTL rewrite
- Source repositories: [openhwgroup/cva6](https://github.com/openhwgroup/cva6) and [pulp-platform/axi_riscv_atomics](https://github.com/pulp-platform/axi_riscv_atomics)
- CVA6 vendoring commit: [59f73d27](https://github.com/openhwgroup/cva6/commit/59f73d27e5840fa5f00d416708e22cee1188da34)
- CVA6 vendor lock: `vendor/pulp-platform_axi_riscv_atomics.lock.hjson` pins `550881f12e22dfae405612fc1df6368f4c003e68`
- Affected pre-fix source: [602ede33](https://github.com/pulp-platform/axi_riscv_atomics/commit/602ede338e084558d5da31d7dd63ef76a9c88df6) (the vendored `550881f1` LRSC source is text-equivalent for this path)
- Fix commit: [6e952aa7](https://github.com/pulp-platform/axi_riscv_atomics/commit/6e952aa79ee43c791e0e2c48e12c39b0ff296afc), `axi_riscv_lrsc: Rewrite to fix various problems`
- Authoritative issue: [#4](https://github.com/pulp-platform/axi_riscv_atomics/issues/4), closed as `COMPLETED` by upstream PR [#15](https://github.com/pulp-platform/axi_riscv_atomics/pull/15); closing implementation is `6e952aa7`
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the pre-fix independent channel state machines, the closed upstream issue, and the merged RTL rewrite that adds in-flight transaction tracking
- Retrieved: 2026-09-10

## Failure mechanism

The locked CVA6 dependency revision
`vendor/pulp-platform_axi_riscv_atomics.lock.hjson` used independent read and
write channel state machines. The read path in `R_IDLE` could accept an exclusive AR and
set a reservation without checking whether an overlapping write had already
been accepted on the write path. The write path, meanwhile, cleared the
reservation table when its W data completed, even though the downstream AXI
write could remain in flight until its B response.

The relevant pre-fix structure is:

```systemverilog
// Read channel: no write-in-flight query before an exclusive LR
if (slv_ar_addr_i >= ADDR_BEGIN && slv_ar_addr_i <= ADDR_END &&
        slv_ar_lock_i && slv_ar_len_i == 8'h00) begin
    art_set_addr = slv_ar_addr_i;
    art_set_req  = 1'b1;
    ...
end

// Write channel: clear at WLAST, before the downstream B response
if (slv_w_valid_i && slv_w_ready_o && slv_w_last_i) begin
    wr_clr_addr = w_addr_q;
    wr_clr_req  = 1'b1;
end
```

Because AR and AW/W were allowed to progress independently, the adapter did
not enforce the required ordering between a store and a later LR to an
overlapping address. An accepted write could have its reservation clear
performed before its downstream side effect was complete; a later LR could
then create a new reservation while that write was still in flight.

The upstream rewrite adds queues for in-flight reads and writes. Its read
control path queries the write-in-flight queue before admitting an exclusive
AR, and the write path tracks accepted AW transactions until their matching
B response. The commit message explicitly states that the rewrite orders
stores and store-conditionals according to RVWMO and fixes issue #4.

The CVA6 vendor lock remains at the pre-fix `550881f` snapshot described
above; `6e952aa7` is the merged upstream PULP fix, not a fix already present
in that CVA6 vendor snapshot.

## Two-client trigger

Use two independent AXI clients/harts sharing the adapter and an AXI slave.
Choose an address `X` in the exclusive range.

1. Client A sends a normal write to `X`; the adapter accepts AW and W and
   forwards them, but the downstream write response/commit is deliberately
   delayed.
2. In the old design, the W handshake can already have caused the
   reservation-table clear while the write remains outstanding on the
   downstream AXI interface.
3. Before the delayed write commits, client B sends an exclusive LR at `X`.
   The independent read FSM accepts it because there is no write-in-flight
   overlap check, reads the old value if the slave has not committed A's
   write, and establishes B's reservation.
4. Client A's write then commits. Its clear happened before B's LR, so the
   old adapter does not clear B's newly established reservation. Client B's
   subsequent SC at `X` can therefore pass despite the intervening write.

The corrected design blocks the LR while the overlapping write is tracked.
The trigger needs the two client transactions and their shared ordering
relationship; it is not a standalone single-client LR or write failure.

## Source and deduplication evidence

The affected CVA6 vendor source is [`vendor/pulp-platform/axi_riscv_atomics/src/axi_riscv_lrsc.sv`](https://github.com/openhwgroup/cva6/blob/59f73d27e5840fa5f00d416708e22cee1188da34/vendor/pulp-platform/axi_riscv_atomics/src/axi_riscv_lrsc.sv).
The canonical fix is [6e952aa7](https://github.com/pulp-platform/axi_riscv_atomics/commit/6e952aa79ee43c791e0e2c48e12c39b0ff296afc), and its commit body cites the
closed [issue #4](https://github.com/pulp-platform/axi_riscv_atomics/issues/4).

This record is distinct from
`CVA6-AXI-RISCV-ATOMIC-BURST-RESERVATION-INVALIDATION`, which clears only a
burst base address and misses later beats. That record concerns reservation
coverage across a burst; this one concerns ordering an LR against an
independent write that remains in flight.

No new simulation is claimed; the closed upstream issue and exact rewrite
are the confirmation evidence.
