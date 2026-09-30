# XiangShan out-of-order MIP reads hid an inter-core interrupt

- Record ID: XIANGSHAN-INTERCORE_MIP_CSR_ORDERING
- Core: XiangShan
- Scope: upstream
- Record kind: issue plus fix PR
- Source repository: [OpenXiangShan/XiangShan](https://github.com/OpenXiangShan/XiangShan)
- Source issue: [#5102 — bug in local interrupt behaviour](https://github.com/OpenXiangShan/XiangShan/issues/5102)
- Fix PR: [#5131 — fix CSR out-of-order read xip registers](https://github.com/OpenXiangShan/XiangShan/pull/5131)
- Fix commit: [153aa25a](https://github.com/OpenXiangShan/XiangShan/commit/153aa25ab6fa346685616e7c56db9fd1fb1ae3c1)
- Equivalent v3 fix: [5360a746](https://github.com/OpenXiangShan/XiangShan/commit/5360a746cb78d41ed1eacfa99028c3cc473dc079)
- Affected revision named by the issue: [master at the reported reproduction](https://github.com/OpenXiangShan/XiangShan/tree/58a45450fd3814b68acc144d2d89682d13a83dd3)
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the two-hart trace, maintainer root-cause explanation, and the merged v2/v3-equivalent scheduling fix
- Retrieved: 2026-09-09

## Two-hart trigger

The issue provides a two-hart trace. On Core 1, a memory-mapped operation
causes an inter-core interrupt, and a nearby CSR read observes `mip`. The
expected behavior is for the read to observe the interrupt state established
by the preceding memory operation. XiangShan's out-of-order CSR read path could
execute the `mip` read first, before the MMIO operation had committed.

The reported comparison was asymmetric: the RTL and reference started with
the same commit PC, but the Core 1 commit-group trace diverged around the
inter-core interrupt sequence. The maintainer explanation identifies the
ordering of the MMIO and `mip` read as the relevant failure mechanism.

This is a genuine multi-hart ordering problem rather than a generic CSR
compliance issue: one hart's MMIO operation changes interrupt state consumed by
another hart's architectural `mip` read, while the implementation permits the
read to bypass the operation.

## RTL mechanism and correction

The out-of-order CSR read classification in
`src/main/scala/xiangshan/backend/fu/NewCSR/CSROoORead.scala` did not include
the interrupt-pending CSR family. PR #5131 adds `mip`, `sip`, `vsip`, `hip`,
`hvip`, and `mvip` to both the backward and in-order blocking lists. The
resulting restriction prevents those CSR reads from being issued through the
out-of-order path when their value can depend on ordered interrupt/MMIO state.

The maintainer's issue comment says the problem was caused by out-of-order CSR
reads and links the fixing PR; the follow-up comment reports that the test case
passed with PR #5131. The merged commit changes the CSR scheduling list, which
is the relevant ordering boundary.

## Evidence limits

The public issue provides the two-core trace and the maintainer's explanation,
and the merged PR provides the targeted RTL correction. This census did not
rebuild the affected historical revision or independently replay the MMIO/
inter-core-interrupt test. The status is therefore based on the source issue,
review discussion, and exact merged diff rather than a local dynamic run.
