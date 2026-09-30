# ReleaseAck ordering checks omitted clean-release and Acquire paths

- Record ID: `ROCKET-DCACHE_RELEASEACK_ACQUIRE_PROBEACK`
- Core: Rocket Chip
- Source repository: [chipsalliance/rocket-chip](https://github.com/chipsalliance/rocket-chip)
- Scope: shared TileLink DCache ReleaseAck, ProbeAck, and Acquire ordering
- Record kind: canonical upstream DCache coherence ordering fix
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact post-#1999 base, the two omitted ordering predicates, the peer-hart trigger, the complete fix chain, and merged PR #2832
- Affected parent: [86a2f2cc](https://github.com/chipsalliance/rocket-chip/commit/86a2f2cca699f149bcc082ef2828654a0a4e3f4b)
- Fixed revisions: [c72355c0](https://github.com/chipsalliance/rocket-chip/commit/c72355c041b508d40e51776e465e44d6e5375a85), [faff1b13](https://github.com/chipsalliance/rocket-chip/commit/faff1b13ce90acde21b543e208cc7061fe5995cb), [9d2ce3e4](https://github.com/chipsalliance/rocket-chip/commit/9d2ce3e4cc903a64f04d72e7c23dfbeca38f46ed), and [8acd6b4c](https://github.com/chipsalliance/rocket-chip/commit/8acd6b4cbb97740ca9cec683210389b1ebb72fb9)
- Canonical fix: [Rocket Chip PR #2832](https://github.com/chipsalliance/rocket-chip/pull/2832), merged as [f2f3a1b3](https://github.com/chipsalliance/rocket-chip/commit/f2f3a1b32643e1bb3a1a9f71ec04435da7b50924)
- Retrieved: 2026-09-10

## Failure mechanism

The affected base already included PR #1999's pending ReleaseAck and
address-qualified Probe block, but two independent omissions remained:

1. Incoming Probe protection was qualified by `release_ack_dirty`, so a
   clean voluntary Release was not protected.
2. Outgoing cached Acquire admission was not blocked for the address region
   covered by the outstanding Release.

The old incoming condition was equivalent to:

```scala
release_ack_wait &&
release_ack_dirty &&
(tl_out.b.bits.address ^ release_ack_addr)(idxMSB, idxLSB) === 0
```

As a result, a clean Release could still be followed by a ProbeAck, and a
local cached request could issue an Acquire before the ReleaseAck that
completed the prior Release.

## Necessary multi-client trigger

1. Hart A emits a voluntary clean or dirty Release and waits for
   ReleaseAck.
2. Hart B requests the same line or a conflicting ownership transition,
   causing the manager to send a Probe to Hart A.
3. The affected DCache can accept the Probe for a clean Release because the
   old predicate requires `release_ack_dirty`.
4. In the same protected Release window, Hart A can also issue a cached
   Acquire without the missing outgoing admission check.
5. The shared coherence manager can then observe a ProbeAck or Acquire that
   violates the TileLink Release ordering rule.

The external Probe/ownership transition requires a second coherent client;
the outgoing Acquire omission is in the same shared coherence ordering
window.

## Canonical fix and closure

PR #2832 removes the dirty-only qualification and applies an address-qualified
block to both incoming Probe handling and outgoing cached-request admission:

```scala
!(release_ack_wait &&
  (s2_req.addr ^ release_ack_addr)
    (((pgIdxBits + pgLevelBits) min paddrBits) - 1, idxLSB) === 0)
```

The incoming B-channel condition is likewise address-qualified without
`release_ack_dirty`. The four PR commits are merged as
`f2f3a1b32643e1bb3a1a9f71ec04435da7b50924`, whose history contains the
exact fixed implementation. The affected base already contains the full
PR #1999 change, so this is a later distinct ordering omission.

Source evidence:

- [affected `DCache.scala`](https://github.com/chipsalliance/rocket-chip/blob/86a2f2cca699f149bcc082ef2828654a0a4e3f4b/src/main/scala/rocket/DCache.scala)
- [fixed `DCache.scala`](https://github.com/chipsalliance/rocket-chip/blob/f2f3a1b32643e1bb3a1a9f71ec04435da7b50924/src/main/scala/rocket/DCache.scala)
- [PR #2832](https://github.com/chipsalliance/rocket-chip/pull/2832)

## Duplicate boundary

`ROCKET-DCACHE_RELEASEACK_PROBE` covers the earlier #1999 base and its
incoming Probe admission fix. This record begins after that fix and adds
clean-Release protection, expanded address qualification, and outgoing
Acquire blocking.
