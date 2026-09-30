# TLAtomicAutomata lost an error from the synthetic Get stage

- Record ID: `ROCKET-TLATOMIC_AUTOMATA_GET_ERROR_MERGE`
- Core: Rocket Chip
- Source repository: [chipsalliance/rocket-chip](https://github.com/chipsalliance/rocket-chip)
- Scope: shared TileLink atomic emulation and split-response error propagation
- Record kind: canonical upstream TileLink RTL fix
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact pre-fix CAM fields, the split Get/Put response path, the direct error merge, and the canonical PR closure
- Affected parent: [dcf67b49](https://github.com/chipsalliance/rocket-chip/commit/dcf67b49fa77e212e8b9506c52a14cd1e84cbe34)
- Fix commit: [25ea7fa8](https://github.com/chipsalliance/rocket-chip/commit/25ea7fa8521ac76898ade16178fb3b57adeaff8b), `tilelink: AtomicAutomata should OR the Get error with the Put error`
- Canonical closure: [merge 1f5fb5d6](https://github.com/chipsalliance/rocket-chip/commit/1f5fb5d64371c600632f21642b66b11996d9e394), retained in upstream master [55bcad0f](https://github.com/chipsalliance/rocket-chip/commit/55bcad0f59436de98ea510334121de8546b9e9d7)
- Retrieved: 2026-09-10

## Failure mechanism

At the affected parent, the CAM entry saved the data returned by the first
synthetic `Get` but had no field for its error status:

```scala
class CAM_D(params: CAMParams) extends GenericParameterizedBundle(params) {
  val data = UInt(width = params.a.dataBits)
}
```

The response handler therefore saved only the data:

```scala
when (en && d_ackd) {
  r.data := out.d.bits.data
}
```

The adapter then used the final synthetic `Put` response to reconstruct the
AMO response. If the `Get` returned `AccessAckData` with `error = 1` and the
later `Put` returned `AccessAck` with `error = 0`, the old implementation
returned the saved data with the final non-error status. The first-stage
failure was hidden and the atomic operation was reported as successful.

## Necessary shared-fabric trigger

1. A Rocket tile issues an unsupported AMO through a shared TileLink path.
2. `TLAtomicAutomata` splits the request into a synthetic `Get` and receives
   `AccessAckData` with its error bit asserted.
3. The adapter saves the data, advances to the synthetic `Put`, and does not
   save the first-stage error.
4. The shared downstream manager returns `AccessAck` for the `Put` with its
   error bit clear.
5. The adapter reconstructs the AMO result from the saved data and the final
   response status, hiding the earlier `Get` error.

The affected adapter is part of the canonical shared Rocket bus. The
`PeripheryBus` places `TLAtomicAutomata` between the system-bus ingress and
the periphery bus in
[`PeripheryBus.scala`](https://github.com/chipsalliance/rocket-chip/blob/dcf67b49fa77e212e8b9506c52a14cd1e84cbe34/src/main/scala/coreplex/PeripheryBus.scala),
and multiple Rocket tiles connect to the common system and periphery buses
through the coreplex TileLink topology. The trigger therefore applies at a
shared memory or I/O manager boundary used by multi-tile systems.

## Canonical fix and closure

The direct fix adds an error field to the CAM and captures the first-stage
status:

```scala
class CAM_D(params: CAMParams) extends GenericParameterizedBundle(params) {
  val data  = UInt(width = params.a.dataBits)
  val error = Bool()
}

r.data := out.d.bits.data
r.error := out.d.bits.error
```

The final response now merges both stages:

```scala
in.d.bits.error := d_cam_error || out.d.bits.error
```

The corrected implementation remains in
[`tilelink/AtomicAutomata.scala`](https://github.com/chipsalliance/rocket-chip/blob/55bcad0f59436de98ea510334121de8546b9e9d7/src/main/scala/tilelink/AtomicAutomata.scala).

This record is distinct from the zero-latency CAM-match record. That record
addresses omission of the live `AMO` state in response selection; this record
addresses loss of the synthetic `Get` error while merging a split atomic
operation.
