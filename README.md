# RK3588 Linux BSP Docker Build Environment

基于 Docker 容器化的 SBC Linux 系统镜像构建工具，为 RK3588 / RK3588S 开发板构建可直接烧录启动的 GPT 磁盘镜像。

整条流水线在一个命令里完成：拉取 SDK → 编译 U-Boot → 编译内核 → 生成根文件系统（Buildroot 或 Debian）→ 组装 GPT 镜像 → 校验镜像 → 可选 QEMU 冒烟启动测试。宿主机只需要 Docker 和 GNU Make，不需要安装交叉工具链、QEMU 或任何 Rockchip 专有工具。

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/lsy1291455142/rk3588-build)

> [!TIP]
> **一键云端构建**：本项目已完整支持 GitHub Codespaces。点击上方按钮可直接在云端打开预配置好 Docker-in-Docker 和编译工具链的开发环境，无需在本地配置 Docker 和运行环境。
> * **免费额度**：GitHub 个人账户每月赠送 **120 核时**（默认 2 核机器可运行 60 小时）与 **15 GB 存储**空间。
> * **省流建议**：不使用时容器会自动暂停（不计运行时间）。为了避免持续占用 15 GB 存储额度，编译/测试完成后建议及时去 [GitHub Codespaces 管理页](https://github.com/codespaces) 删除不用的实例。

## 能做什么

- 配置驱动的多板型支持 — 新增板子只需创建一个 `.conf` 配置文件
- 用 `repo` manifest 锁定 kernel / u-boot / rkbin / buildroot 四个组件的来源与版本
- 用板级 defconfig 加共享 fragment 构建内核，产出 Image、DTB 和模块包
- 用 Buildroot external tree 或 mmdebstrap 生成最小化根文件系统；Debian 可选功能集（`nm`/`wifibt` 等）
- 按 GPT 布局组装裸镜像，内置 extlinux 启动配置、SHA-256 校验和与构建元数据
- 支持板级构建钩子（hooks），可在构建各阶段插入自定义逻辑
- 用 QEMU virt 机器对 Debian 镜像做完整的串口登录 + SSH + systemd 健康检查

## 快速开始

### 查看支持的板型

```bash
make list-boards
```

### 完整构建（以 ROCK 5C + Debian 13 为例）

```bash
make build                           # 构建 Docker 构建器镜像（一次性）
make fetch BOARD=rk3588s-rock-5c     # 拉取 SDK 到独立 volume（一次性）
make build-all \
  BOARD=rk3588s-rock-5c \
  ROOTFS=debian DEBIAN_RELEASE=13
```

产物在 `output/rk3588s-rock-5c/debian-13/`：

- `rk3588s-rock-5c-debian-13.img` — 裸 GPT 镜像，可直接 `dd` 烧录
- `rk3588s-rock-5c-debian-13.img.zst` — zstd 压缩镜像
- `rk3588s-rock-5c-debian-13.sha256` — 校验和
- `image-build-info.txt` — 完整的构建元数据（各组件 commit、分区布局、哈希）

默认账号 `user` / `password`，root 密码同为 `password`。首次启动自动扩容根分区并开启 SSH。

### QEMU 冒烟测试

```bash
make test-debian-qemu \
  BOARD=rk3588s-rock-5c \
  DEBIAN_RELEASE=13
```

### 交互式配置

```bash
make use-board              # 交互式选择板型
make use-volume             # 交互式选择 SDK volume
make use-rootfs             # 交互式选择根文件系统类型
make info                   # 查看当前配置
```

## 已支持的板型

| Profile | 硬件 | 内核 | 说明 |
|---|---|---|---|
| `rk3588-evb1-lp4-v10-linux` | Rockchip EVB1 参考板 | rockchip_linux_defconfig | 参考实现 |
| `rk3588s-rock-5c` | Radxa ROCK 5C | rockchip_linux_defconfig | manifest 全量锁定 commit |
| `rk3588-cokepi-plus-lp4-v10` | CokePi Plus (RK3588) | cokepi_main_defconfig | 需本地 CokePi SDK |
| `rk3588s-cokepi-model-lp4-v10` | CokePi Model (RK3588S) | cokepi_main_defconfig | 需本地 CokePi SDK |
| `rk3588-muse` | MUSE RK3588 (eMMC) | rockchip_linux_defconfig | kernel 来自 MUSEInstitute fork |

运行 `make list-boards` 查看完整列表。

## 如何添加新板子

这是本工具的核心设计 — 添加新板子**无需修改任何构建脚本或 Makefile**。

### 步骤 1: 创建配置文件

```bash
make new-board BOARD=my-board
# 编辑 configs/boards/my-board.conf
```

### 步骤 2: 填写配置

打开生成的 `configs/boards/my-board.conf`，按注释提示填写：

- **`BOARD_DESCRIPTION`** — 板型描述
- **`KERNEL_DEFCONFIG`** / **`KERNEL_DTB`** — 内核配置
- **`UBOOT_DEFCONFIG`** / **`UBOOT_BOARD`** — U-Boot 配置
- **`CONSOLE`** — 串口配置（如 `ttyFIQ0,1500000n8`）
- **`BOOTLOADER_LAYOUT`** — 启动链布局（Rockchip 统一用 `rockchip-gpt-idblock-extlinux-v1`）
- 磁盘/分区尺寸、扇区偏移等

完整配置变量说明见 `configs/boards/TEMPLATE.conf`。

### 步骤 3: 验证配置

```bash
make validate-board BOARD=my-board
```

### 步骤 4: 添加 SDK manifest（如需要）

在 `manifests/` 下创建对应的 `.xml` manifest 文件，并在 board.conf 中设置 `SOURCE_MANIFEST`。

### 步骤 5: 构建钩子（可选）

如果需要在构建流程中执行板级特殊逻辑，创建 `configs/boards/my-board.hooks.sh`：

```bash
# 可用钩子函数（均可选，不需要的不用定义）：
pre_build_kernel()    { echo "自定义内核预处理"; }
post_build_kernel()   { echo "自定义内核后处理"; }
pre_build_uboot()     { echo "自定义 U-Boot 预处理"; }
post_build_uboot()    { echo "自定义 U-Boot 后处理"; }
pre_build_rootfs()    { echo "自定义 rootfs 预处理"; }
post_build_rootfs()   { echo "自定义 rootfs 后处理"; }
pre_make_image()      { echo "自定义镜像组装预处理"; }
post_make_image()     { echo "自定义镜像组装后处理"; }
```

## 高级定制：添加预装软件包与固件

### 1. 预装额外的 APT 软件包 (Debian)

无需修改源码脚本，有三种极简方式添加：

- **方式 A (命令行直接指定)**:
  ```bash
  make build-all BOARD=rk3588s-rock-5c DEBIAN_EXTRA_PACKAGES="htop i2c-tools python3-pip"
  ```
- **方式 B (在 `.env` 中全局指定)**:
  ```ini
  DEBIAN_EXTRA_PACKAGES=htop i2c-tools network-manager-gnome docker.io
  ```
- **方式 C (在板级配置中固定)**:
  在 `configs/boards/<my-board>.conf` 中增加：
  ```bash
  DEBIAN_EXTRA_PACKAGES="htop i2c-tools python3-pip"
  ```

### 2. 预装自定义硬件固件 (Firmware)

把任何固件文件或文件夹放进项目根目录的 `assets/firmware/`，构建时会自动同步到 Rootfs 的 `/lib/firmware/`：

```
assets/firmware/
├── my_custom_firmware.bin
└── rtl_bt/
```

若是板型专属固件，也可放在 `configs/boards/<board>/firmware/` 下。

## 文档

完整文档在 `docs/` 目录，用 VitePress 构建：

```bash
cd docs
npm install
npm run dev      # 本地预览
npm run build    # 构建静态站点
```

或者直接阅读 Markdown：

- [简介](docs/intro/what-is.md) — 项目定位与设计理念
- [快速上手](docs/usage/quick-start.md) — 从零到烧录镜像
- [日常构建](docs/usage/daily-build.md) — 增量构建与切换
- [烧录与启动](docs/usage/flash-and-boot.md) — 写入 SD/eMMC 与首次启动
- [SDK 来源](docs/usage/sdk.md) — fetch、import、自定义 manifest
- [架构](docs/how-it-works/architecture.md) — 目录、容器、volume 布局
- [构建流水线](docs/how-it-works/pipeline.md) — 五个阶段的详细数据流
- [磁盘与启动契约](docs/how-it-works/boot-contract.md) — GPT 布局与引导链
- [板型](docs/boards/supported.md) — 已支持板型详解
- [新增板型](docs/boards/add-board.md) — 板级 profile 编写指南
- [Make 目标](docs/reference/make-targets.md) — 完整目标参考
- [变量与 .env](docs/reference/variables.md) — 所有可配置变量
- [排错](docs/reference/troubleshooting.md) — 常见问题与修复

## 环境要求

- Docker（Linux、macOS 或 Windows + WSL2）
- GNU Make
- 约 50 GB 可用磁盘空间（SDK 源码 + 构建产物 + 镜像）

x86_64 宿主机首次构建 Debian rootfs 时会自动注册 ARM64 binfmt 模拟，无需手动干预。ARM64 宿主机（如 Apple Silicon）则原生运行。

## 项目结构一览

```
rk3588-build/
├── Makefile                  # 所有构建入口（make help 查看）
├── Dockerfile                # 双阶段：Ubuntu 构建器 + Debian rootfs 构建器
├── docker-compose.yml        # 服务与 volume 编排
├── manifests/                # repo manifest（每个 SDK 来源一个 XML）
├── configs/
│   ├── boards/               # 板级 profile（每板一个 .conf + 可选 .hooks.sh）
│   │   ├── TEMPLATE.conf     # 配置模板（新增板型的起点）
│   │   ├── rk3588s-rock-5c.conf
│   │   └── ...
│   └── kernel/               # 共享内核 config fragment
├── scripts/
│   ├── lib/
│   │   ├── common.sh         # 公共 shell 库（配置加载、钩子、overlay）
│   │   └── bootloader_layouts.sh  # 启动链布局抽象层
│   ├── fetch_sources.sh      # SDK 拉取与更新
│   ├── build_kernel.sh       # 内核编译
│   ├── build_uboot.sh        # U-Boot 引导链编译
│   ├── build_buildroot.sh    # Buildroot rootfs
│   ├── build_debian.sh       # Debian rootfs (mmdebstrap)
│   ├── make_image.sh         # GPT 镜像组装
│   ├── verify_image.sh       # 镜像深度校验
│   └── test_debian_qemu.sh   # QEMU 冒烟测试
├── rootfs/
│   ├── buildroot/            # Buildroot external tree
│   └── debian/               # Debian overlay (通用 + feature + 板级)
├── patches/                  # 可选本地补丁（手动应用）
├── docs/                     # VitePress 文档站点
└── output/                   # 所有构建产物（按板型和 rootfs 分目录）
```

## 许可证与免责

本项目仅包含构建编排代码，不包含任何 Rockchip 厂商源码。kernel、u-boot、rkbin、buildroot 均通过 manifest 从各自上游仓库拉取，遵循各自许可证。
