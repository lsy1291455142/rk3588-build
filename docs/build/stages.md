# 阶段说明

## 准备 builder

```bash
make build
# 或从 GHCR 拉取后打本地 tag（见 Builder 镜像）
```

Debian rootfs 另需 ARM64 builder：选择 `ROOTFS=debian` 时由 `build-rootfs` / `build-all` 自动准备，也可先执行 `make build-debian-builder`。

## 接入 SDK

公开 BSP：

```bash
make fetch-rock5c   # 或其他 fetch-*
```

本地大体积 SDK（不复制源码，bind-backed volume）：

```bash
make import-local-sdk \
  SDK_PATH=/absolute/path/to/sdk \
  SDK_VOLUME=rk3588-sdk-local
make verify-sdk-volume SDK_VOLUME=rk3588-sdk-local
```

SDK 根目录须直接包含 `kernel/`、`u-boot/`、`rkbin/`、`buildroot/`。manifest 中的 Buildroot 固定为官方 `2025.02.15`；ROCK 5C profile 另将 kernel / u-boot / rkbin / buildroot 锁定为已验证 commit。

## Kernel（`scripts/build_kernel.sh`）

- 使用 symlink source view，不复制 SDK 内核树，也不对导入的 `SDK/kernel` 执行 `mrproper`
- 加载 `configs/boards/<board>.conf`
- 应用 BSP defconfig，再合并 `configs/kernel/rootfs-base.config`
- 产出精确一个 DTB（`KERNEL_DTB`）、`Image`、`modules.tar`
- **删除产物 DTB 中的 `/chosen/bootargs`**，避免 Rockchip U-Boot 合并参数时用厂商固定 `root=PARTUUID=...` 覆盖 extlinux
- 记录 Kernel release 与源码 revision

rootfs 构建依赖 `modules.tar`，须先完成 Kernel。

## U-Boot / loader（`scripts/build_uboot.sh`）

- 调用 BSP 的 `./make.sh`（`UBOOT_BOARD`）
- 按 board profile 选择 `UBOOT_PYTHON`（`python2` 或 `python3`）；全局 `python` 仍为 Python 3，仅在当前构建进程内切换
- 挑选 loader 与 `uboot.img`，检查体积是否越过预留扇区
- 校验 U-Boot 具备 MMC、FAT、extlinux、`booti`、`distro_bootcmd`
- 若启用要求签名镜像的 FIT/AVB 公钥校验，构建失败（与当前未签名 extlinux 流程不兼容）

产物区分：

| 文件 | 魔数 | 用途 |
|---|---|---|
| `idblock.img` | `RKNS` | 写入磁盘 sector 64 |
| `download-loader.bin` | `LDR ` | USB 下载（如 `rkdeveloptool db`），**不能**原样写入 sector 64 |

## rootfs

Buildroot 与 Debian 均提供无桌面基础系统：串口登录、DHCP、SSH、sudo、常用诊断工具、与当前 Kernel 匹配的 `/lib/modules`、首次启动扩容。

| 类型 | 要点 |
|---|---|
| Buildroot | glibc、BusyBox init、Dropbear；外部树 `rootfs/buildroot/` |
| Debian | `mmdebstrap`、systemd-networkd、OpenSSH；版本 11/12/13 → bullseye/bookworm/trixie |

Debian 在固定 `linux/arm64` 容器中构建（privileged，供临时挂载）。x86_64 主机注册 ARM64 binfmt；ARM64 主机原生执行。Debian 11 常规源不可用时可回退 `archive.debian.org`（仅复现，不代表仍有安全更新）。

`ROOTFS` 取值为 `buildroot`、`debian` 或 `all`。未设置时，`build-rootfs` / `image` / `verify-image` / `build-all` 直接报错，不会根据已有输出目录猜测。

## 打包镜像（`scripts/make_image.sh`）

不使用 loop mount；通过 `sgdisk`、`mtools`、`dd` 直接写 raw image：

```text
0 .. 16 MiB                 GPT + bootloader 预留
sector 64                   idblock.img (RKNS)
sector 16384                uboot.img
16 MiB .. 272 MiB           FAT32，label BOOT
272 MiB .. last usable LBA  ext4，label / PARTLABEL rootfs
```

FAT 内容：

```text
/Image
/<KERNEL_DTB 文件名>
/extlinux/extlinux.conf
```

extlinux 使用：

```text
root=PARTLABEL=rootfs rootwait rw console=... [EXTRA_KERNEL_ARGS]
```

由内核按分区名挂载 rootfs，不依赖 initramfs 或固定 `mmcblk` 设备名。rootfs 文件系统初始大小由 `ROOTFS_SIZE_MIB` 决定；GPT 中 root 分区更大，Debian 首次启动会扩到磁盘末尾。

## 离线校验（`scripts/verify_image.sh`）

`make image` 结束后自动执行。检查包括：

- GPT 主备表与分区起止
- boot / rootfs 类型与名称
- 固定偏移处的 RKNS IDBlock 与 U-Boot
- FAT 中的 Image、DTB、extlinux
- 产物 DTB 与 FAT 内 DTB 均无 `/chosen/bootargs`
- rootfs 标签、模块目录、开发账户、root 登录、扩容钩子
- raw image 与 `.img.zst` 的 SHA256

## QEMU 冒烟（可选）

```bash
make test-debian-qemu \
  BOARD=rk3588s-rock-5c \
  SDK_VOLUME=rk3588-sdk-rock5c \
  DEBIAN_RELEASE=13
```

使用本次构建的 Kernel 与完整 GPT 镜像副本，在 ARM64 `virt` 上验证串口登录、systemd、扩容、网络与 SSH。**不能**模拟 RK3588 DDR / PMIC / MMC 与真实 loader/U-Boot 路径，不能替代板级串口验收。
