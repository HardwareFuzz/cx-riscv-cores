# SecureIbex could not elaborate with a one-cycle lockstep offset

- Record ID: `IBEX-LOCKSTEP-OFFSET-ONE-ELABORATION`
- Core: Ibex
- Source repository: [lowRISC/ibex](https://github.com/lowRISC/ibex)
- Scope: SecureIbex primary/shadow lockstep parameterization and cache-response delay
- Record kind: canonical upstream lockstep RTL elaboration fix
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact parent/fix chain, the zero-width and port-shape failure, and merged upstream PR #2363
- Affected parent: [fc9ffad5](https://github.com/lowRISC/ibex/commit/fc9ffad59ad077f18160af9b74413903ac77ea41)
- Fixed revision: [871d644e](https://github.com/lowRISC/ibex/commit/871d644e032d9a05e4dbc1cce2cfb4ff264822e9)
- Canonical fix: [Ibex PR #2363](https://github.com/lowRISC/ibex/pull/2363), merged in upstream `master`
- Merge commit: [19592a1f](https://github.com/lowRISC/ibex/commit/19592a1fc7ba7e85427906cd4d86b8356b91a45d)
- Retrieved: 2026-09-10

## Failure mechanism

The affected parent exposed the `LockstepOffset` parameter through
`ibex_top` into the SecureIbex lockstep wrapper, but the wrapper's RTL still
assumed an offset greater than one. In [`rtl/ibex_lockstep.sv`](https://github.com/lowRISC/ibex/blob/fc9ffad59ad077f18160af9b74413903ac77ea41/rtl/ibex_lockstep.sv), it computed the width of the shadow reset counter as:

```systemverilog
localparam int unsigned LockstepOffsetW = $clog2(LockstepOffset);

logic [LockstepOffsetW-1:0] rst_shadow_cnt;

prim_count #(
  .Width(LockstepOffsetW)
) u_rst_shadow_cnt (
  ...
);
```

The same parent declared the cache-response delay arrays with an additional
offset dimension:

```systemverilog
logic [TagSizeECC-1:0]  shadow_tag_rdata_q  [IC_NUM_WAYS][LockstepOffset];
logic [LineSizeECC-1:0] shadow_data_rdata_q [IC_NUM_WAYS][LockstepOffset];
```

and connected only one dimension at the shadow-core port:

```systemverilog
.ic_tag_rdata_i(shadow_tag_rdata_q[0])
```

## Multi-instance trigger and consequence

The trigger is a valid SecureIbex configuration with:

```text
SecureIbex = 1
LockstepOffset = 1
```

`SecureIbex=1` instantiates the primary core and the delayed shadow core.
With `LockstepOffset=1`, `$clog2(1)` is zero. The parent consequently
instantiates `prim_count` with `Width=0` and creates zero-width counter state,
while the cache-response arrays and their shadow-core port connection retain
incompatible shapes for the one-cycle case. The upstream PR records the
resulting `port or terminal connection type check failed on instance`
compilation/elaboration failure.

The configuration therefore cannot complete RTL elaboration, simulation
compilation, or synthesis into a usable one-cycle SecureIbex design. This is
a construction-time failure of the primary/shadow multi-execution wrapper;
it is not a single-core runtime behavior or an SMP hart claim.

## Canonical fix and closure

The direct fix [`871d644e`](https://github.com/lowRISC/ibex/commit/871d644e032d9a05e4dbc1cce2cfb4ff264822e9) has immediate parent
`fc9ffad59ad077f18160af9b74413903ac77ea41` and handles the one-cycle case
explicitly. It uses a non-zero-width utility for the offset width, generates
the reset counter only when the offset is greater than one, and introduces
the correct single-cycle cache-response delay connections. The fix also adds
the required primitive utility dependency to the core description.

The complete upstream closure is [Ibex PR #2363](https://github.com/lowRISC/ibex/pull/2363), titled `Reduce the lockstep delay to 1 cycle`. The PR documents that the old RTL did not support `LockstepOffset=1`, includes the direct RTL repair, and was merged into upstream `master` on 2026-02-07 as
[`19592a1f`](https://github.com/lowRISC/ibex/commit/19592a1fc7ba7e85427906cd4d86b8356b91a45d).

Source evidence:

- [affected `rtl/ibex_top.sv`](https://github.com/lowRISC/ibex/blob/fc9ffad59ad077f18160af9b74413903ac77ea41/rtl/ibex_top.sv)
- [affected `rtl/ibex_lockstep.sv`](https://github.com/lowRISC/ibex/blob/fc9ffad59ad077f18160af9b74413903ac77ea41/rtl/ibex_lockstep.sv)
- [direct fixed `rtl/ibex_lockstep.sv`](https://github.com/lowRISC/ibex/blob/871d644e032d9a05e4dbc1cce2cfb4ff264822e9/rtl/ibex_lockstep.sv)
- [direct fixed `rtl/ibex_top.core`](https://github.com/lowRISC/ibex/blob/871d644e032d9a05e4dbc1cce2cfb4ff264822e9/rtl/ibex_top.core)
- [PR #2363](https://github.com/lowRISC/ibex/pull/2363)
- [merge commit `19592a1f`](https://github.com/lowRISC/ibex/commit/19592a1fc7ba7e85427906cd4d86b8356b91a45d)

## Duplicate boundary

The existing Ibex records cover other SecureIbex primary/shadow mechanisms:
reset convergence, fault-injection hardening, ECC and memory-response
replication, register-file paths, CSR propagation, and shared clock control.
None covers the `LockstepOffset=1` zero-width/port-shape elaboration failure.
This record remains within the multi-instance lockstep scope and does not
claim independently addressable SMP harts.
