# SDK 从哪来

构建系统本身不含任何 Rockchip 厂商源码。kernel、u-boot、rkbin、buildroot 全部通过 Google `repo` + manifest 从各自上游拉取，或导入本地已下载的 SDK。本页说明拉取模型、版本锁定、本地导入与自定义 manifest。

## 拉取模型

`fetch_sources.sh` 是唯一拉取入口，被 `make fetch` / `make fetch-custom` / `make update` 调用。它把 `manifests/` 目录临时初始化为 git 仓库作为 manifest 源，再 `repo init -u file://<tmp> -m <manifest>` + `repo sync`（带重试，默认 3 次，间隔递增）。每个组件拉取后打印 `rev (branch)`。

## 内置 manifest 与板型映射

`manifests/` 下每个 `.xml` 是一个 SDK 来源，板型通过 `boards/<BOARD>/board.conf` 的 `SOURCE_MANIFEST` 选择：

| manifest | 对应板型（示例） |
|---|---|
| `rk3588-rock5c.xml` | `rk3588s-rock-5c`（Radxa ROCK 5C，全量锁定 commit） |
| `rk3588-linux-5.10.xml` | `rk3588-evb1-lp4-v10-linux`（官方 5.10 SDK，可用 fetch-custom 换 6.1/6.6） |
| `rk3588-muse-5.10.xml` | `rk3588-muse`（MUSE 维护的 fork） |
| `rk3588-radxa.xml` / `rk3588-orangepi.xml` / `rk3588-firefly.xml` / `rk3588-linux-6.1.xml` / `rk3588-linux-6.6.xml` | 仓库内置的其它可选来源 |

`make fetch BOARD=<board>` 自动派生卷名 `rk3588-sdk-<manifest 去 rk3588- 前缀去 .xml>`（如 `rk3588-rock5c`）。CokePi 系列板型不设置 `SOURCE_MANIFEST`，需本地导入（见下）。

## 版本锁定

当板级 `SOURCE_MANIFEST` 设置后，`board.conf` 的 `EXPECTED_KERNEL_REVISION` / `EXPECTED_UBOOT_REVISION` / `EXPECTED_RKBIN_REVISION` / `EXPECTED_BUILDROOT_REVISION` 必须为 40 位完整 Git SHA。`common.sh` 的 `validate_board_source_revisions` 在 `build-*` 各阶段前比对实际 `HEAD`；`fetch_sources.sh` 拉取后也会校验。不匹配即中止，保证可复现。manifest 内 `project revision=` 同样锁定各组件 commit（如 `rk3588-rock5c.xml` 锁定 kernel `567401fe...`、u-boot `4218b05a...`、rkbin `ecb4fcbe...`、buildroot `c49ae721...`）。

## 导入本地 SDK

对已有本地 SDK 目录的板型（如 CokePi）：

```bash
make import-local-sdk SDK_PATH=/abs/path/to/sdk SDK_VOLUME=rk3588-sdk-local
```

该命令创建 bind-backed Docker 卷（`--driver local --opt type=none --opt o=bind --opt device=<path>`），源码始终留在原地、不复制。随后写入 `.env` 的 `SDK_VOLUME`。`make verify-sdk-volume` 会校验卷内四组件目录存在且 builder 用户（uid 1000）可写。

## 自定义 manifest

本地文件：

```bash
make fetch-custom SDK_VOLUME=<v> MANIFEST=my.xml
```

远程 URL：

```bash
make fetch-custom SDK_VOLUME=<v> \
  CUSTOM_MANIFEST_URL=https://example.com/manifests.git \
  CUSTOM_MANIFEST_NAME=my.xml
```

自定义 manifest 必须有 `<remote name="buildroot" ...>`（由 `check.sh` 的 `check_manifests` 校验）。格式与标准 `repo` manifest 相同：`<project name= path= remote= revision= />`。

## 管理 SDK volume

| 命令 | 作用 |
|---|---|
| `make fetch BOARD=<b>` | 拉取到派生卷 |
| `make update SDK_VOLUME=<v>` | 更新已有卷 |
| `make import-local-sdk ...` | 本地目录以 bind 卷接入 |
| `make verify-sdk-volume SDK_VOLUME=<v>` | 校验四组件与可写性 |
| `make use-volume` | 切换当前卷 |
| `make status` | 列出 `rk3588-*` 卷 |

## 浅克隆与完整克隆

`DEPTH`（默认 `1`）控制 `repo` 浅克隆深度；`0` 为完整克隆。`fetch_sources.sh` 在 `DEPTH != 0` 时给 `repo init` 加 `--depth=<DEPTH>`。浅克隆更快但无法回溯历史；需要 `git` 历史做补丁开发时用 `DEPTH=0`。
