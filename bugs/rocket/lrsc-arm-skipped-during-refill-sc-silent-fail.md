# Rocket: LR/SC 保留被无关 L2 probe 静默破坏 → 背靠背 SC 合法失败(diff-spike #872 根因)

> Status: **fixed in our fork** (`cx-build` branch), verified against a rebuilt Verilator simulator (A/B).
> Dated 2026-08-11。由 HardwareFuzz riscv_fuzz_test diff-spike 矩阵复现(#872)。
> 影响:rocket-vs-spike 差分测试的 SC 写入误报(rocket 不写、spike 写 0x00)——**rocket 真实缺陷**,非 fuzz 框架误报。

---

## 概述

RISC-V `lr.w`/`sc.w`(Zalrsc)要求:LR 建立对某地址的 load-reservation,其后对**同一地址**的 SC 若无其他代理写入/探针,必须成功。Spike 的保留是纯地址匹配(`riscv-isa-sim/riscv/mmu.h:253-270`),只被 store/probe 失效,无时间窗口,SC 必成功。

Rocket 的 DCache 在**保留有效期间(`lrscValid`)无条件阻塞所有 L2 probe**(`tl_out.b.ready=0`)。单核场景下,LR 之后往往紧跟一次 **I$ miss refill**,该 refill 的相干检查会触发一个 **L2 probe**;它被阻塞 → refill 停到保留倒计时过期 → SC 到达时 `lrscValid=0` → **静默失败**(不写内存、不抛异常)。全程无任何冲突 store/probe(probe 只查无关行),SC 却失败——与 spike 分歧,且**窗口越大越糟**(自反馈,见下)。

## 复现

- 来源:`artifacts/diff_spike_execfix_20260810_new/fresh_all_50_lowp12_rerun3/` rv64_rocket case_09,rv64 + Zalrsc。
- 失败用例:全局索引 #872(测试内 #710),`sc.w x0, x0, (x5)`,x5=0x87ffffa8(fuzz 报告的内存相对偏移标记为 `0xb0`,同一地址)。
- 观测:**rocket** 无写(SC 失败);**spike** 写 0xb0=0x00(SC 成功)。探针复读确认两核心状态真实不一致;重放稳定复现。
- 若非 `sc.w x0,x0`(写零寄存器)而是写非零值,rocket 不写内存 + SC 失败码,spike 写值——**后续读该地址的指令将真实分叉**。

## 根因:probe 阻塞的反馈环(决定性证据)

`DCache.scala` 中 `lrscValid` 同时是保留有效性和 **L2 probe 服务闸门**:

```scala
val block_probe_for_core_progress = blockProbeAfterGrantCount > 0.U || lrscValid
tl_out.b.ready := ... && !(block_probe_for_core_progress || block_probe_for_ordering || s1_valid || s2_valid)
```

单核场景的事件链(LR 后的下一条取指恰好 I$ miss):

```
LR arm → lrscValid=1 → block_probe_for_core_progress=1 → tl_out.b.ready=0
→ I$ miss 的 refill 需 L2 相干 probe(检查 D$ 行归属)被挡
→ refill 停顿 → 前端无指令 → SC 迟到
→ countdown(80)过期 → lrscValid=0 → SC 失败
```

**自反馈证据**(窗口对 gap 的影响,探针实测):

| lrscCycles | LR→SC gap | 结果 |
|-----------|-----------|------|
| 80(upstream) | 99 | SC 失败(count=0) |
| 1024(试改) | **1043** | SC 仍失败(count=0) |

gap = I$ refill 自然延迟(~19) + 保留窗口(80/1024) —— **窗口越大 probe 挡越久、SC 越晚到**,窗口自己制造让它失效的延迟。所以"加长窗口"或"核心停摆期冻结 countdown"**都不可能修好**(见"否决方案")。

旁证:probe 周期 ~61 拍、共 327 次,均来自 L2(I$ refill / PTW 的相干检查);#872 的 LR→SC 窗口内恰有 probe 清掉保留。

## 修复:按地址限定 probe 处理

只让**命中保留行**的 probe 破坏/阻塞保留;无关行 probe 放行(I$ refill 不被挡 → SC 准时到达 → 窗口内成功)。

`DCache.scala`(三处):

```scala
// 1. 只按地址清除:仅命中保留块的 probe 才清零
when (s1_probe && (probe_bits.address >> blockOffBits) === lrscAddr) { lrscCount := 0.U }

// 2. 只按地址阻塞:仅命中保留块的 probe 才被挡,无关 probe 放行
val probe_is_lrsc_line = (tl_out.b.bits.address >> blockOffBits) === lrscAddr
val block_probe_for_core_progress = blockProbeAfterGrantCount > 0.U || (lrscValid && probe_is_lrsc_line)
```

- 语义:对保留地址的 probe(真冲突)仍立即失效保留——多核语义不变;无关 probe(相干检查)不再破坏保留,且不再阻塞 refill。
- `lrscCycles` 保持 upstream 的 **80**(修复后无需长窗口;回退了 1024 实验)。

同时保留此前已确认的 arm-guard 修复(`!cached_grant_wait` 移除,refill 在飞时命中 LR 也 arm;见 git 历史与本文件附录)。

## 验证(A/B,Verilator 模拟器重放 #872)

| 构建 | 改动 | LR→SC gap / 结果 |
|------|------|------------------|
| upstream 原二进制 | 无 | 99 / SC 失败(count=0),差异复现 |
| 仅移除 arm guard | 单改 | 99 / 仍失败(证明 #872 非 arm-skip) |
| lrscCycles=1024 | 加窗 | **1043 / 仍失败**(证明是反馈环,非窗口不足) |
| 地址限定 probe(最终) | 修反馈环 | **23 / SC 成功(count=57, valid=1, scfail=0);write-diff 报告消失;pass_001 rocket/spike 均 1366 writes / 0 exception** |

无死锁、无回归。最终二进制不带任何调试探针。

## 否决方案(均实测失败,勿重试)

1. **`!s2_valid` 冻结 countdown**:D$ 流水线空是常态(ALU 指令、取指间隙),冻结使 `lrscValid` 无限保持 → `block_probe_for_core_progress` 永久压 `tl_out.b.ready` → L2 probe 永不到达 → 总线死锁,模拟 10 分钟超时挂起。
2. **`!ibuf.io.inst(0).valid` 冻结**(经 HellaCacheIO 传核心停摆信号):ibuf 批次取指间隙周期性为空 → 同样无限冻结保留 → 同样死锁(30s 裸跑超时,零输出)。
3. **加长窗口(lrscCycles 80→1024)**:反馈环使 gap 随窗口等比例放大,gap=1043>1024,仍失败;且放大 probe 压制窗口,多核延迟更糟。

本质:任何让保留存活超过"D$ 自身停顿"的方案,都会把 probe 闸门关死;probe 闸门与保留有效性强耦合是本 bug 的土壤。

## 对 diff-fuzz 的意义

这是 rocket 与 spike 在 Zalrsc 上**真实的架构性分歧**(rocket 因无关 probe 阻塞反馈环静默失败),不是 fuzz 框架误报。修复后该差异从矩阵中消失。**若软件真的在 LR 后立刻取指 miss,无此修复将永久失败;此修复使无冲突 LR/SC 按契约成功。** 与 spike 的剩余差异只剩 SC 成功后的 backoff(3 拍)内二次 SC 失败(两核心行为一致,非差异源)。

重放命令:

```
export RISCV_FUZZ_PLUGIN_DIRS=$PWD/riscv_fuzz_plugins
export PATH=/opt/riscv/bin:$PATH
export CX_RISCV_CORES_ROCKET_CHIP_RV64FD_1C=<构建产物 rocket-chip_rv64fd_1c>
./target/release/riscv_fuzz_test replay \
  --config artifacts/diff_spike_execfix_20260810_new/replay_rocket_fix.toml \
  --run-dir /tmp/rocket_replay_check
```

> 构建注意:`./build.sh --isa rv64fd --clean` 必须带 `--clean`——mill/verilator 缓存 Scala→Verilog→C++ 全链路,不带会产出 md5 不变的陈旧二进制(实测两次"成功"构建 md5 均 `a495f3535`)。Scala 改动后须核对产物 md5 已变。

## 附录:关键信号位置

- `DCache.scala`: `cached_grant_wait`(:221)、`probe_bits`(:182)、`lrscValid`(:471)、LR arm(:483)、countdown 冻结(:495)、**保留清除(地址限定)**(:503)、**probe 阻塞(地址限定)**(:806-810)、`s1_probe`(:181)
- `RocketCore.scala`: `lrscCycles`(:72)
- Spike:`riscv-isa-sim/riscv/mmu.h:253-270`(纯地址匹配,无时间窗)
- riscv-spec Zalrsc:§A.5.3(保留由 store/probe 失效;SC 允许失败但软件须重试)

---

## 补遗(2026-08-11 二期):LR arm 被递减/backoff 遮蔽 → 连续 LR/SC 对第二个静默失败

diff-spike rerun5 rv32_rocket case_09(同一 bug 族的**另一条路径**)复现:

- 失败用例:`sc.w x0,x0,(x6)` @ 0x87ffff1c,rocket 无写 vs spike 写 0x00(测试内 #559 / 全局 #779)。
- 程序语义:两个背靠背 LR/SC 对——Pair A `lr.w x13,(x5); sc.w x0,x0,(x5)`(SC1 成功,写 0x87ffff38),Pair B `lr.w x0,(x6); sc.w x0,x0,(x6); sc.w.aq x11,x8,(x6)`(SC2 该成功却失败)。
- **与 #872 的区别**:#872 是 LR 后隔 ~99 拍 + I$ refill probe 反馈环;本 case **LR→SC 背靠背(gap≈1 拍)、无 probe、无 refill**,LR 命中。
- **根因:LR arm 在 when 链中优先级过低**。对 `lrscCount` 的多个 when 赋值被合成 if-else 链,arm(`lrscCount:=79; lrscAddr:=...`)排在**递减(count-1)和 backoff(=3)之后**。Pair A 的 SC1 成功→backoff=3 残留;Pair B 的 LR 到达时 `lrscCount>0`→递减/backoff 遮蔽 arm→`lrscAddr` 保持旧地址(0x87ffff38)→SC2 用 0x87ffff1c 检查→地址不匹配→静默失败。
- 证据:生成的 `DCache.sv` 优先级链 `probe清0 > backoff(3) > 递减 > arm(79)`,arm 最低;单指令复现(孤立 Pair B,count=0)成功、完整历史失败、删 Pair A 历史后成功——全部吻合"残留 count 遮蔽 arm"。
- **修复**:把 arm 移到 when 链最后(递减、backoff 之后),使 arm 优先于它们、probe 清 0 仍最高。同步收窄 backoff 为仅 SC/AMO 触发(原为任意指令,LR→SC 间隔 1 拍即被压到 3)。
- **验证**:--clean 重建 rv32fd_1c(md5 变),重放 case_09 原 testcase → write-diff 应消失。
- **教训**:back-to-back LR/SC 对是 fuzz 常见形态;upstream 的 arm 优先级缺陷只会在残留保留上暴露。三处 if-else 共同操作 lrscCount 时,必须保证 arm 是最新一次 LR 的绝对优先。

### 修复验证(2026-08-11,隔离 worktree)

- 因并行 agent 同时改动 `RocketCore.scala`(64-slot ll_tracker),在主工作区重放会解析失败(`duplicate register write`),故在**独立 worktree**(`fix/lrsc-arm-priority` @ b25229a27,仅含本 DCache 修复)中 `--clean` 重建验证。
- rv32fd_1c:重放 case_09 原 testcase → `write_removal_rounds: 0`,SC1 写成功,write-diff 消失。
- rv64fd_1c:重放 case_11 回归 → 仅剩既有的 `div` write-diff(rerun5 原报该 case 的原因),**无任何 LR/SC/AMO 新差异**。
- 提交:`36ed46385 fix(dcache): LR arm must take priority over countdown/backoff`,已 ff 合并回 `cx-build`。
