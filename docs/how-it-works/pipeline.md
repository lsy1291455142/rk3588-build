# 构建流水线

`make build-all` 按顺序执行四个阶段，每个阶段都是独立的脚本，可以单独运行。

## 阶段一：build-uboot

脚本：`scripts/build_uboot.sh`

输入：SDK 中的 `u-boot/` 和 `rkbin/`，板级 profile 中的 `UBOOT_*` 字段。

流程：

1. 加载板级 profile，校验所有必填字段
2. 如果板级 profile 声明了 `EXPECTED_*_REVISION`，校验 u-boot 和 rkbin 的 Git commit
3. 在 ARM64 宿主机上，用 `qemu-x86_64-static` 包装 rkbin 里的 x86-64 工具
4. 执行 Rockchip `make.sh <board>` 编译 U-Boot
5. 执行 `make.sh --idblock` 生成 RKNS IDBlock
6. 校验引导链契约（检查 U-Boot 配置包含 extlinux 支持、不含 FIT 签名/AVB）
7. 校验 loader 魔数（`LDR `）和 IDBlock 魔数（`RKNS`）
8. 校验 IDBlock 和 uboot.img 不超过预留区域大小

输出到 `output/<board>/common/`：

- `download-loader.bin` — 下载 loader（LDR 格式）
- `idblock.img` — 磁盘 IDBlock（RKNS 格式）
- `uboot.img` — U-Boot 主镜像
- `trust.img`、`u-boot.itb` — 可选附加产物
- `uboot-build-info.txt` — 构建元数据

## 阶段二：build-kernel

脚本：`scripts/build_kernel.sh`

输入：SDK 中的 `kernel/`，板级 profile 中的 `KERNEL_*` 字段，`configs/kernel/rootfs-base.config`。

流程：

1. 加载板级 profile，校验内核 commit（如果有锁定）
2. 创建符号链接「干净视图」— 某些厂商内核在 Git 里跟踪了 Kbuild 生成文件，导致 `O=` 外源构建失败。脚本创建一个符号链接目录，隐藏 `.config`、`include/config`、`arch/arm64/include/generated` 三个脏标记
3. 写入 `.scmversion` 防止 Kbuild 调用 git（外源构建目录不是 git 仓库）
4. 用板级 defconfig 配置内核，再用 `merge_config.sh` 合并共享 fragment
5. 校验合并后的配置包含所有必需选项（ext4、MMC、devtmpfs、namespace、cgroup、virtio 等）
6. 编译 `Image`、DTB、模块
7. 安装模块到 staging 目录，删除 `build`/`source` 符号链接
8. 从 DTB 中删除 `/chosen/bootargs`（防止 U-Boot 覆盖 extlinux 的 APPEND 行）
9. 打包产物

输出到 `output/<board>/common/`：

- `Image` — 内核镜像
- `<board>.dtb` — 设备树（已删除 bootargs）
- `modules.tar` — 模块归档
- `kernel.config` — 完整配置
- `kernel-release` — 版本号
- `System.map` — 符号表
- `kernel-build-info.txt` — 构建元数据

### 共享内核 fragment

`configs/kernel/rootfs-base.config` 在板级 defconfig 之后合并，确保所有板型都有一致的基础能力：ext4、MMC、devtmpfs、namespace、cgroup、virtio（QEMU 测试需要）、PL011 串口（QEMU virt 控制台）、PL031 RTC 等。

板级专用的内核选项应该放在 BSP defconfig 里，不要堆进共享 fragment。

## 阶段三：build-rootfs

根据 `ROOTFS` 变量走两条路径之一。

### Buildroot 路径

脚本：`scripts/build_buildroot.sh`

输入：SDK 中的 `buildroot/`，`rootfs/buildroot/` external tree，内核阶段的 `modules.tar`。

流程：

1. 生成用户表（Buildroot 的 `BR2_ROOTFS_USERS_TABLES`）
2. 用 `rk3588_rootfs_defconfig` 配置 Buildroot
3. 编译（`BR2_EXTERNAL` 指向本项目的 external tree）
4. post-build 脚本安装内核模块、配置 sudoers
5. 校验 rootfs 标签是 `rootfs`，包含内核模块和用户账号
6. 用 e2fsck 检查文件系统完整性

输出到 `output/<board>/buildroot/`：`rootfs.ext4`、`rootfs.tar`、`buildroot.config`、`rootfs-build-info.txt`。

### Debian 路径

脚本：`scripts/build_debian.sh`，在 ARM64 容器中运行。

输入：内核阶段的 `modules.tar`，板级 profile 中的 `CONSOLE`、`ROOTFS_SIZE_MIB`。

流程：

1. 解析 `DEBIAN_RELEASE`（11/12/13 → bullseye/bookworm/trixie）
2. 解析 `DEBIAN_FEATURES`（nm、hwdebug、tools、firstboot-info、wifibt、all）
3. 用 `mmdebstrap --variant=minbase` 构建最小化 Debian rootfs，并安装基础包 + feature 包
4. 创建用户/密码，写入 hostname
5. 应用 `rootfs/debian/` 分层 overlay（通用 → networkd 或 nm → feature → board）
6. 安装串口 getty 波特率 drop-in（路径依赖 `CONSOLE_DEVICE`）
7. 安装内核模块并 `depmod`；可选 `install_wifibt_firmware`
8. 启用 systemd unit（NM 或 networkd、resolved、ssh、firstboot、serial-getty）
9. 校验 systemd / SSH / usrmerge 布局
10. 打包 `rootfs.ext4` 与 `rootfs.tar`

输出到 `output/<board>/debian-<release>/`：`rootfs.ext4`、`rootfs.tar`、`rootfs-build-info.txt`。

### Debian 功能集

`DEBIAN_FEATURES` 是一个逗号分隔的 token 列表：

| Token | 安装的包 | 效果 |
|---|---|---|
| `nm` | network-manager | 用 NetworkManager 替代 systemd-networkd |
| `hwdebug` | i2c-tools, usbutils, pciutils, mmc-utils | 硬件调试工具 |
| `tools` | tmux, htop, strace | 常用工具 |
| `firstboot-info` | （无额外包） | 首次启动串口摘要 + MOTD |
| `all` | 以上全部 | |

不指定时用板级 profile 的 `DEBIAN_FEATURES_DEFAULT`（如果有），否则 minbase。`DEBIAN_FEATURES=none` 强制 minbase。

## 阶段四：image 与 verify-image

脚本：`scripts/make_image.sh` 和 `scripts/verify_image.sh`

输入：前三个阶段的所有产物。

流程（make_image）：

1. 生成 `extlinux/extlinux.conf`，指向 Image 和 DTB，APPEND 行包含 `root=PARTLABEL=rootfs`
2. 创建 FAT32 boot 分区镜像，放入 Image、DTB、extlinux.conf
3. 创建 GPT 磁盘镜像（sgdisk），两个分区：boot（FAT32）和 rootfs（ext4）
4. 用 dd 写入 IDBlock（sector 64）、uboot.img（sector 16384）、boot FAT、rootfs ext4
5. 用 zstd 压缩镜像
6. 生成 SHA-256 校验和
7. 写入 `image-build-info.txt` 元数据

流程（verify_image，make_image 完成后自动触发）：

1. 检查所有前置产物存在
2. 校验 DTB 不含 `/chosen/bootargs`
3. 如果板型锁定了源码版本，校验所有构建元数据中的 commit 匹配
4. 校验内核配置包含所有必需选项
5. 校验镜像大小精确等于 `IMAGE_SIZE_MIB`
6. 用 sgdisk 验证 GPT 完整性
7. 逐分区校验起始/结束扇区、类型码、分区名
8. 从镜像中提取 IDBlock 和 uboot.img，与原始产物逐字节比对
9. 挂载 boot FAT 分区，提取 Image、DTB、extlinux.conf，与原始产物比对
10. 校验 extlinux.conf 指向正确的 DTB，包含正确的 root= 和 console= 参数
11. 提取 rootfs 分区，e2fsck 检查，blkid 校验标签
12. 校验 rootfs 中包含内核模块、用户账号、root 登录可用
13. Debian 额外校验：usrmerge 布局、systemd 二进制、firstboot 脚本、网络服务、serial getty 配置
14. 校验 SHA-256 文件与镜像匹配

任何一步失败立即退出，不产出最终镜像。

## 可选阶段：test-debian-qemu

脚本：`scripts/test_debian_qemu.sh` + `scripts/lib/qemu_smoke.py`

在 QEMU virt 机器里启动 Debian 镜像，验证：

1. 串口登录（用户名 + 密码）
2. 首次启动扩容完成（`/var/lib/rk3588-firstboot.done` 存在）
3. 根分区已扩容到 ≥ 3 GB
4. systemd 状态为 `running`，无失败单元
5. SSH 服务活跃
6. 网络服务活跃（NetworkManager 或 systemd-networkd）
7. systemd-resolved 活跃
8. SSH 配置语法正确
9. 获取到 IPv4 地址
10. SSH 密码登录成功
11. 串口日志无 Kernel panic / Oops / BUG / 启动失败等错误模式

测试用 `initcall_blacklist` 屏蔽了 DRM、cpufreq、RGA 等在 QEMU virt 里无意义的 Rockchip 驱动初始化，用 `console=ttyAMA0` 替代 `ttyFIQ0`（QEMU virt 的串口是 PL011）。
