# CVA6 CLINT compared the packed multi-core mtimecmp array as one value

- Record ID: `CVA6-MULTICORE_CLINT_TIMER_IRQ`
- Core: CVA6
- Scope: multi-core CLINT timer compare and per-hart interrupt routing
- Record kind: canonical upstream SystemVerilog RTL fix
- Source repository: [openhwgroup/cva6](https://github.com/openhwgroup/cva6)
- Affected parent: [8e23bb89](https://github.com/openhwgroup/cva6/commit/8e23bb89b20392db7941e3898645273926728c8a)
- Fix commit: [5ac28386](https://github.com/openhwgroup/cva6/commit/5ac2838606edd911ff030e75d216c74246ff95bd), `Make timer handle multiple cores`
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the canonical parent/fix diff and the current per-core CLINT integration
- Affected revisions: `ariane_timer.sv` revisions before `5ac28386`
- Retrieved: 2026-09-10

## Failure mechanism

The parent `ariane_timer.sv` already allocated one 64-bit compare register
per core:

```systemverilog
parameter int unsigned NR_CORES = 1;
logic [NR_CORES-1:0][63:0] mtimecmp_n, mtimecmp_q;
output logic irq_o;
```

Register reads and writes selected an individual `mtimecmp_q` entry using
the core encoded in the address. The interrupt generator, however, treated
the complete packed array as one scalar compare:

```systemverilog
if (mtimecmp_q != 0 && mtime_q >= mtimecmp_q)
    irq_o = 1'b1;
else
    irq_o = 1'b0;
```

With `NR_CORES = 2`, `mtimecmp_q` is a packed 128-bit value containing two
independent deadlines, while `mtime_q` is 64 bits and `irq_o` is one bit.
The relational operation therefore compares a zero-extended global time
against the entire packed array, not against either core's 64-bit entry. A
nonzero high entry can make the packed comparison false even when the low
entry's deadline has expired. Even when the condition is true, one scalar
interrupt cannot identify which of the two cores should receive it.

The fix changes the output to `[NR_CORES-1:0]` and performs the comparison
inside a loop for every `mtimecmp_q[i]`:

```systemverilog
for (int unsigned i = 0; i < NR_CORES; i++) begin
    if (mtimecmp_q[i] != 0 && mtime_q >= mtimecmp_q[i])
        irq_o[i] = 1'b1;
    else
        irq_o[i] = 1'b0;
end
```

## Two-hart trigger

Configure `NR_CORES = 2` and give the two hart timer clients different
deadlines. For example, at global `mtime = T`, write
`mtimecmp_q[0] = T + 1` and `mtimecmp_q[1] = T + 100`. At `mtime = T + 1`
the required result is `irq_o[0] = 1` and `irq_o[1] = 0`.

In the parent implementation, the nonzero high `mtimecmp_q[1]` participates
in the single 128-bit comparison, so the expired low deadline can be hidden
by the packed value; regardless of the comparison result, the scalar output
cannot independently notify hart 0 and hart 1. Reversing the two deadlines
shows the same inability to deliver independent timer events.

The issue is absent for `NR_CORES = 1`, where the packed array contains only
one 64-bit entry and the old output has one bit. It is consequently a
multi-core timer cardinality and routing defect, not a generic single-core
timer event.

## Source and deduplication evidence

The historical pre-fix source is [`ariane_timer.sv`](https://github.com/openhwgroup/cva6/blob/8e23bb89b20392db7941e3898645273926728c8a/ariane_timer.sv).
The complete correction is in [5ac28386](https://github.com/openhwgroup/cva6/commit/5ac2838606edd911ff030e75d216c74246ff95bd).
The current canonical OpenPiton peripheral integration passes `NumHarts` to
the CLINT and exposes a timer interrupt vector, confirming the intended
per-hart interface.

This record is distinct from:

- `CVA6-MULTIHART_DEBUG_REQ_WIDTH`, which fixes Debug Module request/status
  widths rather than CLINT timer state.

No new simulation is claimed; the canonical parent/fix diff and the retained
per-core integration establish the historical defect and its closure.
