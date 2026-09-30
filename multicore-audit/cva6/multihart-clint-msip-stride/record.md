# CVA6 CLINT used the wrong per-hart stride for MSIP

- Record ID: `CVA6-MULTIHART_CLINT_MSIP_STRIDE`
- Core: CVA6
- Scope: multi-hart CLINT software-interrupt routing
- Record kind: canonical upstream SystemVerilog CLINT RTL fix
- Source repository: [openhwgroup/cva6](https://github.com/openhwgroup/cva6)
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the pre-fix and fixing RTL, the exact multi-hart address decode, and merged CVA6 PR #188
- Status: fixed in upstream history
- Evidence level: A
- Observed configuration: `NR_CORES >= 2` with the standard per-hart MSIP memory map
- Affected revision: `0c47db86118a043aeb55694d7519e7bfd490508f`
- Fixed revision: `07df142624b7e4c580410db73a78d43d53085580`

## Failure mechanism

The affected implementation is `src/clint/clint.sv`. In the affected
revision, the MSIP decode treated each software-interrupt register as an
eight-byte slot:

```systemverilog
[MSIP_BASE:MSIP_BASE+8*NR_CORES]
msip_n[$unsigned(address[AddrSelWidth-1+3:3])] = wdata[0];
```

The architectural CLINT layout uses a four-byte MSIP slot for each hart. The
decoder consequently selected the wrong hart for an access to hart 1 and
later harts, and the address range also described the wrong register layout.
The read path used the same incorrect slot selection. This is an actual
runtime register-addressing error: an IPI write intended for one hart can
update another `msip_q` bit or fail to address the intended bit.

## Two-hart trigger

1. Instantiate the CLINT with `NR_CORES = 2` or greater.
2. From the shared bus, write the standard four-byte MSIP address belonging to
   hart 1, then observe `ipi_o[1]` and `ipi_o[0]`.
3. The affected decoder uses address bit 3 as the hart selector instead of
   bit 2. The hart-1 slot is therefore not decoded according to the standard
   per-hart map; the corresponding read path has the same defect.

With one core there is no higher-hart slot whose address can be misdecoded.
The second hart is therefore necessary to expose the per-hart routing error.

## Fix

The merged fix in PR #188 changes both MSIP ranges from `8*NR_CORES` to
`4*NR_CORES`, selects the hart with
`address[AddrSelWidth-1+2:2]`, and uses the low address bit to select the
appropriate 32-bit half of the 64-bit AXI data beat:

```systemverilog
[MSIP_BASE:MSIP_BASE+4*NR_CORES]
msip_n[$unsigned(address[AddrSelWidth-1+2:2])] = wdata[32*address[2]];
```

The same correction is applied to MSIP reads. Timer compare registers remain
on their separate eight-byte layout; this record is only about MSIP/IPI
addressing and is distinct from the existing CVA6 timer-interrupt record.

## Source evidence

- Pre-fix CLINT source: [`src/clint/clint.sv`](https://github.com/openhwgroup/cva6/blob/0c47db86118a043aeb55694d7519e7bfd490508f/src/clint/clint.sv)
- Fix: [07df1426](https://github.com/openhwgroup/cva6/commit/07df142624b7e4c580410db73a78d43d53085580)
- Upstream closure: [CVA6 PR #188](https://github.com/openhwgroup/cva6/pull/188)
