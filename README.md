# cx-riscv-cores

`cx-riscv-cores` 是 HardwareFuzz 的统一 RISC-V core 构建仓库。

这个仓库提供这些能力：

- 从各个 core 子仓库构建统一命名的最终产物
- 把所有最终产物集中放到一个目录，默认是 `./artifacts`
- 把这些产物导出成稳定的 `CX_RISCV_CORES_*` 环境变量

文档中的统一接口就是 `CX_RISCV_CORES_*` 这组环境变量。

## 产物和变量规则

- 默认产物目录：`./artifacts`
- 默认日志目录：`./logs/<YYYYMMDD>`
- build 产物命名规则：`<core>_<isa>[_<preset>]_<Nc>[_cov|_cov_light]`
- 环境变量命名规则：`CX_RISCV_CORES_<UPPER_SNAKE_BASENAME>`

例子：

```text
rocket-chip_rv64fd_2c           -> CX_RISCV_CORES_ROCKET_CHIP_RV64FD_2C
rocket-chip_rv64fd_2c_cov       -> CX_RISCV_CORES_ROCKET_CHIP_RV64FD_2C_COV
boom_rv64fd_2c                 -> CX_RISCV_CORES_BOOM_RV64FD_2C
xiangshan_rv64_aligned_1c       -> CX_RISCV_CORES_XIANGSHAN_RV64_ALIGNED_1C
xiangshan_difftest_rv64_2c_so   -> CX_RISCV_CORES_XIANGSHAN_DIFFTEST_RV64_2C_SO
```

固定环境变量有两个：

- `CX_RISCV_CORES_ROOT`
- `CX_RISCV_CORES_ARTIFACT_DIR`

可选环境变量有一个：

- `CX_RISCV_CORES_SPIKE`

除了上面这些固定项，其他 `CX_RISCV_CORES_*` 都是从 `artifact-dir` 里当前实际存在的文件动态生成的：

- 文件存在，就导出对应变量
- 文件不存在，就不会导出对应变量

说明：

- `CX_RISCV_CORES_SPIKE` 由当前系统 `PATH` 中的 `spike` 推导出来
- `scripts/generate_env.sh` 会在 `artifacts/` 中没有 `spike` 文件时尝试从 `PATH` 解析 `spike`
- 如果系统里没有 `spike`，这个变量不会被导出

补充：

- 用本仓库里的本地脚本时，`CX_RISCV_CORES_ROOT` 指向仓库根目录
- 用下面的 release 安装脚本时，`CX_RISCV_CORES_ROOT` 指向安装根目录

## 从 Release 直接安装

如果你不想先 clone 仓库，而是想直接把 release 里的统一产物下载到本机并安装环境变量，可以直接用这个脚本：

```bash
curl -fsSL https://raw.githubusercontent.com/HardwareFuzz/cx-riscv-cores/main/scripts/install_release.sh | bash
```

这条命令默认会做这些事：

- 把 `dev-release` 的全部产物下载到 `~/.local/share/cx-riscv-cores/artifacts`
- 生成 `~/.config/cx-riscv-cores/env.sh`
- 更新 `~/.bashrc`
- 更新 `~/.profile`
- 如果存在 `~/.zshrc`，也会更新它

常用例子：

```bash
# 下载全部 release 产物到自定义安装根目录
curl -fsSL https://raw.githubusercontent.com/HardwareFuzz/cx-riscv-cores/main/scripts/install_release.sh | \
  bash -s -- --dir /opt/cx-riscv-cores

# 只下载部分产物到指定目录，并安装环境变量
curl -fsSL https://raw.githubusercontent.com/HardwareFuzz/cx-riscv-cores/main/scripts/install_release.sh | \
  bash -s -- --artifact-dir /data/cx-riscv-cores --only 'rocket-chip_*' --only 'xiangshan_*unaligned*'

# 只下载，不修改 shell 启动文件
curl -fsSL https://raw.githubusercontent.com/HardwareFuzz/cx-riscv-cores/main/scripts/install_release.sh | \
  bash -s -- --artifact-dir /tmp/cx-riscv-cores --download-only
```

说明：

- `--only` / `--skip` 使用 shell glob 匹配 release asset 名称，支持重复传入，也支持逗号分隔
- `--artifact-dir` 表示文件直接下载到这个目录
- `--dir` 表示安装根目录；产物会放在 `DIR/artifacts`
- 脚本会校验 release manifest 里的 SHA-256，已有同校验和文件会直接复用，不重复下载
- `curl | bash` 无法直接修改当前父 shell，所以脚本会安装 `env.sh` 并更新 shell 启动文件；当前会话如果要立刻生效，执行一次 `. ~/.config/cx-riscv-cores/env.sh`

## 顶层脚本

### `scripts/install_release.sh`

这是“无需 clone 仓库”的 release 安装入口，也支持直接在本仓库里执行。

用法：

```bash
./scripts/install_release.sh
./scripts/install_release.sh --dir /opt/cx-riscv-cores
./scripts/install_release.sh --artifact-dir /data/cx-riscv-cores --only 'rocket-chip_*'
./scripts/install_release.sh --list --only 'xiangshan_*'
```

参数如下：

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `--dir DIR` | `~/.local/share/cx-riscv-cores` | 安装根目录；默认下载到 `DIR/artifacts` |
| `--artifact-dir DIR` | 跟随 `--dir` | 直接指定产物目录 |
| `--env-file FILE` | `~/.config/cx-riscv-cores/env.sh` | 环境变量导出文件路径 |
| `--release TAG` | `dev-release` | 目标 GitHub release tag |
| `--repo OWNER/REPO` | `HardwareFuzz/cx-riscv-cores` | 目标 GitHub 仓库 |
| `--only GLOB[,GLOB]` | 全部 | 只下载匹配的 release asset |
| `--skip GLOB[,GLOB]` | 不跳过 | 跳过匹配的 release asset |
| `--list` | 关闭 | 只列出匹配结果，不下载 |
| `--download-only` | 关闭 | 只下载，不生成 `env.sh`，也不改 shell rc |
| `--no-profile` | 关闭 | 生成 `env.sh`，但不修改 `~/.bashrc` / `~/.profile` / `~/.zshrc` |
| `--help`, `-h` | 关闭 | 显示帮助 |

### `scripts/build_all.sh`

这是仓库的统一构建入口。

默认行为：

- 输出目录使用 `CX_OUT_DIR`，如果没设置则使用 `./artifacts`
- 日志目录默认是 `./logs/<YYYYMMDD>`
- `--cores both`
- `--matrix minimal`
- `--branch-source origin`
- 默认启用 XiangShan
- 默认不启用 coverage
- 1-core 构建使用各子仓库的 `cx-build` 分支
- 2-core 构建使用各子仓库的 `cx-2hart-build` 分支
- 结束后会自动执行 `scripts/stage_runtime_support.sh`

参数如下：

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `--out-dir DIR` | `CX_OUT_DIR` 或 `./artifacts` | 统一产物输出目录 |
| `--log-dir DIR` | `./logs/<YYYYMMDD>` | 每个 core 的构建日志目录 |
| `--branch-source <auto\|local\|origin>` | `origin` | 子仓库分支解析方式 |
| `--cores <1\|2\|both>` | `both` | 构建 1-core、2-core 或两者都构建 |
| `--matrix <minimal\|all>` | `minimal` | 选择默认矩阵或完整矩阵；除 XiangShan 外，其他 core 的 `minimal` 已覆盖全部支持 ISA 变体 |
| `--isa PATTERN` | 不限制 | 只构建匹配的 ISA 标签；可重复传入，也支持逗号分隔和 shell glob |
| `--only a,b,c` | 构建全部 | 只构建指定 core；支持 `picorv32,kronos,ibex,vexriscv,cva6,rocket-chip,boom,xiangshan,openc906,openc910` |
| `--skip-xiangshan` | 关闭 | 跳过 XiangShan |
| `--with-xiangshan` | 开启 | 保留的兼容参数，效果等同默认行为 |
| `--xiangshan-preset <default\|aligned\|unaligned\|both\|all>` | `auto` | XiangShan preset 选择；`auto` 会跟随 `--matrix`。发布产物只保留显式 `unaligned` / `aligned` 标签；`default` 是 `unaligned` 的兼容别名，`all` 是 `both` 的兼容别名 |
| `--clean` | 关闭 | 把 `--clean` 透传到各子仓库 `build.sh` |
| `--coverage` | 关闭 | 构建 `_cov` 版本 |
| `--coverage-light` | 关闭 | 构建 `_cov_light` 版本 |
| `--no-coverage` | 开启 | 显式指定无 coverage，默认就是这个行为 |
| `--dry-run` | 关闭 | 只打印命令，不执行 |
| `--help`, `-h` | 关闭 | 显示帮助 |

最常用的命令：

```bash
# 默认最小矩阵，构建 1-core 和 2-core
./scripts/build_all.sh

# 只构建 1-core
./scripts/build_all.sh --cores 1

# 只构建部分 core
./scripts/build_all.sh --only picorv32,ibex,vexriscv

# 构建完整矩阵
./scripts/build_all.sh --matrix all

# 只构建 rocket-chip 的 rv64* 变体
./scripts/build_all.sh --only rocket-chip --matrix all --isa 'rv64*'

# 只构建 BOOM 的默认 1-core / 2-core provider
./scripts/build_all.sh --only boom

# 构建 XiangShan 的 aligned/unaligned 命名产物
./scripts/build_all.sh --only xiangshan --matrix all --xiangshan-preset both

# 构建 coverage 版本
./scripts/build_all.sh --coverage
```

约束和注意事项：

- `build_all.sh` 的 `1c` 和 `2c` 是通过切到 `cx-build` / `cx-2hart-build` 两个分支分别构建出来的
- `picorv32` 和 `kronos` 的 `1c` / `2c` 能力就是这样拼出来的，不是单个分支同时支持两者
- `ibex` 只支持 `rv32imc`
- `vexriscv` 的 `2c` 不支持 `rv32f`
- 对于同时支持 plain / `f` / `fd` 标签的 core，`build_all.sh` 和对应子仓库 `build.sh` 现在都只发布带 `f` / `fd` 的标签，不再保留 plain `rv32` / `rv64`
- `cva6` 的统一发布矩阵现在只保留 `rv32f_*` / `rv64fd_*`，不再保留 plain `rv32_*` / `rv64_*`
- `boom` 使用 `cores/boom` 里的 Chipyard `main` 分支，不跟随其他 core 的 `cx-build` / `cx-2hart-build` 分支约定
- `boom` 当前只发布 `rv64fd` provider；默认 `1c` / `2c` 都使用 `small` 配置；如果你要切换成 `medium` / `large`，直接运行 `cores/boom/build.sh --variant ...`
- `openc906` 使用 `cx-build` 分支（单 hart，Verilator 后端，支持 coverage `_cov` / `_cov_light`）；`openc910` 同时使用 `cx-build`（单 hart）和 `cx-2hart-build`（双 hart），都是 Verilator 后端，支持 coverage `_cov` / `_cov_light`
- `xiangshan` 的 `--isa` 目前只影响产物命名，不改变 RTL/config

### `scripts/generate_env.sh`

这个脚本用于把环境变量导出语句打印到标准输出，不修改你的 shell 配置。

用法：

```bash
./scripts/generate_env.sh
./scripts/generate_env.sh --artifact-dir /abs/path/to/artifacts
```

参数如下：

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `--artifact-dir DIR` | `CX_OUT_DIR` 或 `./artifacts` | 扫描这个目录并生成 `export ...` |
| `--help`, `-h` | 关闭 | 显示帮助 |

行为说明：

- 只扫描 `artifact-dir` 目录下的一级文件
- 会忽略 `*.json`
- 扫描前会先执行一次 `scripts/stage_runtime_support.sh`

### `scripts/install_env.sh`

这个脚本会把 `generate_env.sh` 的输出安装成长期可用的 shell 环境。

用法：

```bash
./scripts/install_env.sh
./scripts/install_env.sh --artifact-dir /abs/path/to/artifacts
source ~/.bashrc
```

参数如下：

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `--artifact-dir DIR` | `CX_OUT_DIR` 或 `./artifacts` | 用这个目录生成最终的环境变量文件 |
| `--help`, `-h` | 关闭 | 显示帮助 |

执行后会做这些事：

- 生成 `~/.config/cx-riscv-cores/env.sh`
- 在 `~/.bashrc` 中插入 source block
- 在 `~/.profile` 中插入 source block
- 如果存在 `~/.zshrc`，也会插入 source block

## `build_all.sh` 可生成的产物矩阵

下面的表列的是 `build_all.sh` 在不同选项下会生成到 `artifact-dir` 的基础 basename，不重复列 coverage 版本。

这里描述的是“脚本可生成的文件集合”，不是“当前 `artifacts/` 目录此刻一定已经存在的文件集合”。

表里的环境变量名也表示：

- 当这个文件存在时，`generate_env.sh` 会导出这个变量名
- 当这个文件不存在时，这个变量不会出现

coverage 规则统一如下：

- 支持 coverage 的可构建二进制可以带 `_cov` 后缀，对应环境变量名追加 `_COV`
- 支持 light coverage 的可构建二进制可以带 `_cov_light` 后缀，对应环境变量名追加 `_COV_LIGHT`
- 运行时支持文件 `.so` 不存在 coverage 变体
- 这些 coverage 文件只有在你真的执行过对应 coverage 构建后才会出现在 `artifact-dir`
- coverage 支持是 per-core 能力；例如 picorv32/kronos 等 stub-coverage 后端不发布单独的 `_cov` 产物

例子：

```text
ibex_rv32imc_2c_cov                   -> CX_RISCV_CORES_IBEX_RV32IMC_2C_COV
xiangshan_rv64fd_unaligned_1c_cov_light -> CX_RISCV_CORES_XIANGSHAN_RV64FD_UNALIGNED_1C_COV_LIGHT
```

表中的 `minimal` 表示默认 `./scripts/build_all.sh` 会生成的产物。

除了 XiangShan 仍然保留精简默认矩阵，其他 core 的 `minimal` 与 `all` 在产物集合上已经一致。

表中的 `all` 表示 `./scripts/build_all.sh --matrix all` 会生成的产物。

### 环境变量总览

| 环境变量 | 含义 |
| --- | --- |
| `CX_RISCV_CORES_ROOT` | 本仓库根目录绝对路径 |
| `CX_RISCV_CORES_ARTIFACT_DIR` | 当前使用的产物目录绝对路径 |
| `CX_RISCV_CORES_SPIKE` | 可选；当 `spike` 可在 `PATH` 中找到时导出 |

### PicoRV32

| Artifact basename | Env var | `minimal` | `all` | Notes |
| --- | --- | --- | --- | --- |
| `picorv32_rv32_1c` | `CX_RISCV_CORES_PICORV32_RV32_1C` | 是 | 是 | 来自 `cx-build` |
| `picorv32_rv32_2c` | `CX_RISCV_CORES_PICORV32_RV32_2C` | 是 | 是 | 来自 `cx-2hart-build` |

### Kronos

| Artifact basename | Env var | `minimal` | `all` | Notes |
| --- | --- | --- | --- | --- |
| `kronos_rv32_1c` | `CX_RISCV_CORES_KRONOS_RV32_1C` | 是 | 是 | 来自 `cx-build` |
| `kronos_rv32_2c` | `CX_RISCV_CORES_KRONOS_RV32_2C` | 是 | 是 | 来自 `cx-2hart-build` |

### Ibex

| Artifact basename | Env var | `minimal` | `all` | Notes |
| --- | --- | --- | --- | --- |
| `ibex_rv32imc_1c` | `CX_RISCV_CORES_IBEX_RV32IMC_1C` | 是 | 是 | 只支持 `rv32imc` |
| `ibex_rv32imc_2c` | `CX_RISCV_CORES_IBEX_RV32IMC_2C` | 是 | 是 | 只支持 `rv32imc` |

### VexRiscv

| Artifact basename | Env var | `minimal` | `all` | Notes |
| --- | --- | --- | --- | --- |
| `vexriscv_rv32fd_1c` | `CX_RISCV_CORES_VEXRISCV_RV32FD_1C` | 是 | 是 | 默认 1-core 产物 |
| `vexriscv_rv32f_1c` | `CX_RISCV_CORES_VEXRISCV_RV32F_1C` | 是 | 是 | 只支持 `1c`；子仓库 `build.sh` 也不再接受 plain `rv32` |
| `vexriscv_rv32fd_2c` | `CX_RISCV_CORES_VEXRISCV_RV32FD_2C` | 是 | 是 | 默认 2-core 产物 |

### CVA6

`cva6` 子仓库 `build.sh` 现在直接只接受 `rv64fd` / `rv32f`，统一发布目录里的 basename 也保持这两个 canonical 标签。

| Artifact basename | Env var | `minimal` | `all` | Notes |
| --- | --- | --- | --- | --- |
| `cva6_rv64fd_1c` | `CX_RISCV_CORES_CVA6_RV64FD_1C` | 是 | 是 | 默认产物；内部实际使用 `cv64a6_full_sv39` |
| `cva6_rv64fd_2c` | `CX_RISCV_CORES_CVA6_RV64FD_2C` | 是 | 是 | 默认产物；内部实际使用 `cv64a6_full_sv39` |
| `cva6_rv32f_1c` | `CX_RISCV_CORES_CVA6_RV32F_1C` | 是 | 是 | 默认产物；内部实际使用 `cv32a6_full_sv32` |
| `cva6_rv32f_2c` | `CX_RISCV_CORES_CVA6_RV32F_2C` | 是 | 是 | 默认产物；内部实际使用 `cv32a6_full_sv32` |

### Rocket Chip

| Artifact basename | Env var | `minimal` | `all` | Notes |
| --- | --- | --- | --- | --- |
| `rocket-chip_rv64fd_1c` | `CX_RISCV_CORES_ROCKET_CHIP_RV64FD_1C` | 是 | 是 | 默认产物 |
| `rocket-chip_rv64fd_2c` | `CX_RISCV_CORES_ROCKET_CHIP_RV64FD_2C` | 是 | 是 | 默认产物 |
| `rocket-chip_rv64f_1c` | `CX_RISCV_CORES_ROCKET_CHIP_RV64F_1C` | 是 | 是 | 默认最小矩阵也会构建 |
| `rocket-chip_rv64f_2c` | `CX_RISCV_CORES_ROCKET_CHIP_RV64F_2C` | 是 | 是 | 默认最小矩阵也会构建 |
| `rocket-chip_rv32fd_1c` | `CX_RISCV_CORES_ROCKET_CHIP_RV32FD_1C` | 是 | 是 | 默认最小矩阵也会构建 |
| `rocket-chip_rv32fd_2c` | `CX_RISCV_CORES_ROCKET_CHIP_RV32FD_2C` | 是 | 是 | 默认最小矩阵也会构建 |
| `rocket-chip_rv32f_1c` | `CX_RISCV_CORES_ROCKET_CHIP_RV32F_1C` | 是 | 是 | 默认最小矩阵也会构建 |
| `rocket-chip_rv32f_2c` | `CX_RISCV_CORES_ROCKET_CHIP_RV32F_2C` | 是 | 是 | 默认最小矩阵也会构建 |

`rocket-chip` 当前由 `build_all.sh` 发布的 ISA 标签都走对应的 max-extension trace config：

- `rv64fd`：`B + Zicond + FP16 + FD + H`
- `rv64f`：`B + Zicond + FP16 + F + H`
- `rv32fd` / `rv32f`：沿用已有的 RV32 max-extension configs

`rocket-chip` 子仓库 `build.sh` 现在也只接受这四个带 `f` / `fd` 的标签，不再单独发布 plain `rv64` / `rv32`。

### BOOM

`boom` 的默认 provider 现在基于 Chipyard BOOM V4 trace 配置：

- `1c` 默认产物使用 `small` 变体
- `2c` 默认产物使用 `small` 变体
- `cores/boom/build.sh --variant small|medium|large` 可以额外构建带变体标签的 simulator ELF，例如 `boom_rv64fd_large_1c`
- 默认 provider 保留 `F/D` 与 trace 输出，并切到源码里实际接入了 `B_table` 的 v4 decode
- 重新构建并替换 `artifacts/boom_rv64fd_{1c,2c}` 后，运行时已确认默认 provider 支持 `Zicond`、`Zfh/Zfhmin`、`Zbc`、`Zbkx`、`Zicbom/Zicboz` 以及 `Zkn/Zknd/Zkne/Zknh/Zksed/Zksh`

| Artifact basename | Env var | `minimal` | `all` | Notes |
| --- | --- | --- | --- | --- |
| `boom_rv64fd_1c` | `CX_RISCV_CORES_BOOM_RV64FD_1C` | 是 | 是 | 默认单核 provider；底层配置是 `CXBoomSmallV4TraceConfig` |
| `boom_rv64fd_2c` | `CX_RISCV_CORES_BOOM_RV64FD_2C` | 是 | 是 | 默认双核 provider；底层配置是 `CXBoomDualSmallV4TraceConfig` |

### OpenC906

当前 OpenC906 顶层产物是 RV64 单 hart Verilator smart_run 的真实 `Vtop` ELF；`rv64f` / `rv64fd` 是对同一类 simulator 的能力标签。支持 `_cov` 与 `_cov_light` coverage 产物（Verilator 内建覆盖率，运行时通过 `+covfile=<path>` 写出 `coverage.dat`）。运行前把 ELF 转成 `inst.pat` / `data.pat` 所需的 `Srec2vmem` 由 `scripts/stage_runtime_support.sh` 统一放到 artifacts 目录。不发布 RV32、2-hart 或 vector 产物。

| Artifact basename | Env var | `minimal` | `all` | Notes |
| --- | --- | --- | --- | --- |
| `openc906_rv64f_1c` | `CX_RISCV_CORES_OPENC906_RV64F_1C` | 是 | 是 | RV64F 标签、单 hart、无 coverage；来自 `cx-build` |
| `openc906_rv64fd_1c` | `CX_RISCV_CORES_OPENC906_RV64FD_1C` | 是 | 是 | RV64FD 标签、单 hart、无 coverage；来自 `cx-build` |

### OpenC910

当前 OpenC910 顶层产物是 RV64 smart_run 的真实 `Vtop` ELF，发布 1-hart (cx-build) 和 2-hart (cx-2hart-build) 两组产物；后端是 Verilator + CX_TRACE testbench。`rv64f` / `rv64fd` 是对同一类 simulator 的能力标签。支持 `_cov` 与 `_cov_light` coverage 产物（每个 hart 配置都各有一份）。运行前把 ELF 转成 `inst.pat` / `data.pat` 所需的 `Srec2vmem` 由 `scripts/stage_runtime_support.sh` 统一放到 artifacts 目录。不发布 RV32 或 vector 产物。

| Artifact basename | Env var | `minimal` | `all` | Notes |
| --- | --- | --- | --- | --- |
| `openc910_rv64f_1c` | `CX_RISCV_CORES_OPENC910_RV64F_1C` | 是 | 是 | RV64F 标签、单 hart、无 coverage；来自 `cx-build` |
| `openc910_rv64fd_1c` | `CX_RISCV_CORES_OPENC910_RV64FD_1C` | 是 | 是 | RV64FD 标签、单 hart、无 coverage；来自 `cx-build` |
| `openc910_rv64f_2c` | `CX_RISCV_CORES_OPENC910_RV64F_2C` | 是 | 是 | RV64F 标签、双 hart、无 coverage；来自 `cx-2hart-build` |
| `openc910_rv64fd_2c` | `CX_RISCV_CORES_OPENC910_RV64FD_2C` | 是 | 是 | RV64FD 标签、双 hart、无 coverage；来自 `cx-2hart-build` |

### XiangShan

`xiangshan` 的 `--isa` 目前只影响文件名，不改变实际 RTL/config。子仓库 `build.sh` 和 `build_all.sh` 现在都只发布 `rv64f_*` / `rv64fd_*` 这两组标签，不再发布 plain `rv64_*`。

更准确地说：

- `rv64fd*` 这组是 `build_all.sh` 的 canonical XiangShan 发布标签
- `rv64f*` 这些文件是 `build_all.sh` 在构建完成后通过 `cp -f` 复制出来的别名文件，不是额外的 RTL build
- 当前源码里 `TLMinimalConfig` 默认就启用了硬件 misaligned load/store，所以 `default` 和 `unaligned` 在配置语义上等价；仓库现在统一只保留显式 `unaligned` 标签，避免重复和歧义

| Artifact basename | Env var | `minimal` | `all` | Notes |
| --- | --- | --- | --- | --- |
| `xiangshan_rv64f_aligned_1c` | `CX_RISCV_CORES_XIANGSHAN_RV64F_ALIGNED_1C` | 否 | 是 | 由同 preset 的 `rv64fd` canonical 产物复制生成 |
| `xiangshan_rv64f_aligned_2c` | `CX_RISCV_CORES_XIANGSHAN_RV64F_ALIGNED_2C` | 否 | 是 | 由同 preset 的 `rv64fd` canonical 产物复制生成 |
| `xiangshan_rv64fd_aligned_1c` | `CX_RISCV_CORES_XIANGSHAN_RV64FD_ALIGNED_1C` | 否 | 是 | `aligned` preset 的 canonical 发布标签 |
| `xiangshan_rv64fd_aligned_2c` | `CX_RISCV_CORES_XIANGSHAN_RV64FD_ALIGNED_2C` | 否 | 是 | `aligned` preset 的 canonical 发布标签 |
| `xiangshan_rv64f_unaligned_1c` | `CX_RISCV_CORES_XIANGSHAN_RV64F_UNALIGNED_1C` | 否 | 是 | 由同 preset 的 `rv64fd` canonical 产物复制生成 |
| `xiangshan_rv64f_unaligned_2c` | `CX_RISCV_CORES_XIANGSHAN_RV64F_UNALIGNED_2C` | 否 | 是 | 由同 preset 的 `rv64fd` canonical 产物复制生成 |
| `xiangshan_rv64fd_unaligned_1c` | `CX_RISCV_CORES_XIANGSHAN_RV64FD_UNALIGNED_1C` | 是 | 是 | `unaligned` preset 的 canonical 发布标签；这是默认最小矩阵下的 XiangShan 产物 |
| `xiangshan_rv64fd_unaligned_2c` | `CX_RISCV_CORES_XIANGSHAN_RV64FD_UNALIGNED_2C` | 是 | 是 | `unaligned` preset 的 canonical 发布标签；这是默认最小矩阵下的 XiangShan 产物 |

### Runtime Support

这些文件不是主 simulator 可执行文件，而是 `scripts/stage_runtime_support.sh` 复制进统一产物目录的运行时依赖。

| Artifact basename | Env var | `minimal` | `all` | Notes |
| --- | --- | --- | --- | --- |
| `boom_dramsim2_system.ini` | `CX_RISCV_CORES_BOOM_DRAMSIM2_SYSTEM_INI` | 是 | 是 | BOOM DRAMSim runtime support；运行时会和下面那份 ini 组合成 `dramsim2_ini/` 目录 |
| `boom_dramsim2_DDR3_micron_64M_8B_x4_sg15.ini` | `CX_RISCV_CORES_BOOM_DRAMSIM2_DDR3_MICRON_64M_8B_X4_SG15_INI` | 是 | 是 | BOOM DRAMSim runtime support |
| `openc_srec2vmem` | `CX_RISCV_CORES_OPENC_SREC2VMEM` | 是 | 是 | OpenC906/OpenC910 共同使用的 `Srec2vmem` |
| `xiangshan_difftest_rv64_1c_so` | `CX_RISCV_CORES_XIANGSHAN_DIFFTEST_RV64_1C_SO` | 是 | 是 | 来自 `cores/XiangShan/ready-to-run/riscv64-nemu-interpreter-so` |
| `xiangshan_difftest_rv64_2c_so` | `CX_RISCV_CORES_XIANGSHAN_DIFFTEST_RV64_2C_SO` | 是 | 是 | 来自 `cores/XiangShan/ready-to-run/riscv64-nemu-interpreter-dual-so` |

## 最小工作流

如果你只需要本仓库的标准接口，流程就是这三步：

```bash
./scripts/build_all.sh
./scripts/install_env.sh
source ~/.bashrc
```

然后直接消费环境变量，例如：

```bash
echo "$CX_RISCV_CORES_ROCKET_CHIP_RV64FD_2C"
echo "$CX_RISCV_CORES_XIANGSHAN_DIFFTEST_RV64_2C_SO"
```
