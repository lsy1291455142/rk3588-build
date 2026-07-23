# 第一次构建

本页用 ROCK 5C + Debian 13 走完整流程：构建器 → 拉取 SDK → 一键构建 → 产物 → 烧录 → QEMU 测试。宿主只需 Docker 与 GNU Make。

## 1. 克隆项目

```bash
git clone <repo-url> rk3588-build
cd rk3588-build
```

## 2. 构建 Docker 构建器

```bash
make build
```

构建 `rk3588-build:latest`（amd64/x86_64 与 arm64 通用）。x86_64 宿主首次构建 Debian rootfs 会自动注册 ARM64 binfmt 模拟（`make build-debian-builder` 内部调用 `register-arm64-binfmt`）。

## 3. 拉取 SDK 源码

```bash
make fetch BOARD=rk3588s-rock-5c
```

按板级 `SOURCE_MANIFEST`（`rk3588-rock5c.xml`）用 `repo` 拉取 `kernel`/`u-boot`/`rkbin`/`buildroot` 到派生卷 `rk3588-sdk-rock5c`，并自动写入 `.env` 的 `SDK_VOLUME`。本地已有 SDK 的板型（如 CokePi）改用 `make import-local-sdk SDK_PATH=/abs SDK_VOLUME=<v>`。

## 4. 一键构建

```bash
make build-all \
  BOARD=rk3588s-rock-5c \
  SDK_VOLUME=rk3588-sdk-rock5c \
  ROOTFS=debian DEBIAN_RELEASE=13
```

`build-all` 依次执行 `build-uboot` → `build-kernel` → `build-rootfs` → `image`（image 之后自动 `verify-image`）。可附加 `DEBIAN_PACKAGES=...` 与 `DEBIAN_OVERLAYS=...`。

## 5. 查看产物

产物在 `output/rk3588s-rock-5c/debian-13/`：

- `<BOARD>-debian-13.img` — 裸 GPT 镜像，可直接 `dd` 烧录
- `<BOARD>-debian-13.img.zst` — zstd 压缩镜像（级别 `ZSTD_LEVEL`，默认 6）
- `<BOARD>-debian-13.sha256` — 校验和（裸镜像与压缩镜像）
- `image-build-info.txt` — 完整构建元数据（各组件 commit、分区布局、SHA256）
- `rootfs.ext4` / `rootfs.tar` / `initrd.img` — 中间产物

默认账号 `user` / `password`（Debian；root 密码同为 `password`）。首次启动自动扩容根分区并开启 SSH。

## 6. 烧录

```bash
# 解压
zstd -d output/rk3588s-rock-5c/debian-13/rk3588s-rock-5c-debian-13.img.zst

# 写入 SD 卡（替换 /dev/sdX 为真实设备，务必确认！）
sudo dd if=output/rk3588s-rock-5c/debian-13/rk3588s-rock-5c-debian-13.img \
  of=/dev/sdX bs=4M status=progress conv=fsync
```

eMMC 烧录通常通过板厂工具或把 eMMC 作 USB 大容量设备处理，流程同理。详见 [烧录与启动](/usage/flash-and-boot)。

## 7. 可选：QEMU 冒烟测试

无需真实硬件即可验证 Debian 镜像可启动、可串口登录、SSH 与 systemd 健康：

```bash
make test-debian-qemu \
  BOARD=rk3588s-rock-5c \
  SDK_VOLUME=rk3588-sdk-rock5c \
  DEBIAN_RELEASE=13
```

测试在 QEMU `virt` 里用构建出的内核与完整 GPT 镜像启动，自动注入 SoC 特性黑名单（见 `configs/soc/rk3588.conf`），通过 `/var/lib/sbc-firstboot.done` 与 `systemd is-system-running` 等判定启动成功，并做 SSH 密码登录与 IPv4 检查。结果写入 `output/<BOARD>/debian-<rel>/qemu-smoke/result.txt`。

## 下一步

- 想换板型/SDK/rootfs 而不改命令？见 [日常构建](/usage/daily-build) 的 `make use-*` 交互切换。
- 想加自己的板子？见 [新增板型](/boards/add-board)。
- 想理解两阶段构建与分区布局？见 [架构](/how-it-works/architecture) 与 [磁盘与启动契约](/how-it-works/boot-contract)。
