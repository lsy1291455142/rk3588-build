# Debian 软件包与可选 Overlay

构建 Debian rootfs 时，在 minbase 之上通过 `DEBIAN_PACKAGES` 安装**真实 APT 包名**。
项目专属行为（NetworkManager 配置、firstboot 摘要、WiFi/BT 固件、串口 getty 等）以
`rootfs/debian/overlays/` 可选插件形式存在，不再使用 `nm` / `hwdebug` 这类 feature token，
也不再写死进构建核心。

## 配置文件怎么放

| 路径 | 何时应用 |
|---|---|
| `boards/<board>/rootfs/plugin.sh` | 匹配当前 `BOARD` 时（始终） |
| `boards/<board>/rootfs/overlay/` | 板级插件应用，或无 plugin 时静态拷贝 |
| `rootfs/debian/overlays/<name>/plugin.sh` | `DEBIAN_OVERLAYS` 选中时 |
| 插件自带 `overlay` / `overlay-*` | 由对应插件按需应用 |

- 文件以 `.in` 结尾时按模板处理，`@BOARD@`、`@ROOTFS_HOSTNAME@`、`@DEBIAN_PACKAGES@`、`@DEBIAN_OVERLAYS@` 等在安装时展开。
- 详见 [`rootfs/debian/README.md`](../../rootfs/debian/README.md)。

## 软件包列表

`DEBIAN_PACKAGES`（或板级 `DEBIAN_PACKAGES_DEFAULT`）写什么就装什么，逗号/空格分隔。

| 示例 | 效果 |
|---|---|
| `network-manager,wpasupplicant` | 只安装这些 apt 包 |
| `i2c-tools,usbutils,pciutils,mmc-utils` | 硬件调试工具 |
| `tmux,htop,strace` | 常用诊断工具 |
| `none` / `minbase` / `off` | 强制 minbase，忽略板级默认 |
| （空） | 使用板级默认；板级也空则只有 minbase |

优先级：命令行 `DEBIAN_PACKAGES` > 板级 `DEBIAN_PACKAGES_DEFAULT` > minbase。

```bash
make build-rootfs DEBIAN_PACKAGES=network-manager,wpasupplicant,i2c-tools
make build-rootfs DEBIAN_PACKAGES=none
```

构建元数据 `rootfs-build-info.txt` 记录 `debian_packages`、`debian_overlays` 和 `network_stack`。

## 可选 Overlay 插件

`DEBIAN_OVERLAYS`（或板级 `DEBIAN_OVERLAYS_DEFAULT`）选择附件插件。

| 值 | 含义 |
|---|---|
| （空） | 板级默认；板级也空则无插件 |
| `none` / `off` / `-` | 强制无可选 overlay |
| `all` | 启用 `overlays/*` 全部插件 |
| `base,console,firstboot,network` | 显式列表（按顺序） |

| Overlay | 行为 |
|---|---|
| `base` | SSH 密码/root 登录、hostkey ExecStartPre、udev GPU 权限；启用 ssh / resolved |
| `console` | 串口 getty 波特率 drop-in + 启用 `serial-getty@CONSOLE_DEVICE` |
| `firstboot` | 首次启动扩容 rootfs |
| `firstboot-info` | 首次启动串口摘要 + MOTD |
| `network` | 有 `/usr/sbin/NetworkManager` → 写 NM conf 并启用；否则启用 systemd-networkd + 有线 DHCP |

```bash
make build-rootfs DEBIAN_OVERLAYS=base,console,firstboot,network
make build-rootfs DEBIAN_OVERLAYS=none
make build-rootfs DEBIAN_OVERLAYS=all
```

插件只做镜像布局需要的 enable（串口 getty、firstboot、NM 与 networkd 互斥等）。
常规 deb 包 postinst / systemd preset 仍按 Debian 自身逻辑处理。

## 只读根文件系统（ro-overlay 模式）

默认 `rw-ext4` 是单个可写 ext4 根分区。对于工业设备、车载、数字标牌等常被硬断电、
要求**断电不损坏根分区**、且**重启可恢复出厂**的场景，可选 `ro-overlay` 模式：

- 根分区改为**只读 SquashFS**（压缩、不可写，断电不会损坏）；
- 额外 `data` 分区为 **ext4**，作为 OverlayFS 的上层（upperdir）承载所有写操作与用户数据；
- 启动经由 Debian `initramfs-tools` 的 `local-bottom` hook（`overlayroot`）把
  SquashFS 根与 ext4 `data` 分区组装成可写的 OverlayFS 根；
- 数据分区不可挂载时回退为易失 tmpfs 上层，保证仍可读启动；
- **格式化/清空 `data` 分区 = 恢复出厂设置**（删除所有写入与用户数据，只读根保持不变）。

开启方式（不影响默认 `rw-ext4` 行为）：

```bash
# 对未预设默认的板型，需显式指定模式：
make build-all BOARD=... ROOTFS=debian ROOTFS_MODE=ro-overlay

# 可选：固定 data 分区大小（MiB），0 = 占满根分区之后的剩余空间
make build-all BOARD=... ROOTFS=debian ROOTFS_MODE=ro-overlay DATA_SIZE_MIB=512

# 仅构建/校验/启测（与 rw-ext4 用法一致，只是多传 ROOTFS_MODE）
make image            ROOTFS=debian ROOTFS_MODE=ro-overlay
make verify-image     ROOTFS=debian ROOTFS_MODE=ro-overlay
make test-debian-qemu ROOTFS=debian ROOTFS_MODE=ro-overlay
```

> 注：本仓库的 `rk3588s-cokepi-model-lp4-v10` 板型已在 `boards/rk3588s-cokepi-model-lp4-v10/board.conf` 中设置
> `ROOTFS_MODE_DEFAULT="ro-overlay"`，因此对该板执行上面的 `make build-all BOARD=... ROOTFS=debian`
> 即可，无需再传 `ROOTFS_MODE=ro-overlay`。

该模式会：构建时生成 `initrd.img` 与 `rootfs.squashfs`；镜像含 3 个 GPT 分区
（`boot`、`rootfs`=squashfs、`data`=ext4）；extlinux 以 `ro overlayroot=PARTLABEL=data`
引导并加载 `initrd.img`。`verify-image` 与 `test-debian-qemu` 均会自动按该模式校验/启动。
板级 profile 可用 `ROOTFS_MODE_DEFAULT` / `DATA_SIZE_MIB_DEFAULT` 固化默认值。

### 内核与依赖

- **内核**：`scripts/build_kernel.sh` 始终合并 `configs/kernel/rootfs-base.config` 与
  `configs/kernel/squashfs-overlay.config`（含 `CONFIG_OVERLAY_FS=y`、`CONFIG_SQUASHFS=y`
  等），所以单个内核产物即可启动 `rw-ext4` 与 `ro-overlay` 两种镜像，无需为 overlay
  单独编内核。
- **initramfs 的 mount**：`ro-overlay` 构建会自动安装 `initramfs-tools` 与 `busybox`。
  initramfs-tools 在缺少 busybox 时会回退到 klibc 的 `mount`，而 klibc mount **不支持
  overlay 文件系统**（`mount -t overlay` 会打印 `Usage: ...` 后失败）。busybox 的 mount
  支持 overlay，且其 `zz-busybox` 钩子会把 `/bin/busybox` 打进 initramfs；`overlayroot`
  钩子（`rootfs/debian/ro-overlay/overlay/etc/initramfs-tools/scripts/local-bottom/overlayroot`）
  会优先调用 `/bin/busybox mount` 组装 overlay 根。

### 在真实板子上验证 overlay 生效

烧录镜像并启动后，在板端确认 overlay 确实挂载且数据落在持久 ext4 分区（而非易失 tmpfs 回退）：

```bash
# 根文件系统类型应为 overlay
findmnt -n -o FSTYPE /          # 期望: overlay

# /proc/mounts 中根应带 lowerdir/upperdir/workdir
grep ' / ' /proc/mounts

# 下层只读 squashfs 与持久数据分区是否就位：/data 必须是 ext4（不是 tmpfs）
mount | grep -E ' /ro | /data '

# 启动日志应出现装配记录，且不应出现 "using volatile tmpfs upper"
dmesg | grep -i overlayroot
```

最硬的证据是**断电/重启持久性**：写入落到 `/data` 的 ext4 上，重启后仍在；若回退到 tmpfs
则重启即丢。

```bash
echo "overlay-ok-$(date +%s)" | sudo tee /overlay_test_marker
sudo reboot
# 重新登录后
cat /overlay_test_marker        # 仍在 -> overlay 用持久 ext4 数据分区，生效 ✓
```

恢复出厂：格式化/清空 `data` 分区（`PARTLABEL=data`），所有写入与用户数据消失，只读
SquashFS 根不变。

### QEMU 测试注意事项

`make test-debian-qemu` 在 QEMU `virt` 机器里模拟启动，会自动以 `overlayroot=PARTLABEL=data`
加载 `initrd.img`，并用 `initcall_blacklist` 屏蔽在 QEMU virt 中无意义的 Rockchip 驱动
（`rockchip_drm_init`、`rockchip_cpufreq_driver_init`、`rga_init`、`regulatory_init_db`、
`system_heap_create`）。其中 `system_heap_create` 必须屏蔽：QEMU `virt` 没有真实 ATF/EL3，
Rockchip SiP SMC 调用（如 DMA system heap 初始化的 `sip_smc_get_dram_map`）会陷入未定义指令。
这些屏蔽**仅用于 QEMU 仿真**，真实硬件启动不受影响。

### 分区与挂载关系图

**1) 磁盘 GPT 分区布局**

```text
┌────────────────────────── 磁盘镜像 (GPT) ──────────────────────────┐
│ p1  boot    FAT32    label=BOOT   Image / DTB / extlinux.conf / initrd.img │
│ p2  rootfs  SquashFS 8300        ← 只读根 (lower)        = rootfs.squashfs    │
│ p3  data    ext4     8300        ← 可写上层+用户数据      = mkfs.ext4 (空)     │
└───────────────────────────────────────────────────────────────────┘
```

**2) 启动时的挂载组装（initramfs 内部）**

```text
 extlinux:
   LINUX /Image
   INITRD /initrd.img
   APPEND root=PARTLABEL=rootfs rootwait ro overlayroot=PARTLABEL=data

 ┌─ initramfs 常规根挂载 ─────────┐   ┌─ overlayroot hook (local-bottom) ───────────┐
 │ p2 (squashfs) ──ro──▶ ${rootmnt}│   │ 1. resolve_device(PARTLABEL=data) → p3        │
 │                                │   │ 2. p3 (ext4) ───────────▶ /overlay            │
 │                                │   │ 3. move ${rootmnt} ──────────▶ /ro            │
 │                                │   │ 4. mount -t overlay (lower=/ro,               │
 │                                │   │      upper=/overlay/overlay/upper,           │
 │                                │   │      work =/overlay/overlay/work) ─▶ ${rootmnt}│
 │                                │   │ 5. move /ro ─▶ ${rootmnt}/ro                  │
 │                                │   │    move /overlay ─▶ ${rootmnt}/data          │
 └────────────────────────────────┘   └──────────────────────────────────────────┘
                                         ▼ switch_root 到 ${rootmnt}
```

**3) 运行视角（系统里实际看到的挂载）**

```text
        ┌──────────── /  (OverlayFS, 可写) ────────────┐
        │  读: 未改→squashfs │ 已改→data                 │
        │  写: ─────────────────────────────────────▶   │
        └──────────┬───────────────────────┬──────────┘
              lower│                   upper / work│
                   ▼                        ▼
             /ro = p2 SquashFS        /data = p3 ext4
             (只读, 永不被写)          (存放所有写操作 + 用户数据, 持久)
```

**4) 断电保护与恢复出厂**

```text
 写文件:    /etc/foo ──▶ upper ──▶ /data (ext4)              重启保留 ✓
 硬断电:    SquashFS 根不可写 → 根分区不会损坏 ✓
 恢复出厂:  清空/格式化 p3 (data) → 所有写入消失, 只读根不变 ✓
```

## 板级 plugin（与 overlays 同规范）

板型专属逻辑放在 `boards/<BOARD>/rootfs/`，接口与可选 overlay 一致：

- 有 `plugin.sh` → 构建时 `source` 并调用 `board_plugin_apply(root_dir)`
- 仅有 `overlay/` → 静态拷贝
- 规范说明：[boards/README.md](../../boards/README.md)

## WiFi/BT 固件（板级 plugin 示例）

WiFi/BT 不是通用插件，也不进 `DEBIAN_PACKAGES`。CokePi Model 的板级
`plugin.sh` 在 `make build-rootfs` 时从 `packages/*.deb`（或已 stage 的 overlay）
把 Radxa `aic8800-firmware`（默认 3.0，`info_len=4`）装进 rootfs，并带上 `/vendor` 兼容链。
容器内 `rootfs/:ro`，不会回写板级目录。

```bash
make build-rootfs   # 自动从 packages/*.deb 装固件进 rootfs

# 可选（仅可写 host 树）：把 blob 物化到 overlay/
./boards/rk3588s-cokepi-model-lp4-v10/rootfs/stage-aic8800-firmware.sh
```

详见 [boards/rk3588s-cokepi-model-lp4-v10/README.md](../../boards/rk3588s-cokepi-model-lp4-v10/rootfs/README.md)。

