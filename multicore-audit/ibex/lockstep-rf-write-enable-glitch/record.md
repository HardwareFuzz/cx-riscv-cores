# SecureIbex decoded register-file write enable could evade lockstep

- Record ID: `IBEX-LOCKSTEP_RF_WRITE_ENABLE_GLITCH`
- Core: Ibex
- Scope: SecureIbex primary/shadow shared register-file state path
- Record kind: canonical upstream lockstep RTL security fix
- Source repository: [lowRISC/ibex](https://github.com/lowRISC/ibex)
- Fix PR: [#1605 — Add spurious write enable check for secure Ibex](https://github.com/lowRISC/ibex/pull/1605)
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the pre-fix decoded write-enable RTL, the
  SecureIbex primary-to-shadow register-file path, and the merged PR #1605
- Status: fixed in upstream history
- Evidence level: A
- Observed configuration: `SecureIbex=1`, with the primary and delayed shadow
  execution instances and any of the FF, FPGA, or latch register-file
  implementations
- Affected/base revision: `d819fa62961367cb35f2ab5daac3d4a93e6451a6`
- Fixing revision: `cfd9b45cfceb0961f56b08dd8a494b55779f7b3f`
- Fix merged revision: `ccc9bef3ecbc31b02b1aeec1544fa3412b618a32`

## Failure mechanism

In the affected register files, the write-enable decoder derives one write
strobe from the write address and the incoming enable. In the FF
implementation, for example, each register is updated by its decoded strobe:

```systemverilog
we_a_dec[i] = (waddr_a_i == 5'(i)) ? we_a_i : 1'b0;
...
else if (we_a_dec[i]) begin
  rf_reg_q[i] <= wdata_a_i;
end
```

The decoded bus was not checked against the original address and enable. A
runtime fault or glitch in that decoded write-enable path could therefore
assert the strobe for the wrong register, or assert more than one register
strobe, and commit `wdata_a_i` into register-file state that the instruction
did not select. The same countermeasure was missing from the corresponding
FPGA and latch register-file paths.

## Two-instance trigger and impact

1. Enable SecureIbex, which instantiates a primary execution instance and a
   delayed shadow instance.
2. Execute an instruction that writes the register file while a fault is
   injected in the decoded write-enable network.
3. The single register-file storage is modified at an unintended word (or by
   an unintended write strobe).
4. The primary later reads the corrupted register value, and the delayed
   shadow receives the same register-file data path after its lockstep delay.
   The pair consequently has no independent register-file state with which to
   expose this particular corruption through the normal lockstep comparison.

The decoded write error itself is also an invalid single-Ibex operation. The
multi-execution condition recorded here is the SecureIbex security consequence:
the primary and shadow consume the same physical register-file state/data
path, so the state corruption is common to both execution instances and can
escape their comparison. The primary and shadow are not independently
addressable SMP harts.

## Fix and upstream closure

PR #1605 adds the `WrenCheck` parameter and enables it for SecureIbex. The FF
and latch implementations decode all words, buffer the decoded vector, and
check its one-hot relationship with `waddr_a_i` and `we_a_i` using
`prim_onehot_check`. The FPGA implementation checks its write strobe in the
same secure configuration. The resulting error is connected to
`alert_major_internal_o` in `ibex_top.sv`.

The PR's affected/base revision is `d819fa62`; the fixing change is the
separate commit `cfd9b45c`, whose direct Git parent is
`91745a076c7d466f0e0c0e2fd4150a2a66ccb503`. The latter updates a vendored
revision and is why the PR base is not the direct parent of the fixing commit.
The final upstream revision `ccc9bef3` adds the countermeasure label and is a
descendant of the fixing change.

## Source evidence

- Pre-fix FF register file: [`rtl/ibex_register_file_ff.sv`](https://github.com/lowRISC/ibex/blob/d819fa62961367cb35f2ab5daac3d4a93e6451a6/rtl/ibex_register_file_ff.sv)
- Pre-fix top-level lockstep path: [`rtl/ibex_top.sv`](https://github.com/lowRISC/ibex/blob/d819fa62961367cb35f2ab5daac3d4a93e6451a6/rtl/ibex_top.sv)
- Fixing commit: [cfd9b45c](https://github.com/lowRISC/ibex/commit/cfd9b45cfceb0961f56b08dd8a494b55779f7b3f)
- Merged upstream revision: [ccc9bef3](https://github.com/lowRISC/ibex/commit/ccc9bef3ecbc31b02b1aeec1544fa3412b618a32)
- Upstream closure: [Ibex PR #1605](https://github.com/lowRISC/ibex/pull/1605)
