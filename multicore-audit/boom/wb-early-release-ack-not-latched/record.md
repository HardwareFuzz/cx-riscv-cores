# BOOM early ReleaseAck was not latched across a multi-beat Release

- Record ID: `BOOM-WB_EARLY_RELEASE_ACK_NOT_LATCHED`
- Core: BOOM
- Source repository: [riscv-boom/riscv-boom](https://github.com/riscv-boom/riscv-boom)
- Scope: shared L1 TileLink Release and ReleaseAck ordering
- Record kind: canonical upstream Chisel/RTL coherence/liveness fix
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact affected parent, the one-cycle `mem_grant` path, the multi-beat Release state machine, the direct acknowledgement-latching fix, and the merged PR closure
- Affected parent: [7637d647fb937a810ddea1e78cf37569cbbe3267](https://github.com/riscv-boom/riscv-boom/commit/7637d647fb937a810ddea1e78cf37569cbbe3267)
- Direct fix: [01eed18de7543d973f7d2b45a589caf786f02848](https://github.com/riscv-boom/riscv-boom/commit/01eed18de7543d973f7d2b45a589caf786f02848)
- Canonical closure: [BOOM PR #275](https://github.com/riscv-boom/riscv-boom/pull/275), merged as [ac28f02dafc5cfa284bb83e1c0c7d2b99c20a92a](https://github.com/riscv-boom/riscv-boom/commit/ac28f02dafc5cfa284bb83e1c0c7d2b99c20a92a)
- Retrieved: 2026-09-10

## Failure mechanism

At the affected parent, `BoomWritebackUnit` in
 [`src/main/scala/lsu/dcache.scala`](https://github.com/riscv-boom/riscv-boom/blob/7637d647fb937a810ddea1e78cf37569cbbe3267/src/main/scala/lsu/dcache.scala)
receives `io.mem_grant` as a one-cycle indication of the downstream
TileLink D-channel handshake (`tl_out.d.fire()`). For a voluntary writeback,
the unit remains in `s_active` while it sends the cache-line Release over the
C channel, one beat per successful `io.release.fire()`.

The parent does not retain an acknowledgement that arrives while the Release
is still being transmitted. The state transition after the final Release beat
enters `s_grant` for a voluntary request, and `s_grant` waits for
`io.mem_grant` as a new pulse. A D-channel `ReleaseAck` already accepted in
`s_active` has no second handshake associated with it. The writeback unit
therefore remains in `s_grant` after all C beats have completed, with no
acknowledgement left to release it to `s_invalid`.

The defect is a transaction-lifetime error across independent TileLink
channels: the C-channel Release completion and the D-channel ReleaseAck are
not required to be observed by this state machine in the same cycle or in the
same order as the final C beat. Treating `io.mem_grant` as a transient pulse
loses a valid early response and strands the writeback unit.

## Necessary multi-client trigger

Use two coherent BOOM clients/harts sharing the canonical L1 TileLink
interconnect. The triggering transaction is a voluntary dirty-line writeback
from Hart A:

1. Hart A allocates `BoomWritebackUnit` for a dirty cache line and issues a
   multi-beat TileLink C-channel `Release` for the line.
2. The shared coherent manager/interconnect accepts the Release beats and
   returns the corresponding D-channel `ReleaseAck` before Hart A's final C
   beat is accepted. This is a legal response ordering at the independent
   C-channel Release / D-channel ReleaseAck boundary.
3. `tl_out.d.fire()` asserts `io.mem_grant` for one cycle while the unit is
   still in `s_active`; subsequent C beats continue to handshake through
   `io.release`.
4. Hart A's final Release beat then fires. The affected state machine enters
   `s_grant`, but the earlier D-channel pulse has already disappeared.
5. No second `ReleaseAck` is generated for the completed Release. The unit
   waits forever for another `io.mem_grant`, remains unavailable for a new
   writeback, and is stranded in the shared L1 coherence path.

The second coherent client establishes the shared multi-hart TileLink
boundary on which the Release and ReleaseAck are independently scheduled;
the failure is in the BOOM L1 writeback state machine at that boundary, not
in a private local data path. The essential protocol conditions are the
multi-beat Release and the early D-channel acknowledgement ordering.

## Canonical fix and closure

The direct fix at
[`01eed18de7543d973f7d2b45a589caf786f02848`](https://github.com/riscv-boom/riscv-boom/commit/01eed18de7543d973f7d2b45a589caf786f02848)
adds an `acked` register to `BoomWritebackUnit`. A new writeback request
clears the register; an observed `io.mem_grant` sets it even while the unit is
still sending C-channel Release beats. After the final Release beat, the
`s_grant` state consumes the latched acknowledgement and returns the unit to
`s_invalid`. The early D-channel handshake is therefore preserved across the
remaining C-channel beats and the writeback unit is not stranded.

The direct fix is the exact historical child of affected parent
`7637d647fb937a810ddea1e78cf37569cbbe3267`. It was carried by
[BOOM PR #275](https://github.com/riscv-boom/riscv-boom/pull/275), whose
canonical merge is
[ac28f02dafc5cfa284bb83e1c0c7d2b99c20a92a](https://github.com/riscv-boom/riscv-boom/commit/ac28f02dafc5cfa284bb83e1c0c7d2b99c20a92a).
The merged closure retains the acknowledgement-latching behavior in the
canonical BOOM history.

This is distinct from `BOOM-WB_LAST_C_BEAT_LOST`: that record is triggered
when the final C beat is not accepted but the writeback unit advances anyway,
so the final `ReleaseData` or `ProbeAckData` beat is withdrawn. This record
requires every C beat, including the final beat, to fire; its independent
failure is an earlier D-channel `ReleaseAck` pulse that is not retained while
the multi-beat Release completes.

It is also distinct from the existing BOOM records: it does not concern
`BOOM-LDLD_SNOOP_PNR_BLOCK` load-ordering state,
`BOOM-MSHR_PROBER_META_READ_CONFLICT` metadata-read arbitration,
`BOOM-LR_RESERVATION_PROBE_ADMISSION` LR/SC Probe admission,
`BOOM-PREFETCH_MSHR_PROBE_CLEAR` prefetch-MSHR clearing,
`BOOM-PROBE_NACK_LRSC_RESERVATION` Probe-induced LR/SC reservation
bookkeeping, or `BOOM-PROBER_INVALID_MSHR_READY` stale metadata in an invalid
MSHR. The affected logic here is solely the writeback unit's Release/D-channel
acknowledgement lifetime.
