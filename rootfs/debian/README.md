# Debian rootfs layout

本目录是 Debian rootfs 的构建附件与可选能力集合，由 `scripts/build_debian.sh`（在 `debian-rootfs` 镜像中以 root 原生运行）消费。核心逻辑在脚本，本目录只放「数据/插件」，不放构建流程。

## Layout

```text
rootfs/debian/
├── overlays/                 # 可选 overlay 插件（DEBIAN_OVERLAYS 选择）
│   ├── base/                 # SSH / udev / resolved
│   ├── console/              # 串口 getty 波特率（板级 CONSOLE 速度）
│   ├── firstboot/            # 首启根分区扩容（growpart + resize2fs）
│   ├── firstboot-info/       # 首启 banner / MOTD
│   └── network/              # NetworkManager / systemd-networkd 自适应
└── ro-overlay/               # ro-overlay 模式专属 initramfs hook
    └── overlay/etc/initramfs-tools/scripts/local-bottom/overlayroot
```

另见 `boards/<BOARD>/rootfs/`（板级 plugin/overlay，始终应用，见 `boards/README.md`）。

## Packages

基础包由 `build_debian.sh` 内 `PACKAGES` 数组固定包含：`ca-certificates`、`cloud-guest-utils`、`curl`、`dbus`、`e2fsprogs`、`ethtool`、`gdisk`、`iproute2`、`iputils-ping`、`kmod`、`less`、`net-tools`、`openssh-server`、`passwd`、`procps`、`psmisc`、`sudo`、`systemd-sysv`、`udev`、`util-linux`、`vim-tiny`、`wget`；非 Debian 11 追加 `systemd-resolved`；`ro-overlay` 追加 `initramfs-tools`、`busybox`。

额外包只经 `DEBIAN_PACKAGES`（CLI / `.env`）或板级 `DEBIAN_PACKAGES_DEFAULT`，且为**精确 apt 包名**。`resolve_debian_packages` 拒绝功能别名（`nm`、`wifibt`、`hwdebug`、`all` 等）并去重。

## Overlay plugins

每个插件目录含 `plugin.sh`（`plugin_apply(root_dir)` 入口）+ 可选 `overlay/` 静态树 + 可选 `overlay-nm/`（NetworkManager 专属文件）。插件可调用 `common.sh` 的 `apply_rootfs_overlay_tree`、`expand_overlay_template_text`、`enable_unit`。内置插件见 `rootfs/debian/overlays/README.md`。

### Board plugins

`boards/<BOARD>/rootfs/` 的 `plugin.sh`（`board_plugin_apply`）或静态 `overlay/` 始终应用，且顺序在可选 overlay 之前。规则见 `boards/README.md`。

## Templates

overlay 内的 `*.in` 文件在 `apply_rootfs_overlay_tree` 拷贝时展开 `@PLACEHOLDER@` 标记（`expand_overlay_template_text`），可用占位符：`@BOARD@`、`@BOARD_DESCRIPTION@`、`@ROOTFS_HOSTNAME@`、`@KERNEL_DTB@`、`@DEBIAN_PACKAGES@`、`@DEBIAN_OVERLAYS@`、`@CONSOLE_DEVICE@`、`@CONSOLE_SPEED@`、`@ROOTFS_USERNAME@`。展开后的文件去掉 `.in` 后缀，权限沿用源文件。

## What stays in the build script

以下逻辑保留在 `build_debian.sh`，不放本目录：mmdebstrap 调用、组件选择、hostname/hosts、用户与 root 密码、模块安装与 `depmod`、usrmerge 校验、`systemd-analyze verify`、SSH host key 生成、镜像（ext4/squashfs）打包与内容校验、元数据写入。本目录只承载可被插件机制表达的可选文件与 hook。

## ro-overlay initramfs hook

`ro-overlay/overlay/etc/initramfs-tools/scripts/local-bottom/overlayroot` 在 initramfs 阶段运行：检测 `overlayroot=PARTLABEL=data`，把 SquashFS 根（lower）与 data 分区 ext4（upper/work）组装成 OverlayFS，随后 `switch_root`。脚本优先用 busybox 的 mount（构建时 `ro-overlay` 分支会把 `busybox` 加入 rootfs 以确保 initramfs 内有可用的 overlayfs mount）。
