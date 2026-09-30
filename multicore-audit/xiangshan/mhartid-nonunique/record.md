# XiangShan reported the same `mhartid` for every core

- Record ID: `XIANGSHAN-MHARTID_NONUNIQUE`
- Core: XiangShan
- Scope: architectural per-hart CSR identity
- Record kind: canonical upstream multicore CSR implementation fix
- Source repository: [OpenXiangShan/XiangShan](https://github.com/OpenXiangShan/XiangShan)
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the literal-zero pre-fix CSR state, the merged dual-core PR #393, and the later per-core hart-ID IO correction
- Status: fixed in upstream history
- Evidence level: A
- Observed configuration: two or more XiangShan cores reading the architectural `mhartid` CSR
- Affected revision: `296bfcd2a1cff7bb0ba5656323c36b7865a28826`
- Initial fixed revision: `e90d257d80eb8b4b974161893161692b596bbff9`
- Canonical per-core follow-up: `7a77cff24dc51dba9a6f986195acd7aab4cd5578`

## Failure mechanism

The affected path is `src/main/scala/xiangshan/backend/fu/CSR.scala`. The
pre-fix CSR already exposed the architectural `mhartid` address, but every
CSR instance initialized it to zero:

```scala
val mhartid = RegInit(UInt(XLEN.W), 0.U) // the hardware thread running the code
```

As a result, independently instantiated cores did not have distinct
architectural identities. Software running on hart 1 or any later hart read
zero just like hart 0, so hart-indexed startup, interrupt, and scheduler
state could be assigned to the wrong CPU.

## Two-hart trigger

1. Instantiate two XiangShan cores and execute `csrr mhartid` on each core.
2. Hart 0 reads zero, as expected for the first hart, but hart 1 also reads
   zero in the affected revision.
3. Use the returned values for per-hart startup or interrupt routing; the
   two architectural clients now alias the same hart identity.

The second core is necessary: a single core whose architectural ID is zero
does not reveal the duplicate-identity defect.

## Canonical fix and deduplication

The dual-core support merge [PR #393](https://github.com/OpenXiangShan/XiangShan/pull/393), merge commit [666dc712](https://github.com/OpenXiangShan/XiangShan/commit/666dc712f44575ff5b5fba8258106cbce6349ed4d), includes [e90d257](https://github.com/OpenXiangShan/XiangShan/commit/e90d257d80eb8b4b974161893161692b596bbff9), which initially assigns distinct elaborated hart numbers. The canonical follow-up [7a77cff](https://github.com/OpenXiangShan/XiangShan/commit/7a77cff24dc51dba9a6f986195acd7aab4cd5578) replaces the global elaboration counter with an explicit per-core `hartId` IO:

```scala
val mhartid = RegInit(UInt(XLEN.W), csrio.hartId)
```

The two commits are one fix chain for the same architectural identity
defect. The later IO-based form is the robust canonical multi-core
connection, not a separate record.

## Source evidence

- Pre-fix path: [`CSR.scala`](https://github.com/OpenXiangShan/XiangShan/blob/296bfcd2a1cff7bb0ba5656323c36b7865a28826/src/main/scala/xiangshan/backend/fu/CSR.scala)
- Initial dual-core fix: [e90d257](https://github.com/OpenXiangShan/XiangShan/commit/e90d257d80eb8b4b974161893161692b596bbff9)
- Per-core IO follow-up: [7a77cff](https://github.com/OpenXiangShan/XiangShan/commit/7a77cff24dc51dba9a6f986195acd7aab4cd5578)
- Upstream closure: [XiangShan PR #393](https://github.com/OpenXiangShan/XiangShan/pull/393)
