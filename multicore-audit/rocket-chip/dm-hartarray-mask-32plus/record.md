# Debug hart-array masks overflowed Scala Int arithmetic at 32 harts

- Record ID: `ROCKET-DM_HARTARRAY_MASK_32PLUS`
- Core: Rocket Chip
- Source repository: [chipsalliance/rocket-chip](https://github.com/chipsalliance/rocket-chip)
- Scope: multi-hart Debug Module HAWINDOW/HAMASK generation
- Record kind: canonical upstream Debug Module generator fix
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact affected parent, the Scala mask arithmetic, the 32-plus-hart trigger, and the canonical mainline fix
- Affected parent: [373f78d7](https://github.com/chipsalliance/rocket-chip/commit/373f78d7d5a288633920c63112086d70622c1188)
- Fixed revision: [579e60a0](https://github.com/chipsalliance/rocket-chip/commit/579e60a08e96373d93ff09d6070377a015f2efba), `Support >= 32 cores in debug unit (#2173)`
- Canonical closure: direct mainline commit [579e60a0](https://github.com/chipsalliance/rocket-chip/commit/579e60a08e96373d93ff09d6070377a015f2efba), referencing issue #2170
- Retrieved: 2026-09-10

## Failure mechanism

The affected Debug Module generated HAWINDOW slices with Scala `Int`
arithmetic:

```scala
val sliceMask =
  if (nComponents > ((ii * haWindowSize) + haWindowSize - 1))
    0xFFFFFFFF
  else
    (1 << (nComponents - (ii * haWindowSize))) - 1
```

For a Debug Module with 32 or more hart components, the full-slice literal
and shift can overflow or become sign-limited before the Chisel hardware
literal is created. The generated hart-array presence mask can consequently
misidentify high-numbered harts or their addressability.

## Necessary multi-hart trigger

1. Instantiate the Debug Module with at least 32 hart components.
2. An external debugger reads the HAWINDOW/HAMASK hart-array window,
   including a full or partial high slice.
3. The affected generator emits an incorrect presence mask from the
   `Int`-limited calculation.
4. The debugger can misidentify which high-numbered harts exist or can be
   selected.

The defect is intrinsically multi-hart: the failing configuration is the
32-plus-component Debug Module, not a single-hart use of the generator.

## Canonical fix and closure

The fixed generator uses arbitrary-precision `BigInt` arithmetic:

```scala
val sliceMask =
  if (nComponents > ((ii * haWindowSize) + haWindowSize - 1))
    (BigInt(1) << haWindowSize) - 1
  else
    (BigInt(1) << (nComponents - (ii * haWindowSize))) - 1
```

This produces the correct full and partial HAWINDOW masks beyond the Scala
32-bit boundary. Commit `579e60a08e96373d93ff09d6070377a015f2efba` is the
canonical mainline landing commit and its direct parent is the exact
affected revision `373f78d7d5a288633920c63112086d70622c1188`.

Source evidence:

- [affected `Debug.scala`](https://github.com/chipsalliance/rocket-chip/blob/373f78d7d5a288633920c63112086d70622c1188/src/main/scala/devices/debug/Debug.scala)
- [fixed `Debug.scala`](https://github.com/chipsalliance/rocket-chip/blob/579e60a08e96373d93ff09d6070377a015f2efba/src/main/scala/devices/debug/Debug.scala)
- [fixed commit](https://github.com/chipsalliance/rocket-chip/commit/579e60a08e96373d93ff09d6070377a015f2efba)

## Duplicate boundary

This is distinct from the CVA6 Debug Module request-width record and from
Rocket's halt-group/extTrigger state-machine record. It covers generator
arithmetic for 32-plus-hart HAWINDOW masks.
