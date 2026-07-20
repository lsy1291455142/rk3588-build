# RK3588 完整系统镜像构建流程

本文说明本项目如何从 SDK 源码得到可烧录的 GPT 镜像，以及各阶段的职责与约束。命令速查与板型列表见仓库根目录 [README.md](../README.md)。

---

## 1. 为什么只有 Image、DTB、U-Boot 不够

| 组件 | 作用 |
|---|---|
| loader / IDBlock | DDR 初始化、加载 U-Boot |
| U-Boot | 读分区、加载 Kernel 与 DTB |
| Kernel `Image` | 启动 Linux |
| DTB | 描述板级硬件 |
| 内核模块 | 与 Kernel release 匹配的驱动 |
| rootfs | 提供 `/sbin/init` 与用户空间 |
| 分区表 + 启动配置 | 固定偏移与挂载方式 |

缺少 rootfs 时，内核常见停在 `VFS: Unable to mount root fs` 或 `No working init found`。本项目输出的是**整盘 raw GPT 镜像**，不是单独的 bootloader 或 Rockchip `update.img`。

---

## 2. 构建流水线总览

```text
builder 镜像
    → SDK（fetch 或本地导入）
    → build-kernel   → Image / DTB / modules.tar
    → build-uboot    → idblock.img / uboot.img / download-loader.bin
    → build-rootfs   → Buildroot 和/或 Debian rootfs
    → image          → GPT raw image + .img.zst + SHA256
    → verify-image   （image 后自动执行）
    → 可选 test-debian-qemu
```

`SDK_VOLUME`、`BOARD`、`ROOTFS` 三者均无默认值，须通过 `.env`、`make use-*` 或命令行显式给出。

---

## 3. 阶段说明

### 3.1 准备 builder

```bash
make build
# 或从 GHCR 拉取后打本地 tag（见 README）
```

Debian rootfs 另需 ARM64 builder：选择 `ROOTFS=debian` 时由 `build-rootfs` / `build-all` 自动准备，也可先执行 `make build-debian-builder`。

### 3.2 接入 SDK

公开 BSP：

```bash
make fetch-rock5c   # 或其他 fetch-*
```

本地大体积 SDK（不复制源码，bind-backed volume）：

```bash
make import-local-sdk   SDK_PATH=/absolute/path/to/sdk   SDK_VOLUME=rk3588-sdk-local
make verify-sdk-volume SDK_VOLUME=rk3588-sdk-local
# CokePi 可用：make verify-cokepi-sdk SDK_VOLUME=rk3588-sdk-cokepi-rkr9
```

SDK 根目录须直接包含 `kernel/`、`u-boot/`、`rkbin/`、`buildroot/`。manifest 中的 Buildroot 固定为官方 `2025.02.15`；ROCK 5C profile 另将 kernel / u-boot / rkbin / buildroot 锁定为已验证 commit。

### 3.3 Kernel（`scripts/build_kernel.sh`）

- 使用 symlink source view，不复制 SDK 内核树，也不对导入的 `SDK/kernel` 执行 `mrproper`
- 加载 `configs/boards/<board>.conf`
- 应用 BSP defconfig，再合并 `configs/kernel/rootfs-base.config`
- 产出精确一个 DTB（`KERNEL_DTB`）、`Image`、`modules.tar`
- **删除产物 DTB 中的 `/chosen/bootargs`**，避免 Rockchip U-Boot 合并参数时用厂商固定 `root=PARTUUID=...` 覆盖 extlinux
- 记录 Kernel release 与源码 revision

rootfs 构建依赖 `modules.tar`，须先完成 Kernel。

### 3.4 U-Boot / loader（`scripts/build_uboot.sh`）

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

### 3.5 rootfs

Buildroot 与 Debian 均提供无桌面基础系统：串口登录、DHCP、SSH、sudo、常用诊断工具、与当前 Kernel 匹配的 `/lib/modules`、首次启动扩容。

| 类型 | 要点 |
|---|---|
| Buildroot | glibc、BusyBox init、Dropbear；外部树 `rootfs/buildroot/` |
| Debian | `mmdebstrap`、systemd-networkd、OpenSSH；版本 11/12/13 → bullseye/bookworm/trixie |

Debian 在固定 `linux/arm64` 容器中构建（privileged，供临时挂载）。x86_64 主机注册 ARM64 binfmt；ARM64 主机原生执行。Debian 11 常规源不可用时可回退 `archive.debian.org`（仅复现，不代表仍有安全更新）。

`ROOTFS` 取值为 `buildroot`、`debian` 或 `all`。未设置时，`build-rootfs` / `image` / `verify-image` / `build-all` 直接报错，不会根据已有输出目录猜测。

### 3.6 打包镜像（`scripts/make_image.sh`）

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

### 3.7 离线校验（`scripts/verify_image.sh`）

`make image` 结束后自动执行。检查包括：

- GPT 主备表与分区起止
- boot / rootfs 类型与名称
- 固定偏移处的 RKNS IDBlock 与 U-Boot
- FAT 中的 Image、DTB、extlinux
- 产物 DTB 与 FAT 内 DTB 均无 `/chosen/bootargs`
- rootfs 标签、模块目录、开发账户、root 登录、扩容钩子
- raw image 与 `.img.zst` 的 SHA256

### 3.8 QEMU 冒烟（可选）

```bash
make test-debian-qemu   BOARD=rk3588s-rock-5c   SDK_VOLUME=rk3588-sdk-rock5c   DEBIAN_RELEASE=13
```

使用本次构建的 Kernel 与完整 GPT 镜像副本，在 ARM64 `virt` 上验证串口登录、systemd、扩容、网络与 SSH。**不能**模拟 RK3588 DDR / PMIC / MMC 与真实 loader/U-Boot 路径，不能替代板级串口验收。

---

## 4. 完整命令示例

### ROCK 5C + Debian 13

```bash
make build
make fetch-rock5c
make build-all   BOARD=rk3588s-rock-5c   SDK_VOLUME=rk3588-sdk-rock5c   ROOTFS=debian   DEBIAN_RELEASE=13
make test-debian-qemu   BOARD=rk3588s-rock-5c   SDK_VOLUME=rk3588-sdk-rock5c   DEBIAN_RELEASE=13
```

### CokePi Model + 本地 SDK

```bash
make build
make import-local-sdk   SDK_PATH=/absolute/path/to/rk3588_linux-5.10-cokepi-rkr9   SDK_VOLUME=rk3588-sdk-cokepi-rkr9
make verify-cokepi-sdk SDK_VOLUME=rk3588-sdk-cokepi-rkr9
make build-all   BOARD=rk3588s-cokepi-model-lp4-v10   SDK_VOLUME=rk3588-sdk-cokepi-rkr9   ROOTFS=debian   DEBIAN_RELEASE=13
```

### EVB1 + Buildroot / Debian / 两者

```bash
make fetch-510

make build-all   BOARD=rk3588-evb1-lp4-v10-linux   SDK_VOLUME=rk3588-sdk-rockchip-5.10   ROOTFS=buildroot

make build-all   BOARD=rk3588-evb1-lp4-v10-linux   SDK_VOLUME=rk3588-sdk-rockchip-5.10   ROOTFS=debian   DEBIAN_RELEASE=13

make build-all   BOARD=rk3588-evb1-lp4-v10-linux   SDK_VOLUME=rk3588-sdk-rockchip-5.10   ROOTFS=all   DEBIAN_RELEASE=13
```

仅重新打包（`common/` 与对应 rootfs 产物已齐全）：

```bash
make image   BOARD=rk3588-evb1-lp4-v10-linux   SDK_VOLUME=rk3588-sdk-rockchip-5.10   ROOTFS=buildroot
```

---

## 5. 启动契约（摘要）

1. 磁盘启动链：sector 64 的 **RKNS** IDBlock → sector 16384 的 `uboot.img` → FAT 中 extlinux
2. 启动参数以 **extlinux** 为准；打包 DTB 不得保留 `/chosen/bootargs`
3. rootfs 通过 `PARTLABEL=rootfs` 定位
4. USB 下载用 `download-loader.bin`（LDR），与盘上 IDBlock 不是同一文件

---

## 6. 新板卡检查清单

```bash
cp configs/boards/rk3588-evb1-lp4-v10-linux.conf    configs/boards/rk3588-myboard.conf
# 或直接使用已提供的 MUSE profile：
# configs/boards/rk3588-muse.conf + manifests/rk3588-muse-5.10.xml
# make fetch-muse
```

至少确认：

| 字段 | 说明 |
|---|---|
| `KERNEL_DEFCONFIG` / `KERNEL_DTB` | 与硬件匹配的 defconfig 与唯一 DTB |
| `UBOOT_DEFCONFIG` / `UBOOT_BOARD` | BSP `make.sh` 参数 |
| `UBOOT_PYTHON` | 仅 `python2` 或 `python3` |
| `DOWNLOAD_LOADER_GLOBS` / `UBOOT_IMAGE_NAMES` | 产物匹配规则 |
| `CONSOLE` / `EXTRA_KERNEL_ARGS` | 串口与附加内核参数 |
| `IMAGE_SIZE_MIB` / `BOOT_*` / `ROOTFS_SIZE_MIB` | 镜像与分区几何 |
| `IDBLOCK_SECTOR` / `UBOOT_SECTOR` | 须在 `BOOT_START_MIB` 之前，当前布局为 64 / 16384 |

然后：

1. `fetch-*` 或 `import-local-sdk` 接入正确 SDK
2. `make build-all BOARD=rk3588-myboard SDK_VOLUME=... ROOTFS=...`
3. 通过 `verify-image`
4. 在硬件上用 1500000 8N1 串口做最终验收

DTB、DRAM 初始化或存储控制器与硬件不符时，即使离线校验通过，板卡仍可能无法启动。

---

## 7. 校验能力边界

| 能证明 | 不能证明 |
|---|---|
| 镜像 GPT / 分区 / bootloader 偏移正确 | DDR / PMIC 初始化在真机成功 |
| FAT 内容与 extlinux 契约 | 真实 MMC / eMMC 时序与稳定性 |
| rootfs 完整性与默认账户 | 外设、显示、NPU 等板级功能 |
| QEMU virt 上 Debian 基本可引导 | 真实 U-Boot 加载路径 |

硬件验收以开发板串口日志为准。
