# SecureIbex FPGA counters could reset differently in the lockstep pair

- Record ID: `IBEX-LOCKSTEP_FPGA_COUNTER_RESET_MISMATCH`
- Core: Ibex
- Scope: SecureIbex primary/shadow counter reset convergence
- Record kind: canonical upstream lockstep RTL FPGA fix
- Source repository: [lowRISC/ibex](https://github.com/lowRISC/ibex)
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the pre-fix counter reset branch, the final non-DSP fix, and upstream PR #2228
- Status: fixed in upstream history
- Evidence level: A
- Observed configuration: `FPGA_XILINX`, `CounterWidth >= 49`, and the primary/shadow SecureIbex instances
- Affected revision: `0945aa84c635a1756311c076a6a7a5b5c239532f`
- Fixed revision: `667fd20d2ede51caececccbcbda3652074424ce2`

## Failure mechanism

SecureIbex contains a primary execution instance and a delayed shadow
instance whose architectural counters must converge according to the
lockstep timing. In the affected Xilinx implementation, all counter widths
used the synchronous-reset clock event:

```systemverilog
always_ff @(posedge clk_i)
```

Xilinx DSP counters below 49 bits require a synchronous reset, but counters
of 49 bits and above are implemented with ordinary flops and require the
asynchronous reset branch. The affected RTL used the DSP reset choice for the
non-DSP counters as well. Around reset assertion or release, the two
lockstep counter instances could consequently expose different `mcycle`
values, producing a lockstep mismatch in the supported FPGA configuration.

## Two-instance trigger

1. Configure `FPGA_XILINX` with a non-DSP counter (`CounterWidth >= 49`).
2. Instantiate the SecureIbex primary and delayed shadow execution
   instances.
3. Assert and release reset with the lockstep logic active, then observe the
   two `mcycle` values and the comparison result.
4. The affected non-DSP counter does not respond to reset asynchronously as
   required, so reset timing can leave the primary and shadow counter values
   different.

The failure is specifically a lockstep multi-execution convergence failure;
it is not a claim about two independently addressable SMP harts.

## Fix history and closure

An earlier fix, [54985d21](https://github.com/lowRISC/ibex/commit/54985d21b055967c39d0a77b45ae0d573b55b0f7), described the same counter reset
problem but was subsequently reverted by [0945aa84](https://github.com/lowRISC/ibex/commit/0945aa84c635a1756311c076a6a7a5b5c239532f). It is not used as the final fix
for this record.

The final merged correction in PR #2228 selects the reset style by counter
implementation: DSP counters retain synchronous reset, while non-DSP
counters use:

```systemverilog
always_ff @(posedge clk_i or negedge rst_ni)
```

The final fix is therefore the `0945aa84 -> 667fd20d` history, not the
reverted intermediate patch.

## Source evidence

- Pre-fix counter source: [`rtl/ibex_counter.sv`](https://github.com/lowRISC/ibex/blob/0945aa84c635a1756311c076a6a7a5b5c239532f/rtl/ibex_counter.sv)
- Reverted intermediate fix: [54985d21](https://github.com/lowRISC/ibex/commit/54985d21b055967c39d0a77b45ae0d573b55b0f7)
- Final fix: [667fd20d](https://github.com/lowRISC/ibex/commit/667fd20d2ede51caececccbcbda3652074424ce2)
- Upstream closure: [Ibex PR #2228](https://github.com/lowRISC/ibex/pull/2228)
