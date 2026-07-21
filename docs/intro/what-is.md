# 这是什么

rk3588-build 是一个面向 RK3588 / RK3588S 开发板的全系统镜像构建项目。它把「拉源码 → 编译引导 → 编译内核 → 做根文件系统 → 拼磁盘镜像 → 校验 → 测试」这条原本需要在宿主机上装一堆工具、手动执行几十条命令的流程，收敛成一条 `make build-all`。

## 解决什么问题

RK3588 的 BSP 构建有几个公认的痛点：

**工具链碎片化。** 内核要交叉编译器，U-Boot 要 Rockchip 私有的 `make.sh` 和 `rkbin` 里的闭源工具，rootfs 要 Buildroot 或 debootstrap，拼镜像要 sgdisk / mtools / dd。在宿主机上把这些装齐本身就要半天。

**版本不可复现。** 厂商 SDK 通常是一个庞大的 repo 集合，今天拉下来的代码和上周的可能不一样。出了问题很难定位是哪次提交引入的。

**产物不可靠。** 手动 dd 拼镜像容易写错扇区偏移，DTB 里的 `bootargs` 可能覆盖 extlinux 配置，rootfs 可能缺内核模块。镜像能烧不代表能启动。

rk3588-build 用三个手段应对：

1. **Docker 双阶段构建器** — 一个 Ubuntu 镜像负责编译内核和 U-Boot，一个 ARM64 Debian 镜像负责用 mmdebstrap 做 rootfs。宿主机零依赖。
2. **repo manifest + 板级 profile 锁定** — 每个 SDK 来源一个 XML manifest，锁定四个组件的 Git commit。板级 profile 里可以写 `EXPECTED_*_REVISION`，构建前强制校验。
3. **自动化深度校验** — `make_image.sh` 拼完镜像后 `verify_image.sh` 逐字节比对 IDBlock、U-Boot、内核、DTB、rootfs，检查 extlinux 配置、内核配置、文件系统完整性、用户账号、首次启动脚本。

## 产出什么

一次 `make build-all` 最终产出：

- 一个 `.img` 裸 GPT 磁盘镜像，可直接 `dd` 到 SD 卡或 eMMC
- 对应的 `.img.zst` zstd 压缩版本，适合分发
- `.sha256` 校验和文件
- `image-build-info.txt` 元数据，记录每个组件的 Git commit、分区布局、所有哈希值

镜像内置 extlinux 启动配置，首次启动自动扩容根分区到实际磁盘大小，自动开启 SSH（密码登录）。

## 不是什么

- **不是发行版。** 不包含桌面环境，不追求开箱即用的用户体验。目标是可靠的 headless 服务器/开发板镜像。
- **不是内核/U-Boot 源码。** 所有源码通过 manifest 从上游拉取，本仓库只有构建编排。
- **不是通用 ARM 构建框架。** 只针对 RK3588/RK3588S，复用 Rockchip 的引导链约定（IDBlock + uboot.img + GPT + extlinux）。

## 设计理念

**声明式板型。** 每块板一个 `.conf` 文件，声明内核 defconfig、DTB 文件名、U-Boot 配置、磁盘几何参数。不加板型判断逻辑到脚本里。

**单一事实来源。** 磁盘布局（起始扇区、分区大小、保留区域）只在板级 profile 里定义一次，镜像组装和镜像校验都从同一个变量读取。

**失败即停。** 所有脚本 `set -Eeuo pipefail`，任何一步校验失败立即退出并给出具体原因，不产出半成品。

**可追溯。** 每个构建产物旁边都有一份 `*-build-info.txt`，记录源码 commit、构建参数、产物哈希。出问题时可以精确定位差异。
