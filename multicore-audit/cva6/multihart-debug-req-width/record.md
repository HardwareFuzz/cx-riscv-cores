# CVA6 Debug Module truncated per-hart halt requests to hart 0

- Record ID: `CVA6-MULTIHART_DEBUG_REQ_WIDTH`
- Core: CVA6
- Scope: multi-hart Debug Module request and abstract-command status routing
- Record kind: canonical upstream SystemVerilog RTL fix
- Source repository: [openhwgroup/cva6](https://github.com/openhwgroup/cva6)
- Affected parent: [76bf0940](https://github.com/openhwgroup/cva6/commit/76bf094098895b772c34411057f1e9fab2642a46)
- Fix commit: [9d1f6b1b](https://github.com/openhwgroup/cva6/commit/9d1f6b1b76050078cf55e1fc129f1e888bd77a75), `Fix multi-hart debug issues`
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the canonical parent/fix diff and its retained multi-hart upstream integration
- Affected revisions: CVA6 Debug Module revisions before `9d1f6b1b`
- Retrieved: 2026-09-10

## Failure mechanism

The parent revision already parameterized `dm_top` by `NrHarts` and exposed a
per-hart debug request vector, but its `dm_mem` child declared the output as a
scalar while the input request was a vector:

```systemverilog
module dm_mem #(
    parameter int NrHarts = -1
)(
    output logic               debug_req_o,
    input  logic [NrHarts-1:0] haltreq_i,
    ...
);

assign debug_req_o = haltreq_i;
```

For `NrHarts > 1`, the assignment context truncates `haltreq_i` to the
one-bit `debug_req_o`. The parent `dm_top` connects that scalar child output
to its `[NrHarts-1:0] debug_req_o` port, so only the low request bit can be
delivered. Hart 0 can receive `haltreq_i[0]`; a request represented only in
`haltreq_i[1]` or any higher bit is not delivered to the corresponding hart.

The same parent/fix diff closes a related cardinality error in the shared
abstract-command status path. `dm_mem` produced scalar `cmderror_valid_o`,
`cmderror_o`, and `cmdbusy_o`, while `dm_top` declared arrays and
`dm_csrs` indexed them by `selected_hart`. A selected high hart could
therefore read an array element that was never driven by the scalar child.
The fix makes those signals shared scalars throughout and removes the
incorrect per-hart indexing. This is recorded as one Debug Module width and
routing defect, not as a separate command-engine record.

The exact changes are visible in the [canonical fix
diff](https://github.com/openhwgroup/cva6/commit/9d1f6b1b76050078cf55e1fc129f1e888bd77a75):
`dm_mem.debug_req_o` becomes `[NrHarts-1:0]`, while the command status
signals become scalars consistently between `dm_mem`, `dm_top`, and
`dm_csrs`.

## Two-hart trigger

Configure `NrHarts = 2` in the canonical `dm_top` integration.

1. Configure `NrHarts = 2` and assert only hart 1's halt request,
   `haltreq_i = 2'b10`. The old scalar `dm_mem.debug_req_o` drops this
   high-hart request at the child boundary.
2. In the same two-hart configuration, select hart 1 and issue an abstract
   command. The pre-fix scalar/array status mismatch can expose the same
   cardinality error when `dm_csrs` indexes command status for the selected
   high hart.

This cannot be triggered in the same way with one hart: for `NrHarts = 1`
the request vector and scalar output have the same effective width and there
is no high-hart status index to misroute. The failure is a per-hart routing
error in a shared multi-hart debug module.

## Source and deduplication evidence

The relevant canonical files are [`src/debug/dm_mem.sv`](https://github.com/openhwgroup/cva6/blob/76bf094098895b772c34411057f1e9fab2642a46/src/debug/dm_mem.sv),
[`src/debug/dm_top.sv`](https://github.com/openhwgroup/cva6/blob/76bf094098895b772c34411057f1e9fab2642a46/src/debug/dm_top.sv), and
[`src/debug/dm_csrs.sv`](https://github.com/openhwgroup/cva6/blob/76bf094098895b772c34411057f1e9fab2642a46/src/debug/dm_csrs.sv).
The current canonical OpenPiton peripheral path still instantiates the
Debug Module with `NumHarts` and exposes a `[NumHarts-1:0]` debug request,
confirming that the fixed vector is part of the intended multi-hart design.

This record is distinct from the existing CVA6 records:

- This record concerns Debug Module signal width and selected-hart status
  routing in different source files and is closed by a different canonical
  commit.

No new simulation is claimed; the parent/fix RTL diff is the confirmation
evidence.
