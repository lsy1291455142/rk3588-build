# RK3588 开发板完整系统镜像构建流程

## 为什么只有 Image、DTB 和 U-Boot 还不能启动 Linux 系统

`Image` 是 Linux 内核，DTB 描述硬件，loader 和 U-Boot 负责初始化 SoC 并加载
内核。内核启动后仍然需要挂载根文件系统并执行 `/sbin/init`。缺少 rootfs 时，
常见结果是内核停在：

```text
VFS: Unable to mount root fs
No working init found
```

因此一个可用的存储镜像至少包含：

1. Rockchip loader
2. U-Boot
3. Kernel Image
4. 与硬件匹配的 DTB
5. 与 Kernel release 匹配的模块
6. Buildroot 或 Debian rootfs
7. 分区表和启动配置

## 项目中的构建阶段

### 1. 拉取 SDK

manifest 会拉取 `kernel/`、`u-boot/`、`rkbin/` 和固定为 `2025.02.15` 的官方
`buildroot/`。

```bash
make build
make build-debian-builder  # 需要 Debian rootfs 时执行
make fetch-510
```

### 2. 构建 Kernel

`scripts/build_kernel.sh` 执行以下工作：

- 加载 `configs/boards/<board>.conf`
- 应用 BSP Kernel defconfig
- 合并 `configs/kernel/rootfs-base.config`
- 构建 `Image`、一个精确 DTB 和 modules
- 安装模块并输出 `modules.tar`
- 记录 Kernel release 和源码 revision

根文件系统构建依赖 `modules.tar`，因此必须先构建 Kernel。

### 3. 构建 Rockchip 启动链

`scripts/build_uboot.sh` 使用 BSP 自带的 `./make.sh rk3588`，并从结果中选择
loader 和 `uboot.img`。脚本会在复制前检查二进制是否超出板级配置保留的扇区
范围，并验证 U-Boot 配置和 `u-boot.bin` 确实包含 MMC、FAT、extlinux、
`booti` 与 `distro_bootcmd` 启动链。若启用了要求签名镜像的 FIT/AVB 公钥校验，
构建会直接失败，避免生成与当前未签名 extlinux 镜像不兼容的 bootloader。

### 4. 构建 rootfs

Buildroot 和 Debian 都提供无桌面的基础系统：

- 串口登录
- DHCP
- SSH
- sudo
- `iproute2`、ping、ethtool、procps、kmod 等诊断工具
- root 账户可通过串口和 SSH 密码登录
- 开发用户和 root，默认密码为 `rk3588`
- 与当前 Kernel release 匹配的 `/lib/modules`
- 首次启动扩展 ext4 文件系统

Buildroot 使用 glibc、BusyBox init、Dropbear 和外部树
`rootfs/buildroot/`。Debian 使用 ARM64 `mmdebstrap`、systemd-networkd 和
OpenSSH。

Debian 版本映射如下：

```text
11 -> bullseye
12 -> bookworm
13 -> trixie
```

Debian 11 常规镜像不可用时可以回退到 `archive.debian.org`。归档源只能用于
复现旧系统，不代表仍有安全更新。

Debian rootfs 容器以 privileged 模式运行，以允许 `mmdebstrap` 在构建过程中
创建临时挂载。不要在该服务中运行不可信脚本。

### 5. 生成磁盘镜像

`scripts/make_image.sh` 不使用 loop mount。它通过 `sgdisk`、`mtools`、`dd`
直接构建 raw image：

```text
0 .. 16 MiB                 GPT + Rockchip boot chain reserved area
sector 64                   loader.bin
sector 16384                uboot.img
16 MiB .. 272 MiB           FAT32, label BOOT
272 MiB .. last usable LBA  ext4, label rootfs
```

FAT 分区包含：

```text
/Image
/<board>.dtb
/extlinux/extlinux.conf
```

extlinux 使用 `root=LABEL=rootfs rootwait rw`，所以 rootfs 不依赖固定的
`/dev/mmcblkXpY` 名称。

rootfs ext4 初始大小由板级配置的 `ROOTFS_SIZE_MIB` 决定。镜像中的 GPT root
分区更大，首次启动时 `resize2fs` 在线扩展文件系统。

### 6. 离线验证

`scripts/verify_image.sh` 在不挂载镜像的情况下验证：

- GPT 主备表和两分区起止 LBA
- boot/rootfs 分区类型与名称
- loader 和 U-Boot 固定偏移处的二进制内容
- FAT 中的 Image、DTB 和 extlinux
- rootfs ext4 一致性和 `rootfs` 标签
- `/lib/modules/<kernel-release>`
- 开发用户存在且 root 账户已启用
- Buildroot 或 Debian 的首次启动扩容钩子
- raw image 和 `.img.zst` 的 SHA256

`make image` 在打包后自动执行此验证。

## 完整命令

```bash
# Buildroot
make build-all \
  BOARD=rk3588-evb1-lp4-v10-linux \
  ROOTFS=buildroot

# Debian 13
make build-all \
  BOARD=rk3588-evb1-lp4-v10-linux \
  ROOTFS=debian \
  DEBIAN_RELEASE=13

# Buildroot + Debian 13
make build-all \
  BOARD=rk3588-evb1-lp4-v10-linux \
  ROOTFS=all \
  DEBIAN_RELEASE=13
```

只重新制作镜像时，已有 common 和 rootfs 产物必须齐全：

```bash
make image \
  BOARD=rk3588-evb1-lp4-v10-linux \
  ROOTFS=buildroot
```

## 新板卡适配

最终镜像不会自动猜测开发板。复制内置 profile 后，需要逐项确认：

```bash
cp configs/boards/rk3588-evb1-lp4-v10-linux.conf \
   configs/boards/rk3588-myboard.conf
```

重点参数：

```text
KERNEL_DEFCONFIG
KERNEL_DTB
UBOOT_DEFCONFIG
UBOOT_BOARD
LOADER_GLOBS
UBOOT_IMAGE_NAMES
CONSOLE
IMAGE_SIZE_MIB
BOOT_START_MIB
BOOT_SIZE_MIB
ROOTFS_SIZE_MIB
LOADER_SECTOR
UBOOT_SECTOR
```

如果 DTB、DRAM 初始化文件或存储控制器配置与硬件不匹配，即使镜像结构验证
通过，板卡也可能无法启动。离线校验只能证明镜像内部一致，不能替代串口启动
和真实 SD/eMMC 硬件测试。
