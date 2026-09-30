# CoupledL2 allowed RXSNP to race CMO rprobe/cmometaw work

- Record ID: `XIANGSHAN-COUPLEDL2-RXSNP_CMO_BLOCKING_RACE`
- Core: XiangShan / CoupledL2 (XSCache)
- Record kind: canonical upstream CoupledL2 CHI CMO/snoop blocking fix
- Source repository: [OpenXiangShan/CoupledL2](https://github.com/OpenXiangShan/CoupledL2)
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact RXSNP blocking-condition expansion and merged PR #370
- Scope: shared CHI remote snoop versus local CMO state transition
- Status: fixed in upstream history
- Evidence level: A
- Observed configuration: a local CMO MSHR and a remote RN-F RXSNP for the same line
- Affected revision: `ad488fab6d1549a58781cbfbc503a8c8fdb0bf1b`
- Fixed revision: `6194a1b0559c833ade717d9179881cdb04b6258c`

## Failure mechanism

The affected path is `src/main/scala/coupledL2/tl2chi/RXSNP.scala`, with
CMO state exported by `MSHR.scala`. Before the repair, `reqBlockSnpMask`
blocked an RXSNP only for refill/release-ack and a limited set of MSHR
states:

```scala
s.valid && s.bits.set === task.set && s.bits.reqTag === task.tag &&
  (s.bits.w_grantfirst || s.bits.aliasTask.getOrElse(false.B) &&
   !s.bits.w_rprobeacklast) &&
  (s.bits.blockRefill || s.bits.w_releaseack) && !s.bits.willFree
```

It did not block the interval in which a CMO MSHR was about to issue
WriteCleanFull/WriteBackFull/Evict or was issuing the compensating
`cmometaw` MainPipe task. During that interval the cache could silently
transition a clean TRUNK line to TIP (or update the metadata compensation)
while an incoming RXSNP for the same set/tag was admitted.

## Two-client trigger

1. RN-F A starts a CMO for line X; its CoupledL2 MSHR reaches the
   `rprobe`/release or `cmometaw` intermediate state.
2. RN-F B sends a remote CHI snoop for X at the same time.
3. The old RXSNP mask does not see the CMO intermediate state and lets the
   snoop proceed. The snoop can observe or update metadata while A's silent
   CMO transition is still in flight, creating an ordering/state race.

The remote RXSNP from RN-F B is necessary. A CMO by itself does not enter
the RXSNP path, and a single-client execution cannot create this race.

## Canonical fix

[6194a1b](https://github.com/OpenXiangShan/CoupledL2/commit/6194a1b0559c833ade717d9179881cdb04b6258c), merged as [PR #370](https://github.com/OpenXiangShan/CoupledL2/pull/370), exports `s_cmometaw` and expands the blocking predicate so that RXSNP is held during the CMO rprobe/cmometaw/WriteBackFull-Evict window:

```scala
s.bits.w_grantfirst ||
  s.bits.aliasTask.getOrElse(false.B) && !s.bits.w_rprobeacklast ||
  !s.bits.s_cmoresp && (!s.bits.w_rprobeacklast || !s.bits.s_cmometaw)
```

The fix is reachable from canonical CoupledL2 `origin/master`.

This is distinct from the existing XiangShan refill/Probe deadlock record:
that record covers L1 refill arbitration, while this one is the CoupledL2
RXSNP admission race with CMO's silent ownership/metadata transition.

## Source evidence

- Pre-fix paths: [`RXSNP.scala`](https://github.com/OpenXiangShan/CoupledL2/blob/ad488fab6d1549a58781cbfbc503a8c8fdb0bf1b/src/main/scala/coupledL2/tl2chi/RXSNP.scala) and [`MSHR.scala`](https://github.com/OpenXiangShan/CoupledL2/blob/ad488fab6d1549a58781cbfbc503a8c8fdb0bf1b/src/main/scala/coupledL2/tl2chi/MSHR.scala)
- Fix: [6194a1b](https://github.com/OpenXiangShan/CoupledL2/commit/6194a1b0559c833ade717d9179881cdb04b6258c)
- Upstream closure: [CoupledL2 PR #370](https://github.com/OpenXiangShan/CoupledL2/pull/370)
