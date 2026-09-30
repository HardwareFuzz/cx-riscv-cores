# CoupledL2 left an Evict line valid while another RN-F nested SnpQuery

- Record ID: `XIANGSHAN-COUPLEDL2-SNPQUERY_NESTED_EVICT_STATE`
- Core: XiangShan / CoupledL2 (XSCache)
- Record kind: canonical upstream CoupledL2 CHI nested-Evict metadata fix
- Source repository: [OpenXiangShan/CoupledL2](https://github.com/OpenXiangShan/CoupledL2)
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact issue timing and upstream PR #353
- Scope: shared CHI SnpQuery versus Evict metadata transition
- Status: fixed in upstream history
- Evidence level: A
- Observed configuration: one RN-F issues Evict while another RN-F sends SnpQuery for the same line
- Affected revision: `489c2b8afd1edd721702b26ec7aefa08cad13faa`
- Fixed revision: `108e6a302f657a297c625684b098964b028e3902`

## Failure mechanism

The affected path is `src/main/scala/coupledL2/tl2chi/MSHR.scala`. Before the
repair, an Evict only set the writeback-control state when its release task
was accepted:

```scala
}.elsewhen (mp_release_valid) {
  state.s_release := true.B
  state.s_cbwrdata.get := isEvict
}
```

The line metadata was invalidated only later in the
`mp_cbwrdata_valid` branch:

```scala
}.elsewhen (mp_cbwrdata_valid) {
  state.s_cbwrdata.get := true.B
  meta.state := INVALID
  meta.dirty := false.B
}
```

During the interval after the plain Evict Release was accepted but before the
MSHR was freed, the MSHR still exposed the old valid state and dirty bit. A
nested SnpQuery could therefore observe the line as present and return the
wrong `SnpResp` state instead of `SnpResp_I`.

## Two-client trigger

1. RN-F A selects line X for a plain `Evict` and the CoupledL2 MSHR accepts
   its Release.
2. Before the MSHR is freed, RN-F B sends SnpQuery for X.
3. The old MSHR still reports its pre-Evict metadata, so B's snoop can see a
   valid/dirty line even though A has already transferred ownership away.

The second RN-F query is necessary to observe the stale state in the Evict
window; a local Evict without an overlapping snoop does not expose the
incorrect response. `WriteEvictOrEvict` and a later CopyBackWrData handshake
are not part of this trigger.

## Canonical fix

[108e6a3](https://github.com/OpenXiangShan/CoupledL2/commit/108e6a302f657a297c625684b098964b028e3902), merged as [PR #353](https://github.com/OpenXiangShan/CoupledL2/pull/353), invalidates the metadata when the plain Evict Release is issued:

```scala
when (isEvict) {
  meta.state := INVALID
  meta.dirty := false.B
}
```

The fix also preserves the intended unchanged-state handling for nested
SnpQuery responses. It is reachable from canonical CoupledL2 `origin/master`.

## Source evidence

- Pre-fix path: [`MSHR.scala`](https://github.com/OpenXiangShan/CoupledL2/blob/489c2b8afd1edd721702b26ec7aefa08cad13faa/src/main/scala/coupledL2/tl2chi/MSHR.scala)
- Fix: [108e6a3](https://github.com/OpenXiangShan/CoupledL2/commit/108e6a302f657a297c625684b098964b028e3902)
- Upstream closure: [CoupledL2 PR #353](https://github.com/OpenXiangShan/CoupledL2/pull/353)
