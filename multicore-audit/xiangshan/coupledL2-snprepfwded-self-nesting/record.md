# CoupledL2 could nest `SnpRespFwded` into its own MSHR

- Record ID: `XIANGSHAN-COUPLEDL2_SNPRESPFORWARDED_SELF_NESTING`
- Core: XiangShan / XSCache
- Source repository: [OpenXiangShan/XSCache](https://github.com/OpenXiangShan/XSCache)
- Record kind: canonical XSCache CHI MSHR state-machine fix
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the upstream self-nesting failure description, exact `req.fromA` guards, and merged XSCache PR #211
- Scope: shared CHI forwarded snoop and nested writeback state
- Status: fixed in upstream history
- Evidence level: A
- Observed configuration: at least two independent RN-F clients, where a home-node forwarded snoop is outstanding while its peer response and completion are still being handled by CoupledL2
- Parent revision: `afd0c10a3ba34af6fd261ea197f2ff53d2822db8`
- Fixed revision: `b76e41b2de4c17c275bcc22f22fb98d6d34d88be`

## Failure mechanism

The affected path is `src/main/scala/coupledL2/tl2chi/MSHR.scala`. A forwarded
snoop request allocates an MSHR that must process its `SnpResp[Data]Fwded`
response and then its original `CompData` in sequence. In the parent revision,
nested-writeback state updates were applied without checking the direction of
the MSHR request:

```scala
when (io.nestedwb.b_inv_dirty) { ... }
when (io.nestedwb.b_toB.get) { ... }
when (io.nestedwb.b_toN.get) { ... }
```

If the forwarded response reached the MainPipe before the original MSHR had
sent its `CompData`, the response could match that same-address MSHR and apply
its own forwarding result as a nested writeback to itself. The upstream failure
description identifies the resulting state-machine failure: the MSHR can remain
stuck in `w_replResp` instead of completing the forwarded snoop transaction.

## Runtime trigger

1. A request from one RN-F causes the home node to issue a forwarded snoop to a
   peer RN-F.
2. CoupledL2 allocates an MSHR for the forwarded snoop and has not yet emitted
   its original completion.
3. The peer RN-F returns `SnpRespFwded` or `SnpRespDataFwded` for the same
   address.
4. The parent MSHR matches its own response through the nested-writeback path
   and updates its own state; the transaction can stick in `w_replResp`.

The requesting RN-F and the peer snooped RN-F are both required: the first
creates the home-node forwarding request and the second supplies the forwarded
response. With only one coherent client, this peer-forwarding interaction does
not arise.

## Fix

PR #211 gates the relevant nested state transitions with `req.fromA`:

```scala
when (io.nestedwb.b_inv_dirty && req.fromA) { ... }
when (io.nestedwb.b_toB.get && req.fromA) { ... }
when (io.nestedwb.b_toN.get && req.fromA) { ... }
```

An MSHR handling the original forwarded snoop no longer consumes its own
forwarding response as an external nested writeback.

## Distinction from other records

This record is the self-match and forward-progress failure for
`SnpRespFwded`. It is distinct from the `SnpOnce*` nested-writeback record,
which covers dirty-data response and permission-state handling, and from the
directory metadata records that do not involve a forwarded response matching
its originating MSHR.

## Source evidence

- Pre-fix path: [`MSHR.scala`](https://github.com/OpenXiangShan/XSCache/blob/afd0c10a3ba34af6fd261ea197f2ff53d2822db8/src/main/scala/coupledL2/tl2chi/MSHR.scala)
- Fix: [b76e41b](https://github.com/OpenXiangShan/XSCache/commit/b76e41b2de4c17c275bcc22f22fb98d6d34d88be)
- Upstream closure: [XSCache PR #211](https://github.com/OpenXiangShan/XSCache/pull/211)
- Relevant diff: restrict nested invalidation and state-transition updates to `req.fromA` requests.
