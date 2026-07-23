# 构建流水线

整条流水线把 SDK 源码变成可烧录的 GPT 镜像，可一步（`make build-all`）完成，也可分阶段执行以便增量构建。本页按阶段说明数据如何在组件间流动，以及每个脚本的输入/输出契约。

## 阶段零：拉取 SDK（`fetch_sources.sh`）

通过 Google `repo` + manifest 把四个组件拉进 SDK 卷。manifest 来自 `boards/<BOARD>/board.conf` 的 `SOURCE_MANIFEST`（本地文件）或 `CUSTOM_MANIFEST_URL`（远程）。拉取后逐组件打印 `rev (branch)`，并在设置 `SOURCE_MANIFEST` 时调用 `validate_board_source_revisions` 比对板级锁定的 `EXPECTED_*_REVISION` 完整 40 位 SHA。本地 SDK 用 `make import-local-sdk` 以 bind 卷接入，跳过此阶段。

## 阶段一：build-uboot（`build_uboot.sh`）

输入：SDK 卷的 `u-boot` 与 `rkbin`，板级 `UBOOT_DEFCONFIG` / `UBOOT_BOARD`。
流程：

1. 解析 `UBOOT_PYTHON`（默认 python3，Rockchip FIT 生成器需要 pyelftools）；ARM64 宿主用 `qemu-x86_64-static` 包装 rkbin 的 x86-64 工具，退出时还原。
2. `bash ./make.sh <UBOOT_BOARD> "CROSS_COMPILE=..."` 编译 U-Boot，再 `make.sh --idblock` 打包 RKNS IDBlock。
3. `validate_extlinux_boot_contract` 校验 U-Boot 配置含 `CONFIG_DISTRO_DEFAULTS`/`CONFIG_CMD_MMC`/`CONFIG_CMD_FAT`/`CONFIG_CMD_FS_GENERIC`/`CONFIG_CMD_PXE`/`CONFIG_CMD_BOOTI`，且二进制含 `run distro_bootcmd;` 与 `extlinux/extlinux.conf`，并拒绝安全启动相关选项。
4. 按 `DOWNLOAD_LOADER_GLOBS` / `UBOOT_IMAGE_NAMES` 找到 download loader（魔术字 `LDR `）与 uboot 镜像（含 `idblock.bin`，魔术字 `RKNS`），校验体积不超保留区。
5. 产出 `common/download-loader.bin`、`common/idblock.img`、`common/uboot.img`，以及 `common/uboot-build-info.txt`（含扇区、格式、SHA256、Python 版本、boot flow）。

## 阶段二：build-kernel（`build_kernel.sh`）

输入：SDK 卷的 `kernel`，板级 `KERNEL_DEFCONFIG` / `KERNEL_DTB`，共享 fragment + 板级 `kernel.config`。
流程：

1. 构建符号链接式源码视图（`link_source_children`），避免污染导入的 SDK 源；预置 `.scmversion` 防止构建期 git 探测；设置 `GIT_CEILING_DIRECTORIES` 与 `GIT_DIR` 指向内核 worktree。
2. `make <KERNEL_DEFCONFIG>`，再用 `merge_config.sh -m` 依次合并：
   - `configs/kernel/rootfs-base.config`（基础能力）
   - `configs/kernel/squashfs-overlay.config`（只读 overlay 所需 SquashFS/OverlayFS，始终合并，对 rw-ext4 惰性无副作用）
   - `KERNEL_EXTRA_FRAGMENTS`（板级共享片段，可选）
   - `boards/<BOARD>/kernel.config`（板级片段，最后合并，可覆盖共享）
3. 强制校验必需内核选项（`CONFIG_OVERLAY_FS`、`CONFIG_SQUASHFS`、`CONFIG_VIRTIO_*`、`CONFIG_DEVTMPFS_MOUNT` 等）。
4. 编译 `Image`、`rockchip/<KERNEL_DTB>`、模块；若 `CONFIG_MALI_CSF_INCLUDE_FW=y` 需镜像 Mali CSF 固件。
5. 若 `DTB_STRIP_BOOTARGS=yes`（默认），用 `fdtput` 删除打包 DTB 的 `/chosen/bootargs`，确保 extlinux `APPEND` 权威。
6. 产出 `common/Image`、`common/<KERNEL_DTB>`、`common/kernel.config`、`common/kernel-release`、`common/modules.tar`、`common/System.map`，以及 `kernel-build-info.txt`（`dtb_bootargs=extlinux-only-v1`、`kernel_source_view=symlink-clean-v1`）。

## 阶段三：build-rootfs

分两条路径，依赖阶段二的 `modules.tar` 与 `kernel-release`。

### Buildroot 路径（`build_buildroot.sh`）

使用 `rootfs/buildroot/` 外部树（`BR2_EXTERNAL`），`rk3588_rootfs_defconfig` 选择 aarch64/cortex-a76_a55、GLIBC、BusyBox init、Dropbear SSH、e2fsprogs 等，输出 ext4（标签 `rootfs`，2048M）与 tar。`post-build.sh` 解包内核模块、写入 sudoers、置可执行 `S02rootfs-resize`/`S40network`。产出 `buildroot/rootfs.ext4`、`buildroot/rootfs.tar`、`buildroot/buildroot.config`。默认账号为 `user`/`password`（由 `validate_rootfs_credentials` 统一提供，可通过 `ROOTFS_USERNAME`/`ROOTFS_PASSWORD` 覆盖）。

### Debian 路径（`build_debian.sh`）

在 `debian-rootfs` 镜像中以 root 运行，必须 `arm64`。流程：

1. 解析 `DEBIAN_RELEASE`→codename/components；`DEBIAN_PACKAGES` 为空时回退 `DEBIAN_PACKAGES_DEFAULT`，`none` 强制仅 minbase；`resolve_debian_packages` 拒绝功能别名，仅接受精确 apt 包名。
2. `mmdebstrap --variant=minbase --include=<PACKAGES>` 生成 `ROOT_DIR`，Debian 11 常规镜像失败时回退 `archive.debian.org`。
3. 设置 hostname/hosts、创建 `ROOTFS_USERNAME` + 解锁 root、应用板级 plugin/overlay（`apply_debian_board_overlay`）、usermerge 校验、安装内核模块并 `depmod`。
4. 按 `DEBIAN_OVERLAYS` 顺序运行可选插件（`run_debian_overlay_plugins`）：`base`（SSH/udev/resolved）、`console`（串口 getty 波特率）、`firstboot`（首启扩容）、`firstboot-info`（banner/MOTD）、`network`（NM/networkd 自适应）。
5. `systemd-analyze verify` 校验关键 unit，生成 SSH host key。
6. `ro-overlay`：生成 initramfs（`update-initramfs`，含 `overlayroot` hook）；否则打包 ext4（标签 `rootfs`，大小 `ROOTFS_SIZE_MIB`）。`ro-overlay` 产出 `rootfs.squashfs`。
7. 产出 `debian-<rel>/rootfs.ext4`（或 `rootfs.squashfs`）、`rootfs.tar`、`rootfs-build-info.txt`（含 `network_stack`、`debian_packages`、`debian_overlays`、`rootfs_mode`）。

## 阶段四：image + verify-image（`make_image.sh` / `verify_image.sh`）

`make_image.sh`：

1. 计算 GPT 几何：`IMAGE_SIZE_MIB` 总盘；boot 分区（第 1，`0700`，`BOOT_START_MIB` 起、`BOOT_SIZE_MIB` 大）；root 分区（第 2，`8300`，标签 `rootfs`）；`ro-overlay` 额外 data 分区（第 3，`8300`，标签 `data`）。
2. 写 `extlinux.conf`（`DEFAULT`/`LABEL`=`EXTLINUX_LABEL`，`LINUX /Image`、`FDT /<DTB>`、`INITRD` 仅 ro-overlay、`APPEND root=PARTLABEL=rootfs rootwait rw|ro ... overlayroot=PARTLABEL=data console=<CONSOLE>`）。
3. `sgdisk` 建 GPT，FAT32 `BOOT` 分区放入 Image/DTB/extlinux.conf（及 DTBO、initrd），`bootloader_layout_write` 写入 idblock/uboot，dd 写入 boot 与 rootfs（ro-overlay 再写 data ext4）。
4. zstd 压缩、写 `.sha256`、写 `image-build-info.txt`（各分区起止扇区、SHA256、组件 commit、boot/root/data 元数据、bootloader 元数据）。

`verify_image.sh`（以 root 运行）端到端校验：`stat` 镜像大小、`sgdisk --verify`、逐项比对分区起止扇区/类型/名称；`bootloader_layout_verify` 比对 embedded idblock/uboot 与 `common/` 产物；从 FAT 提取 Image/DTB/extlinux.conf 比对；校验 extlinux 选择正确 DTB、`rw`/`ro` + `overlayroot` 与 `console`；提取 rootfs（ext4 用 debugfs，SquashFS 用 `unsquashfs`）校验模块属主、`/lib` usrmerge、ELF 解释器、systemd、root 解锁，以及各 overlay 契约（firstboot 的 growpart/resize2fs、`base` 的 SSH+resolved、`console` 的波特率、`network` 的 NM/networkd 互斥）。最后 `sha256sum --check`。

## 可选阶段：test-debian-qemu（`test_debian_qemu.sh` + `qemu_smoke.py`）

仅 Debian。复制镜像为 `qemu-smoke/disk.img`，从 `image-build-info.txt` 读取 `rootfs_mode`，调用 `qemu_smoke.py` 在 QEMU `virt` 启动：注入 `initcall_blacklist`（来自 `configs/soc/rk3588.conf`）与 mask `serial-getty@ttyFIQ0.service`，等待串口登录 → 密码登录 → 运行 `systemd is-system-running`、各 unit 健康、SSH 密码登录、IPv4 获取等检查，最后关机并扫串口日志排除致命/错误模式。ro-overlay 额外校验 `/data` 挂载。
