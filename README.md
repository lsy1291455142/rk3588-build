# RK3588 Linux BSP Docker 编译环境

一键搭建 RK3588 Linux 编译环境，自动安装依赖并拉取公开 SDK 源码。

## 📁 项目结构

```
rk3588-build/
├── Dockerfile              # Docker 镜像定义 (编译依赖 + 交叉工具链)
├── docker-compose.yml      # Compose 编排配置
├── Makefile                # 便捷命令 (build/shell/fetch/compile)
├── .env.example            # 环境变量模板
├── scripts/
│   ├── entrypoint.sh       # 容器入口脚本
│   └── fetch_sources.sh    # SDK 源码拉取脚本
├── configs/                # 自定义编译配置 (defconfig 等)
└── patches/                # 本地补丁目录
```

## 🚀 快速开始

### 1. 构建 Docker 镜像

```bash
cd rk3588-build
make build
# 或
docker compose build
```

### 2. 拉取 SDK 源码

```bash
# 拉取 Rockchip 官方 SDK (默认)
make fetch

# 拉取 Firefly BSP
make fetch-firefly

# 拉取 Radxa BSP
make fetch-radxa
```

### 3. 进入编译环境

```bash
make shell
# 进入容器后可看到:
#   /home/builder/sdk/kernel   - Linux 内核源码
#   /home/builder/sdk/u-boot   - U-Boot 源码
#   /home/builder/sdk/rkbin    - Rockchip 闭源固件 (DDR init, TF-A)
#   /home/builder/sdk/buildroot - 根文件系统构建
```

### 4. 编译

```bash
# 编译 Kernel
make build-kernel

# 编译 U-Boot
make build-uboot

# 或在容器内手动编译
make shell
> cd /home/builder/sdk/kernel
> make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- rockchip_linux_defconfig
> make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
```

## 🔧 配置说明

复制环境变量模板并修改:

```bash
cp .env.example .env
vim .env
```

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `BSP_SOURCE` | `rockchip` | BSP 来源: `rockchip` / `firefly` / `radxa` / `orangepi` / `custom` |
| `BRANCH` | `stable-5.10` | 代码分支 |
| `FETCH_ON_START` | `no` | 容器启动时自动拉取源码 |
| `JOBS` | `0` | 编译并行数 (0=自动) |
| `DEPTH` | `1` | Git 浅克隆深度 (0=完整) |
| `EXTRA_COMPONENTS` | `no` | 拉取额外组件 (device-tree 等) |
| `CCACHE_MAXSIZE` | `10G` | ccache 最大缓存 |
| `DOCKER_CPUS` | `8` | Docker CPU 限制 |
| `DOCKER_MEMORY` | `16G` | Docker 内存限制 |

## 📦 支持的 BSP 来源

### Rockchip 官方 (推荐)

最通用的选择，包含 RK3588 官方驱动支持:

```bash
BSP_SOURCE=rockchip  BRANCH=stable-5.10   # Linux 5.10 (Rockchip LTS)
BSP_SOURCE=rockchip  BRANCH=stable-6.1    # Linux 6.1 (较新)
```

组件来源:
- kernel: https://github.com/rockchip-linux/kernel
- u-boot: https://github.com/rockchip-linux/u-boot
- rkbin:  https://github.com/rockchip-linux/rkbin
- buildroot: https://github.com/rockchip-linux/buildroot

### Firefly AIO-3588

较完整的 BSP，含构建脚本和文档:

```bash
BSP_SOURCE=firefly  BRANCH=main
```

### Radxa Rock 5B

社区活跃，Debian 构建支持:

```bash
BSP_SOURCE=radxa  BRANCH=main
```

### Orange Pi 5

```bash
BSP_SOURCE=orangepi  BRANCH=main
```

### 自定义 Manifest

使用 `repo` 工具拉取自定义 manifest:

```bash
BSP_SOURCE=custom
CUSTOM_MANIFEST_URL=https://your-server/manifests.git
CUSTOM_MANIFEST_NAME=rk3588.xml
```

## 🛠️ 编译流程参考

### 完整编译 Kernel

```bash
make shell

# 1. 选择配置
cd /home/builder/sdk/kernel
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- rockchip_linux_defconfig

# 2. (可选) 自定义配置
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- menuconfig

# 3. 编译
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)

# 4. 编译设备树 (单独)
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- rockchip/rk3588-evb1-v10.dtb

# 产物:
#   arch/arm64/boot/Image        - 内核镜像
#   arch/arm64/boot/dts/rockchip/*.dtb  - 设备树
```

### 完整编译 U-Boot

```bash
make shell

cd /home/builder/sdk/u-boot

# 1. 选择配置 (根据你的参考板)
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- rk3588_defconfig

# 2. 编译
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)

# 产物:
#   u-boot.bin          - U-Boot 二进制
#   rk3588_spl.bin      - SPL
```

### 打包固件 (需 Rockchip 工具)

```bash
# 在容器内, 使用 rkbin 中的工具打包完整固件
# 具体步骤取决于你使用的参考板和存储介质 (eMMC / SD / SPI NAND)
```

## 🔨 适配自定义硬件板

你的硬件与参考板的差异主要在 **Device Tree** 中体现:

```bash
# 1. 找到最接近的参考板设备树
cd /home/builder/sdk/kernel/arch/arm64/boot/dts/rockchip/
ls rk3588-*.dts

# 2. 复制并修改
cp rk3588-evb1-v10.dts rk3588-myboard.dts
vim rk3588-myboard.dts

# 3. 常见需要修改的部分:
#    - PMIC 配置 (电源管理)
#    - 存储介质 (eMMC / SD / SPI NAND)
#    - 显示接口 (HDMI / MIPI DSI / DP)
#    - 网络 PHY
#    - USB 配置
#    - GPIO / LED / 按键
```

## 💡 常用 Makefile 命令

```bash
make help          # 显示所有可用命令
make build         # 构建 Docker 镜像
make shell         # 进入容器 Shell
make fetch         # 拉取 Rockchip 官方 SDK
make fetch-firefly # 拉取 Firefly BSP
make fetch-radxa   # 拉取 Radxa BSP
make build-kernel  # 编译 Kernel
make build-uboot   # 编译 U-Boot
make status        # 查看容器和卷状态
make clean         # 清理所有容器/镜像/卷
```

## ⚠️ 注意事项

1. **网络要求**: 首次拉取源码需要稳定网络，Rockchip kernel 仓库较大 (~2GB)
2. **磁盘空间**: 建议至少预留 **50GB** (源码 + 编译产物 + ccache)
3. **内存**: 编译 Kernel 建议至少 **8GB** 内存，16GB 更佳
4. **闭源固件**: `rkbin` 中的 DDR init / TF-A / GPU / NPU / VPU 固件为闭源预编译，**芯片级通用**，无需修改
5. **浅克隆**: 默认 `DEPTH=1` 加速拉取，如需 `git log / git blame` 请设为 `0`
6. **ccache**: 编译产物通过 Docker 卷持久化，重复编译会自动加速

## 📋 许可证合规 (商用注意)

- **Kernel / U-Boot**: GPL-2.0，分发时**必须提供源码**
- **rkbin 闭源固件**: 需确认 Rockchip 分发条款
- **Mali GPU 驱动**: ARM 闭源，需确认 EULA
- 商用量产建议使用 **Buildroot / Yocto** 从源码构建，便于许可证管理
