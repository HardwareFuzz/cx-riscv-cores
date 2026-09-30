# CoupledL2 did not commit ProbeAck state, dirty, and client effects to the MSHR metadata

- Record ID: `XIANGSHAN-COUPLEDL2-PROBEACK_MSHR_META_STATE`
- Core: XiangShan / CoupledL2 (XSCache)
- Record kind: canonical upstream CoupledL2 CHI ProbeAck metadata fix
- Source repository: [OpenXiangShan/CoupledL2](https://github.com/OpenXiangShan/CoupledL2)
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact MSHR metadata update/export changes and merged PR #377
- Scope: shared CHI ProbeAck/ProbeAckData handling and nested snoop metadata
- Status: fixed in upstream history
- Evidence level: A
- Observed configuration: one RN-F has a live MSHR while another RN-F probes the same line and a nested snoop observes that MSHR
- Affected revision: `38306873ea21e235aa35f2fb062c1243548688d0`
- Fixed revision: `41d16cadb819dfe87e5aa0f4a6a331ff6ea338e9`

## Failure mechanism

The affected path is `src/main/scala/coupledL2/tl2chi/MSHR.scala`, with
RXSNP/MainPipe consuming the exported MSHR information. Before the repair,
ProbeAck effects were kept in temporary flags instead of being committed to
the live metadata. The old response handling included:

```scala
when (c_resp.bits.opcode === ProbeAckData) {
  probeDirty := true.B
}
when (isToN(c_resp.bits.param)) {
  probeGotN := true.B
}
```

and later derived ownership/client effects from `probeGotN` and
`probeDirty`, while nested-snoop consumers read the MSHR's `meta` fields.
The MSHR therefore could receive ProbeAck/ProbeAckData that changed the
line's CHI state, dirty status, or client ownership, yet continue holding the
old live `meta.state` and `meta.clients`; dirty information was represented
partly by the temporary `probeDirty` flag rather than committed uniformly to
the live metadata. A nested snoop or a subsequent response could consequently
make a decision from stale MSHR metadata. This record is limited to the live
state/client metadata commit defect and does not assert that every dirty
export ignored `probeDirty`.

## Two-client trigger

1. RN-F A has a live CoupledL2 MSHR for line X.
2. RN-F B requests ownership or otherwise probes X, causing A to receive a
   ProbeAck or ProbeAckData response while its MSHR remains active.
3. Before the old MSHR completes, a nested snoop/response path consumes the
   MSHR metadata. Because the ProbeAck effects only changed temporary flags,
   that path sees the pre-Probe state/client/dirty values and can produce an
   incorrect response or follow-up transition.

The remote RN-F probe is essential; an MSHR without a second coherent client
does not receive the ProbeAck event that exposes the stale metadata.

## Canonical fix

[41d16ca](https://github.com/OpenXiangShan/CoupledL2/commit/41d16cadb819dfe87e5aa0f4a6a331ff6ea338e9), merged as [PR #377](https://github.com/OpenXiangShan/CoupledL2/pull/377), replaces the temporary-only bookkeeping with live metadata updates, including:

```scala
when (c_resp.bits.opcode === ProbeAckData) {
  probeDirty := true.B
  meta.dirty := true.B
}
when (isToN(c_resp.bits.param)) {
  meta.state := Mux(isT(meta.state), TIP, meta.state)
  meta.clients := Fill(clientBits, false.B)
}
```

It also exports the live `meta` fields to the nested-snoop path and adds
the corresponding release-data guard. The fix is reachable from canonical
CoupledL2 `origin/master`.

This record is distinct from the earlier SnpStashX record: it concerns
ProbeAck/ProbeAckData effects on any live MSHR and the stale metadata exposed
to consumers, not the SnpStashX opcode's forbidden invalidating side effect.

## Source evidence

- Pre-fix path: [`MSHR.scala`](https://github.com/OpenXiangShan/CoupledL2/blob/38306873ea21e235aa35f2fb062c1243548688d0/src/main/scala/coupledL2/tl2chi/MSHR.scala)
- Fix: [41d16ca](https://github.com/OpenXiangShan/CoupledL2/commit/41d16cadb819dfe87e5aa0f4a6a331ff6ea338e9)
- Upstream closure: [CoupledL2 PR #377](https://github.com/OpenXiangShan/CoupledL2/pull/377)
