# std-cache AXI source FIFO could retain a completed AW

- Record ID: `CVA6-STD-CACHE-AXI-W-FIFO-AW-ORDER`
- Core: CVA6
- Source repository: [openhwgroup/cva6](https://github.com/openhwgroup/cva6)
- Scope: shared standard-cache AXI write-source tracking
- Record kind: canonical upstream CVA6 SystemVerilog RTL fix
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact post-#1360 base, the independent AW/W channel state machine, the multi-producer trigger, and merged upstream PR #2461
- Affected parent: [bc7eeb7b](https://github.com/openhwgroup/cva6/commit/bc7eeb7b013056a86ccaa7a376490e9fb2da97c9)
- Fixed revision: [164d7c7f](https://github.com/openhwgroup/cva6/commit/164d7c7fc97529c2c357bf066ec5b099664cfd16)
- Canonical fix: [CVA6 PR #2461](https://github.com/openhwgroup/cva6/pull/2461), merged in upstream `master`
- Retrieved: 2026-09-10

## Failure mechanism

The affected base already includes the fall-through W FIFO and empty-FIFO
source selection from PR #1360. It still pushed the selected W source only
when AW handshook:

```systemverilog
.push_i (axi_req_o.aw_valid & axi_resp_i.aw_ready)
```

and popped it when the W beat completed:

```systemverilog
.pop_i (axi_req_o.w_valid & axi_resp_i.w_ready & axi_req_o.w.last)
```

AW and W are independent AXI channels. If a source A held AW valid while
`aw_ready=0`, but its W beat was accepted with `w_ready=1`, the fall-through
path could complete the W transfer without recording A. When AW later became
ready, the old push then inserted A into the FIFO even though A's W beat had
already completed. A later source B could be routed using this stale FIFO
head, or could be held indefinitely behind it.

## Necessary shared-producer trigger

The failure needs the shared `std_cache_subsystem` source-selection fabric
and distinct AXI producers so that a stale source A can affect a subsequent
source B. The subsystem exposes I$, D$ data/refill, and D$ bypass producers
to the same AXI mux. A single isolated transaction cannot turn the stale
selection into a wrong-source routing or subsequent-transaction liveness
failure.

## Canonical fix and closure

Fix [164d7c7f](https://github.com/openhwgroup/cva6/commit/164d7c7fc97529c2c357bf066ec5b099664cfd16)
introduces explicit `w_fifo_push`, `w_fifo_pop`, and `aw_lock_q` state. The
push occurs when a new AW becomes valid rather than only after AW ready, and
the lock holds its source while AW is stalled:

```systemverilog
assign w_fifo_push = ~aw_lock_q & axi_req_o.aw_valid;
assign w_fifo_pop =
    axi_req_o.w_valid & axi_resp_i.w_ready & axi_req_o.w.last;
assign aw_lock_d =
    ~axi_resp_i.aw_ready & (axi_req_o.aw_valid | aw_lock_q);
```

The same-cycle push/pop behavior cannot leave a completed source as a stale
FIFO entry. PR #2461 is closed and merged in canonical upstream; the fixed
revision is the upstream squash commit whose direct parent is the exact
affected base `bc7eeb7b013056a86ccaa7a376490e9fb2da97c9`.

Source evidence:

- [affected `std_cache_subsystem.sv`](https://github.com/openhwgroup/cva6/blob/bc7eeb7b013056a86ccaa7a376490e9fb2da97c9/core/cache_subsystem/std_cache_subsystem.sv)
- [fixed `std_cache_subsystem.sv`](https://github.com/openhwgroup/cva6/blob/164d7c7fc97529c2c357bf066ec5b099664cfd16/core/cache_subsystem/std_cache_subsystem.sv)
- [PR #2461](https://github.com/openhwgroup/cva6/pull/2461)

## Duplicate boundary

PR #1360 is not a duplicate: its affected base predates the fall-through
change and its failure is the empty-FIFO AW/W deadlock. This record starts
from the later base containing that fix and covers the stale source left by
AW/W completing in the opposite order.
