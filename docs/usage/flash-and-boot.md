# 烧录与启动

本页说明如何把生成的 GPT 镜像写入存储介质、验证烧录、连接串口、首次启动与登录。

## 烧录方式

产物是裸 GPT 镜像（`<BOARD>-<variant>.img`）及其 zstd 压缩包（`.img.zst`）。写入前需先解压：

```bash
zstd -d output/<BOARD>/<variant>/<BOARD>-<variant>.img.zst
```

- **SD 卡**：把卡插入宿主，用 `lsblk` 确认设备（如 `/dev/sdX` 或 `/dev/mmcblkX`），然后：
  ```bash
  sudo dd if=output/<BOARD>/<variant>/<BOARD>-<variant>.img \
    of=/dev/sdX bs=4M status=progress conv=fsync
  ```
- **eMMC**：多数 RK3588 板可通过 maskrom/loader 模式由厂工具（如 `rkdeveloptool`、 balenaEtcher 配合适配器）写入；也可把 eMMC 接为 USB 大容量设备后按 SD 卡方式 `dd`。
- **压缩镜像**：`.img.zst` 便于传输，烧录前必须解压为 `.img`；校验和见同目录 `.sha256`。

## 验证烧录

```bash
sha256sum -c output/<BOARD>/<variant>/<BOARD>-<variant>.sha256
# 或直接比对设备
sudo cmp output/<BOARD>/<variant>/<BOARD>-<variant>.img /dev/sdX
```

镜像本身在构建末已由 `verify-image` 深度校验（分区几何、嵌入式 bootloader、rootfs 内容）。烧录后与原始 `.img` 逐字节一致即说明写入无误。

## 串口连接

板载调试串口为 FiQ 控制台（`CONSOLE`，如 `ttyFIQ0,1500000n8`）。用 USB-TTL 适配器连接对应引脚（通常 VCC/GND/TX/RX），宿主侧：

```bash
screen /dev/ttyUSB0 1500000
# 或 picocom -b 1500000 /dev/ttyUSB0
```

波特率为板级 `CONSOLE` 的第二段（如 `1500000`）。

## 首次启动

插入介质上电。Debian 首次启动会由 `sbc-firstboot` 服务自动扩容根分区（`growpart` + `resize2fs`），并写 `/var/lib/sbc-firstboot.done`；完成后开启 SSH。Buildroot 由 `S02rootfs-resize` init 脚本扩容。ro-overlay 模式不扩容只读根，仅 data 分区随写增大。

## 登录

- **Debian**：默认用户 `user` / 密码 `password`（root 密码同为 `password`）。SSH 默认开启（来自 `base` overlay，`ssh.service` enable 且首次启动生成缺失 host key）。
- **Buildroot**：默认用户 `rk3588` / 密码 `rk3588`（脚本内置回退），SSH 由 Dropbear 提供（已禁用 root 远程登录 `-w`）。

串口与 SSH 均可登录。

## 首次启动信息（Debian）

若启用 `firstboot-info` overlay，首启会在 MOTD/banner 打印板型、内核版本、根扩容结果等提示（由 `/usr/local/sbin/sbc-firstboot-info` 在首启由 `sbc-firstboot` 调用）。

## 修改默认账号密码

两种路径：

- 构建期：设 `ROOTFS_USERNAME` / `ROOTFS_PASSWORD`（Debian；Buildroot 脚本回退为 `rk3588`/`rk3588`），或在板级 `board.conf` 用 `DEBIAN_PACKAGES_DEFAULT` 之类不影响账号。
- 运行期：登录后 `passwd`（改用户）、`sudo passwd root`（改 root）。

> 注意：`ROOTFS_USERNAME` 不能为 `root`，且需符合 Linux 账户命名（小写字母/数字/`-`/`_` 开头），密码不得含冒号或换行（由 `validate_rootfs_credentials` 强制）。
