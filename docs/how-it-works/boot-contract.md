# 磁盘与启动契约

所有板型共享同一个磁盘布局和启动流程，由板级 profile 中的 `BOOTLOADER_LAYOUT="rockchip-gpt-idblock-extlinux-v1"` 声明。

## 磁盘布局

```
扇区 0-33        GPT 主表
扇区 34-63       未使用
扇区 64           IDBlock（RKNS 格式，Rockchip 一级引导）
扇区 64-N         IDBlock 数据（到 UBOOT_SECTOR 之前）
扇区 16384        uboot.img（U-Boot 主镜像）
扇区 16384-N      U-Boot 数据（到 BOOT_START 之前）

16 MiB            BOOT 分区开始（FAT32）
  ├── Image                   内核镜像
  ├── <board>.dtb            设备树
  └── extlinux/extlinux.conf  启动配置

16+256 MiB        rootfs 分区开始（ext4）
  └── （完整 Linux 根文件系统）

IMAGE_SIZE_MIB-33 GPT 备份表
```

具体数值由板级 profile 中的四个字段决定：

| 字段 | 当前值 | 含义 |
|---|---|---|
| `IDBLOCK_SECTOR` | 64 | IDBlock 写入的扇区号 |
| `UBOOT_SECTOR` | 16384 | uboot.img 写入的扇区号（= 8 MiB） |
| `BOOT_START_MIB` | 16 | boot 分区起始位置 |
| `BOOT_SIZE_MIB` | 256 | boot 分区大小 |

约束：`IDBLOCK_SECTOR < UBOOT_SECTOR < BOOT_START_MIB * 2048`，且 `BOOT_START_MIB >= 16`。前 16 MiB 完全保留给引导链。

## 启动流程

```
SoC ROM
  → 从 sector 64 加载 IDBlock（DDR 初始化 + TF-A + U-Boot SPL）
    → U-Boot SPL 初始化 DRAM
      → 加载完整 U-Boot（uboot.img，sector 16384）
        → U-Boot 执行 distro_bootcmd
          → 扫描 MMC 分区，找到 FAT32 boot 分区
            → 读取 extlinux/extlinux.conf
              → 加载 Image 和 DTB 到内存
              → 用 APPEND 行作为内核命令行启动
```

## extlinux 配置

`make_image.sh` 生成的 `extlinux.conf`：

```
DEFAULT rk3588
TIMEOUT 10

LABEL rk3588
    LINUX /Image
    FDT /rk3588s-rock-5c.dtb
    APPEND root=PARTLABEL=rootfs rootwait rw console=ttyFIQ0,1500000n8 earlycon=...
```

关键参数：

- `root=PARTLABEL=rootfs` — 按 GPT 分区标签查找根文件系统，不依赖设备节点名（SD 卡和 eMMC 通用）
- `rootwait` — 等待根设备就绪
- `rw` — 可读写挂载
- `console=` — 来自板级 profile 的 `CONSOLE` 字段
- 其余来自 `EXTRA_KERNEL_ARGS`

## DTB bootargs 清除

Rockchip U-Boot 在加载 DTB 后会读取 `/chosen/bootargs` 并合并到内核命令行，可能覆盖 extlinux 的 APPEND 行。为避免这个问题，`build_kernel.sh` 在打包前用 `fdtput -d` 删除 DTB 中的 `/chosen/bootargs`，`verify_image.sh` 再次确认。

这保证了 extlinux.conf 是内核命令行的唯一来源。

## U-Boot 配置契约

`build_uboot.sh` 校验 U-Boot 编译配置必须包含：

- `CONFIG_DISTRO_DEFAULTS=y` — 启用 distro 启动模式
- `CONFIG_CMD_MMC=y`、`CONFIG_CMD_FAT=y`、`CONFIG_CMD_FS_GENERIC=y` — 能从 MMC FAT 分区读文件
- `CONFIG_CMD_PXE=y`、`CONFIG_CMD_BOOTI=y` — extlinux 和内核启动支持

同时必须不包含：

- `CONFIG_FIT_SIGNATURE=y` — FIT 签名验证（会阻止非签名内核启动）
- `CONFIG_AVB_VBMETA_PUBLIC_KEY_VALIDATE=y` — AVB 验证（同上）

此外在 `u-boot.bin` 二进制中搜索 `run distro_bootcmd;` 和 `extlinux/extlinux.conf` 字符串，确认 distro 启动回退和 extlinux 路径确实编译进了二进制。

## 首次启动扩容

镜像的 rootfs 分区只有 `ROOTFS_SIZE_MIB`（默认 2048 MB），但磁盘可能更大。首次启动时：

**Buildroot**：`S02rootfs-resize` 脚本直接对根设备执行 `resize2fs`，标记 `/var/lib/rk3588-rootfs-expanded`。

**Debian**：`rk3588-firstboot` systemd 服务执行三步操作：
1. `sgdisk -e` 把 GPT 备份头移到磁盘末尾
2. `growpart` 扩展根分区到磁盘剩余空间
3. `resize2fs` 扩展 ext4 文件系统

完成后标记 `/var/lib/rk3588-firstboot.done`，后续启动跳过。服务配置了 `TimeoutStartSec=10min` 和 `ExecStart=-`（失败不阻塞启动），且不会延迟 SSH 启动。
