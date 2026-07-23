# 设计：纯构建核心 + 插件化 + 板子为单元

本页记录构建系统的架构取向与当前实现状态，作为后续维护的参考。所有描述均对应 `scripts/`、`boards/`、`configs/`、`rootfs/` 的实际代码。

## 目标结构

- **纯构建核心（board-name-free）**：`scripts/lib/common.sh`、`build_*.sh`、`make_image.sh`、`verify_image.sh` 不硬编码任何板型名、WiFi/BT 芯片或具体 manifest。板型差异只通过数据（profile、overlay、hook）注入。
- **板子为单元（board-as-unit）**：每个板型一个目录 `boards/<BOARD>/`，含 `board.conf`（配置）、`kernel.config`（自动合并的 fragment）、`rootfs/`（plugin/overlay）、`check.sh`（自检）、`board.hooks.sh`（构建钩子）。
- **可选能力外置为插件**：Debian 的可选能力（`base`/`console`/`firstboot`/`firstboot-info`/`network`）是 `rootfs/debian/overlays/<name>/` 下的目录化插件，由 `DEBIAN_OVERLAYS` 选择，核心只负责分发。
- **平台事实与板型解耦**：SoC 级限制（如 QEMU `virt` 的 initcall 黑名单、FiQ 串口 mask）放在 `configs/soc/<SOC>.conf`，由板级 `SOC=` 选择加载，不进核心脚本。
- **端到端校验即契约**：`verify_image.sh` 与 `scripts/check.sh` 把「镜像长什么样、脚本必须含哪些标记」写成可执行契约，而非文档约定。

## 实施状态（已完成）

- 板型零脚本改动：新增板子只改 `boards/`（`make new-board` 从 `TEMPLATE` 复制）。
- 内核 fragment 分层：`rootfs-base.config` + `squashfs-overlay.config`（始终合并）+ 板级 `kernel.config`（自动合并、可覆盖）。
- Debian 包名精确化：移除 `nm`/`wifibt`/`hwdebug` 等别名，`resolve_debian_packages` 仅接受真实 apt 包名。
- overlay 插件化：`DEBIAN_OVERLAYS` 选择 + `run_debian_overlay_plugins` 顺序应用；板级 `boards/<BOARD>/rootfs/` 始终应用且先于可选 overlay。
- ro-overlay 模式：`ROOTFS_MODE=ro-overlay` 走 SquashFS 根 + ext4 data 分区 + initramfs `overlayroot` hook；内核始终含 OverlayFS/SquashFS 支持。
- QEMU 契约外置：`configs/soc/rk3588.conf` 提供 `QEMU_INITCALL_BLACKLIST` 与 `QEMU_SERIAL_GETTY_MASK`，由 `qemu_smoke.py` 消费。
- 构建器双阶段：`Dockerfile` 的 `rk3588-build`（ubuntu:22.04，通用）与 `debian-rootfs`（debian:trixie，arm64 原生 Debian 构建）。
- 项目自检：`scripts/check.sh` 覆盖语法/lint、manifest、板型 profile、buildroot 外部树、U-Boot 契约、内核契约、QEMU 契约、Debian 包/overlay 契约、失败路径。

## 约束与不可破坏点

以下由代码强制，重构时不得破坏：

- `validate_board_profile`：必填字段、`KERNEL_DTB` 后缀、几何约束（`BOOT_START_MIB>=16`、`IDBLOCK_SECTOR<UBOOT_SECTOR`、剩余容量 >0）、`ROOTFS_MODE` ∈ {rw-ext4, ro-overlay}、`UBOOT_PYTHON` ∈ {python2, python3}、`BOOTLOADER_LAYOUT` == rockchip-gpt-idblock-extlinux-v1（旧名归并）。
- `verify_extlinux_dtb`：打包 DTB 不得含 `/chosen/bootargs`（`DTB_STRIP_BOOTARGS=yes` 默认清除）。
- `validate_extlinux_boot_contract`：U-Boot 必须含 `CONFIG_DISTRO_DEFAULTS` 等且二进制含 `run distro_bootcmd;` 与 `extlinux/extlinux.conf`，不得含 `CONFIG_FIT_SIGNATURE`/`CONFIG_AVB_VBMETA_PUBLIC_KEY_VALIDATE`。
- `ro-overlay` 必须含 `busybox` 与 `initramfs-tools`，且 `overlayroot` hook 用规范 `mount -t overlay` 参数顺序。

## 分阶段迁移（历史）

项目从「单板硬编码」演进到当前「配置驱动 + 插件化」。迁移原则：每步保持 `make check` 全绿，核心脚本不引入板型名，差异下沉到 `boards/`、`configs/`、`rootfs/debian/overlays/`。当前结构已稳定，新增能力优先以插件/hook/overlay 形式落地，而非修改核心。
