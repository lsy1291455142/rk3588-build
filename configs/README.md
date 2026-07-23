# configs/（构建配置中心）

`configs/` 集中存放「共享、板型无关」的构建配置：内核配置 fragment 与 SoC 平台特性。板型专属配置在 `boards/<BOARD>/board.conf`（见 `docs/boards/add-board.md`）。

```text
configs/
├── kernel/
│   ├── rootfs-base.config       # 基础内核能力（rw-ext4 与 ro-overlay 共用）
│   └── squashfs-overlay.config  # 只读 overlay 所需 SquashFS/OverlayFS（始终合并）
└── soc/
    └── rk3588.conf              # RK3588 平台特性（当前仅被 QEMU 测试消费）
```

## 内核 fragment

内核配置由 `scripts/build_kernel.sh` 用 `merge_config.sh -m` 合并，顺序如下（后者可覆盖前者）：

1. `arch/arm64/configs/<KERNEL_DEFCONFIG>` — 板级 defconfig
2. `configs/kernel/rootfs-base.config` — 基础能力
3. `configs/kernel/squashfs-overlay.config` — 只读 overlay 所需（**始终合并**，对 rw-ext4 惰性无副作用，仅增加几 KiB）
4. `KERNEL_EXTRA_FRAGMENTS`（板级共享片段，可选，相对 `configs/`）
5. `boards/<BOARD>/kernel.config`（板级片段，最后合并，可覆盖共享）

### rootfs-base.config

提供根文件系统启动与 QEMU `virt` 所需的基础能力，例如：`CONFIG_EXT4_FS`、`CONFIG_VIRTIO_BLK`/`CONFIG_VIRTIO_NET`/`CONFIG_VIRTIO_MMIO`、`CONFIG_DEVTMPFS_MOUNT`、`CONFIG_SERIAL_AMBA_PL011`、`CONFIG_RTC_DRV_PL031`、`CONFIG_MEMCG`、`CONFIG_NAMESPACES`、`CONFIG_SECCOMP`、`CONFIG_TMPFS`、`CONFIG_AUTOFS_FS`、`CONFIG_INET`、`CONFIG_UNIX` 等。`build_kernel.sh` 在合并后会强制校验一批必需选项（`CONFIG_OVERLAY_FS`、`CONFIG_SQUASHFS`、`CONFIG_VIRTIO_*` 等），缺失即中止。

### squashfs-overlay.config

提供可选只读 overlay 根（`ROOTFS_MODE=ro-overlay`）所需的 `CONFIG_SQUASHFS`（含 `XZ`/`ZSTD`/`LZ4`/`LZO`/`ZLIB` 解压）、`CONFIG_OVERLAY_FS`（含 `REDIRECT_DIR`/`INDEX`）、`CONFIG_BLK_DEV_INITRD`、`CONFIG_RD_GZIP`/`RD_ZSTD`。这些选型使单一内核 artifact 能同时启动 rw-ext4 与 ro-overlay 镜像。

## SoC 特性（soc/）

`configs/soc/<SOC>.conf` 由板级 profile 设 `SOC=<soc>` 后加载（`common.sh` 的 `_load_soc_traits`），承载与具体板子无关的平台事实。当前仅 `rk3588.conf`，且**只被 QEMU `virt` 冒烟测试消费**（`scripts/lib/qemu_smoke.py` 经 `test_debian_qemu.sh` 传入）：

- `QEMU_INITCALL_BLACKLIST`：QEMU `virt` 无真实 ATF/EL3，部分 Rockchip SiP SMC initcall（如 `rockchip_drm_init`、`system_heap_create`、`rga_init`、`regulatory_init_db`、`rockchip_cpufreq_driver_init`）会触发未定义指令而 BUG 内核，需在 QEMU 下黑名单。真实硬件不受影响。
- `QEMU_SERIAL_GETTY_MASK`：RK3588 的 FiQ 串口在 QEMU 下未建模，mask `serial-getty@ttyFIQ0.service` 以免开机卡在登录。

> 这些限制属于平台事实而非板型事实，因此放在 `soc/` 而非 `boards/` 或核心脚本，保持核心板型无关。
