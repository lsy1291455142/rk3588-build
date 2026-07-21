# rk3588-build

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/lsy1291455142/rk3588-build)

> [!TIP]
> **一键云端构建**：本项目已完整支持 GitHub Codespaces。点击上方按钮可直接在云端打开预配置好 Docker-in-Docker 和编译工具链的开发环境，无需在本地配置 Docker 和运行环境。
> * **免费额度**：GitHub 个人账户每月赠送 **120 核时**（默认 2 核机器可运行 60 小时）与 **15 GB 存储**空间。
> * **省流建议**：不使用时容器会自动暂停（不计运行时间）。为了避免持续占用 15 GB 存储额度，编译/测试完成后建议及时去 [GitHub Codespaces 管理页](https://github.com/codespaces) 删除不用的实例。

在 Docker 里基于厂商 BSP 源码，为 RK3588 / RK3588S 开发板构建可直接烧录启动的 GPT 磁盘镜像。

整条流水线在一个命令里完成：拉取 SDK → 编译 U-Boot → 编译内核 → 生成根文件系统（Buildroot 或 Debian）→ 组装 GPT 镜像 → 校验镜像 → 可选 QEMU 冒烟启动测试。宿主机只需要 Docker 和 GNU Make，不需要安装交叉工具链、QEMU 或任何 Rockchip 专有工具。

## 能做什么

- 用 `repo` manifest 锁定 kernel / u-boot / rkbin / buildroot 四个组件的来源与版本
- 用 Rockchip 官方 `make.sh` 构建 U-Boot 引导链（IDBlock + uboot.img + download loader）
- 用板级 defconfig 加共享 fragment 构建内核，产出 Image、DTB 和模块包
- 用 Buildroot external tree 或 mmdebstrap 生成最小化根文件系统
- 按 GPT 布局组装裸镜像，内置 extlinux 启动配置、SHA-256 校验和与构建元数据
- 用 QEMU virt 机器对 Debian 镜像做完整的串口登录 + SSH + systemd 健康检查

## 五分钟跑通（ROCK 5C + Debian 13）

```bash
make build                # 构建 Docker 构建器镜像（一次性）
make fetch-rock5c         # 拉取 ROCK 5C SDK 到独立 volume（一次性）
make build-all \
  BOARD=rk3588s-rock-5c \
  SDK_VOLUME=rk3588-sdk-rock5c \
  ROOTFS=debian DEBIAN_RELEASE=13
```

产物在 `output/rk3588s-rock-5c/debian-13/`：

- `rk3588s-rock-5c-debian-13.img` — 裸 GPT 镜像，可直接 `dd` 烧录
- `rk3588s-rock-5c-debian-13.img.zst` — zstd 压缩镜像
- `rk3588s-rock-5c-debian-13.sha256` — 校验和
- `image-build-info.txt` — 完整的构建元数据（各组件 commit、分区布局、哈希）

默认账号 `rk3588` / `rk3588`，root 密码同为 `rk3588`。首次启动自动扩容根分区并开启 SSH。

跑 QEMU 冒烟测试（串口登录、systemd 健康、SSH 密码登录全验证）：

```bash
make test-debian-qemu \
  BOARD=rk3588s-rock-5c \
  SDK_VOLUME=rk3588-sdk-rock5c \
  DEBIAN_RELEASE=13
```

## 已支持的板型

| Profile | 硬件 | 内核 | 说明 |
|---|---|---|---|
| `rk3588-evb1-lp4-v10-linux` | Rockchip EVB1 参考板 | rockchip_linux_defconfig | 参考实现 |
| `rk3588s-rock-5c` | Radxa ROCK 5C | rockchip_linux_defconfig | manifest 全量锁定 commit |
| `rk3588-cokepi-plus-lp4-v10` | CokePi Plus (RK3588) | cokepi_main_defconfig | 需本地 CokePi SDK |
| `rk3588s-cokepi-model-lp4-v10` | CokePi Model (RK3588S) | cokepi_main_defconfig | 需本地 CokePi SDK |
| `rk3588-muse` | MUSE RK3588 (eMMC) | rockchip_linux_defconfig | kernel 来自 MUSEInstitute fork |

新增板型：复制最接近的 `configs/boards/*.conf`，改字段即可。详见 `docs/boards/add-board.md`。

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
│   ├── boards/               # 板级 profile（每板一个 .conf）
│   └── kernel/               # 共享内核 config fragment
├── scripts/
│   ├── lib/                  # 公共 shell 库 + QEMU 冒烟测试驱动
│   ├── fetch_sources.sh      # SDK 拉取与更新
│   ├── build_kernel.sh       # 内核编译
│   ├── build_uboot.sh        # U-Boot 引导链编译
│   ├── build_buildroot.sh    # Buildroot rootfs
│   ├── build_debian.sh       # Debian rootfs (mmdebstrap)
│   ├── make_image.sh         # GPT 镜像组装
│   ├── verify_image.sh       # 镜像深度校验
│   ├── test_debian_qemu.sh   # QEMU 冒烟测试
│   ├── import_local_sdk.sh   # 导入本地已有 SDK
│   ├── entrypoint.sh         # 容器入口
│   └── check.sh              # 项目自检（make check）
├── rootfs/buildroot/         # Buildroot external tree
├── patches/                  # 可选本地补丁（手动应用）
├── docs/                     # VitePress 文档站点
└── output/                   # 所有构建产物（按板型和 rootfs 分目录）
```

## 许可证与免责

本项目仅包含构建编排代码，不包含任何 Rockchip 厂商源码。kernel、u-boot、rkbin、buildroot 均通过 manifest 从各自上游仓库拉取，遵循各自许可证。
