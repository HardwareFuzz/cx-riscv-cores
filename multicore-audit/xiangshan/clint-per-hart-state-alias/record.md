# XiangShan CLINT aliased timer and software-interrupt state across harts

- Record ID: `XIANGSHAN-CLINT_PER_HART_STATE_ALIAS`
- Core: XiangShan
- Scope: shared CLINT per-hart timer and software-interrupt state
- Record kind: canonical upstream multicore CLINT SystemVerilog/Chisel integration fix
- Source repository: [OpenXiangShan/XiangShan](https://github.com/OpenXiangShan/XiangShan)
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the scalar pre-fix CLINT state, the dual-core register-map correction, and merged PR #393
- Status: fixed in upstream history
- Evidence level: A
- Observed configuration: two or more XiangShan harts sharing the top-level `TLTimer`
- Affected revision: `e90d257d80eb8b4b974161893161692b596bbff9`
- Fixed revision: `0668d426e62fc2b88ac5e3cf9661d6d838b3e904`

## Failure mechanism

The affected paths are `src/main/scala/device/TLTimer.scala` and
`src/main/scala/system/SoC.scala`. Before the repair, the timer exposed
scalar interrupts and held only one timer/software-interrupt state:

```scala
val io = IO(new Bundle() {
  val mtip = Output(Bool())
  val msip = Output(Bool())
})
...
val mtimecmp = RegInit(0.U(64.W))
val msip = RegInit(0.U(64.W))
```

The one `mtimecmp` and one `msip` register were shared by all harts, and the
SoC fanned the same scalar `mtip` and `msip` outputs into every core. One hart
writing a CLINT entry could therefore change the timer/software interrupt
seen by every other hart.

## Two-hart trigger

1. Instantiate two harts using the shared `TLTimer` and program independent
   CLINT clients: hart 0 writes its timer/software-interrupt state while
   hart 1 observes its own state.
2. Set different timer deadlines or write the software-interrupt registers
   from only one hart.
3. In the pre-fix implementation, both harts receive the same scalar timer
   and software-interrupt outputs, and both register operations target the
   single shared state. A hart-specific interrupt cannot remain independent.

The defect is absent in a one-hart instance, where one state and one output
are sufficient. The second hart is necessary to observe the aliasing.

## Canonical fix and deduplication

[0668d42](https://github.com/OpenXiangShan/XiangShan/commit/0668d426e62fc2b88ac5e3cf9661d6d838b3e904), merged as part of [PR #393](https://github.com/OpenXiangShan/XiangShan/pull/393), allocates `mtimecmp(i)` and `msip(i)` for every core, maps the per-hart CLINT addresses, emits `Vec(NumCores, Bool())` interrupts, and connects hart `i` to the matching `mtip(i)`/`msip(i)` output. The shared `mtime` counter is intentionally retained and is not part of this defect.

This is distinct from `CVA6-MULTICORE_CLINT_TIMER_IRQ` in CVA6: the
present record concerns XiangShan's scalar-to-vector CLINT state and SoC
connections, while the CVA6 record concerns a packed-array comparison bug in
a different implementation.

## Source evidence

- Pre-fix paths: [`TLTimer.scala`](https://github.com/OpenXiangShan/XiangShan/blob/e90d257d80eb8b4b974161893161692b596bbff9/src/main/scala/device/TLTimer.scala) and [`SoC.scala`](https://github.com/OpenXiangShan/XiangShan/blob/e90d257d80eb8b4b974161893161692b596bbff9/src/main/scala/system/SoC.scala)
- Fix: [0668d42](https://github.com/OpenXiangShan/XiangShan/commit/0668d426e62fc2b88ac5e3cf9661d6d838b3e904)
- Upstream closure: [XiangShan PR #393](https://github.com/OpenXiangShan/XiangShan/pull/393)
