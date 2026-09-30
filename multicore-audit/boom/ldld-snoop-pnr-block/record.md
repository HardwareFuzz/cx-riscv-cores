# BOOM LD-LD ordering could enter the PNR failure path after a coherent snoop

- Record ID: `BOOM-LDLD_SNOOP_PNR_BLOCK`
- Core: BOOM
- Source repository: [riscv-boom/riscv-boom](https://github.com/riscv-boom/riscv-boom)
- Scope: v4 LSU same-address load ordering and coherent snoop observation
- Record kind: canonical upstream Chisel/RTL memory-ordering fix
- Lifecycle: confirmed-fixed-history
- Confidence: high
- Confirmation: confirmed by the exact affected parent, the v4 LSU state predicates, the external Probe/release observation path, the complete fix chain, and the merged PR closure
- Affected parent: [d2a64f7c](https://github.com/riscv-boom/riscv-boom/commit/d2a64f7ca9fd914d9c686cb23edcd32d3465a02e)
- Fix chain: [7ea65465](https://github.com/riscv-boom/riscv-boom/commit/7ea65465bc8554bd399a132c6686ded5adf8b03a1), [47f874e8](https://github.com/riscv-boom/riscv-boom/commit/47f874e82da2946f20185c6a9b54638473320f4c), [f893d83b](https://github.com/riscv-boom/riscv-boom/commit/f893d83bbab2b7c407b6cca7bfad4f8f189f3a12), and [09ae4559](https://github.com/riscv-boom/riscv-boom/commit/09ae455938c7bc0fc99cea1a2e1f27e793a98ace)
- Canonical closure: [BOOM PR #706](https://github.com/riscv-boom/riscv-boom/pull/706), merged as [1606025f](https://github.com/riscv-boom/riscv-boom/commit/1606025fe0e0b10fcc45f4bd609a4fc30458054f)
- Retrieved: 2026-09-10

## Failure mechanism

At the exact affected parent, the v4 LSU tracked whether each load had been
executed, had succeeded, had failed ordering, or had been observed by an
external release:

```scala
val ldq_executed  = Reg(Vec(numLdqEntries, Bool()))
val ldq_succeeded = Reg(Vec(numLdqEntries, Bool()))
val ldq_order_fail = Reg(Vec(numLdqEntries, Bool()))
val ldq_observed  = Reg(Vec(numLdqEntries, Bool()))
```

An issued load miss can therefore reach `ldq_executed = 1` while its
response is still outstanding and `ldq_succeeded = 0`. The older-load
ordering path used this guard for a younger same-address load:

```scala
when (!(l_executed || l_succeeded)) {
  s1_set_execute(lcam_ldq_idx(w)) := false.B
  ...
  kill_forward(w) := true.B
}
```

For an older load that was already issued but had not successfully completed,
`l_executed || l_succeeded` is still true. The younger load is consequently
not killed or replayed, even though the older load has not established a
successful ordering point. This is the exact `executed` versus `succeeded`
predicate defect in the pre-fix v4 LSU.

The affected source is [`v4/lsu/lsu.scala`](https://github.com/riscv-boom/riscv-boom/blob/d2a64f7ca9fd914d9c686cb23edcd32d3465a02e/src/main/scala/v4/lsu/lsu.scala).

## Necessary multi-client trigger

The failure requires an external coherent client to mark the younger load as
observed:

1. Hart A issues an older load `L0` to cache line `X`. It misses and is sent
   to the cache, leaving `ldq_executed(L0) = 1` and
   `ldq_succeeded(L0) = 0` while completion is pending.
2. Before `L0` has completed, Hart A issues a younger same-address load `L1`
   to `X`. The faulty older-load guard does not kill or replay `L1`.
3. Hart B performs a store or permission upgrade to `X`. The coherent
   manager sends a real TileLink B-channel Probe to Hart A.
4. Hart A's DCache emits the corresponding C-channel release through
   `io.dmem.release`. The registered release search matches `L1`'s physical
   block address and sets `ldq_observed(L1) = 1`.
5. When the older-load ordering search runs, `L1` satisfies the pre-fix
   predicates `l_executed || l_succeeded`, `!s1_executing_loads`, and
   `l_observed`. The LSU sets `ldq_order_fail(L1)` and `failed_load`, then
   exposes the condition through:

   ```scala
   val ld_xcpt_valid =
     (ldq_order_fail.asUInt & ldq_valid.asUInt) =/= 0.U
   ```

The external Probe and release from Hart B are necessary. A single hart can
create the older/younger load state, but cannot create the coherent snoop
that marks the younger load observed and drives this PNR/ordering-failure
path.

The release search is the actual shared path:

```scala
val fired_release = RegNext(will_fire_release)
...
when (do_release_search(w) &&
      l_valid &&
      l_addr.valid &&
      !l_addr_is_virtual &&
      block_addr_matches(w)) {
  ldq_observed(i) := true.B
}
```

## Canonical fix and closure

The initial fix changes the older-load test to require both execution and
successful completion:

```scala
when (!(l_executed && l_succeeded)) {
```

The merged PR then closes the back-to-back completion window with
`ldq_will_succeed`:

```scala
val ldq_will_succeed = WireDefault(ldq_succeeded)
ldq_succeeded := ldq_will_succeed
...
when (!(l_executed && (l_succeeded || l_will_succeed))) {
```

The fix chain also updates the ordinary DCache-response and store-to-load
forwarding paths to write `ldq_will_succeed`, and retains an assertion for
the formerly reachable ordering-failure branch. The live canonical v4 LSU
still contains this complete predicate and the next-cycle success tracking.

The exact ancestry of the merged closure is:

```text
d2a64f7ca9fd914d9c686cb23edcd32d3465a02e
  -> 7ea65465bc8554bd399a132c6686ded5adf8b03a
  -> 47f874e82da2946f20185c6a9b54638473320f4c
  -> f893d83bbab2b7c407b6cca7bfad4f8f189f3a12
  -> 09ae455938c7bc0fc99cea1a2e1f27e793a98ace
  -> 1606025fe0e0b10fcc45f4bd609a4fc30458054f (PR merge)
```

The complete fixed v4 source is retained in current canonical master at
[v4/lsu/lsu.scala](https://github.com/riscv-boom/riscv-boom/blob/58ef2720eae13be26b3008c02b5a74ce29c61c44/src/main/scala/v4/lsu/lsu.scala).
The record is distinct from the retained BOOM Probe/MSHR/LRSC records: it
concerns the v4 LSU's same-address `ldq_executed`/`ldq_succeeded` ordering
predicate and the externally generated release's `ldq_observed` update.
