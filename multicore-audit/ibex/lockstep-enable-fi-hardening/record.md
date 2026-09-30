# SecureIbex lockstep comparison enable was fail-open under a stuck-at-0 fault

- Record ID: `IBEX-LOCKSTEP_ENABLE_FI_HARDENING`
- Core: Ibex
- Source repository: [lowRISC/ibex](https://github.com/lowRISC/ibex)
- Scope: SecureIbex primary/shadow lockstep comparison control
- Record kind: canonical upstream lockstep RTL security fix
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact single-bit comparator gate, the canonical FI rationale, and merged PR #2129
- Affected parent: [b6d8b9f0](https://github.com/lowRISC/ibex/commit/b6d8b9f07582cd9f77b5c1f1680ad1ab68532796)
- Fixed revision: [8ec0c6f1](https://github.com/lowRISC/ibex/commit/8ec0c6f18ec22c00de7538e7dccc648e7864aa9e), `Harden lockstep enable against FI`
- Canonical fix: [Ibex PR #2129](https://github.com/lowRISC/ibex/pull/2129), merged in upstream `master`
- Retrieved: 2026-09-10

## Failure mechanism

In the pre-fix `rtl/ibex_lockstep.sv`, the state that enabled comparison was
a normal one-bit register:

```systemverilog
logic rst_shadow_n, enable_cmp_q;
```

The reset counter logic eventually loaded that bit, and the comparison used
it directly:

```systemverilog
enable_cmp_q <= rst_shadow_set_q;

assign outputs_mismatch =
  enable_cmp_q & (shadow_outputs_q != core_outputs_q[0]);
```

A permanent stuck-at-0 fault on `enable_cmp_q` therefore disabled the
comparison permanently. After that, a second fault affecting either
execution instance could make primary and shadow outputs differ without
raising the lockstep alert. The defect is the fail-open single-bit control,
not an ordinary instruction mismatch.

## Necessary two-instance trigger

1. Instantiate SecureIbex's primary `u_ibex_core` and delayed shadow
   `u_shadow_core`; the two output streams feed the comparison in
   `ibex_lockstep`.
2. Apply a permanent stuck-at-0 fault to the pre-fix `enable_cmp_q`.
3. Cause a second fault in one execution instance so
   `shadow_outputs_q != core_outputs_q[0]`.
4. The old gate forces `outputs_mismatch` to zero and hides the primary/
   shadow divergence.

Both execution instances are necessary to define the protected lockstep
property: the comparator has no second output stream, and `enable_cmp_q`
does not protect a single standalone `ibex_core` in this sense.

## Canonical fix

[8ec0c6f1](https://github.com/lowRISC/ibex/commit/8ec0c6f18ec22c00de7538e7dccc648e7864aa9e), merged as [PR #2129](https://github.com/lowRISC/ibex/pull/2129), changes the reset-set and comparison-enable controls to the hardened `ibex_mubi_t` encoding:

```systemverilog
ibex_mubi_t rst_shadow_set_d, rst_shadow_set_q;
ibex_mubi_t enable_cmp_d, enable_cmp_q;

assign outputs_mismatch =
  (enable_cmp_q != IbexMuBiOff) &
  (shadow_outputs_q != core_outputs_q[0]);
```

It also reports invalid reset-counter encodings through the major alert.
Thus a single stuck-at-0 bit is no longer indistinguishable from a valid
comparison-disabled state.

This record is distinct from `IBEX-LOCKSTEP_CORE_BUSY_CLOCK_GATING`, which concerns
shared busy/clock control stopping or desynchronizing the shadow. It also
does not cover reset-state, CSR propagation, or parameter elaboration.

## Source evidence

- Pre-fix path: [`rtl/ibex_lockstep.sv`](https://github.com/lowRISC/ibex/blob/b6d8b9f07582cd9f77b5c1f1680ad1ab68532796/rtl/ibex_lockstep.sv)
- Fix: [8ec0c6f1](https://github.com/lowRISC/ibex/commit/8ec0c6f18ec22c00de7538e7dccc648e7864aa9e)
- Upstream closure: [Ibex PR #2129](https://github.com/lowRISC/ibex/pull/2129)
