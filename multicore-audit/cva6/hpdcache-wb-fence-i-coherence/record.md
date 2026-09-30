# HPDcache write-back could race fence.i instruction fetch

- Record ID: `CVA6-HPDCACHE-WB-FENCE-I-COHERENCE`
- Core: CVA6
- Source repository: [openhwgroup/cva6](https://github.com/openhwgroup/cva6)
- Scope: shared I$/D$ memory ordering in HPDcache write-back configuration
- Record kind: canonical upstream CVA6 SystemVerilog RTL fix
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact affected parent, the controller/frontend RTL path, the shared I$/D$ trigger and reported runtime failures, and merged upstream PR #2971
- Affected parent: [2700d144](https://github.com/openhwgroup/cva6/commit/2700d14471963909923bdcfa1b013b4d1b30e567)
- Fixed revision: [6d08ed13](https://github.com/openhwgroup/cva6/commit/6d08ed138974734cfe9d38380ded2e74c45bdd18)
- Canonical fix: [CVA6 PR #2971](https://github.com/openhwgroup/cva6/pull/2971), merged in upstream `master`
- Retrieved: 2026-09-10

## Failure mechanism

In the affected `core/controller.sv`, `fence.i` started both the I$ flush
and the D$ write-back flush when `DcacheFlushOnFence` was enabled. The old
`fence_active_q` state halted commit/core progress but did not halt the
frontend. In `core/frontend/frontend.sv`, instruction requests and NPC
advance could therefore continue after the I$ flush while the D$ flush was
still pending:

```systemverilog
assign icache_dreq_o.req = instr_queue_ready;
assign if_ready = icache_dreq_i.ready & instr_queue_ready;
```

With a dirty instruction line in the write-back D$, the I$ could refill from
backing memory before that dirty D$ line had been written back. The I$ then
installed stale instruction bytes and the hart could execute old code.

## Necessary shared-memory-client trigger

The canonical HPDcache configuration uses independent I$ miss/read and D$
read/write/write-data clients that are arbitrated onto a shared upstream
memory/AXI interface. The failure depends on the D$ write-back completion
lagging the I$ flush/refill; it is an ordering defect between these two
shared-memory clients, not an isolated frontend calculation.

PR #2971 reports the affected `riscv-tests/rv32ui/fence_i` behavior and
HPDcache write-back Linux boot failures when D$ writeback lagged behind I$
flush.

## Canonical fix and closure

Fix [6d08ed13](https://github.com/openhwgroup/cva6/commit/6d08ed138974734cfe9d38380ded2e74c45bdd18)
adds `fence_i_active_q`, keeps the frontend halted until
`flush_dcache_ack_i`, and gates both instruction requests and frontend
ready/NPC advance with `~halt_frontend_i`:

```systemverilog
assign icache_dreq_o.req =
    instr_queue_ready & ~halt_frontend_i;

assign if_ready =
    icache_dreq_i.ready & instr_queue_ready & ~halt_frontend_i;
```

The frontend therefore cannot refill or advance until the dirty D$ writeback
has completed. PR #2971 is closed and merged; the fixed revision is the
upstream squash commit whose direct parent is the exact affected base
`2700d14471963909923bdcfa1b013b4d1b30e567`.

Source evidence:

- [affected `controller.sv`](https://github.com/openhwgroup/cva6/blob/2700d14471963909923bdcfa1b013b4d1b30e567/core/controller.sv)
- [affected `frontend.sv`](https://github.com/openhwgroup/cva6/blob/2700d14471963909923bdcfa1b013b4d1b30e567/core/frontend/frontend.sv)
- [fixed `controller.sv`](https://github.com/openhwgroup/cva6/blob/6d08ed138974734cfe9d38380ded2e74c45bdd18/core/controller.sv)
- [fixed `frontend.sv`](https://github.com/openhwgroup/cva6/blob/6d08ed138974734cfe9d38380ded2e74c45bdd18/core/frontend/frontend.sv)
- [PR #2971](https://github.com/openhwgroup/cva6/pull/2971)

## Duplicate boundary

No retained CVA6 record covers the fence.i/I$/D$ write-back ordering path.
The AXI records cover standard-cache AW/W source tracking, while the
existing atomic records cover the separate LR/SC monitor implementation.
