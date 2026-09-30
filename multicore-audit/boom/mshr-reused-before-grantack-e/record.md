# BOOM MSHR reused before GrantAck E completion

- Record ID: `BOOM-MSHR_REUSED_BEFORE_GRANTACK_E`
- Core: BOOM
- Scope: shared L1 TileLink D/E transaction lifetime and MSHR source-ID reuse
- Record kind: canonical upstream Chisel/RTL coherence-progress fix
- Source repository: [riscv-boom/riscv-boom](https://github.com/riscv-boom/riscv-boom)
- Affected parent: [`d182b07e6db1b38d5585628f882fb04310ee8368`](https://github.com/riscv-boom/riscv-boom/commit/d182b07e6db1b38d5585628f882fb04310ee8368)
- Direct fix: [`c07279a9f3aadfa818e627171817ec02f0e72bdb`](https://github.com/riscv-boom/riscv-boom/commit/c07279a9f3aadfa818e627171817ec02f0e72bdb)
- Pull request: [#275](https://github.com/riscv-boom/riscv-boom/pull/275), merged as [`ac28f02dafc5cfa284bb83e1c0c7d2b99c20a92a`](https://github.com/riscv-boom/riscv-boom/commit/ac28f02dafc5cfa284bb83e1c0c7d2b99c20a92a)
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: exact parent/fix state-machine change and canonical upstream merge
- Affected revisions: the MSHR implementation at the affected parent and its descendants before the direct fix
- Retrieved: 2026-09-10

## Failure mechanism

In the affected BOOM L1 MSHR implementation, a completed TileLink
acquire/refill queues its required `GrantAck` in `grantackq`. The MSHR exposes
that queued E-channel completion through `io.mem_finish`, but the parent only
drives `io.mem_finish.valid` while the MSHR state is `s_invalid`. The same
`s_invalid` state asserts readiness for a new primary request.

The two conditions allow the MSHR to be reused while the earlier transaction's
E-channel obligation is still pending. A legal TileLink E-channel backpressure
event can occur after the MSHR has reached the invalid state: the shared
TileLink fabric may hold `io.mem_finish.ready` low, so the queued `GrantAck`
cannot handshake in that cycle. If a later miss is accepted at the same time
the MSHR advertises primary-request readiness, the state leaves `s_invalid`
for the new miss while `grantackq` still contains the earlier `GrantAck`.

The earlier transaction has not completed its D/E lifetime, but the MSHR's
source-ID allocation is available to the later miss. The queued `GrantAck` is
then no longer presented by the state machine that owns it, while the same
MSHR/source-ID context is reused for new traffic. This violates the TileLink
transaction lifetime at the shared D/E boundary: the old grant completion can
remain stranded and the coherent operation can lose progress, including a
permanent MSHR/interconnect stall when the required E-channel completion
cannot be retired.

The trigger is legal protocol backpressure, not an invalid manager response.
An E-channel consumer is permitted to deassert `ready`; the MSHR must retain
ownership until the `GrantAck` handshake completes.

## Necessary multi-client trigger

The failure occurs in the shared coherent L1 TileLink path used by multiple
BOOM clients or harts:

1. A BOOM L1 client issues an acquire for a line and receives the manager's
   D-channel Grant or GrantData response. The MSHR records the corresponding
   E-channel `GrantAck` in `grantackq`.
2. The MSHR reaches the parent implementation's `s_invalid` state before the
   E-channel handshake is accepted. The shared D/E fabric applies legal
   backpressure, leaving the `GrantAck` queued.
3. The same shared fabric admits a later miss. Because `s_invalid` also makes
   the MSHR ready for a primary request, the MSHR accepts that miss and its
   source-ID context is reused while the earlier E-channel obligation remains
   outstanding.
4. The old MSHR state no longer presents the queued `GrantAck` through
   `io.mem_finish`; the earlier coherent transaction cannot complete, and the
   resulting source-lifetime conflict can block coherence progress.

This is a multi-client/shared-fabric failure because the trigger is the
independent readiness and ordering of TileLink D and E channels at the common
coherence interconnect. A shared manager or another coherent client can apply
the required E-channel backpressure while traffic from the shared fabric
provides the later miss. The defect is in the canonical L1 MSHR/TileLink
transaction-lifetime logic, rather than in a local arithmetic or test-only
path.

## Source and deduplication evidence

The affected and fixed history is in the BOOM L1 MSHR implementation:

- [Affected `dcache.scala` at parent `d182b07e`](https://github.com/riscv-boom/riscv-boom/blob/d182b07e6db1b38d5585628f882fb04310ee8368/src/main/scala/lsu/dcache.scala)
- [Direct fix `dcache.scala` at `c07279a9`](https://github.com/riscv-boom/riscv-boom/blob/c07279a9f3aadfa818e627171817ec02f0e72bdb/src/main/scala/lsu/dcache.scala)
- [Merged upstream revision `ac28f02d`](https://github.com/riscv-boom/riscv-boom/commit/ac28f02dafc5cfa284bb83e1c0c7d2b99c20a92a)

This record is distinct from `BOOM-PROBER_INVALID_MSHR_READY`. That record
concerns stale index metadata retained by an already invalid MSHR, which
incorrectly deasserts `probe_rdy` and blocks B-channel Probe admission at the
ProbeUnit/MSHR rendezvous. The present record concerns a queued GrantAck that
has not completed on E, premature MSHR reuse from `s_invalid`, and the
resulting D/E transaction-lifetime and source-ID progress failure. The two
records have different affected parents, different direct fixes, different
signals, and different TileLink channels.

## Canonical fix and closure

The direct fix [`c07279a9f3aadfa818e627171817ec02f0e72bdb`](https://github.com/riscv-boom/riscv-boom/commit/c07279a9f3aadfa818e627171817ec02f0e72bdb) adds explicit
`s_mem_finish` handling to the MSHR state machine. The E-channel completion
is retained as an independent phase, and the MSHR is not returned to the
reusable invalid state until the `GrantAck` handshake has completed. This
keeps the queued E-channel response owned by the MSHR that created it and
prevents its source-ID context from being reused prematurely.

The fix is the direct child of the affected parent in the upstream BOOM
history. It was merged through [BOOM pull request #275](https://github.com/riscv-boom/riscv-boom/pull/275) as
[`ac28f02dafc5cfa284bb83e1c0c7d2b99c20a92a`](https://github.com/riscv-boom/riscv-boom/commit/ac28f02dafc5cfa284bb83e1c0c7d2b99c20a92a), establishing canonical upstream
closure for the corrected Chisel/RTL implementation.
