# CoupledL2 could retain stale `CopyBackWrData` across a nested-writeback retry

- Record ID: `XIANGSHAN-COUPLEDL2_WRITEBACK_RETRY_CBWRDATA`
- Core: XiangShan / CoupledL2
- Scope: shared CHI replacement writeback and peer-snoop nesting
- Record kind: canonical upstream CoupledL2 CHI RTL fix
- Source repository: [OpenXiangShan/CoupledL2](https://github.com/OpenXiangShan/CoupledL2)
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact `s_cbwrdata` state correction, the CHI peer-RN path, and merged CoupledL2 PR #199
- Status: fixed in upstream history
- Evidence level: A
- Observed configuration: at least two RN-F clients sharing the CoupledL2 home node
- Affected revision: `1b986c60625579ffe63f4c1eb40fff1b27b83827`
- Fixed revision: `2315b49f0d81584e1b3b3776377d9af1e36be19d`

## Failure mechanism

The affected path is `src/main/scala/coupledL2/tl2chi/MSHR.scala`. A
replacement block could be nested by a peer snoop while its writeback was
waiting to retry. Before the fix, the retry path reset retry bookkeeping but
did not recompute the `s_cbwrdata` bit from the current metadata and
`probeDirty` state. The MSHR could therefore issue an incorrect CHI data
combination on the retry: an `Evict` could carry `CopyBackWrData`, or a
`WriteBackFull` could omit data that the protocol required.

The fixing change adds the missing reassignment when a release is retried:

```scala
when (release_valid2) {
  state.s_cbwrdata.get := !(isT(meta.state) && meta.dirty || probeDirty)
}
```

The same fix commit adds assertions distinguishing the no-data `Evict` form
from the data-bearing `WriteBackFull` form. This closes the mechanism at the
actual CHI message boundary rather than merely changing arbitration latency.

## Two-client trigger

1. RN-F A owns a replacement victim and begins its CHI writeback/release.
2. RN-F B requests the same line, causing the home node to send a snoop to
   RN-F A while A's replacement transaction is active.
3. The snoop nests in A's MSHR, changes the metadata or probe-dirty condition,
   and forces the replacement writeback to retry.
4. In the affected revision, the stale `s_cbwrdata` state selects the wrong
   CHI data form on the retried transaction.

The CoupledL2 test topology connects separate L2/RN-F instances to distinct
home-node RN ports, and its `peerRNs_valids_vec_s4`/`request_snoop_s4` path
generates the peer snoop from directory ownership. Removing RN-F B removes
the nested peer-snoop event; removing RN-F A removes the replacement
writeback. Both independent clients are therefore necessary to form this
failure.

## Deduplication boundary

This is distinct from the existing refill-versus-RXSNP record: that record
concerns a refill's latest ReleaseBuffer data being read too early. It is also
distinct from the SnpQuery/Evict record, which concerns metadata remaining
valid after a plain Evict, and from the missed-forward-snoop record, which
concerns directory-miss DCT nesting. This record is limited to stale
`s_cbwrdata` selection on a replacement retry.

## Source evidence

- Pre-fix MSHR: [`src/main/scala/coupledL2/tl2chi/MSHR.scala`](https://github.com/OpenXiangShan/CoupledL2/blob/1b986c60625579ffe63f4c1eb40fff1b27b83827/src/main/scala/coupledL2/tl2chi/MSHR.scala)
- Fix: [2315b49f](https://github.com/OpenXiangShan/CoupledL2/commit/2315b49f0d81584e1b3b3776377d9af1e36be19d)
- Upstream closure: [CoupledL2 PR #199](https://github.com/OpenXiangShan/CoupledL2/pull/199)
