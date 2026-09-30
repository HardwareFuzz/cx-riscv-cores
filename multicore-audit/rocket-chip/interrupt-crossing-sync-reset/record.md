# ROCKET-INTERRUPT_CROSSING_SYNC_RESET

- Record ID: `ROCKET-INTERRUPT_CROSSING_SYNC_RESET`
- Core: Rocket Chip
- Source repository: [chipsalliance/rocket-chip](https://github.com/chipsalliance/rocket-chip)
- Scope: Canonical per-tile CLINT/PLIC interrupt crossing between shared periphery and Rocket tiles
- Record kind: HDL/RTL defect
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: Independently confirmed from the exact affected parent, direct upstream fix, merged pull request, canonical per-tile wiring, and fixed canonical master source.
- Retrieved: 2026-09-10
- Affected parent: [`f86489b59e82c4ae4e39b6ba0caf9fd279d4aa16`](https://github.com/chipsalliance/rocket-chip/commit/f86489b59e82c4ae4e39b6ba0caf9fd279d4aa16)
- Fix: [`8ec06151b07b1f5430917ab0968ea925dfd936a0`](https://github.com/chipsalliance/rocket-chip/commit/8ec06151b07b1f5430917ab0968ea925dfd936a0)
- Pull request: [#1080](https://github.com/chipsalliance/rocket-chip/pull/1080)
- Canonical closure: merged as [`8ec06151b07b1f5430917ab0968ea925dfd936a0`](https://github.com/chipsalliance/rocket-chip/commit/8ec06151b07b1f5430917ab0968ea925dfd936a0), retained by canonical master [`55bcad0f59436de98ea510334121de8546b9e9d7`](https://github.com/chipsalliance/rocket-chip/commit/55bcad0f59436de98ea510334121de8546b9e9d7)

## Confirmation

The direct fix [`8ec06151b07b1f5430917ab0968ea925dfd936a0`](https://github.com/chipsalliance/rocket-chip/commit/8ec06151b07b1f5430917ab0968ea925dfd936a0) is the direct child of affected parent [`f86489b59e82c4ae4e39b6ba0caf9fd279d4aa16`](https://github.com/chipsalliance/rocket-chip/commit/f86489b59e82c4ae4e39b6ba0caf9fd279d4aa16), and it was merged by [PR #1080](https://github.com/chipsalliance/rocket-chip/pull/1080). The fixed source remains in [`Crossing.scala` at canonical master](https://github.com/chipsalliance/rocket-chip/blob/55bcad0f59436de98ea510334121de8546b9e9d7/src/main/scala/interrupts/Crossing.scala). The affected implementation is [`Crossing.scala` at the parent](https://github.com/chipsalliance/rocket-chip/blob/f86489b59e82c4ae4e39b6ba0caf9fd279d4aa16/src/main/scala/interrupts/Crossing.scala).

## Failure mechanism

The affected `IntSyncCrossingSource` used a synchronously reset register:

```scala
out.sync := RegNext(in)
```

Because the reset of that source-side state is synchronous, it is only sampled when the source clock domain runs. If the source clock has not run yet, or if the source domain is powered down, a stale or high interrupt state can remain in the crossing register. The destination tile can consequently observe the interrupt as asserted after reset and continue seeing it as asserted. A hart can become wedged in interrupt handling or fail to make forward progress because the stale interrupt state is never cleared by a clock edge in the inactive source domain.

The affected block is an HDL clock/reset-crossing defect: reset correctness depends on activity in the source domain even though the interrupt is consumed by a separately clocked tile domain.

## Necessary multi-client trigger

The trigger requires the canonical multi-tile RocketCoreplex interrupt topology: a shared periphery interrupt source such as CLINT or PLIC drives a per-tile interrupt crossing, and the source and tile domains do not share the same clock/reset activity. The affected `RocketCoreplex` creates one tile wrapper per tile and connects each tile's CLINT/PLIC interrupt path through `wrapper.crossIntIn`. The crossing helper in [`CrossingWrapper.scala`](https://github.com/chipsalliance/rocket-chip/blob/f86489b59e82c4ae4e39b6ba0caf9fd279d4aa16/src/main/scala/coreplex/CrossingWrapper.scala) instantiates the source and sink sides of this interrupt boundary, and the per-tile wiring is present in [`RocketCoreplex.scala`](https://github.com/chipsalliance/rocket-chip/blob/f86489b59e82c4ae4e39b6ba0caf9fd279d4aa16/src/main/scala/coreplex/RocketCoreplex.scala).

With multiple tiles, the shared CLINT/PLIC domain supplies independent interrupt paths to multiple hart wrappers. A source-domain reset/clock pause on one path can leave that hart's interrupt state stuck while the other tile paths continue operating, making the stale level a per-hart forward-progress failure at a shared periphery-to-tile boundary. The trigger is the legal inactive-source-domain condition, not a special test-only connection.

## Canonical fix and closure

The direct fix changes the source-side register to an asynchronously reset implementation:

```scala
out.sync := AsyncResetReg(Cat(in.reverse)).toBools
```

This makes reset effective without waiting for a source-domain clock edge and prevents the stale/high crossing state from surviving source-domain inactivity. The fix is [PR #1080](https://github.com/chipsalliance/rocket-chip/pull/1080), merged as [`8ec06151b07b1f5430917ab0968ea925dfd936a0`](https://github.com/chipsalliance/rocket-chip/commit/8ec06151b07b1f5430917ab0968ea925dfd936a0), and is retained in canonical master [`55bcad0f59436de98ea510334121de8546b9e9d7`](https://github.com/chipsalliance/rocket-chip/commit/55bcad0f59436de98ea510334121de8546b9e9d7).

The finding is distinct from the PLIC `meip`/`seip` ordering record, which concerns two-hart interrupt-vector connection order, and from the CLINT MSIP stride record, which concerns per-hart software-interrupt address/state mapping. This record concerns reset behavior at the per-tile interrupt clock crossing.
