# 架构与目录

## 整体结构

项目由三层组成：

```
宿主机
  ├── Makefile            # 用户入口，参数校验，docker compose 调用
  ├── .env                # 记住当前板型/SDK/rootfs 选择
  └── output/             # 所有构建产物（bind mount）

Docker 容器
  ├── rk3588-build        # 主构建器（Ubuntu 22.04）
  │   ├── 编译内核、U-Boot
  │   ├── 组装 GPT 镜像
  │   └── 运行 Buildroot
  └── debian-rootfs       # Debian rootfs 构建器（ARM64）
      └── 用 mmdebstrap 构建 Debian rootfs

Docker Volume
  ├── rk3588-sdk-*        # SDK 源码（每个来源一个 volume）
  └── rk3588-ccache       # 编译缓存
```

## 两个 Docker 镜像

`Dockerfile` 是双阶段的：

**`rk3588-build`（Ubuntu 22.04）** — 主构建器，负责：

- 交叉编译 ARM64 内核（`gcc-aarch64-linux-gnu`）
- 用 Rockchip `make.sh` 构建 U-Boot 引导链
- 运行 Buildroot 构建 rootfs
- 用 sgdisk / mtools / dd 组装 GPT 镜像
- 运行 QEMU 冒烟测试

包含 Python 2.7（Rockchip U-Boot 的 FIT 生成器需要）和 Python 3（其他所有工具）。e2fsprogs 从源码编译 1.47.2，因为 Ubuntu 22.04 自带的版本不支持 Debian Trixie 的 ext4 特性。

**`debian-rootfs`（Debian Trixie ARM64）** — 专用 rootfs 构建器：

- 以 `linux/arm64` 平台运行（x86_64 宿主机上通过 binfmt 模拟）
- 用 `mmdebstrap` 构建最小化 Debian rootfs
- 需要 `privileged: true` 来执行 chroot 和 mount 操作

分离的原因：mmdebstrap 必须在目标架构（ARM64）上原生运行，不能用交叉编译。

## 目录映射

| 宿主机路径 | 容器内路径 | 方式 | 说明 |
|---|---|---|---|
| `./scripts/` | `/home/builder/scripts/` | 只读 | 构建脚本 |
| `./manifests/` | `/home/builder/manifests/` | 只读 | repo manifest |
| `./configs/` | `/home/builder/configs/` | 只读 | 板型与内核配置 |
| `./rootfs/` | `/home/builder/rootfs/` | 只读 | Buildroot external tree |
| `./patches/` | `/home/builder/patches/` | 只读 | 可选补丁 |
| `./output/` | `/home/builder/output/` | 读写 | 构建产物 |
| (volume) | `/home/builder/sdk/` | 读写 | SDK 源码 |
| (volume) | `/home/builder/.ccache/` | 读写 | 编译缓存 |

脚本和配置以只读 bind mount 挂载，改宿主机上的文件立即生效，不需要重新构建 Docker 镜像。只有 `Dockerfile` 本身变更时才需要 `make build`。

## SDK Volume

每个 SDK 来源对应一个独立的 Docker volume（如 `rk3588-sdk-rock5c`），容器内挂载为 `/home/builder/sdk`。内部结构：

```
/home/builder/sdk/
├── kernel/           # Linux 内核源码
├── u-boot/           # U-Boot 源码
├── rkbin/            # Rockchip 闭源固件
├── buildroot/        # Buildroot 源码
└── .rk3588-build/    # 构建中间产物（按板型分目录）
    └── <board>/
        ├── kernel/       # 内核 O= 构建目录
        ├── kernel-source/ # 内核符号链接视图
        ├── buildroot/    # Buildroot O= 构建目录
        └── debian-*/     # Debian rootfs 构建目录
```

中间产物放在 SDK volume 而不是 `output/`，因为它们只在构建过程中需要，且可以被安全删除重来。

## 输出目录

```
output/
└── <board>/                          # 板型名（如 rk3588s-rock-5c）
    ├── common/                       # 跨 rootfs 共享的产物
    │   ├── Image                     # 内核镜像
    │   ├── <board>.dtb              # 设备树二进制
    │   ├── modules.tar               # 内核模块归档
    │   ├── kernel.config             # 完整内核配置
    │   ├── kernel-release            # 内核版本字符串
    │   ├── System.map                # 内核符号表
    │   ├── download-loader.bin       # Rockchip 下载 loader
    │   ├── idblock.img               # RKNS IDBlock
    │   ├── uboot.img                 # U-Boot 主镜像
    │   ├── kernel-build-info.txt     # 内核构建元数据
    │   └── uboot-build-info.txt      # U-Boot 构建元数据
    ├── buildroot/                    # Buildroot rootfs 产物
    │   ├── rootfs.ext4
    │   ├── rootfs.tar
    │   ├── <board>-buildroot.img     # 完整磁盘镜像
    │   ├── <board>-buildroot.img.zst
    │   ├── <board>-buildroot.sha256
    │   ├── image-build-info.txt
    │   └── rootfs-build-info.txt
    └── debian-<release>/             # Debian rootfs 产物（如 debian-13）
        ├── rootfs.ext4
        ├── rootfs.tar
        ├── <board>-debian-<rel>.img
        ├── <board>-debian-<rel>.img.zst
        ├── <board>-debian-<rel>.sha256
        ├── image-build-info.txt
        ├── rootfs-build-info.txt
        └── qemu-smoke/               # QEMU 测试产物（可选）
            ├── serial.log
            ├── ssh.log
            └── result.txt
```

`common/` 存内核和 U-Boot 产物，因为它们与 rootfs 类型无关。`buildroot/` 和 `debian-*/` 各自存 rootfs 和最终镜像。

## 容器入口

`entrypoint.sh` 做以下事情：

1. 如果以 root 启动，用 `gosu` 降到 `builder` 用户（uid 1000），确保输出文件权限正确
2. 配置交叉编译环境（`CROSS_COMPILE=aarch64-linux-gnu-`）
3. 启用 ccache
4. 配置 Git（用户名、LFS）
5. 打印环境信息横幅
6. 如果是交互式 shell，运行环境自检（检查所有工具可用）

在 ARM64 宿主机上可以通过 `USE_NATIVE_BUILD=yes` 切换到原生 GCC 编译，省去交叉编译开销。
