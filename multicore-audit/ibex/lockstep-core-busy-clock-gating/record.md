# SecureIbex core-busy clock gating could suppress the delayed comparison

- Record ID: `IBEX-LOCKSTEP_CORE_BUSY_CLOCK_GATING`
- Core: Ibex
- Source repository: [lowRISC/ibex](https://github.com/lowRISC/ibex)
- Scope: SecureIbex primary/shadow lockstep shared clock control
- Record kind: canonical upstream lockstep RTL security fix
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact affected parent, the closed issue and merged PR, the shared gated-clock path, and the upstream fixed RTL
- Affected parent: [f385d4d6](https://github.com/lowRISC/ibex/commit/f385d4d6b1d1a2455baf0bec7cc77d3073c37cff)
- Fixed revision: [28935490](https://github.com/lowRISC/ibex/commit/28935490c28923f486314e61696820bf45e23aae), `Protect core_busy_o with a multi-bit encoding`
- Canonical fix: [Ibex PR #1865](https://github.com/lowRISC/ibex/pull/1865), merged in upstream `master`
- Related issue: [Ibex issue #1827](https://github.com/lowRISC/ibex/issues/1827), `core_busy_o not protected by lockstep`
- Retrieved: 2026-09-10

## Failure mechanism

At the exact affected parent, `rtl/ibex_core.sv` exported a scalar busy
signal formed from the primary core's internal activity:

```systemverilog
assign core_busy_o = ctrl_busy | if_busy | lsu_busy;
```

`rtl/ibex_top.sv` registered that scalar signal and used it in the clock
enable for the common core clock:

```systemverilog
logic core_busy_d, core_busy_q;

assign clock_en = core_busy_q | debug_req_i | irq_pending | irq_nm_i;

prim_clock_gating core_clock_gate_i (
  .clk_i    (clk_i),
  .en_i     (clock_en),
  .test_en_i(test_en_i),
  .clk_o    (clk)
);
```

The gated `clk` drives both the primary `u_ibex_core` and the
`u_ibex_lockstep` wrapper. The delayed `u_shadow_core` inside that wrapper
also receives the same gated clock. A low glitch that reaches the ungated
`clk_i` sampling edge, or a persistent stuck-at-0 fault, on the primary
`core_busy_o` could therefore make `core_busy_q` and `clock_en` go low while
the shadow was still delayed. If the other clock-enable terms are inactive,
the shared gate then stopped the clock before the delayed lockstep state
reached the comparison point, so the expected output mismatch and major alert
could be delayed or missed.

The canonical issue documents this exact runtime behavior: the primary
`core_busy_o` controls the shared clock, the lockstep instance is delayed by
several cycles, and a low glitch can put the core to sleep instead of letting
the lockstep comparison handle the fault. It also gives a concrete
reproduction through the OpenTitan `chip_sw_ibex_lockstep_glitch` test, with
`core_busy_o` selected as the fault-injected output. The referenced OpenTitan
PR [#15221](https://github.com/lowRISC/opentitan/pull/15221) is merged and
contains that test.

## Necessary two-instance trigger

1. Instantiate SecureIbex's primary core and delayed shadow execution
   instance.
2. Run a sequence in which the shadow is behind the primary and the shared
   core clock is controlled by `core_busy_o`.
3. Inject a low glitch that is sampled by the ungated `clk_i`, or a persistent
   stuck-at-0 fault, into the pre-fix primary busy output while the delayed
   comparison is pending. Keep `debug_req_i`, `irq_pending`, `irq_nm_i`, and
   the test-clock override inactive so they do not force the clock on.
4. Observe that the common clock gate disables both execution instances
   before the comparison can produce its mismatch/alert response.

Both primary and shadow instances are necessary to define the missed-alert
condition: the fault exploits the shared clock that must advance the delayed
shadow and its comparison registers. This is a SecureIbex lockstep finding,
not a claim about two independently addressable SMP harts.

## Canonical fix

Merged commit [28935490c](https://github.com/lowRISC/ibex/commit/28935490c28923f486314e61696820bf45e23aae)
changes the busy path to a hardened multi-bit encoding. In the core it
derives independently buffered encoded busy values from `ctrl_busy`,
`if_busy`, and `lsu_busy`, and exports an `ibex_mubi_t` rather than a scalar
signal. At the top level the busy state is stored through the protected
multi-bit flop and clock enable is asserted for every value other than the
valid encoded off value:

```systemverilog
assign clock_en =
    (core_busy_q != IbexMuBiOff) |
    debug_req_i | irq_pending | irq_nm_i;
```

Consequently, a single-bit fault on the encoded `core_busy_o`/`core_busy_q`
path cannot turn a valid busy encoding into the valid off encoding. A non-Off
invalid value also leaves the shared clock enabled because it satisfies
`core_busy_q != IbexMuBiOff`, preserving the clock edges needed by the delayed
shadow and its comparison. The fix does not add a dedicated invalid-encoding
alert; once clocked progress resumes, the existing delayed whole-output
comparison can report a mismatch when the affected signal reaches the
lockstep comparison path.

The affected and fixed RTL paths are visible in:

- [affected `rtl/ibex_core.sv`](https://github.com/lowRISC/ibex/blob/f385d4d6b1d1a2455baf0bec7cc77d3073c37cff/rtl/ibex_core.sv)
- [affected `rtl/ibex_top.sv`](https://github.com/lowRISC/ibex/blob/f385d4d6b1d1a2455baf0bec7cc77d3073c37cff/rtl/ibex_top.sv)
- [affected `rtl/ibex_lockstep.sv`](https://github.com/lowRISC/ibex/blob/f385d4d6b1d1a2455baf0bec7cc77d3073c37cff/rtl/ibex_lockstep.sv)
- [fixed `rtl/ibex_core.sv`](https://github.com/lowRISC/ibex/blob/28935490c28923f486314e61696820bf45e23aae/rtl/ibex_core.sv)
- [fixed `rtl/ibex_top.sv`](https://github.com/lowRISC/ibex/blob/28935490c28923f486314e61696820bf45e23aae/rtl/ibex_top.sv)
- [fixed `rtl/ibex_lockstep.sv`](https://github.com/lowRISC/ibex/blob/28935490c28923f486314e61696820bf45e23aae/rtl/ibex_lockstep.sv)

## Upstream closure and duplicate boundary

PR #1865 is merged. Its merge commit is
`28935490c28923f486314e61696820bf45e23aae`, whose direct parent is the exact
affected revision `f385d4d6b1d1a2455baf0bec7cc77d3073c37cff`. The current
upstream `master` retains the multi-bit busy and protected clock-enable logic.
Issue #1827 is closed as completed and links the fix PR.

No retained Ibex record covers the
`core_busy_o -> core_busy_q -> clock_en -> common gated clock` path. The
closest record, `IBEX-LOCKSTEP_ENABLE_FI_HARDENING`, protects the separate
comparison-enable state; it does not cover clock stopping before the delayed
shadow comparison. The remaining retained records cover CSR propagation,
reset convergence, memory-integrity replication, response-valid handling,
FPGA counter reset, or register-file paths. They do not cover this busy/clock
control defect.
