# TLAtomicAutomata missed a zero-latency AccessAck for an emulated AMO

- Record ID: `ROCKET-TLATOMIC_AUTOMATA_ZERO_LATENCY_ACK`
- Core: Rocket Chip
- Source repository: [chipsalliance/rocket-chip](https://github.com/chipsalliance/rocket-chip)
- Scope: shared TileLink atomic emulation and response matching
- Record kind: canonical upstream TileLink RTL fix
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact CAM state predicate, the same-cycle Get/Put response path, the direct fix, and the canonical merge
- Affected parent: [f83d1d0a](https://github.com/chipsalliance/rocket-chip/commit/f83d1d0aaf01f490b7c9816e764abb1bc8d47e76)
- Fix commit: [ed4224dd](https://github.com/chipsalliance/rocket-chip/commit/ed4224dde4d899982617dbcc3fd7ccd474f5bf9e), `tilelink2 AtomicAutomata: fix AccessAck on same cycle as PutFull`
- Canonical closure: [merge 1b016051](https://github.com/chipsalliance/rocket-chip/commit/1b016051e888cc76c55e2a9a519b0c2bf568c49), retained in upstream master [55bcad0f](https://github.com/chipsalliance/rocket-chip/commit/55bcad0f59436de98ea510334121de8546b9e9d7)
- Retrieved: 2026-09-10

## Failure mechanism

At the affected parent, the atomic adapter used a CAM with these states:

```scala
val FREE = UInt(0)
val GET  = UInt(3)
val AMO  = UInt(2)
val ACK  = UInt(1)
```

The D-channel response match omitted the `AMO` state:

```scala
val cam_dmatch =
  cam_s.map(e => e.state === GET || e.state === ACK)
```

When a downstream manager does not implement the requested atomic operation,
the adapter splits it into a synthetic `Get`, saves the returned data, changes
the CAM entry to `AMO`, and emits a synthetic `PutFull`. A manager with a
zero-latency response can return the `PutFull` `AccessAck` in the same cycle
that the request is accepted. During that response the CAM entry is still in
state `AMO`, so the old predicate does not select it. The response is not
converted back through the saved atomic-operation data, and the active CAM
entry is not released. This leaves an incorrect AMO response path and a
permanently occupied atomic-adapter slot.

## Necessary shared-fabric trigger

1. A Rocket tile issues an AMO to a manager that requires software emulation.
2. `TLAtomicAutomata` sends the synthetic `Get` and receives its data,
   entering the `AMO` CAM state.
3. The adapter emits the synthetic `PutFull`.
4. The downstream TileLink manager accepts that `PutFull` and returns
   `AccessAck` without an intervening cycle.
5. The affected CAM matcher sees an `AMO` entry, excludes it, and fails to
   retire or replace the response.

The adapter is on a shared canonical Rocket fabric. The coreplex places the
atomic adapter around the TileLink crossbar in
[`BaseCoreplex.scala`](https://github.com/chipsalliance/rocket-chip/blob/f83d1d0aaf01f490b7c9816e764abb1bc8d47e76/src/main/scala/coreplex/BaseCoreplex.scala),
and the coreplex connects tile ports into the common coherent system bus.
The same shared fabric is used by multi-tile Rocket configurations, so the
atomic response can be generated at a shared memory or I/O boundary.

## Canonical fix and closure

The direct fix changes the matcher to include every live CAM entry:

```scala
val cam_dmatch = cam_s.map(e => e.state =/= FREE)
```

It also removes the redundant `out.d.valid` condition from the same-cycle
bypass path. The corrected source is retained in
[`uncore/tilelink2/AtomicAutomata.scala`](https://github.com/chipsalliance/rocket-chip/blob/55bcad0f59436de98ea510334121de8546b9e9d7/src/main/scala/uncore/tilelink2/AtomicAutomata.scala).

This record concerns the missing `AMO` CAM match for a zero-latency final
`AccessAck`. It is distinct from the later AtomicAutomata error-merge record,
which preserves the error from the synthetic `Get` across the split
transaction.
