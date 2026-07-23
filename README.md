# RK3588 Linux BSP Docker Build Environment

基于 Docker 容器化的 SBC Linux 系统镜像构建工具，为 RK3588 / RK3588S 开发板构建可直接烧录启动的 GPT 磁盘镜像。

整条流水线在一个命令里完成：拉取 SDK → 编译 U-Boot → 编译内核 → 生成根文件系统（Buildroot 或 Debian）→ 组装 GPT 镜像 → 校验镜像 → 可选 QEMU 冒烟启动测试。宿主机只需要 Docker 和 GNU Make，不需要安装交叉工具链、QEMU 或任何 Rockchip 专有工具。

完整文档在 `docs/`（VitePress 站点，见下方「文档」）。本文档为仓库总览，详细内容以 `docs/` 为准。

## 能做什么

- 配置驱动的多板型支持 — 新增板子只需创建一个 `board.conf` 配置文件，不改任何脚本。
- 用 `repo` manifest 锁定 kernel / u-boot / rkbin / buildroot 四个组件的来源与版本（ROCK 5C 还锁全部组件 commit）。
- 用板级 defconfig 加共享 fragment 构建内核，产出 Image、DTB 和模块包（板级 `kernel.config` 自动合并可覆盖）。
- 用 Buildroot external tree 或 mmdebstrap 生成最小化根文件系统；Debian 额外支持精确 APT 包与可选 overlay 插件（base/console/firstboot/firstboot-info/network）及板级 plugin。
- 按 GPT 布局组装裸镜像，内置 extlinux 启动配置、SHA-256 校验和与构建元数据。
- 双 rootfs 布局：`rw-ext4`（可写 ext4 根）与 `ro-overlay`（只读 SquashFS 根 + ext4 数据分区，由 initramfs 组装 OverlayFS）。
- 支持板级构建钩子（hooks）与板级 rootfs 附件（plugin/overlay）。
- 用 QEMU `virt` 机器对 Debian 镜像做完整的串口登录 + SSH + systemd 健康检查。

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

Debian 默认账号 `user` / `password`，root 密码同为 `password`。Buildroot 默认账号为 `rk3588` / `rk3588`（见 `scripts/build_buildroot.sh` 内置回退）。首次启动自动扩容根分区并开启 SSH。

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

| Profile | 硬件 | 内核 defconfig | 说明 |
|---|---|---|---|
| `rk3588-evb1-lp4-v10-linux` | Rockchip EVB1 参考板 | `rockchip_linux_defconfig` | 官方 5.10 SDK（manifest `rk3588-linux-5.10.xml`） |
| `rk3588s-rock-5c` | Radxa ROCK 5C | `rockchip_linux_defconfig` | manifest 全量锁定 commit |
| `rk3588-cokepi-plus-lp4-v10` | CokePi Plus (RK3588) | `cokepi_main_defconfig` | 需本地 CokePi SDK 导入 |
| `rk3588s-cokepi-model-lp4-v10` | CokePi Model (RK3588S) | `cokepi_main_defconfig` | 需本地 CokePi SDK 导入；默认 `ro-overlay` |
| `rk3588-muse` | MUSE RK3588 (eMMC) | `rockchip_linux_defconfig` | kernel 来自 MUSE fork（`rk3588-muse-5.10.xml`） |

运行 `make list-boards` 查看完整列表。

## 如何添加新板子

这是本工具的核心设计 — 添加新板子**无需修改任何构建脚本或 Makefile**。

1. `make new-board BOARD=my-board` 生成 `boards/my-board/board.conf` 与空 `kernel.config`。
2. 按 `boards/TEMPLATE/board.conf` 注释填写必填字段（`KERNEL_DEFCONFIG` / `KERNEL_DTB` / `UBOOT_DEFCONFIG` / `UBOOT_BOARD` / `CONSOLE` 等）。
3. `make validate-board BOARD=my-board` 校验。
4. 若从上游拉取 SDK，在 `manifests/` 建 manifest 并设 `SOURCE_MANIFEST`；否则 `make import-local-sdk`。
5. 可选：板级 `rootfs/`（plugin/overlay）与 `board.hooks.sh`。

完整字段说明见 `docs/boards/add-board.md` 与 `boards/TEMPLATE/board.conf`。

## 高级定制

- **额外 APT 包（Debian）**：`DEBIAN_PACKAGES="network-manager,wpasupplicant,i2c-tools"`（精确包名；`none` 仅 minbase；功能别名如 `nm`/`wifibt` 已被拒绝），或板级 `DEBIAN_PACKAGES_DEFAULT`。
- **可选 overlay 插件**：`DEBIAN_OVERLAYS=base,console,network`（`all` / `none` / 显式列表）。
- **静态硬件固件**：放入板级或插件的 `overlay/lib/firmware/`；动态固件（如 `.deb` 提取）由板级 `plugin.sh` 在构建期生成。
- **只读根（ro-overlay）**：`ROOTFS_MODE=ro-overlay`，生成 SquashFS 根 + ext4 数据分区，防掉电损坏。

## 文档

完整文档在 `docs/`，用 VitePress 构建（导航与侧边栏见 `docs/.vitepress/config.ts`）。本地预览：

```bash
cd docs
npm install
npm run dev      # 本地预览
npm run build    # 构建静态站点
```

或直接阅读 Markdown：

- [简介 / 这是什么](docs/intro/what-is.md)
- [环境要求](docs/intro/requirements.md)
- [快速上手](docs/usage/quick-start.md)
- [日常构建](docs/usage/daily-build.md)
- [烧录与启动](docs/usage/flash-and-boot.md)
- [Debian 软件包与可选 Overlay](docs/usage/debian-features.md)
- [SDK 来源](docs/usage/sdk.md)
- [架构](docs/how-it-works/architecture.md)
- [构建流水线](docs/how-it-works/pipeline.md)
- [磁盘与启动契约](docs/how-it-works/boot-contract.md)
- [已支持板型](docs/boards/supported.md)
- [新增板型](docs/boards/add-board.md)
- [Make 目标](docs/reference/make-targets.md)
- [变量与 .env](docs/reference/variables.md)
- [排错](docs/reference/troubleshooting.md)

## 环境要求

- Docker（Linux、macOS 或 Windows + WSL2）与 GNU Make
- 约 50 GB 可用磁盘空间（SDK 源码 + 构建产物 + 镜像）
- x86_64 宿主首次构建 Debian rootfs 时自动注册 ARM64 binfmt 模拟；ARM64 宿主（如 Apple Silicon）原生运行

## 项目结构一览

```text
rk3588-build/
├── Makefile                  # 所有构建入口（make help 查看）
├── Dockerfile                # 双阶段：ubuntu:22.04 构建器 + debian:trixie ARM64 rootfs 构建器
├── docker-compose.yml        # 服务与 volume 编排
├── manifests/                # repo manifest（每个 SDK 来源一个 XML）
├── boards/                   # 板子为单元：每板一个目录（board.conf / kernel.config / rootfs / check.sh）
│   ├── TEMPLATE/             # 配置模板（make new-board 的起点）
│   └── ...
├── configs/
│   ├── kernel/               # 共享内核 fragment（rootfs-base.config / squashfs-overlay.config）
│   └── soc/                  # SoC 特性（rk3588.conf：QEMU 黑名单 / 串口 getty mask）
├── scripts/
│   ├── lib/
│   │   ├── common.sh         # 公共库：profile 加载、校验、overlay、元数据
│   │   ├── bootloader_layouts.sh  # 启动链布局抽象层
│   │   └── qemu_smoke.py     # QEMU 冒烟测试驱动
│   ├── fetch_sources.sh      # SDK 拉取与更新
│   ├── build_kernel.sh       # 内核编译
│   ├── build_uboot.sh        # U-Boot + IDBlock
│   ├── build_buildroot.sh    # Buildroot rootfs
│   ├── build_debian.sh       # Debian rootfs（mmdebstrap）
│   ├── make_image.sh         # GPT 镜像组装
│   ├── verify_image.sh       # 镜像深度校验
│   ├── test_debian_qemu.sh   # QEMU 冒烟测试入口
│   ├── check.sh              # 项目自检
│   ├── entrypoint.sh         # 容器入口
│   └── import_local_sdk.sh   # 本地 SDK 以 bind 卷导入
├── rootfs/
│   ├── buildroot/            # Buildroot external tree
│   └── debian/               # Debian rootfs 附件与可选 overlay 插件
├── patches/                  # 可选本地补丁（手动应用）
├── docs/                     # VitePress 文档站点
└── output/                   # 所有构建产物（按板型和 rootfs 分目录）
```

## 许可证与免责

本项目仅包含构建编排代码，不包含任何 Rockchip 厂商源码。kernel、u-boot、rkbin、buildroot 均通过 manifest 从各自上游仓库拉取，遵循各自许可证。
