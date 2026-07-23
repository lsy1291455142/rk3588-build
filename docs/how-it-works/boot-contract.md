# 磁盘与启动契约

构建系统对磁盘布局、启动链、extlinux 配置和 DTB 处理有严格契约，由 `verify_image.sh` 在产出后强制校验。本页记录这些契约，便于理解镜像为何这样布局，以及改动时哪些约束不可破坏。

## 磁盘布局（GPT）

镜像总大小为 `IMAGE_SIZE_MIB`（默认 2048 MiB）。以 512 字节扇区计，总扇区数 `IMAGE_SIZE_MIB * 2048`，末 34 扇区保留给次级 GPT。三个分区的几何由 `make_image.sh` 计算，常量来自板级 profile：

| 分区 | 编号 | 类型 | 标签 | 起始 | 大小 | 内容 |
|---|---|---|---|---|---|---|
| boot | 1 | `0700` | `BOOT` | `BOOT_START_MIB * 2048`（默认扇区 32768） | `BOOT_SIZE_MIB`（默认 256 MiB） | FAT32：Image、`<DTB>`、extlinux.conf（及 DTBO、initrd） |
| rootfs | 2 | `8300` | `rootfs` | boot 末扇区 +1 | rw-ext4：`ROOTFS_SIZE_MIB`（默认 1700 MiB）；ro-overlay：SquashFS 体积 +1 MiB 余量 | ext4（rw-ext4）或 SquashFS（ro-overlay） |
| data | 3 | `8300` | `data` | rootfs 末扇区 +1 | ro-overlay 专属：`DATA_SIZE_MIB`（0 = 占满剩余） | ext4，作为 OverlayFS upper，挂载 `/data` |

约束（来自 `common.sh` 的 `validate_board_profile`）：`BOOT_START_MIB >= 16`（保留 IDBlock/U-Boot 空间）；`IDBLOCK_SECTOR < UBOOT_SECTOR`（默认 64 < 16384）；`UBOOT_SECTOR` 在 boot 分区之前；`ROOTFS_SIZE_MIB` 不超过剩余容量；`IDBLOCK_SECTOR >= 34`（不覆盖主 GPT）。

bootloader 区域（idblock 在 `IDBLOCK_SECTOR`，uboot 在 `UBOOT_SECTOR`）由 `bootloader_layouts.sh` 的 `rockchip-gpt-idblock-extlinux-v1` 写入，与 GPT 分区并存于镜像前段。

## 启动流程

1. SoC 上电从 eMMC/SD 读取 `IDBLOCK_SECTOR` 处的 RKNS IDBlock（含 DDR 初始化与 TF-A 等），随后加载 `UBOOT_SECTOR` 的 U-Boot。
2. U-Boot 启用 `CONFIG_DISTRO_DEFAULTS`，执行 `run distro_bootcmd`，扫描 boot 分区（FAT32）的 `extlinux/extlinux.conf`。
3. extlinux 选择 `EXTLINUX_LABEL` 条目，加载 `/Image`、设备树 `/<DTB>`（ro-overlay 还加载 `/initrd.img`），以 `APPEND` 的内核命令行启动。
4. rw-ext4：内核挂载第 2 分区为可读写根（`root=PARTLABEL=rootfs rootwait rw`）。
5. ro-overlay：initramfs 的 `overlayroot` hook（由 `overlayroot=PARTLABEL=data` 触发）把 SquashFS 根作为 lower、data 分区的 overlay 作为 upper，组装可读写 OverlayFS 后 `switch_root`；data 分区即用户可写层。

## extlinux 配置

`make_image.sh` 生成的 `extlinux.conf` 形态：

```text
DEFAULT <EXTLINUX_LABEL>
TIMEOUT 10

LABEL <EXTLINUX_LABEL>
    LINUX /Image
    FDT /<KERNEL_DTB>
    FDTOVERLAYS /overlays/<dtbo> ...   # 仅当 KERNEL_DTBO 非空
    INITRD /initrd.img                  # 仅 ro-overlay
    APPEND root=PARTLABEL=rootfs rootwait rw console=<CONSOLE> <EXTRA_KERNEL_ARGS>   # rw-ext4
    APPEND root=PARTLABEL=rootfs rootwait ro overlayroot=PARTLABEL=data console=<CONSOLE> <EXTRA_KERNEL_ARGS>  # ro-overlay
```

校验点：`verify_image.sh` 确认 `FDT /<DTB>` 命中、`rw`/`ro`、`overlayroot=PARTLABEL=data`（ro-overlay）、`console=<CONSOLE>` 与板级 `CONSOLE` 一致；从镜像提取的 DTB 不得再含 `/chosen/bootargs`（见下）。

## DTB bootargs 清除

Rockchip U-Boot 会在 extlinux `APPEND` 之后合并 DTB 的 `/chosen/bootargs`，并覆盖 `root=` 等重复键。`build_kernel.sh` 在打包前，若 `DTB_STRIP_BOOTARGS=yes`（默认），用 `fdtput -d` 删除编译产物 DTB 的 `/chosen/bootargs`，使 extlinux 的 `APPEND` 始终权威（保证镜像启动的是其标签对应的根分区）。`kernel-build-info.txt` 记录 `dtb_bootargs=extlinux-only-v1`；`verify_image.sh` 既校验打包 DTB 无 `/chosen/bootargs`，也复检产物 DTB，防止重新编译后回退。设 `DTB_STRIP_BOOTARGS=no` 可保留 DTB 中的 bootargs（用于板子确需自带命令行的情况）。

## U-Boot 配置契约

`build_uboot.sh` 的 `validate_extlinux_boot_contract` 强制：

- 必需：`CONFIG_DISTRO_DEFAULTS`、`CONFIG_CMD_MMC`、`CONFIG_CMD_FAT`、`CONFIG_CMD_FS_GENERIC`、`CONFIG_CMD_PXE`、`CONFIG_CMD_BOOTI`。
- 禁止：`CONFIG_FIT_SIGNATURE`、`CONFIG_AVB_VBMETA_PUBLIC_KEY_VALIDATE`（避免覆盖 extlinux 启动路径）。
- 二进制须含字符串 `run distro_bootcmd;` 与 `extlinux/extlinux.conf`。

这是因为镜像启动完全依赖 U-Boot 的 distro 自动扫描，而非硬编码的 FIT/AVB 启动。

## 首次启动扩容

- **Debian**：`firstboot` overlay 安装 `sbc-firstboot`（服务 `sbc-firstboot.service`，`WantedBy=multi-user.target`，`Before=ssh.service`、`TimeoutStartSec=10min`、`ExecStart=-/usr/local/sbin/sbc-firstboot`）。该脚本从 sysfs 取根分区号，`growpart` 扩容分区，`resize2fs` 扩容文件系统，完成后写 `/var/lib/sbc-firstboot.done`。`firstboot-info` overlay 可选地让其在首启打印 banner/MOTD。
- **Buildroot**：`board/rk3588/overlay/etc/init.d/S02rootfs-resize` 在 BusyBox init 启动时对根设备 `resize2fs`（用 `/var/lib/rk3588-rootfs-expanded` 去重）。

ro-overlay 不扩容根（SquashFS 只读、固定），仅 data 分区在运行时按 OverlayFS 自然增长；"恢复出厂"等价于清空/重建 data 分区。
