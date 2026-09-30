# SecureIbex register-file read MUX fault could feed the same wrong word to both instances

- Record ID: `IBEX-LOCKSTEP_RF_READ_MUX_FI`
- Core: Ibex
- Scope: SecureIbex primary/shadow shared register-file read-data path
- Record kind: canonical upstream lockstep RTL security fix
- Source repository: [lowRISC/ibex](https://github.com/lowRISC/ibex)
- Source issue: [OpenTitan #20715 — Register file read MUX fault injection](https://github.com/lowRISC/opentitan/issues/20715)
- Fix PR: [Ibex #2117 — Fix FI vulnerability in RF](https://github.com/lowRISC/ibex/pull/2117)
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the pre-fix address-indexed MUX, the explicit
  fault-injection result in issue #20715, and the merged PR #2117
- Status: fixed in upstream history
- Evidence level: A
- Observed configuration: `SecureIbex=1` using the FF or FPGA register-file
  implementation covered by the demonstrated fault-injection path, with the
  primary and delayed shadow execution instances
- Affected parent revision: `d56143d03b0f6ef42a66a7f4fad1b6a016d664b2`
- Fixing/merged revision: `35bbdb7be3872e07b3ddd3f6bb09b8260c939bd6`
- Follow-up for a separate latch-checker address connection typo:
  `2617c43c0a20cfcd0d9fff86cbd172b8328ae285` (Ibex PR #2216)

## Failure mechanism

The affected FF register file selects read data with an ordinary address
indexed array expression:

```systemverilog
assign rdata_a_o = rf_reg[raddr_a_i];
assign rdata_b_o = rf_reg[raddr_b_i];
```

The corresponding FPGA implementation also used address-indexed reads. In a
netlist, these expressions implement address-selection MUXes. OpenTitan issue
#20715 reports the concrete runtime fault-injection result for the read path:

```text
r_addr_a_i = 5
expected rdata_a_o = rf_reg[5]
retrieved rdata_a_o = rf_reg[15]
No alert was triggered.
```

Thus a fault in the synthesized read-address/MUX selection can deliver a
different register word to Ibex without activating the SecureIbex alert path.
This is a data-selection error in implemented RTL/netlist behavior, not an
elaboration-only parameter or topology result.

## Two-instance trigger and impact

1. Enable SecureIbex so the primary and delayed shadow execution instances
   are present.
2. Read a register through the FF or FPGA register file while the synthesized
   read-selection network has the documented fault.
3. The faulty selection occurs before the primary/shadow split in
   `ibex_top.sv`: the primary consumes the selected data, while the same
   register-file data bits are buffered and delivered to the delayed shadow.
4. Both instances therefore consume the same wrong word, and the lockstep
   comparator has no independent read result with which to raise an alert.

A read-MUX fault can also produce a wrong value in a single core. The
multi-execution result retained here is the confirmed SecureIbex escape:
the read-selection fault is common to both primary and shadow because they
share the register-file read-data path. The two instances are not
independently addressable SMP harts.

## Fix and scope limitation

PR #2117 adds `RdataMuxCheck` and enables it for SecureIbex. It one-hot
encodes both read addresses, buffers the selectors so the checker is not
optimized away, checks the selector/address relationship with
`prim_onehot_check`, and replaces the ordinary address-indexed MUX with
`prim_onehot_mux`. The fix also connects the error to the existing major
internal alert path.

The merged change includes the FF, FPGA, and latch implementations. A later
review found that the latch implementation's port-A checker used
`raddr_b_int` as its address input; Ibex PR #2216 fixes that independent
connection typo. This record is deliberately limited to the demonstrated
FF/FPGA read-MUX fault-injection vulnerability and does not claim that
`35bbdb7b` alone is the final correction for that later latch-specific typo.

## Source evidence

- Pre-fix FF read MUX: [`rtl/ibex_register_file_ff.sv`](https://github.com/lowRISC/ibex/blob/d56143d03b0f6ef42a66a7f4fad1b6a016d664b2/rtl/ibex_register_file_ff.sv)
- Fix: [35bbdb7b](https://github.com/lowRISC/ibex/commit/35bbdb7be3872e07b3ddd3f6bb09b8260c939bd6)
- Runtime fault-injection report: [OpenTitan issue #20715](https://github.com/lowRISC/opentitan/issues/20715)
- Upstream closure: [Ibex PR #2117](https://github.com/lowRISC/ibex/pull/2117)
- Latch follow-up: [Ibex PR #2216](https://github.com/lowRISC/ibex/pull/2216), fixed by [2617c43c](https://github.com/lowRISC/ibex/commit/2617c43c0a20cfcd0d9fff86cbd172b8328ae285)
