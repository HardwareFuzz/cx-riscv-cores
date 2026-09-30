# std-cache AXI W valid could deadlock behind AW backpressure

- Record ID: `CVA6-STD-CACHE-AXI-WVALID-AWREADY-DEADLOCK`
- Core: CVA6
- Source repository: [openhwgroup/cva6](https://github.com/openhwgroup/cva6)
- Scope: shared standard-cache AXI fabric and independent I$/D$/bypass producers
- Record kind: canonical upstream CVA6 SystemVerilog RTL fix
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact affected parent, the AW/W RTL loop, the shared-producer trigger, and merged upstream PR #1360
- Affected parent: [885be3c1](https://github.com/openhwgroup/cva6/commit/885be3c1e45e2c1b687880d65b2161ea1830cdc0)
- Fixed revision: [03c14db7](https://github.com/openhwgroup/cva6/commit/03c14db7978a088f1289665b7467d477efe9d0e2)
- Canonical fix: [CVA6 PR #1360](https://github.com/openhwgroup/cva6/pull/1360), merged as `0da4dff148fff3fa1a385c43dbb4ee390ae19082`
- Retrieved: 2026-09-10

## Failure mechanism

At the affected parent, `core/cache_subsystem/std_cache_subsystem.sv`
merged independent `axi_req_icache`, `axi_req_bypass`, and `axi_req_data`
request sources into one upstream AXI interface. The write-data source was
selected through a non-fall-through FIFO that was pushed only after the
address channel handshook:

```systemverilog
.push_i (axi_req_o.aw_valid & axi_resp_i.aw_ready)
```

When the FIFO was empty, the old selector defaulted to source zero. The
`stream_mux` input order made that source the I$ write channel, which does
not provide the D$/bypass W beat required by a pending write.

AXI permits the downstream interface to present `aw_ready=0` while
`w_ready=1`. A D$ or bypass producer could then hold a valid AW/W pair while
the AW handshake was blocked. Since the FIFO was not fall-through and was
not pushed, the required W source was not propagated. The downstream waited
for the matching W transfer while the CVA6 path waited for AW progress,
leaving the transaction stuck.

## Necessary shared-fabric trigger

The affected subsystem has multiple independent request producers sharing
the AXI channels: I$ miss traffic, D$ data/refill traffic, and D$ bypass
traffic. The failure uses one of the D$/bypass producers together with the
shared downstream AW/W backpressure and source-selection fabric. It is a
shared-client AXI liveness failure, rather than an isolated instruction
pipeline calculation.

## Canonical fix and closure

Fix [03c14db7](https://github.com/openhwgroup/cva6/commit/03c14db7978a088f1289665b7467d477efe9d0e2)
made the W FIFO fall-through and selected the current AW source while the
FIFO was empty:

```systemverilog
.FALL_THROUGH (1'b1)

assign w_select_arbiter =
    w_fifo_empty ? (axi_req_o.aw_valid ? w_select : 0)
                 : w_select_fifo;
```

The current AW-associated W valid can therefore reach the downstream
interface before AW is accepted, breaking the AW/W dependency loop. PR
#1360 is merged in canonical upstream. Its merge commit is
`0da4dff148fff3fa1a385c43dbb4ee390ae19082`, whose parents are the exact
affected base and the fixed revision.

Source evidence:

- [affected `std_cache_subsystem.sv`](https://github.com/openhwgroup/cva6/blob/885be3c1e45e2c1b687880d65b2161ea1830cdc0/core/cache_subsystem/std_cache_subsystem.sv)
- [fixed `std_cache_subsystem.sv`](https://github.com/openhwgroup/cva6/blob/03c14db7978a088f1289665b7467d477efe9d0e2/core/cache_subsystem/std_cache_subsystem.sv)
- [PR #1360](https://github.com/openhwgroup/cva6/pull/1360)

## Duplicate boundary

This is distinct from `CVA6-STD-CACHE-AXI-W-FIFO-AW-ORDER`, whose later
affected base already contains the fall-through change and whose defect is
the stale FIFO entry left by an AW that waits while W completes. The present
record covers the earlier empty-FIFO AW/W deadlock.
