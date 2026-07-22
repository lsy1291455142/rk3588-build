# 烧录与启动

## 烧录方式

### SD 卡（推荐用于首次验证）

Linux / macOS：

```bash
# 确认 SD 卡设备名（如 /dev/sdX 或 /dev/mmcblkX）
lsblk

sudo dd if=output/<board>/<variant>/<board>-<variant>.img \
  of=/dev/sdX bs=4M status=progress conv=fsync
```

Windows：用 [balenaEtcher](https://www.balena.io/etcher/) 或 [Rufus](https://rufus.ie/) 选择 `.img` 文件写入 SD 卡。

### eMMC

方式一：先烧 SD 卡启动，再在系统内把镜像 dd 到 eMMC：

```bash
# 在开发板上执行（假设 eMMC 是 /dev/mmcblk0）
sudo dd if=/path/to/image.img of=/dev/mmcblk0 bs=4M status=progress conv=fsync
sudo sync
```

方式二：用 Rockchip 的 `rkdeveloptool` 进入 maskrom 模式烧录。镜像中的 `download-loader.bin` 和 `idblock.img` 就是为这种模式准备的，但完整流程需要 Rockchip 工具链支持，超出本项目范围。

### 压缩镜像

`.img.zst` 文件先解压再烧录：

```bash
zstd -d image.img.zst -o image.img
```

或者管道直接写入：

```bash
zstd -dc image.img.zst | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
```

## 验证烧录

烧录完成后重新插入 SD 卡，应该能看到两个分区：

- `BOOT`（FAT32，约 256 MB）— 包含 `Image`、`*.dtb`、`extlinux/extlinux.conf`
- `rootfs`（ext4）— Linux 根文件系统

## 串口连接

所有支持的板型统一使用 `ttyFIQ0`，波特率 **1500000**，8N1。

Linux：

```bash
sudo screen /dev/ttyUSB0 1500000
# 或
sudo minicom -D /dev/ttyUSB0 -b 1500000
```

macOS：

```bash
screen /dev/tty.usbserial-* 1500000
```

Windows：用 PuTTY 或 Tera Term，选 Serial，波特率 1500000。

## 首次启动

上电后串口会输出 U-Boot 和内核日志。首次启动的关键行为：

1. **根分区扩容** — `rk3588-firstboot` 服务自动把根分区扩到磁盘实际大小
2. **SSH host key 生成** — 首次启动时自动生成
3. **网络 DHCP** — 自动获取 IP（Buildroot 用 udhcpc，Debian 用 systemd-networkd 或 NetworkManager）

Debian 镜像首次启动约需 30-60 秒（扩容 + SSH key 生成），之后每次启动约 10-15 秒。

## 登录

| 方式 | 账号 | 密码 |
|---|---|---|
| 串口 | `rk3588` | `rk3588` |
| SSH | `rk3588` | `rk3588` |
| root | `root` | `rk3588` |

SSH 登录（先查 IP）：

```bash
# 串口里执行
ip addr show

# 宿主机上
ssh rk3588@<board-ip>
```

## 首次启动信息（Debian）

当 `DEBIAN_OVERLAYS` 包含 `firstboot-info`（板级默认通常包含）时，首次启动完成后串口会打印一段板型摘要，后续每次登录的 MOTD 也会显示板型信息。不需要时可从 overlay 列表中去掉 `firstboot-info`，或设 `DEBIAN_OVERLAYS=none`。

## 修改默认账号密码

构建时通过变量覆盖：

```bash
make build-all \
  BOARD=... SDK_VOLUME=... ROOTFS=debian \
  ROOTFS_USERNAME=myuser \
  ROOTFS_PASSWORD=mypassword
```

或者在已启动的系统里用 `passwd` 修改。
