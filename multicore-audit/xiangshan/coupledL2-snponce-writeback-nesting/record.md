# CoupledL2 could lose dirty data when `SnpOnce*` nested a writeback

- Record ID: `XIANGSHAN-COUPLEDL2_SNPONCE_WRITEBACK_NESTING`
- Core: XiangShan / CoupledL2
- Scope: shared CHI `SnpOnce`/`SnpOnceFwd` and writeback nesting
- Record kind: canonical upstream CoupledL2 CHI RTL fix
- Source repository: [OpenXiangShan/CoupledL2](https://github.com/OpenXiangShan/CoupledL2)
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the merged PR's state table, explicit failure description, and exact MSHR/MainPipe/RXSNP corrections in PR #309
- Status: fixed in upstream history
- Evidence level: A
- Observed configuration: at least two RN-F clients sharing the CoupledL2 home node
- Affected revision: `56d5cf82b2159f0e8b83bb7db2f9ad566a86dd89`
- Fixed revision: `394b7392f5899ae277b0ff55b9ad694afbf3e4f9`

## Failure mechanism

The affected CoupledL2 CHI path allowed `SnpOnce` or `SnpOnceFwd` to nest an
in-flight writeback without applying the complete CHI state/data rules. The
upstream fix records two coupled failures in this exact nested protocol
case:

1. For a dirty writeback, `CopyBackWrData(Dirty)` could be marked invalid and
   `SnpOnceFwd` could omit data to the home node. Because the peer RN also
   does not retain data for that forwarding opcode, the dirty line could be
   absent from both the home node and the RN set. A later Grant could then
   obtain erroneous data from the lower level.
2. When a writeback nested `SnpOnce`, the directory metadata was not changed
   to `TIP`. A later `SnpUnique` could therefore see `TRUNK` rather than `TIP`
   and fail to invalidate the line; a subsequent L1 acquire could obtain
   permission locally without the required lower-level acquisition.

The fix's state table distinguishes initial `I`, `UC`, `UD`, and `SC` states,
whether the opcode is forwarded, and whether the snoop is nested. The RTL
changes add the missing `probeDirty` propagation, `SnpOnce`/`SnpOnceFwd`
response cases, and the `TIP` metadata update for a nested writeback.

## Two-client trigger

1. RN-F A holds or emits a dirty writeback/replacement transaction for a line.
2. RN-F B issues a request that makes the home node send `SnpOnce` or
   `SnpOnceFwd` to A while A's writeback is active.
3. The nested snoop takes the affected response and metadata path. The dirty
   data can be retained by neither the home node nor the peer RN, or the
   directory can retain the wrong `TRUNK` state.
4. A later peer operation such as Grant or `SnpUnique` observes the lost data
   or stale permission state.

The CHI implementation's peer-RN directory path supplies the nested snoop,
so RN-F B is necessary in addition to RN-F A's writeback. This is a true
two-client protocol interaction, not an internal retry of one MSHR.

## Fix and deduplication

The merged PR #309 updates `Common.scala`, both CHI and legacy TL2TL MSHR/
MainPipe paths, `RXSNP.scala`, and the CHI opcode helpers. It explicitly
implements the `SnpOnceX`-writeback state table and sets nested writeback
metadata to `TIP` with no clients. This record combines the two failures
because they are the single nested `SnpOnce*`-writeback protocol correction
closed by that PR.

It is distinct from the existing `SNP_ONCE_DIRTY_DATA_INHERITANCE` record,
which concerns ordinary `SnpOnce` dirty-state inheritance without an
in-flight writeback, and from the existing SnpStash, WriteCleanFull, and
directory-miss nested records.

## Source evidence

- Pre-fix paths: [`src/main/scala/coupledL2/tl2chi/MSHR.scala`](https://github.com/OpenXiangShan/CoupledL2/blob/56d5cf82b2159f0e8b83bb7db2f9ad566a86dd89/src/main/scala/coupledL2/tl2chi/MSHR.scala), [`src/main/scala/coupledL2/tl2chi/RXSNP.scala`](https://github.com/OpenXiangShan/CoupledL2/blob/56d5cf82b2159f0e8b83bb7db2f9ad566a86dd89/src/main/scala/coupledL2/tl2chi/RXSNP.scala)
- Fix: [394b7392](https://github.com/OpenXiangShan/CoupledL2/commit/394b7392f5899ae277b0ff55b9ad694afbf3e4f9)
- Upstream closure: [CoupledL2 PR #309](https://github.com/OpenXiangShan/CoupledL2/pull/309)
