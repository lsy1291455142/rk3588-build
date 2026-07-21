# 第一次构建

本指南以 Radxa ROCK 5C + Debian 13 为例，从零走到可烧录的镜像文件。

## 1. 克隆项目

```bash
git clone https://github.com/lsy1291455142/rk3588-build.git
cd rk3588-build
```

## 2. 构建 Docker 构建器

```bash
make build
```

这一步构建 `rk3588-build:latest` 镜像，包含交叉编译器、QEMU、Python 2/3、Rockchip 工具链依赖。约需 5-10 分钟，只需做一次。

## 3. 拉取 SDK 源码

```bash
make fetch-rock5c
```

这会用 `repo` 工具按 `manifests/rk3588-rock5c.xml` 拉取四个组件到名为 `rk3588-sdk-rock5c` 的 Docker volume：

- `kernel` — Radxa fork 的 Linux 内核
- `u-boot` — Radxa fork 的 U-Boot
- `rkbin` — Rockchip 闭源固件（DDR 初始化、TF-A）
- `buildroot` — Buildroot 源码

约 3-5 GB，需要较好的网络。如果中途失败，重新运行同一命令即可续传。

验证 SDK 完整性：

```bash
make verify-sdk-volume SDK_VOLUME=rk3588-sdk-rock5c
```

## 4. 一键构建

```bash
make build-all \
  BOARD=rk3588s-rock-5c \
  SDK_VOLUME=rk3588-sdk-rock5c \
  ROOTFS=debian \
  DEBIAN_RELEASE=13
```

这一步依次执行：

1. `build-uboot` — 编译 U-Boot 引导链（约 2 分钟）
2. `build-kernel` — 编译内核 Image + DTB + 模块（约 10-20 分钟）
3. `build-rootfs` — 用 mmdebstrap 构建 Debian 13 rootfs（约 5-15 分钟）
4. `image` — 组装 GPT 镜像 + 校验（约 1 分钟）

x86_64 宿主机首次构建 Debian rootfs 时会自动注册 ARM64 binfmt，无需干预。

## 5. 查看产物

```
output/rk3588s-rock-5c/
├── common/                          # 跨 rootfs 共享产物
│   ├── Image                        # 内核镜像
│   ├── rk3588s-rock-5c.dtb         # 设备树
│   ├── modules.tar                  # 内核模块包
│   ├── kernel.config                # 完整内核配置
│   ├── kernel-release               # 内核版本号
│   ├── download-loader.bin          # Rockchip 下载 loader
│   ├── idblock.img                  # RKNS IDBlock
│   ├── uboot.img                    # U-Boot 主镜像
│   ├── kernel-build-info.txt        # 内核构建元数据
│   └── uboot-build-info.txt         # U-Boot 构建元数据
└── debian-13/                       # Debian 13 专属产物
    ├── rootfs.ext4                  # 根文件系统镜像
    ├── rootfs.tar                   # 根文件系统 tar 包
    ├── rk3588s-rock-5c-debian-13.img      # 完整 GPT 磁盘镜像
    ├── rk3588s-rock-5c-debian-13.img.zst  # zstd 压缩镜像
    ├── rk3588s-rock-5c-debian-13.sha256   # 校验和
    ├── image-build-info.txt               # 镜像构建元数据
    └── rootfs-build-info.txt              # rootfs 构建元数据
```

## 6. 烧录

把 `.img` 写入 SD 卡（假设 SD 卡是 `/dev/sdX`）：

```bash
sudo dd if=output/rk3588s-rock-5c/debian-13/rk3588s-rock-5c-debian-13.img \
  of=/dev/sdX bs=4M status=progress conv=fsync
```

或者用压缩镜像（先解压）：

```bash
zstd -d rk3588s-rock-5c-debian-13.img.zst -o rk3588s-rock-5c-debian-13.img
```

插入 ROCK 5C，接串口（1500000 波特率），上电。首次启动会自动扩容根分区并开启 SSH。

默认账号：`rk3588` / `rk3588`，root 密码同为 `rk3588`。

## 7. 可选：QEMU 冒烟测试

没有硬件也可以验证镜像能启动：

```bash
make test-debian-qemu \
  BOARD=rk3588s-rock-5c \
  SDK_VOLUME=rk3588-sdk-rock5c \
  DEBIAN_RELEASE=13
```

这会在 QEMU virt 机器里启动镜像，自动完成串口登录、等待 systemd 就绪、检查所有服务健康、测试 SSH 密码登录，最后安全关机。全部通过会输出 `QEMU Debian smoke test passed`。

## 下一步

- [日常构建](daily-build.md) — 修改源码后如何增量构建
- [烧录与启动](flash-and-boot.md) — 更多烧录方式和首次启动细节
- [SDK 来源](sdk.md) — 使用其他开发板 SDK 或本地源码
