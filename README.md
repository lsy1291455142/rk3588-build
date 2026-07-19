# RK3588 Linux BSP Docker Build Environment

基于 Docker 的 RK3588 BSP 构建环境。在容器中完成 loader、U-Boot、内核、设备树、模块与 rootfs 的编译，并打包为可直接写入 SD / eMMC 的 GPT raw 镜像。

本仓库管理的是**构建流程与板级配置**，不是厂商 BSP 本体。SDK 通过独立 Docker volume 接入；CokePi 等无法公开拉取的 SDK 使用本地导入。

构建阶段说明见 [完整系统镜像构建流程](docs/RK3588_SYSTEM_IMAGE_BUILD_FLOW.md)。板级字段说明见 [configs/README.md](configs/README.md)。

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/lsy1291455142/rk3588-build)

### GitHub Codespaces

本项目支持在 GitHub Codespaces 中直接打开，预配置 Docker-in-Docker 与编译工具链，无需在本地安装 Docker 与交叉编译环境。点击上方徽章即可创建实例。

- 个人账户通常每月有一定核时与存储额度（以 GitHub 当前政策为准）
- 空闲实例会自动暂停；长期不用建议在 [Codespaces 管理页](https://github.com/codespaces) 删除，避免持续占用存储

---

## 能得到什么 / 不包含什么

| 会产出 | 不包含 |
|---|---|
| Kernel `Image`、指定 DTB、`modules.tar` | 桌面环境 |
| Rockchip loader（`idblock.img` / `download-loader.bin`）、`uboot.img` | Mali / MPP / RKNPU 用户态 |
| Buildroot 或 Debian rootfs | Rockchip `update.img` |
| FAT32 boot + extlinux、ext4 rootfs | SPI NAND 布局 |
| 4 GiB GPT raw image、`.img.zst`、SHA256、离线校验 | 真实硬件 bring-up 保证 |

离线校验只证明镜像结构与内容一致；串口启动与板级功能仍需在硬件上确认。

---

## 环境要求

- Docker Engine / Desktop
- Docker Compose v2
- GNU Make

Windows 建议在 Git Bash 或 WSL 中执行 `make`。宿主机无需预先安装交叉编译器或 QEMU。

| 宿主机 | Kernel / U-Boot | Buildroot | Debian rootfs |
|---|---|---|---|
| x86_64 | 交叉编译 | 交叉编译 | ARM64 容器 + QEMU binfmt |
| ARM64 | 交叉或原生 | 交叉编译 | 原生 ARM64 |

`make` 会按宿主机架构自动处理 binfmt 与兼容库；x86_64 会安装 i386 依赖以运行部分 rkbin 工具，ARM64 会安装 `qemu-user-static` 以运行其中的 x86 预编译工具。

---

## 三个核心参数

所有组件构建与镜像打包都依赖下面三个变量，**均无默认值**。缺一不可时目标会直接失败。

| 变量 | 含义 | 设置方式 |
|---|---|---|
| `SDK_VOLUME` | 存放 BSP 源码的 Docker volume | `make fetch-*` / `import-local-sdk` / `use-volume-*` / CLI |
| `BOARD` | `configs/boards/<name>.conf` 板级配置 | `make use-board-*` / CLI |
| `ROOTFS` | `buildroot` \| `debian` \| `all` | `make use-rootfs-*` / CLI |

可写入 `.env` 供后续命令继承，也可在单次命令中覆盖：

```bash
make use-volume-rock5c
make use-board-rock5c
make use-rootfs-debian
make use-current

# 等价的一次性传参
make build-all \
  BOARD=rk3588s-rock-5c \
  SDK_VOLUME=rk3588-sdk-rock5c \
  ROOTFS=debian \
  DEBIAN_RELEASE=13
```

可选变量见 [`.env.example`](.env.example)。常用项：`DEBIAN_RELEASE`（默认 13）、`ROOTFS_USERNAME` / `ROOTFS_PASSWORD`、`JOBS`、`ZSTD_LEVEL`。

---

## 已支持板型

| `BOARD` | 硬件 | 配套 `SDK_VOLUME` | 源码来源 |
|---|---|---|---|
| `rk3588s-rock-5c` | Radxa ROCK 5C | `rk3588-sdk-rock5c` | `make fetch-rock5c`（锁定 commit） |
| `rk3588-evb1-lp4-v10-linux` | Rockchip EVB1 LP4 V1.0 | `rk3588-sdk-rockchip-5.10` | `make fetch-510` |
| `rk3588-cokepi-plus-lp4-v10` | CokePi Plus（RK3588） | `rk3588-sdk-cokepi-rkr9` | 本地 `import-local-sdk` |
| `rk3588s-cokepi-model-lp4-v10` | CokePi Model（RK3588S） | `rk3588-sdk-cokepi-rkr9` | 本地 `import-local-sdk` |

CokePi 两套 profile 分别使用 SDK 中 HDMI 设备树：

- Plus：`rk3588-cpp-hdmi.dtb`
- Model：`rk3588s-cpm-hdmi1.dtb`

按板卡丝印选择，Plus 与 Model 不可混用。其他板型在生成镜像前需新增匹配的 board profile，并确认 DTB、U-Boot 与存储布局。

---

## 快速路径

先构建或拉取 builder 镜像，再准备 SDK，再指定 `BOARD` / `ROOTFS` 执行完整构建。

### 路径 A：ROCK 5C + Debian 13（公开源，推荐入门）

```bash
make build
make fetch-rock5c
make build-all \
  BOARD=rk3588s-rock-5c \
  SDK_VOLUME=rk3588-sdk-rock5c \
  ROOTFS=debian \
  DEBIAN_RELEASE=13
make test-debian-qemu \
  BOARD=rk3588s-rock-5c \
  SDK_VOLUME=rk3588-sdk-rock5c \
  DEBIAN_RELEASE=13
```

`test-debian-qemu` 在 ARM64 virt 上做冒烟测试（串口登录、systemd、扩容、网络/SSH），**不能**替代真实硬件验收。

### 路径 B：CokePi（本地 SDK）

SDK 需已解压，根目录直接包含 `kernel/`、`u-boot/`、`rkbin/`、`buildroot/`。导入为 bind-backed volume，**不复制**源码。

```bash
# builder：本地构建，或拉取 GHCR 后打本地 tag
make build
# docker pull ghcr.io/lsy1291455142/rk3588-build:latest
# docker tag ghcr.io/lsy1291455142/rk3588-build:latest rk3588-build:latest

make import-local-sdk \
  SDK_PATH=/absolute/path/to/rk3588_linux-5.10-cokepi-rkr9 \
  SDK_VOLUME=rk3588-sdk-cokepi-rkr9
make verify-cokepi-sdk SDK_VOLUME=rk3588-sdk-cokepi-rkr9

# Model 示例；Plus 改为 use-board-cokepi-plus / 对应 BOARD
make use-board-cokepi-model
make use-rootfs-debian
make build-all \
  BOARD=rk3588s-cokepi-model-lp4-v10 \
  SDK_VOLUME=rk3588-sdk-cokepi-rkr9 \
  ROOTFS=debian \
  DEBIAN_RELEASE=13
```

### 路径 C：EVB1 + Buildroot

```bash
make build
make fetch-510
make build-all \
  BOARD=rk3588-evb1-lp4-v10-linux \
  SDK_VOLUME=rk3588-sdk-rockchip-5.10 \
  ROOTFS=buildroot
```

---

## Builder 镜像

### 本地构建

```bash
make build                 # 构建 rk3588-build:latest
make build-debian-builder  # Debian rootfs 用 ARM64 builder（按需）
```

Debian rootfs 在独立 `linux/arm64` 容器中构建（`mmdebstrap`，privileged）。选择 `ROOTFS=debian` 时，`build-rootfs` / `build-all` 会自动准备该 builder。仅在可信主机与可信代码上执行。

Builder 基于 Ubuntu 22.04，同时提供 Python 2/3，供不同 U-Boot BSP 使用。`UBOOT_PYTHON` 在 board profile 中显式指定；全局 `python` 仍指向 Python 3。

### 从 GHCR 拉取

CI 只发布 **`rk3588-build` 工具链镜像**，不包含厂商 SDK、板级 `.img`，也不推送 `debian-rootfs`。

镜像为 **multi-arch**：`linux/amd64` 与 `linux/arm64` 同一 tag。Docker 会按宿主机架构自动拉取对应变体；x86_64 主机交叉编译目标板，ARM64 主机可原生运行 builder。

```text
ghcr.io/lsy1291455142/rk3588-build:latest
ghcr.io/lsy1291455142/rk3588-build:main
ghcr.io/lsy1291455142/rk3588-build:sha-<short-sha>
```

触发：`main` 上与 builder 相关路径变更自动构建并 push；PR 只构建不 push；也可在 Actions 中手动运行 `docker-rk3588-build`。

```bash
# 私有 package 时先登录（需 read:packages）
echo "$GHCR_TOKEN" | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin

docker pull ghcr.io/lsy1291455142/rk3588-build:latest
docker tag ghcr.io/lsy1291455142/rk3588-build:latest rk3588-build:latest
```

Makefile / Compose 默认使用本地名 `rk3588-build:latest`，拉取后需打上述 tag。使用本仓库 `docker compose` 时，工作区中的 `scripts/`、`configs/` 等仍会 bind mount 覆盖镜像内副本。

---

## SDK 管理

每个 BSP 源码对应独立 volume，互不污染：

| 命令 | Volume |
|---|---|
| `make fetch-510` | `rk3588-sdk-rockchip-5.10` |
| `make fetch-61` | `rk3588-sdk-rockchip-6.1` |
| `make fetch-66` | `rk3588-sdk-rockchip-6.6` |
| `make fetch-firefly` | `rk3588-sdk-firefly` |
| `make fetch-radxa` | `rk3588-sdk-radxa` |
| `make fetch-rock5c` | `rk3588-sdk-rock5c` |
| `make fetch-orangepi` | `rk3588-sdk-orangepi` |

自定义：

```bash
make fetch-custom SDK_VOLUME=rk3588-sdk-custom MANIFEST=my-board.xml
make fetch-custom \
  SDK_VOLUME=rk3588-sdk-custom \
  CUSTOM_MANIFEST_URL=https://example.com/manifests.git \
  CUSTOM_MANIFEST_NAME=board.xml
make update SDK_VOLUME=rk3588-sdk-radxa
docker volume ls --filter name=rk3588
```

### 本地导入（大体积 SDK）

```bash
make import-local-sdk \
  SDK_PATH=/absolute/path/to/sdk \
  SDK_VOLUME=rk3588-sdk-local
make verify-sdk-volume SDK_VOLUME=rk3588-sdk-local
```

要求 SDK 根目录含 `kernel/`、`u-boot/`、`rkbin/`、`buildroot/`。容器内 `/home/builder/sdk` 直接映射该目录；构建缓存写在 SDK 下的 `.rk3588-build/`。删除 Docker volume **不会**删除宿主机源码；移动宿主机路径会使 volume 失效。Docker daemon 须能访问传入的绝对路径。

本地 volume 只解决源码接入；新硬件仍须增加 board profile。

---

## 构建目标与产物

```bash
make build-kernel    # Image、DTB、modules.tar
make build-uboot     # idblock.img、uboot.img、download-loader.bin
make build-rootfs    # Buildroot 和/或 Debian rootfs
make image           # 打包 GPT 镜像，并自动 verify-image
make verify-image    # 单独离线校验
make build-all       # kernel + uboot + rootfs + image
make test-debian-qemu
make test-debian-all # 复用一次 bootloader/kernel，依次打 Debian 11/12/13
```

产物目录：

```text
output/<board>/
├── common/
│   ├── Image
│   ├── <board-or-dtb-name>.dtb
│   ├── modules.tar
│   ├── idblock.img          # RKNS，写入 sector 64
│   ├── uboot.img
│   ├── download-loader.bin  # LDR，供 rkdeveloptool db
│   └── *-build-info.txt
├── buildroot/
│   ├── rootfs.ext4
│   ├── <board>-buildroot.img[.zst]
│   └── ...
└── debian-13/
    ├── rootfs.ext4
    ├── <board>-debian-13.img[.zst]
    └── ...
```

打包进 FAT 的 DTB 会去掉 `/chosen/bootargs`，保证启动参数以 extlinux 为准（`root=PARTLABEL=rootfs`），避免厂商 DTB 中固定 `root=PARTUUID=...` 覆盖。

### 镜像布局

```text
sector 0                    Protective MBR / GPT
sector 64                   idblock.img (RKNS)
sector 16384                uboot.img
16 MiB .. 272 MiB           FAT32 BOOT：Image、DTB、extlinux
272 MiB .. image end        ext4 rootfs（PARTLABEL=rootfs）
```

rootfs 文件系统初始约 2 GiB，分区占满镜像剩余空间。Debian 首次启动会修复备份 GPT、扩展分区与 ext4。

### 默认登录

```text
用户: rk3588
密码: rk3588
root 密码: rk3588
```

`ROOTFS_USERNAME` / `ROOTFS_PASSWORD` 可改。默认密码仅适合隔离实验环境。

---

## 烧录

务必核对目标设备名，写错会覆盖宿主机磁盘：

```bash
zstd -d output/<board>/<variant>/<board>-<variant>.img.zst
sudo dd if=output/<board>/<variant>/<board>-<variant>.img \
  of=/dev/sdX bs=4M status=progress conv=fsync
```

---

## 新板适配要点

1. 准备对应 SDK（`fetch-*` 或 `import-local-sdk`）
2. 复制最近似的 `configs/boards/*.conf`，修改 DTB、defconfig、U-Boot 参数与串口
3. 确认 loader / U-Boot 扇区不与 boot 分区重叠
4. 用 `BOARD=...` 构建并做离线校验，再在硬件上串口验收

字段说明见 [configs/README.md](configs/README.md)，阶段细节见 [构建流程](docs/RK3588_SYSTEM_IMAGE_BUILD_FLOW.md)。

---

## CI 与依赖更新

- **GitHub Actions**：`.github/workflows/docker-rk3588-build.yml` 分别在 x64 / ARM runner 上构建 `linux/amd64` 与 `linux/arm64`，合并为 multi-arch 清单后推送 `rk3588-build` 至 GHCR。
- **Dependabot**：`.github/dependabot.yml` 跟踪 Docker 基础镜像与 Actions 版本。对 `ubuntu` / `debian` 的 **major** 升级已 ignore——builder 固定在 Ubuntu 22.04（Python 2、i386 兼容栈），大版本升级需单独评估，不宜直接合入。

---

## 其他命令

```bash
make help
make check
make shell          # 进入构建容器
make status
make clean          # 停止容器
make clean-all      # 停止并删除 volume / 镜像
```

---

## 许可证

分发镜像时需同时处理 Kernel、U-Boot、Buildroot/Debian 软件包及 rkbin 固件各自的许可证义务。容器构建不免除 Kernel / U-Boot 的 GPL 源码提供义务。
