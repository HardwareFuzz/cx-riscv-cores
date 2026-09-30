# ROCKET-PLIC_MEIP_SEIP_FLAT_ORDER

- Record ID: `ROCKET-PLIC_MEIP_SEIP_FLAT_ORDER`
- Core: Rocket Chip
- Source repository: [chipsalliance/rocket-chip](https://github.com/chipsalliance/rocket-chip)
- Scope: Multi-hart PLIC `meip`/`seip` interrupt-context ordering and tile interrupt routing
- Record kind: HDL/RTL and interconnect wiring defect
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: Independently confirmed from the exact affected parent, direct upstream fix, merged pull request, canonical PLIC flattening and tile decoder order, and fixed canonical master source.
- Retrieved: 2026-09-10
- Affected parent: [`5453ae9e5f9e3c51c5ba86575b5ec62ac240289c`](https://github.com/chipsalliance/rocket-chip/commit/5453ae9e5f9e3c51c5ba86575b5ec62ac240289c)
- Fix: [`93fe30e843ef61847acbe0260ff7f864d12d9f32`](https://github.com/chipsalliance/rocket-chip/commit/93fe30e843ef61847acbe0260ff7f864d12d9f32)
- Pull request: [#3606](https://github.com/chipsalliance/rocket-chip/pull/3606)
- Canonical closure: merge [`51e8773b00c45bb3267b4cbaa4499ee4c6ec8fad`](https://github.com/chipsalliance/rocket-chip/commit/51e8773b00c45bb3267b4cbaa4499ee4c6ec8fad), retained by canonical master [`55bcad0f59436de98ea510334121de8546b9e9d7`](https://github.com/chipsalliance/rocket-chip/commit/55bcad0f59436de98ea510334121de8546b9e9d7)

## Confirmation

The direct fix [`93fe30e843ef61847acbe0260ff7f864d12d9f32`](https://github.com/chipsalliance/rocket-chip/commit/93fe30e843ef61847acbe0260ff7f864d12d9f32) is the direct child of affected parent [`5453ae9e5f9e3c51c5ba86575b5ec62ac240289c`](https://github.com/chipsalliance/rocket-chip/commit/5453ae9e5f9e3c51c5ba86575b5ec62ac240289c). It was merged by [PR #3606](https://github.com/chipsalliance/rocket-chip/pull/3606) as [`51e8773b00c45bb3267b4cbaa4499ee4c6ec8fad`](https://github.com/chipsalliance/rocket-chip/commit/51e8773b00c45bb3267b4cbaa4499ee4c6ec8fad), and the corrected ordering remains in canonical master [`55bcad0f59436de98ea510334121de8546b9e9d7`](https://github.com/chipsalliance/rocket-chip/commit/55bcad0f59436de98ea510334121de8546b9e9d7). The affected connection logic is in [`HasHierarchicalElements.scala` at the parent](https://github.com/chipsalliance/rocket-chip/blob/5453ae9e5f9e3c51c5ba86575b5ec62ac240289c/src/main/scala/subsystem/HasHierarchicalElements.scala), while the fixed explicit connection loop is retained in [`HasHierarchicalElements.scala` at canonical master](https://github.com/chipsalliance/rocket-chip/blob/55bcad0f59436de98ea510334121de8546b9e9d7/src/main/scala/subsystem/HasHierarchicalElements.scala).

## Failure mechanism

At the affected parent, `HasHierarchicalElements` constructs and connects all PLIC machine-external-interrupt nodes before constructing and connecting the supervisor-external-interrupt nodes. The connection order is therefore:

```text
context 0: tile 0 meip
context 1: tile 1 meip
context 2: tile 0 seip
context 3: tile 1 seip
```

The tile-side connection and interrupt decoder expect each tile's machine and supervisor inputs next to one another:

```text
context 0: tile 0 meip
context 1: tile 0 seip
context 2: tile 1 meip
context 3: tile 1 seip
```

The PLIC flattens its interrupt contexts in connection order. In [`Plic.scala` at the parent](https://github.com/chipsalliance/rocket-chip/blob/5453ae9e5f9e3c51c5ba86575b5ec62ac240289c/src/main/scala/devices/tilelink/Plic.scala), the output contexts are collected with `intnode.out.unzip` followed by `io_harts.flatten`, and each target is computed from the corresponding flattened hart entry. The old [`HasTiles.scala` connection sequence](https://github.com/chipsalliance/rocket-chip/blob/5453ae9e5f9e3c51c5ba86575b5ec62ac240289c/src/main/scala/subsystem/HasTiles.scala) connects `meip` followed by `seip` for each tile, and [`Interrupts.scala`](https://github.com/chipsalliance/rocket-chip/blob/5453ae9e5f9e3c51c5ba86575b5ec62ac240289c/src/main/scala/tile/Interrupts.scala) decodes the same per-tile order.

For two tiles with supervisor mode enabled, the two middle contexts are crossed: the PLIC context intended for tile 0 `seip` is delivered to tile 1 `meip`, and the context intended for tile 1 `meip` is delivered to tile 0 `seip`. A pending and enabled interrupt associated with either middle context can therefore reach the wrong hart and/or privilege-level input. This is a deterministic two-hart routing mismatch caused by the differing flattening and consumption orders.

## Necessary multi-client trigger

The trigger requires at least two Rocket tiles, with the PLIC connected to both tiles and supervisor interrupt inputs present. The affected parent must build the flat PLIC context vector as all `meip` outputs followed by all `seip` outputs, while the tile side consumes contexts in per-tile `meip,seip` order. With two tiles, the flattening mismatch creates the concrete `M0,M1,S0,S1` versus `M0,S0,M1,S1` mapping and misroutes the middle contexts. A one-tile system does not expose the cross-tile permutation, so the two-hart condition is necessary.

## Canonical fix and closure

The direct fix separates node-map construction from node connection and then connects the two interrupt nodes for each tile in sequence:

```scala
for (i <- 0 until nTotalTiles) {
  meipNodes.get(i).foreach { _ := plicOpt.map(_.intnode).getOrElse(meipIONode.get) }
  seipNodes.get(i).foreach { _ := plicOpt.map(_.intnode).getOrElse(seipIONode.get) }
}
```

This produces `M0,S0,M1,S1,...`, matching the tile decoder and PLIC context expectations. The fixed source comment states that the `meip`/`seip` nodes must be connected in `MSMSMS` order. The fix is [PR #3606](https://github.com/chipsalliance/rocket-chip/pull/3606), merged as [`51e8773b00c45bb3267b4cbaa4499ee4c6ec8fad`](https://github.com/chipsalliance/rocket-chip/commit/51e8773b00c45bb3267b4cbaa4499ee4c6ec8fad), and retained in canonical master [`55bcad0f59436de98ea510334121de8546b9e9d7`](https://github.com/chipsalliance/rocket-chip/commit/55bcad0f59436de98ea510334121de8546b9e9d7).

This record is distinct from the CLINT MSIP stride record: it does not concern CLINT address arithmetic, `ipiWidth`, software-interrupt slot size, or `msip` state mapping. It concerns PLIC `meip`/`seip` output-context ordering and the resulting two-hart interrupt routing.
