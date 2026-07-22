# configs/

构建配置中心：板级 profile + 共享内核 fragment。

## 板级 profile（`boards/`）

每块支持的开发板对应一个 `.conf` 文件，文件名（去掉 `.conf`）就是 `BOARD` 变量的值。

当前内置：

| Profile | 硬件 | 关键特征 |
|---|---|---|
| `rk3588-evb1-lp4-v10-linux` | Rockchip EVB1 参考板 | 参考实现，`UBOOT_PYTHON=python3` |
| `rk3588s-rock-5c` | Radxa ROCK 5C | manifest 全量锁定 commit |
| `rk3588-cokepi-plus-lp4-v10` | CokePi Plus (RK3588) | `KERNEL_DTB=rk3588-cpp-hdmi.dtb`，需本地 SDK |
| `rk3588s-cokepi-model-lp4-v10` | CokePi Model (RK3588S) | `KERNEL_DTB=rk3588s-cpm-hdmi1.dtb`，需本地 SDK |
| `rk3588-muse` | MUSE RK3588 (eMMC) | kernel 来自 MUSEInstitute fork |

CokePi Plus 和 Model 共用 SDK 但 DTB 不同，必须按板子丝印选择 profile，不可混用。

### 字段说明

必填字段：

| 字段 | 说明 |
|---|---|
| `BOARD_DESCRIPTION` | 板子描述 |
| `KERNEL_DEFCONFIG` | 内核 defconfig 文件名 |
| `KERNEL_DTB` | DTB 文件名（`.dtb` 结尾） |
| `UBOOT_DEFCONFIG` | U-Boot defconfig |
| `UBOOT_BOARD` | Rockchip `make.sh` 板名 |
| `UBOOT_BUILD_SYSTEM` | 固定 `rockchip-make-sh` |
| `UBOOT_PYTHON` | `python2` 或 `python3` |
| `BOOTLOADER_LAYOUT` | 固定 `rockchip-gpt-idblock-extlinux-v1` |
| `DOWNLOAD_LOADER_GLOBS` | loader 文件匹配模式（分号分隔） |
| `UBOOT_IMAGE_NAMES` | U-Boot 镜像匹配模式（分号分隔） |
| `CONSOLE` | 串口设备和波特率 |
| `IMAGE_SIZE_MIB` | 总镜像大小 |
| `BOOT_START_MIB` | boot 分区起始（>= 16） |
| `BOOT_SIZE_MIB` | boot 分区大小 |
| `ROOTFS_SIZE_MIB` | rootfs 初始大小 |
| `IDBLOCK_SECTOR` | IDBlock 扇区号（>= 34） |
| `UBOOT_SECTOR` | U-Boot 扇区号 |

可选字段：

| 字段 | 说明 |
|---|---|
| `EXTRA_KERNEL_ARGS` | 额外内核命令行参数 |
| `SOURCE_MANIFEST` | 对应 `manifests/` 文件名；设置后可用 `make fetch BOARD=...` |
| `EXPECTED_KERNEL_REVISION` | 锁定 kernel commit（完整 40 位 SHA） |
| `EXPECTED_UBOOT_REVISION` | 锁定 u-boot commit |
| `EXPECTED_RKBIN_REVISION` | 锁定 rkbin commit |
| `EXPECTED_BUILDROOT_REVISION` | 锁定 buildroot commit |
| `DEBIAN_PACKAGES_DEFAULT` | Debian 默认额外 APT 包名列表 |
| `DEBIAN_OVERLAYS_DEFAULT` | Debian 默认可选 overlay 插件列表 |
| `ROOTFS_HOSTNAME_DEFAULT` | 默认主机名 |

新增板型：复制最接近的 profile 改字段即可。详见 `docs/boards/add-board.md`。

### 磁盘布局约束

- 前 16 MiB 预留引导链
- IDBlock：sector 64（Rockchip 标准）
- uboot.img：sector 16384（8 MiB 处）
- FAT boot 分区：自 16 MiB 起，默认 256 MiB
- rootfs 分区：紧随 boot 分区，初始 2048 MiB（首次启动自动扩容）

`IDBLOCK_SECTOR` 必须 >= 34（不覆盖 GPT 主表），`UBOOT_SECTOR` 必须在 boot 分区之前。

## 内核 fragment（`kernel/`）

`rootfs-base.config` 在板级 defconfig 之后通过 `merge_config.sh` 合并，确保所有板型有一致的基础能力：

- 文件系统：ext4、tmpfs（含 POSIX ACL 和 xattr）、autofs
- 设备：devtmpfs（含自动挂载）、MMC（含 Rockchip DW 和 SDHCI）
- 命名空间与 cgroup：namespaces、cgroups、memcg、seccomp
- 虚拟化：virtio（blk、net、MMIO、rng）— QEMU 测试需要
- 串口：PL011（QEMU virt 控制台）
- RTC：PL031（QEMU virt）
- 其他：fhandle、inotify、signalfd、timerfd、packet socket

板级专用的内核选项放在 BSP defconfig 或额外的板级适配中，不要堆进共享 baseline。

## Debian 软件包与可选 Overlay

`DEBIAN_PACKAGES` 写真实 APT 包名（逗号/空格分隔）。无 `nm`/`hwdebug` 等 feature 别名。
可选附件由 `DEBIAN_OVERLAYS` 选择 `rootfs/debian/overlays/` 插件；WiFi/BT 固件由 `WIFIBT_CHIP` + `wifibt` overlay 控制。

优先级：命令行 `DEBIAN_PACKAGES` > 板级 `DEBIAN_PACKAGES_DEFAULT` > minbase。`DEBIAN_PACKAGES=none` 强制 minbase。
`DEBIAN_OVERLAYS` 同理：命令行 > 板级 `DEBIAN_OVERLAYS_DEFAULT` > 无插件；`none` 强制关闭。

```bash
make build-rootfs DEBIAN_PACKAGES=network-manager,wpasupplicant,i2c-tools
make build-rootfs DEBIAN_PACKAGES=none DEBIAN_OVERLAYS=none
make build-rootfs DEBIAN_PACKAGES=network-manager,wpasupplicant \
  DEBIAN_OVERLAYS=base,console,firstboot,network,wifibt WIFIBT_CHIP=AP6275S
./rootfs/debian/overlays/wifibt/sync-assets.sh /path/to/full-bsp AP6275S
```

构建元数据记录 `debian_packages` / `debian_overlays` / `network_stack`。

## Debian overlay 布局

- `rootfs/debian/boards/<board>/overlay/` — 板级覆盖（始终）
- `rootfs/debian/overlays/<name>/` — 可选插件（`plugin.sh` + 静态文件）

详见 `rootfs/debian/README.md` 与 `docs/usage/debian-features.md`。
