# CoupledL2 admitted a same-address Probe while ReleaseAck was outstanding

- Record ID: `XIANGSHAN-COUPLEDL2_TL2TL_PROBE_RELEASEACK_CONFLICT`
- Core: XiangShan / XSCache
- Source repository: [OpenXiangShan/XSCache](https://github.com/OpenXiangShan/XSCache)
- Record kind: canonical XSCache TL2TL coherence RTL fix
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact `SinkB.scala` conflict predicate and merged XSCache PR #208
- Scope: shared TL2TL replacement and Probe ordering
- Status: fixed in upstream history
- Evidence level: A
- Observed configuration: at least two independent RN-F/L2 clients, with one client replacing a line while its ReleaseAck is outstanding and another client causing a same-address Probe
- Parent revision: `d2c8a9a9bb61ab8f1ff27c149ed4b0942f2f319c`
- Fixed revision: `0d23d1fdbe175970482690d30282b92102a617d7`

## Failure mechanism

The affected path is `src/main/scala/coupledL2/tl2tl/SinkB.scala`. Its
`replaceConflictMask` compares an incoming Probe task with the set and tag of
each replacement MSHR. In the parent revision, the same-address conflict was
blocked only when both of these conditions were true:

```scala
s.bits.blockRefill && !s.bits.w_releaseack
```

After the refill-blocking phase had cleared but the replacement still awaited
`ReleaseAck`, the conjunction was false. The same-address Probe could
therefore be accepted while the replacement transaction was still in the
ReleaseAck window, contrary to the conflict exclusion required by the
replacement state machine.

## Runtime trigger

1. RN-F A starts a replacement Release for a cache line and does not yet
   receive its `ReleaseAck`.
2. The MSHR for A reaches the state where `blockRefill` is clear but
   `w_releaseack` remains false.
3. RN-F B requests the same line. The home node sends a Probe to RN-F A.
4. `SinkB` matches the same set and tag, but the old conjunction fails and
   admits the Probe into the outstanding ReleaseAck conflict window.

RN-F A supplies the outstanding replacement, while RN-F B supplies the
independent request that causes the peer Probe. Removing either client removes
this nested same-address interaction; this is not a single-client queue or
elaboration-only condition.

## Fix

PR #208 changes the predicate to block either side of the conflict:

```scala
s.bits.blockRefill || !s.bits.w_releaseack
```

The same-address Probe remains excluded until the replacement no longer has
either blocking condition.

## Distinction from other records

This record concerns TL2TL B-channel Probe admission while a replacement waits
for `ReleaseAck`. It is distinct from the CoupledL2 retry record that fixes
stale `CopyBackWrData` state, and from the RXSNP CMO record that extends a
different blocking predicate around `rprobe` and `cmometaw` work.

## Source evidence

- Pre-fix path: [`SinkB.scala`](https://github.com/OpenXiangShan/XSCache/blob/d2c8a9a9bb61ab8f1ff27c149ed4b0942f2f319c/src/main/scala/coupledL2/tl2tl/SinkB.scala)
- Fix: [0d23d1f](https://github.com/OpenXiangShan/XSCache/commit/0d23d1fdbe175970482690d30282b92102a617d7)
- Upstream closure: [XSCache PR #208](https://github.com/OpenXiangShan/XSCache/pull/208)
- Relevant diff: split the same-address replacement conflict from the refill-blocking condition.
