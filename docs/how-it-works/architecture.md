# 架构与目录

本页说明构建系统的整体结构、两个 Docker 镜像、目录映射、SDK 卷与输出布局。设计目标是：宿主只需 Docker 与 GNU Make，所有交叉工具链、QEMU、Rockchip 专有工具都封装在容器内；新增板型不改任何脚本。

## 整体结构

```text
rk3588-build/
├── Makefile                  # 所有 make 入口与交互菜单
├── Dockerfile                # 双阶段：rk3588-build（x86_64/amd64 或 arm64 通用）+ debian-rootfs（arm64）
├── docker-compose.yml        # 两个服务 + 三个命名卷的编排
├── manifests/                # repo manifest XML（每个 SDK 来源一个）
├── boards/                   # 板型为单元：每板一个目录（board.conf / kernel.config / rootfs / check.sh）
│   └── TEMPLATE/             # 新建板型模板（make new-board 的起点）
├── configs/
│   ├── kernel/               # 共享内核 fragment（rootfs-base.config / squashfs-overlay.config）
│   └── soc/                  # SoC 平台特性（如 rk3588.conf：QEMU 黑名单 / 串口 getty mask）
├── scripts/
│   ├── lib/
│   │   ├── common.sh         # 公共库：profile 加载、校验、overlay 应用、元数据
│   │   ├── bootloader_layouts.sh  # 启动链布局抽象层（rockchip-gpt-idblock-extlinux-v1）
│   │   └── qemu_smoke.py     # QEMU 冒烟测试驱动（pexpect）
│   ├── fetch_sources.sh      # SDK 拉取 / 更新（repo + manifest）
│   ├── build_uboot.sh        # U-Boot + RKNS IDBlock
│   ├── build_kernel.sh       # 内核 Image / DTB / 模块
│   ├── build_buildroot.sh    # Buildroot rootfs
│   ├── build_debian.sh       # Debian rootfs（mmdebstrap）
│   ├── make_image.sh         # GPT 裸镜像组装
│   ├── verify_image.sh       # 镜像深度校验
│   ├── test_debian_qemu.sh   # 调用 qemu_smoke.py
│   ├── check.sh              # 项目自检（语法/契约/manifest）
│   ├── entrypoint.sh         # 容器入口（编译器/缓存/git 自检）
│   └── import_local_sdk.sh   # 本地 SDK 以 bind 卷导入
├── rootfs/
│   ├── buildroot/            # Buildroot external tree（defconfig / board overlay / post-build）
│   └── debian/               # Debian 可选 overlay 插件 + ro-overlay initramfs hook
│       └── overlays/         # base / console / firstboot / firstboot-info / network
├── docs/                     # VitePress 文档站点（即本站点）
├── patches/                  # 可选本地补丁（手动应用，仓库未自动套用）
└── output/                   # 所有构建产物（按板型 + rootfs 分目录）
```

## 两个 Docker 镜像

`Dockerfile` 定义两个构建阶段（stage）：

1. **`rk3588-build`**（目标 `rk3588-build`）：基于 `ubuntu:22.04` 的通用构建器，安装交叉编译器 `aarch64-linux-gnu-`、`gcc-arm-linux-gnueabihf`、设备树编译器、`qemu-system-arm`、Python 2.7（Rockchip `make.sh`/FIT 生成器需要）、`repo`、e2fsprogs 1.47.2（支持 Debian trixie 的 ext4 特性）、`shellcheck` 等。amd64 宿主额外启用 i386 兼容（rkbin 工具需要）；arm64 宿主安装 `qemu-user-static` 以运行为 x86-64 的 rkbin 工具。UID 1000 的 `builder` 用户拥有工作区。入口 `entrypoint.sh`。

2. **`debian-rootfs`**（目标 `debian-rootfs`）：基于 `debian:trixie-slim` 的 ARM64 原生构建器，仅安装 `mmdebstrap`、`systemd`、`squashfs-tools`、`mount` 等 Debian rootfs 构建所需的最小集合。`docker-compose.yml` 中标记为 `platform: linux/arm64` 且 `privileged: true`。Debian rootfs 必须在此镜像中原生构建（x86_64 宿主通过 binfmt 模拟）。

## 目录映射

`docker-compose.yml` 把宿主机源码以只读方式挂入容器，SDK 与输出为可写卷：

| 挂载 | 容器内路径 | 模式 |
|---|---|---|
| `./scripts` | `/home/builder/scripts` | ro |
| `./manifests` | `/home/builder/manifests` | ro |
| `./patches` | `/home/builder/patches` | ro |
| `./configs` | `/home/builder/configs` | ro |
| `./rootfs` | `/home/builder/rootfs` | ro |
| `./boards` | `/home/builder/boards` | ro |
| `./output` | `/home/builder/output` | 可写 |
| SDK 卷（`sdk`） | `/home/builder/sdk` | 可写（external） |
| `rk3588-ccache` | `/home/builder/.ccache` | 可写 |
| `sbc-apt-cache` | `/var/cache/apt/archives`（仅 debian-rootfs） | 可写 |

`PROJECT_DIR` 容器内固定为 `/home/builder`，`SDK_DIR` 为 `/home/builder/sdk`，`OUTPUT_DIR` 为 `/home/builder/output`。板级脚本只读访问 `boards/`，绝不在构建期写回（见 `boards/README.md` 的 plugin 规则）。

## SDK Volume

SDK 源码保存在名为 `rk3588-sdk-<name>` 的 Docker 卷中（或在 `rk3588-sdk-*` 命名空间内）。`make fetch` 按板级 `SOURCE_MANIFEST` 派生卷名（如 `rk3588-sdk-rock5c`）；`make import-local-sdk` 把本地目录以 bind 卷接入（不复制源码）。卷内固定包含四个组件目录：`kernel`、`u-boot`、`rkbin`、`buildroot`。`make verify-sdk-volume` 校验四目录存在且可写。

## 输出目录

产物按 `output/<BOARD>/<variant>/` 组织，其中 `<variant>` 为 `common`（跨 rootfs 共享产物）、`buildroot`，或 `debian-<release>`（如 `debian-13`）。

```text
output/<BOARD>/
├── common/                 # Image, <DTB>, kernel.config, kernel-release, modules.tar, System.map
│                          # idblock.img, uboot.img, download-loader.bin, 以及 *-build-info.txt
├── buildroot/             # rootfs.ext4, rootfs.tar, buildroot.config, rootfs-build-info.txt
└── debian-13/             # rootfs.ext4 或 rootfs.squashfs, initrd.img, rootfs.tar
                             # <BOARD>-debian-13.img, .img.zst, .sha256, image-build-info.txt
```

`IMAGE_STEM` 为 `<BOARD>-<variant>`（如 `rk3588s-rock-5c-debian-13`），镜像与压缩包、校验和同名。`common/` 内的 `kernel-build-info.txt`、`uboot-build-info.txt` 等元数据记录各组件 commit、defconfig、扇区、SHA256 等，供 `verify_image.sh` 与 `image-build-info.txt` 引用。

## 容器入口

`entrypoint.sh` 在容器启动时：若以 root 进入则通过 `gosu` 降权到 builder 用户；配置交叉编译器或 ARM64 原生编译（`USE_NATIVE_BUILD`）；启用 ccache；配置 git 全局身份与 git-lfs；打印环境横幅；按需 `FETCH_ON_START=yes` 自动拉取或仅检查 SDK 是否存在；交互式 shell 时执行工具链自检。
