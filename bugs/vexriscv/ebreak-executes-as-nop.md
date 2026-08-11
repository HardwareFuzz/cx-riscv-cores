# VexRiscv fuzz build: `ebreak` executes as NOP instead of raising a breakpoint exception (mcause=3)

> Status: **draft** — record of a local VexRiscv config bug found and fixed in the HardwareFuzz
> `cx-riscv-cores` fork of VexRiscv (submodule branch `cx-build`, commit 60b3cb202bfcb380d1f9209168bd9a061172dec1).
> Dated 2026-08-11; already fixed and verified (see "Fix verification" at the end).

---

**Title:** [BUG] `ebreak` (0x00100073) executes as a NOP in the fuzz-build VexRiscv instead of raising a breakpoint exception (mcause=3)

## Description

Per the RISC-V unprivileged spec (Chapter "Zicsr, Zifencei, and Privileged ISA" — the *RISC-V
Instruction Set Manual, Volume I: Unprivileged ISA*, and the *Privileged ISA* spec's
"Environment Call and Breakpoint" section), the `ebreak` instruction (encoding `0x00100073`) **must**
raise a breakpoint exception:

> "The `EBREAK` instruction is used by debuggers to cause control to be transferred back to a
> debugging environment... **It causes an unconditional breakpoint exception**."

For a bare-metal/machine-mode configuration the exception is reported as `mcause = 3` (Breakpoint)
in the `mcause` CSR and control transfers to the handler at `mtvec`.

The VexRiscv core used by the HardwareFuzz diff-fuzz framework executes `ebreak` as a NOP instead.
Spike (the reference model in the framework) correctly traps with `mcause=3`. The diff-fuzz
framework compares the DUT against Spike, so any testcase that reaches an `ebreak` produces a
**false positive** — Spike reports an exception while VexRiscv silently falls through to the next
instruction, so architectural state diverges.

## Root cause chain

1. `cores/VexRiscv/src/main/scala/vexriscv/plugin/CsrPlugin.scala:63` — the `CsrPluginConfig` case
   class defaults `ebreakGen: Boolean = false` (software `ebreak` support off; only JTAG/hardware
   ebreak via `withPrivilegedDebug` would otherwise enable it, see
   `CsrPlugin.scala:92` `def withEbreak = ebreakGen || withPrivilegedDebug`).
2. `cores/VexRiscv/src/main/scala/vexriscv/plugin/CsrPlugin.scala:203` — the `linuxFull` preset used
   by the fuzz builds explicitly sets `ebreakGen = false`. (`linuxFull` is defined at
   `CsrPlugin.scala:180`.)
3. `cores/VexRiscv/src/main/scala/vexriscv/demo/GenMax.scala:88`,
   `cores/VexRiscv/src/main/scala/vexriscv/demo/GenMaxRv32F.scala:86`, and
   `cores/VexRiscv/src/main/scala/vexriscv/demo/GenMaxRv32.scala:82` each instantiate
   `new CsrPlugin(CsrPluginConfig.linuxFull(0x80000020l))`. These three `GenMax*` objects are the
   netlist generators for the fuzz builds (`rv32fd` = `GenMax`, `rv32f` = `GenMaxRv32F`).
4. With `withEbreak == false`, `CsrPlugin.scala:602` does **not** register the `EBREAK` environment
   control: `if(withEbreak) decoderService.add(EBREAK, ...)`. Consequently:
   - `CsrPlugin.scala:496` (`val EBREAK = if(withEbreak) newElement() else null`) stays null,
   - the ebreak instruction is decoded with `ENV_CTRL = EnvCtrlEnum_NONE` and simply **retires
     without side effect** (a NOP),
   - `CsrPlugin.scala:1596` — `if(withEbreak) when(arbitration.isValid && input(ENV_CTRL) ===
     EnvCtrlEnum.EBREAK && allowEbreakException){ selfException.valid := True; selfException.code := 3 }`
     — is never generated.
   Note `CsrPlugin.scala:556-557` even emits a SpinalWarning for such configs: "This VexRiscv
   configuration is set without software ebreak instruction support."
5. Netlist reflection — in the generated `cores/VexRiscv/VexRiscv.v` (from `sbt runMain GenMax`)
   the pre-fix netlist has only:
   ```
   localparam EnvCtrlEnum_NONE = 2'd0; localparam EnvCtrlEnum_XRET = 2'd1;
   localparam EnvCtrlEnum_WFI = 2'd2;  localparam EnvCtrlEnum_ECALL = 2'd3;
   ```
   and no `CsrPlugin_selfException_payload_code = 4'b0011` assignment (the mcause=3 source). The
   ebreak opcode therefore contributes nothing to the decode.

Note: the 2-core SMP fuzz build is *not* affected — `vexriscv.demo.smp.VexRiscvSmpCluster.scala`
uses `CsrPluginConfig.openSbi(...)` (`ebreakGen = true`, line 122) or the explicit `ebreakGen = true`
at `VexRiscvSmpCluster.scala:300`, so the SMP netlist already contains the EBREAK decode. The bug is
exclusive to the 1-core `GenMax*` path.

## Repro / observed behavior

Minimal test image: an ELF loaded at `0x80000000` (the fuzz-build reset vector) that installs a trap
handler into `mtvec` then executes `ebreak`:

```
80000000  auipc t0,0x0
80000004  addi  t0,t0,24      # t0 = trap_handler
80000008  csrw  mtvec,t0
8000000c  ebreak
8000000e  lui   a0,0xdeadc    # fall-through marker (only reached if ebreak is a NOP)
80000012  addi  a0,a0,-273    # a0 = 0xdeadbeef
80000016  j     80000016
80000018  csrr  a1,mcause     # trap_handler: record mcause
8000001c  j     8000001c
```

Run through the pre-fix 1-core binary `vexriscv_rv32fd_1c` (built 2026-08-08):

- stdout: only `BOOT`; the process runs forever (falls through into the `j .` loop at `80000016`),
  **no** `EXC ... cause=3` line.
- register trace (`run.regTrace`):
  ```
  PC 8000000c ... retired=1 trap=0 event=inst_terminal     <- ebreak COMMITTED as a NOP
  PC 8000000e : reg[10] = deadc000 ... retired=1 trap=0
  PC 80000012 : reg[10] = deadbeef ... retired=1 trap=0    <- fall-through marker written
  ```
  i.e. the ebreak committed with `trap=0` and execution continued to the next instruction.

Expected behavior (Spike, and the fixed core): a breakpoint exception with `mcause=3`, no
fall-through.

## Proposed fix (applied)

Enable software ebreak generation in the `linuxFull` CSR preset used by the fuzz netlists —
`cores/VexRiscv/src/main/scala/vexriscv/plugin/CsrPlugin.scala`, `linuxFull` block, line 203:

```diff
     noCsrAlu            = false,
     wfiGenAsNop         = false,
-    ebreakGen           = false,
+    ebreakGen           = true,
     userGen             = true,
```

This is the config-level fix; the build pipeline is reproducible
(`build.sh --isa rv32fd --cores 1` runs `sbt runMain vexriscv.demo.GenMax`, which re-emits
`VexRiscv.v` via SpinalHDL, then Verilator consumes it — see
`cores/VexRiscv/build.sh:202-217` and `src/test/cpp/regression/makefile:3`
`VEXRISCV_FILE?=../../../../VexRiscv.v`). No change was made to the generated `VexRiscv.v` by hand,
and no change was made to the simulator harness (`src/test/cpp/regression/main.cpp` /
`main_smp.cpp`), so the runtime interface (ELF/HEX input, trace output format, VCD) is unchanged.

## Fix verification

Post-fix netlist `cores/VexRiscv/VexRiscv.v` (regenerated via `sbt runMain vexriscv.demo.GenMax`):

- `localparam EnvCtrlEnum_EBREAK = 3'd4;` now present alongside the existing three env ctrls.
- `assign when_CsrPlugin_l1596 = ((execute_arbitration_isValid && (execute_ENV_CTRL == EnvCtrlEnum_EBREAK)) && CsrPlugin_allowEbreakException);`
- `CsrPlugin_selfException_payload_code = 4'b0011;` (mcause = 3, Breakpoint) now assigned under
  `if(when_CsrPlugin_l1596)`.
- ebreak decode routes `ENV_CTRL` to `EBREAK` (decoder now has the `EBREAK` entry registered per
  `CsrPlugin.scala:602`).

Rebuilt binaries (from `./build.sh --isa rv32fd --cores 1|2 --out-dir .../artifacts`):

- `/home/canxin/Git/riscv_research/cx-riscv-cores/artifacts/vexriscv_rv32fd_1c` — rebuilt 2026-08-11 (was 2026-06-04).
- `/home/canxin/Git/riscv_research/cx-riscv-cores/artifacts/vexriscv_rv32fd_2c` — rebuilt 2026-08-11 (was 2026-06-07; SMP path already had `ebreakGen=true`, rebuilt for consistency and confirmed non-regressing).

Functional verification (same test ELF as above):

- Post-fix 1-core binary stdout:
  ```
  BOOT
  EXC pc=0x8000000c cause=3 clk_start=147 clk_end=150 clk_span=4 hart=0 token=3 commit_slot=0 retired=0 trap=1 event=inst_terminal start_kind=backend_alloc end_kind=precise_trap
  ```
  `pc=0x8000000c` is exactly the `ebreak` instruction; `cause=3` is the breakpoint exception. The
  instruction retires with `trap=1`, and execution transfers to the trap handler
  (`csrr a1, mcause` at `0x80000018` commits; core spins in the handler loop).
- Post-fix register trace: the fall-through markers `deadc000`/`deadbeef` at `PC 8000000e` /
  `80000012` are **absent** (ebreak no longer commits as a NOP).
- Post-fix 2-core SMP binary: both harts trap into the handler loop (`PC 8000001c` committed
  ~467k times per hart, `PC 8000000e`/`80000012` fall-through count = 0), so the 2-core build is
  confirmed non-regressed and already correct.
