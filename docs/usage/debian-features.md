# Debian 软件包与可选 Overlay

Debian rootfs 由 `build_debian.sh`（mmdebstrap，arm64 原生）生成。基础系统固定包含一组最小包，额外能力通过「精确 apt 包名」与「可选 overlay 插件」两类机制组合，二者分离、互不耦合。

## 配置文件怎么放

- **包名**：经 `DEBIAN_PACKAGES`（CLI / `.env`）或板级 `DEBIAN_PACKAGES_DEFAULT`。
- **overlay 插件**：经 `DEBIAN_OVERLAYS`（CLI / `.env`）或板级 `DEBIAN_OVERLAYS_DEFAULT`（默认 `base,console,firstboot,firstboot-info,network`）。
- **板级静态/插件文件**：放 `boards/<BOARD>/rootfs/`，始终应用（不论 `DEBIAN_OVERLAYS`）。

`DEBIAN_PACKAGES` 为空 → 用板级默认；显式 `none`/`minbase`/`off`/`-` → 仅 minbase。`DEBIAN_OVERLAYS` 为空 → 用板级默认；`none`/`off`/`-` → 无可选插件；`all` → 全部内置插件。

## 软件包列表

基础包（`build_debian.sh` 内 `PACKAGES` 数组，始终包含）：`ca-certificates`、`cloud-guest-utils`、`curl`、`dbus`、`e2fsprogs`、`ethtool`、`gdisk`、`iproute2`、`iputils-ping`、`kmod`、`less`、`net-tools`、`openssh-server`、`passwd`、`procps`、`psmisc`、`sudo`、`systemd-sysv`、`udev`、`util-linux`、`vim-tiny`、`wget`；非 Debian 11 追加 `systemd-resolved`；`ro-overlay` 追加 `initramfs-tools`、`busybox`。

额外包通过 `DEBIAN_PACKAGES` 以逗号/空格分隔的**精确 apt 包名**传入，例如：

```bash
make build-all BOARD=rk3588s-rock-5c ROOTFS=debian \
  DEBIAN_PACKAGES="network-manager,wpasupplicant,i2c-tools,usbutils"
```

`resolve_debian_packages` 会去重、拒绝非法字符，并**明确拒绝功能别名**（旧文档中的 `nm`、`hwdebug`、`wifibt`、`all`、`firstboot-info` 等），错误提示改用真实包名（如 `network-manager`）。`networkmanager` 也会被纠正为 `network-manager`。

## 可选 Overlay 插件

插件位于 `rootfs/debian/overlays/<name>/`，每个含 `plugin.sh`（必需入口）与可选 `overlay/`（静态文件树）。`plugin.sh` 定义 `plugin_apply(root_dir)`，可调用 `common.sh` 的 `apply_rootfs_overlay_tree`、`expand_overlay_template_text`、`enable_unit`、`log_info` 等。内置插件：

| 插件 | 作用 |
|---|---|
| `base` | SSH（`ssh.service` enable、缺失 host key 自动生成）、udev、systemd-resolved（非 11）、基础权限 |
| `console` | 为板级串口（`CONSOLE` 第一段设备）写 `serial-getty@<dev>.service.d/10-baud.conf`，保持板级波特率（`--keep-baud <speed>,115200`）并 enable getty |
| `firstboot` | 安装 `sbc-firstboot` 与 `sbc-firstboot.service`，首启 `growpart` + `resize2fs` 扩容根分区 |
| `firstboot-info` | 安装 `sbc-firstboot-info`（由 `sbc-firstboot` 在首启调用），打印 banner/MOTD |
| `network` | 按是否安装 `NetworkManager` 二进制自适应：有则启用 `NetworkManager.service` 并写 `10-sbc.conf`（含 `wifi.scan-rand-mac-address=no`），否则启用 `systemd-networkd.service`（写 `20-wired.network`）；二者互斥 |

`resolve_debian_overlays` 校验名字是否对应存在的 `plugin.sh`；`all` 展开为全部内置插件；未知名字直接报错。

## 只读根文件系统（ro-overlay 模式）

`ROOTFS_MODE=ro-overlay` 把根文件系统改为**只读 SquashFS + ext4 数据分区（OverlayFS upper）**，防掉电损坏、便于"恢复出厂"（清空 data 分区）。

### 内核与依赖

内核需 `CONFIG_SQUASHFS` 与 `CONFIG_OVERLAY_FS`——已由 `configs/kernel/squashfs-overlay.config` **始终合并**（对 rw-ext4 惰性无副作用，仅增加几 KiB）。`build_debian.sh` 在 ro-overlay 时额外把 `initramfs-tools`、`busybox` 加入 rootfs，并生成 initramfs（`update-initramfs`），内含 `overlayroot` hook（`rootfs/debian/ro-overlay/overlay/etc/initramfs-tools/scripts/local-bottom/overlayroot`），在 `overlayroot=PARTLABEL=data` 触发下组装 OverlayFS。

### 分区与挂载关系

- 第 2 分区：SquashFS 只读根（lower）。
- 第 3 分区（`data`，ext4）：overlay upper + 用户数据，运行时挂载 `/data`。
- 启动时 initramfs 用 `mount -t overlay` 把二者合成可读写根后 `switch_root`。

`DATA_SIZE_MIB`（`0` = 占满剩余）决定 data 分区大小。镜像 `extlinux.conf` 的 `APPEND` 含 `root=PARTLABEL=rootfs rootwait ro overlayroot=PARTLABEL=data`。

### 在真实板子上验证 overlay 生效

启动后执行 `mount | grep overlay` 应看到 `overlay on / type overlay`，且 `/data` 挂载存在（`findmnt -n -o TARGET /data`）。对根文件系统写入（如 `touch /test`）实际落在 data 分区的 upper 层；清空 data 分区即恢复出厂根。

### QEMU 测试注意事项

`test_debian_qemu.sh` 从 `image-build-info.txt` 读 `rootfs_mode`，ro-overlay 时给 QEMU 加 `--initrd` 并校验 `/data` 挂载（见 `qemu_smoke.py` 的 `data_mount` 检查）。其余健康检查（systemd、SSH、网络）与 rw-ext4 一致。

## 板级 plugin（与 overlays 同规范）

`boards/<BOARD>/rootfs/` 下的 `plugin.sh`（定义 `board_plugin_apply`）或 `overlay/` 静态树，在构建时**先于**可选 overlay 应用，且始终生效（不受 `DEBIAN_OVERLAYS` 选择影响）。规则：

- 有 `plugin.sh` 则必须定义 `board_plugin_apply()`；否则直接拷贝 `overlay/` 静态树。
- 不得在 plugin 内安装 APT 包（包只经 `DEBIAN_PACKAGES`）。
- 构建容器以只读挂载 `rootfs/`，plugin 不得回写板级树。
- 静态固件放 `overlay/lib/firmware/`；动态固件（如从 `.deb` 解包）由 `board_plugin_apply()` 在 `ROOT_DIR` 内生成。

示例：CokePi Model 的 `boards/rk3588s-cokepi-model-lp4-v10/rootfs/` 通过 `plugin.sh` 安装 AIC8800D80 固件（来自 `packages/` 本地 `.deb`）并建立 vendor 固件符号链接。详见 `boards/README.md`。

## WiFi/BT 固件（板级 plugin 示例）

没有统一的 `wifibt` overlay。WiFi/BT 固件是板级硬件事实，归板级 plugin 管理：静态 `.bin` 直接放 `overlay/lib/firmware/`；需从厂商 `.deb` 提取的动态固件在 `board_plugin_apply()` 中解包到 `ROOT_DIR`。这样核心保持板型无关，所有板级差异留在 `boards/<BOARD>/`。
