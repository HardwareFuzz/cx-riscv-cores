# SecureIbex lockstep kept memory integrity checking outside the two cores

- Record ID: `IBEX-LOCKSTEP_MEMORY_ECC_NOT_REPLICATED`
- Core: Ibex
- Source repository: [lowRISC/ibex](https://github.com/lowRISC/ibex)
- Scope: SecureIbex primary/shadow memory-integrity redundancy
- Record kind: canonical upstream lockstep RTL security fix
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the shared pre-fix decoder/generator instances, the canonical PR rationale, and the merged upstream history
- Affected parent: [2f1e1883](https://github.com/lowRISC/ibex/commit/2f1e188346decdef988ee7cfafc7d44e8d256e7c)
- Fixed revision: [f7724adc](https://github.com/lowRISC/ibex/commit/f7724adcc76bea0bd909c2ac28cf11226d5cbefe), `Move memory ECC checks and generation into core`
- Canonical fix: [Ibex PR #1556](https://github.com/lowRISC/ibex/pull/1556), merged in upstream `master`
- Retrieved: 2026-09-10

## Failure mechanism

Before the fix, incoming memory integrity checks and outgoing data-integrity
generation were implemented in the shared `rtl/ibex_lockstep.sv` wrapper,
not independently in the primary and shadow `ibex_core` instances. The
pre-fix wrapper contained one instruction decoder, one data decoder, and one
data encoder, representative code being:

```systemverilog
prim_secded_inv_39_32_dec u_instr_intg_dec (
  .data_i ({instr_rdata_intg_q,
            shadow_inputs_q[LockstepOffset-1].instr_rdata}),
  .data_o (),
  .syndrome_o (),
  .err_o (instr_intg_err)
);

prim_secded_inv_39_32_dec u_data_intg_dec (
  .data_i ({data_rdata_intg_q,
            shadow_inputs_q[LockstepOffset-1].data_rdata}),
  .data_o (),
  .syndrome_o (),
  .err_o (data_intg_err)
);

prim_secded_inv_39_32_enc u_data_gen (
  .data_i (data_wdata_i),
  .data_o ({data_wdata_intg_o, unused_wdata})
);
```

The two execution instances therefore depended on a common
memory-integrity checking/generation point and its common error/data fanout.
A fault in that shared logic could make both instances receive the same
incorrect integrity result or payload, leaving no independent integrity
decision for the lockstep comparator to compare.

## Necessary two-instance trigger

1. Instantiate SecureIbex's primary `u_ibex_core` and delayed
   `u_shadow_core`, both performing instruction/data transactions.
2. Exercise the shared wrapper-level instruction/data integrity decoder or
   outgoing data encoder on those transactions.
3. A fault in the common decoder, encoder, or its common error/data fanout
   supplies the same incorrect integrity result to both execution instances.
4. The primary and shadow can then follow the same incorrect integrity path,
   defeating the intended independent lockstep memory-integrity redundancy.

The two instances are necessary to the recorded defect: a single-core ECC
decoder is not a redundancy failure. The problem is specifically that a
SecureIbex primary/shadow pair relied on one shared security decision instead
of replicating it.

## Canonical fix

[f7724adc](https://github.com/lowRISC/ibex/commit/f7724adcc76bea0bd909c2ac28cf11226d5cbefe), merged as [PR #1556](https://github.com/lowRISC/ibex/pull/1556), moves the integrity logic into each core:

- `MemECC` and `MemDataWidth` become `ibex_core` parameters;
- each `ibex_if_stage` contains its own instruction integrity decoder;
- each `ibex_load_store_unit` contains its own data decoder and write-data
  encoder;
- each core turns its local integrity failure into a bus error before the
  replicated lockstep output comparison.

The primary and shadow consequently no longer share the single wrapper-level
ECC checker/generator.

This record is distinct from the existing reset, CSR, offset, and core-busy
records, and from other response-filtering changes: it concerns
the replication boundary of memory-integrity logic itself.

## Source evidence

- Pre-fix shared logic: [`rtl/ibex_lockstep.sv`](https://github.com/lowRISC/ibex/blob/2f1e188346decdef988ee7cfafc7d44e8d256e7c/rtl/ibex_lockstep.sv)
- Fix: [f7724adc](https://github.com/lowRISC/ibex/commit/f7724adcc76bea0bd909c2ac28cf11226d5cbefe)
- Upstream closure: [Ibex PR #1556](https://github.com/lowRISC/ibex/pull/1556)
