# CLINT MSIP fields lost the per-hart four-byte stride

- Record ID: ROCKET-CLINT_MSIP_STRIDE
- Core: Rocket Chip
- Source repository: [chipsalliance/rocket-chip](https://github.com/chipsalliance/rocket-chip)
- Record kind: canonical upstream CLINT generator fix
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the multi-hart address-map regression and exact width/padding correction
- Scope: CLINT software-interrupt address routing
- Status: fixed in upstream history
- Evidence level: A
- Observed configuration: a CLINT with more than one hart
- Affected revision: [1d95fcc](https://github.com/chipsalliance/rocket-chip/commit/1d95fcc882b1761ad2d0a2572dc8938aca805ef), the exact ipiWidth regression; its descendants before
  `afd93df40e3a9b4196a1c75487ec9e0db6c747f3`
- Fixed revision: afd93df40e3a9b4196a1c75487ec9e0db6c747f3

## Symptom

The standard CLINT map gives each MSIP register a four-byte slot. A
regression changed ipiWidth from 32 to 1, so successive one-bit RegFields
could be packed next to each other. Software writing MSIP plus four times the
hart number could therefore address the wrong field for hart 1 and later.

## Trigger

Boot at least two harts and write the standard CLINT MSIP addresses
independently. Check that an IPI sent to hart 1 does not set hart 0 or another
hart's software-interrupt bit.

## Root cause

The field width was incorrectly used as the address stride. A one-bit field
does not mean that the register occupies one bit in the memory map.

## Fix

The fix restores ipiWidth to 32 and represents each MSIP as a one-bit field
followed by 31 bits of padding. Every hart consequently occupies one
four-byte register slot.

## Verification

Run per-hart MSIP write/read tests for at least four harts, including writes
to nonadjacent entries, and observe the corresponding mip.MSIP bit in each
hart. The current source contains the fixed shape; this audit did not run the
test.

## Source evidence

- Local source: src/main/scala/devices/tilelink/CLINT.scala.
- Commits: [1d95fcc](https://github.com/chipsalliance/rocket-chip/commit/1d95fcc882b1761ad2d0a2572dc8938aca805ef1) (regression) and
  [afd93df](https://github.com/chipsalliance/rocket-chip/commit/afd93df40e3a9b4196a1c75487ec9e0db6c747f3) (fix).
- Relevant diff: ipiWidth=32 and 31-bit padding per MSIP field.
