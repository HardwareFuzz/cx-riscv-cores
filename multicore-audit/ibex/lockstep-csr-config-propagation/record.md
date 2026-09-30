# Ibex SecureIbex shadow core missed configured identity CSRs

- Record ID: `IBEX-LOCKSTEP_CSR_CONFIG_PROPAGATION`
- Core: Ibex
- Source repository: [lowRISC/ibex](https://github.com/lowRISC/ibex)
- Scope: SecureIbex lockstep multi-execution
- Record kind: canonical upstream RTL fix
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by upstream PR #2282 and the exact primary-to-shadow parameter chain
- Affected parent: [9156029e](https://github.com/lowRISC/ibex/commit/9156029e77c61daba0874d0718e393aa7ff627ec)
- Affected revisions: descendants of `9156029e` before `0d1b1723253cdf804aad263e805544d54aa5aa57`
- Fixed revision: `0d1b1723253cdf804aad263e805544d54aa5aa57`, included in the
  audited `3250d99482f1963891ef1cf19356eeaeeaa71d30`
- Retrieved: 2026-09-09

## Symptom

With `SecureIbex=1` and a non-zero `CsrMvendorId` or `CsrMimpId`, the primary
core returned the configured value from `mvendorid` or `mimpid` while the
delayed shadow core returned zero. The two execution instances consequently
diverged and the lockstep comparison raised a major alert.

## Trigger

Instantiate `ibex_top` with SecureIbex enabled and a non-zero implementation
or vendor ID, then execute a CSR read of `mvendorid` or `mimpid`. The affected
path is `ibex_top -> ibex_lockstep -> u_shadow_core`; it requires the second
SecureIbex execution instance, but not two independently addressable harts.

## Root cause

Before the fix, the top-level passed `CsrMvendorId` and `CsrMimpId` to the
primary core but omitted them from the `u_ibex_lockstep` parameter list. The
lockstep module therefore instantiated the shadow core with its default CSR
values.

## Fix and verification

The fix propagates both parameters through `ibex_top.sv`, `ibex_lockstep.sv`,
and the `u_shadow_core` instantiation. The upstream commit message explicitly
describes the non-zero-primary/zero-shadow mismatch and its alert consequence.
Re-run the CSR read on the pre-fix parent and fixed revision to verify that
both execution instances observe the same value; this audit did not run that
reproducer.

## Source evidence

- Upstream commit [0d1b1723](https://github.com/lowRISC/ibex/commit/0d1b1723253cdf804aad263e805544d54aa5aa57)
  and [PR #2282](https://github.com/lowRISC/ibex/pull/2282).
- Pre-fix parent
  [9156029e](https://github.com/lowRISC/ibex/commit/9156029e77c61daba0874d0718e393aa7ff627ec).
- Current parameter propagation in
  [`rtl/ibex_top.sv`](https://github.com/lowRISC/ibex/blob/3250d99482f1963891ef1cf19356eeaeeaa71d30/rtl/ibex_top.sv),
  [`rtl/ibex_lockstep.sv`](https://github.com/lowRISC/ibex/blob/3250d99482f1963891ef1cf19356eeaeeaa71d30/rtl/ibex_lockstep.sv),
  and [`rtl/ibex_cs_registers.sv`](https://github.com/lowRISC/ibex/blob/3250d99482f1963891ef1cf19356eeaeeaa71d30/rtl/ibex_cs_registers.sv).

This is a confirmed SecureIbex multi-execution issue. The primary and shadow
cores are not two independently addressable SMP harts.
