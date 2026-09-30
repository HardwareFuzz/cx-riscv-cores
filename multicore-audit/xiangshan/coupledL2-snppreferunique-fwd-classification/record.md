# XIANGSHAN-COUPLEDL2-SNPPREFERUNIQUEFWD-FORWARD-CLASSIFICATION

- Record ID: `XIANGSHAN-COUPLEDL2-SNPPREFERUNIQUEFWD-FORWARD-CLASSIFICATION`
- Core: XiangShan / CoupledL2 (XSCache)
- Source repository: https://github.com/OpenXiangShan/XSCache
- Scope: shared CHI SnpPreferUniqueFwd opcode classification, DCT forwarding, and RN-F ownership/data transfer
- Record kind: canonical upstream CoupledL2 CHI RTL fix
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Affected parent: [ea0c313041219d4f0017628dba15c45343c0ea38](https://github.com/OpenXiangShan/XSCache/commit/ea0c313041219d4f0017628dba15c45343c0ea38)
- Direct fix: [f29277493494e7a7c25475c78ff30f7c66a600d4](https://github.com/OpenXiangShan/XSCache/commit/f29277493494e7a7c25475c78ff30f7c66a600d4)
- Upstream PR: [XSCache PR #460](https://github.com/OpenXiangShan/XSCache/pull/460)
- Canonical closure: direct fix retained in XSCache origin/master at [468bad4927be1a2b7b6182b180ab647f63cf1b5d](https://github.com/OpenXiangShan/XSCache/commit/468bad4927be1a2b7b6182b180ab647f63cf1b5d); linear mainline closure
- Retrieved: 2026-09-11

## Failure mechanism

At the affected parent, [Opcode.scala](https://github.com/OpenXiangShan/XSCache/blob/ea0c313041219d4f0017628dba15c45343c0ea38/src/main/scala/coupledL2/tl2chi/chi/Opcode.scala) defines the CHI SnpPreferUniqueFwd opcode. The other classification helpers already recognize it as an invalidating forward snoop and as a unique snoop:

    def isSnpToNFwd(opcode: UInt): Bool = {
      opcode === SnpUniqueFwd ||
      opcode === SnpPreferUniqueFwd
    }

    def isSnpUniqueX(opcode: UInt): Bool = {
      opcode === SnpUnique ||
      opcode === SnpUniqueFwd ||
      opcode === SnpUniqueStash ||
      opcode === SnpPreferUnique ||
      opcode === SnpPreferUniqueFwd
    }

However, the same parent omits SnpPreferUniqueFwd from isSnpXFwd:

    def isSnpXFwd(opcode: UInt): Bool = {
      opcode === SnpSharedFwd ||
      opcode === SnpCleanFwd ||
      opcode === SnpOnceFwd ||
      opcode === SnpNotSharedDirtyFwd ||
      opcode === SnpUniqueFwd
    }

This creates a deterministic inconsistency between the CHI opcode classifications. The affected [MainPipe.scala](https://github.com/OpenXiangShan/XSCache/blob/ea0c313041219d4f0017628dba15c45343c0ea38/src/main/scala/coupledL2/tl2chi/MainPipe.scala) uses the omitted classification in the forwarding-control path:

    val expectFwd = isSnpXFwd(req_s3.chiOpcode.get)
    val doFwd = expectFwd && canFwd
    val need_dct_s3_b = doFwd

For SnpPreferUniqueFwd, isSnpXFwd evaluates to false. Therefore, for a directory hit with no tag or directory error, the affected logic deterministically produces:

    expectFwd = false
    doFwd = false
    need_dct_s3_b = false

The CoupledL2 does not allocate the DCT forwarding task required to transfer the line to the forwarding destination. The same MainPipe.scala path places SnpPreferUniqueFwd in neverRespData. Its response selection uses doFwd and doRespData in:

    MuxLookup(
      Cat(doFwd, doRespData),
      SnpResp
    )

With the omitted forward classification, the selection falls through to SnpResp rather than the forwarded response form SnpRespFwded or SnpRespDataFwded. The missing classification is not recovered by the data-response path because this opcode is handled by the neverRespData path while the forward-data decision still depends on isSnpXFwd.

The affected [MSHR.scala](https://github.com/OpenXiangShan/XSCache/blob/ea0c313041219d4f0017628dba15c45343c0ea38/src/main/scala/coupledL2/tl2chi/MSHR.scala) uses the same helper for both the forward decision and the hit-release decision:

    val doFwd = isSnpXFwd(req_chiOpcode) && dirResult.hit
    val doFwdHitRelease = isSnpXFwd(req_chiOpcode) && hitWriteX

Consequently, the omitted opcode also prevents the MSHR-side forward and forward-hit-release control paths from recognizing a valid SnpPreferUniqueFwd transaction. The affected opcode, forward predicate, DCT allocation, and response opcode are therefore inconsistent across the CoupledL2 CHI RTL.

## Concrete multi-client trigger

The confirmed trigger is a shared CHI ownership/data-forward transaction with three distinct roles:

1. RN-F A is the snoopee and holds the target cache line. The shared HN-F directory records the line in a state requiring a snoop to A.
2. Independent RN-F B requests the line with a transaction requiring unique ownership and is selected as the forwarding destination.
3. The shared HN-F sends SnpPreferUniqueFwd to RN-F A, requesting that A forward the line to RN-F B.
4. RN-F A's CoupledL2 receives the directory-hit snoop. At the affected parent, isSnpXFwd(SnpPreferUniqueFwd) is false, so A does not allocate the DCT forwarding task and selects the non-forward SnpResp response semantics.
5. The shared HN-F transaction consequently does not receive the forwarded response/data semantics required for the ownership and data transfer from RN-F A to RN-F B.

This is genuinely a multi-client CHI failure. SnpPreferUniqueFwd is issued by the shared HN-F specifically to coordinate a line transfer between the snoopee RN-F A and the independent requesting/forwarding-destination RN-F B. The failing path requires the two RN-F endpoints and the shared HN-F coherence manager; it is not a local single-client request or a private cache response.

## Direct fix

The direct fix [f29277493494e7a7c25475c78ff30f7c66a600d4](https://github.com/OpenXiangShan/XSCache/commit/f29277493494e7a7c25475c78ff30f7c66a600d4) adds the missing opcode to isSnpXFwd in [Opcode.scala](https://github.com/OpenXiangShan/XSCache/blob/f29277493494e7a7c25475c78ff30f7c66a600d4/src/main/scala/coupledL2/tl2chi/chi/Opcode.scala):

    def isSnpXFwd(opcode: UInt): Bool = {
      opcode === SnpSharedFwd ||
      opcode === SnpCleanFwd ||
      opcode === SnpOnceFwd ||
      opcode === SnpNotSharedDirtyFwd ||
      opcode === SnpUniqueFwd ||
      opcode === SnpPreferUniqueFwd
    }

The fixed downstream control paths remain visible in the fixed [MainPipe.scala](https://github.com/OpenXiangShan/XSCache/blob/f29277493494e7a7c25475c78ff30f7c66a600d4/src/main/scala/coupledL2/tl2chi/MainPipe.scala) and [MSHR.scala](https://github.com/OpenXiangShan/XSCache/blob/f29277493494e7a7c25475c78ff30f7c66a600d4/src/main/scala/coupledL2/tl2chi/MSHR.scala) source paths. Once the opcode is included, a valid directory-hit, no-error request evaluates expectFwd = true, doFwd = true, and need_dct_s3_b = true; the MSHR forward paths and forwarded response opcode selection then use the intended CHI semantics.

## Duplicate boundary

This record is distinct from XIANGSHAN-COUPLEDL2-SNPUNIQUEFWD-ILLEGAL-DCT-RESP. That existing record concerns SnpUniqueFwd after the forwarding path has already been selected: its mechanism is an illegal DCT response and FwdState combination. The present record concerns the earlier opcode-classification omission for SnpPreferUniqueFwd, which prevents the forward path from being selected at all, prevents DCT forwarding allocation, and selects SnpResp instead of a forwarded response. The opcode, control predicate, failure stage, and direct fix are different.

## Canonical fix and closure

The direct fix is the exact child of the affected parent and was submitted through [XSCache PR #460](https://github.com/OpenXiangShan/XSCache/pull/460). The linear mainline history retains the fix at canonical origin/master commit [468bad4927be1a2b7b6182b180ab647f63cf1b5d](https://github.com/OpenXiangShan/XSCache/commit/468bad4927be1a2b7b6182b180ab647f63cf1b5d). The fixed [Opcode.scala](https://github.com/OpenXiangShan/XSCache/blob/468bad4927be1a2b7b6182b180ab647f63cf1b5d/src/main/scala/coupledL2/tl2chi/chi/Opcode.scala) contains the completed isSnpXFwd classification, closing the affected CHI RTL path in canonical upstream history.
