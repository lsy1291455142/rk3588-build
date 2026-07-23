# 环境要求

本页说明宿主机的软硬件前提、架构支持、资源建议与验证方式。

## 宿主机

- **Docker**：Linux、macOS（Docker Desktop）或 Windows + WSL2。需要 Docker Engine 与 `docker compose`（Compose v2，`docker compose` 子命令）。
- **GNU Make**：用于驱动 `Makefile` 全部入口。
- 约 **50 GB** 可用磁盘空间（SDK 源码 + 构建产物 + 镜像；`fetch_sources.sh` 默认检查至少 10 GB 余量）。

## 架构支持

- **x86_64 / amd64 宿主**：通用路径。构建器镜像基于 `ubuntu:22.04`，并启用 i386 兼容（rkbin 的 x86-64 预编译工具需要）。首次构建 Debian rootfs 时 `make build-debian-builder` 会自动通过 `tonistiigi/binfmt` 注册 ARM64 binfmt 模拟，使 `debian-rootfs`（`linux/arm64`）容器可在 x86_64 上原生运行。
- **ARM64 / aarch64 宿主**（如 Apple Silicon、ARM 服务器）：原生运行。Dockerfile 在 arm64 分支安装 `qemu-user-static` 以运行为 x86-64 的 rkbin 工具；`entrypoint.sh` 与 `build_uboot.sh` 配合处理。设 `USE_NATIVE_BUILD=yes` 时清空调 `CROSS_COMPILE` 用原生 GCC 加速（仅 ARM64 宿主有效，其它架构回退交叉编译）。

## Docker 资源建议

- 构建内核与 U-Boot 较吃 CPU 与内存；`JOBS` 默认 `0`（自动取 `nproc`）。
- Debian rootfs 构建在 ARM64 容器中做 `mmdebstrap`，建议宿主有 >= 4 GB 内存。QEMU 测试默认 `QEMU_MEMORY_MIB=1024`、`QEMU_CPUS=2`，可按需调大。
- ccache 缓存在 `rk3588-ccache` 卷（上限 `CCACHE_MAXSIZE` 默认 10G），跨构建复用加速。

## 网络

- `make fetch`（或 `fetch-custom`）需要访问 manifest 中声明的 git 远端（如 `github.com/radxa`、`github.com/rockchip-linux`、`gitlab.com/buildroot.org`）。
- Debian rootfs 构建需访问 `DEBIAN_MIRROR` / `DEBIAN_SECURITY_MIRROR`（默认 `deb.debian.org` / `security.debian.org`）；Debian 11 在常规镜像失败时可回退 `archive.debian.org`。

## 验证环境

- 运行 `make build` 后，可 `make shell SDK_VOLUME=<v>` 进入主构建器，`make debian-shell SDK_VOLUME=<v>` 进入 ARM64 Debian 构建器手动排查。
- `make check` 运行项目自检：bash 语法、ShellCheck、manifest XML 与锁版本、板型 profile、buildroot 外部树、U-Boot 契约、内核契约、QEMU 契约、Debian 包/overlay 契约等。CI 或本地改动后建议先跑一次。

## 项目自检

`scripts/check.sh` 是独立于构建的契约测试集，覆盖：

- `check_bash_syntax` / `check_shellcheck`：所有 `*.sh` 语法与 lint。
- `check_manifests`：manifest XML 合法且含 `buildroot` remote（板级拥有的 manifest 还需锁 Buildroot tag）。
- `check_board_profiles` / `run_board_self_checks`：每个板型 `board.conf` 走 `validate_board_profile`，并运行板级 `check.sh` 的 `board_check`。
- `check_kernel_contract` / `check_uboot_boot_contract_guard` / `check_qemu_smoke_contract`：核心脚本含预期的契约标记（如 extlinux 校验、binfmt 注册、overlay 插件文件存在）。
- `check_debian_packages`：包名解析拒绝别名、overlay 选中/禁用/未知、板级 plugin 分发、networkd/NM 互斥等。
- `check_rootfs_configuration` / `check_compose`：rootfs 配置键与 `docker-compose.yml` 结构。
- `self_tests`：失败路径（缺板型、非法 rootfs、危险路径重置）必须按预期报错。
