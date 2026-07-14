# RK3588 Linux BSP Docker 编译环境

一键搭建 RK3588 Linux 编译环境，自动安装依赖并拉取公开 SDK 源码。  
**支持 x86_64 和 ARM64 宿主机**（Mac M1/M2、ARM 服务器等）。

## 📁 项目结构

```
rk3588-build/
├── Dockerfile              # 多架构 Docker 镜像 (x86_64 + ARM64)
├── docker-compose.yml      # Compose 编排配置
├── Makefile                # 便捷命令 (build/shell/fetch/compile)
├── .env.example            # 环境变量模板
├── scripts/
│   ├── entrypoint.sh       # 容器入口脚本 (架构感知 + 原生编译切换)
│   └── fetch_sources.sh    # SDK 源码拉取脚本 (多 BSP 来源 + 重试)
├── manifests/              # repo manifest 文件
│   ├── rk3588-linux-5.10.xml   # Rockchip 官方 Linux 5.10
│   ├── rk3588-linux-6.1.xml    # Rockchip 官方 Linux 6.1
│   ├── rk3588-linux-6.6.xml    # Rockchip 官方 Linux 6.6
│   ├── rk3588-firefly.xml      # Firefly AIO-3588 BSP
│   ├── rk3588-radxa.xml        # Radxa Rock 5B BSP
│   ├── rk3588-orangepi.xml     # OrangePi 5 BSP
│   └── default.xml             # 默认 (指向 5.10)
├── configs/                # 自定义编译配置 (defconfig 等)
└── patches/                # 本地补丁目录
```

## ⚙️ 宿主机前置环境配置

本项目基于 Docker 与 `make` 工具。在开始前，请确保宿主机已安装以下环境：

### 1. 安装 Docker
* **Windows / macOS**: 下载并安装 [Docker Desktop](https://www.docker.com/products/docker-desktop/)。确保 Docker 守护进程已启动。
* **Linux**: 安装 Docker Engine 与 Docker Compose Plugin：
  ```bash
  sudo apt update && sudo apt install -y docker.io docker-compose-v2
  ```

### 2. 安装 Make 工具
`Makefile` 提供了便捷的包装命令。如果宿主机未安装 `make`，可以选择安装它，或直接使用 **Docker 替代命令**：

#### 🛠️ 各平台安装 `make` 指引：
* **Windows (PowerShell / CMD)**:
  使用 Windows 包管理器（推荐）：
  ```powershell
  # 方式一：使用 winget (Windows 10/11 内置)
  winget install GnuWin32.Make
  # 安装后需重新打开终端以使环境变量生效
  
  # 方式二：使用 Scoop
  scoop install make
  
  # 方式三：使用 Chocolatey
  choco install make
  ```
  *(注：也可以在 Git Bash 或 WSL 内直接运行项目。)*

* **macOS**:
  安装 Xcode Command Line Tools：
  ```bash
  xcode-select --install
  ```
  或者使用 Homebrew 安装：
  ```bash
  brew install make
  ```

* **Linux**:
  ```bash
  # Ubuntu / Debian
  sudo apt update && sudo apt install -y make
  
  # CentOS / RedHat
  sudo yum install -y make
  ```

#### 💡 无 Make 环境下的 Docker 替代命令：
如果您不想安装 `make`，可以直接运行对应的 Docker 命令：

| Makefile 命令 | 对应 Docker 替代命令 |
| :--- | :--- |
| `make build` | `docker compose build` |
| `make fetch` | `docker compose run --rm -it rk3588-build /bin/bash -c "/home/builder/fetch_sources.sh"` |
| `make update` | `docker compose run --rm -it rk3588-build /bin/bash -c "/home/builder/fetch_sources.sh update"` |
| `make shell` | `docker compose run --rm rk3588-build /bin/bash` |
| `make build-kernel` | `docker compose run --rm rk3588-build /bin/bash -c "cd /home/builder/sdk/kernel && make rockchip_linux_defconfig && make -j\\$(nproc)"` |
| `make build-uboot` | `docker compose run --rm rk3588-build /bin/bash -c "cd /home/builder/sdk/u-boot && make rk3588_defconfig && make -j\\$(nproc)"` |
| `make build-all` | `docker compose run --rm rk3588-build /bin/bash -c "cd /home/builder/sdk/u-boot && make rk3588_defconfig && make -j\\$(nproc) && cd ../kernel && make rockchip_linux_defconfig && make -j\\$(nproc)"` |
| `make pack` | `docker compose run --rm rk3588-build /bin/bash -c "cd /home/builder/sdk && mkdir -p output && cp kernel/arch/arm64/boot/Image output/ && cp kernel/arch/arm64/boot/dts/rockchip/rk3588*.dtb output/ 2>/dev/null && cp u-boot/u-boot.bin output/"` |

---

## 🚀 快速开始

### 1. 构建 Docker 镜像

```bash
cd rk3588-build

# 自动检测宿主机架构
make build

# 或显式指定
docker compose build
```

### 2. 拉取 SDK 源码

```bash
# 交互式选择 SDK 版本 (推荐)
make fetch

# Rockchip 官方 SDK
make fetch-510      # Linux 5.10 LTS (推荐)
make fetch-61       # Linux 6.1 LTS
make fetch-66       # Linux 6.6

# 第三方 BSP
make fetch-firefly  # Firefly AIO-3588
make fetch-radxa    # Radxa Rock 5B
make fetch-orangepi # OrangePi 5
```

### 3. 更新 SDK 源码

如果您已经拉取过源码，想要更新至最新状态，可以随时使用 `make update`。该命令是非交互式的，它会自动读取当前关联的 Manifest 清单并安全同步：

```bash
# 一键同步并更新已有的 SDK 仓库
make update
```

### 4. 进入编译环境

```bash
make shell
# 进入容器后可看到:
#   /home/builder/sdk/kernel    - Linux 内核源码
#   /home/builder/sdk/u-boot    - U-Boot 源码
#   /home/builder/sdk/rkbin     - Rockchip 闭源固件 (DDR init, TF-A)
```

### 5. 编译

```bash
# 使用 Makefile 一键编译
make build-kernel   # 单独编译内核
make build-uboot    # 单独编译 U-Boot
make build-all      # 一键编译所有组件

# 打包固件
make pack

# 或在容器内手动编译
make shell
> cd /home/builder/sdk/kernel
> make rockchip_linux_defconfig
> make -j$(nproc)
```

## 🖥️ 多架构支持

Docker 镜像同时支持 **x86_64** 和 **ARM64** 宿主机：

| 宿主机架构 | 状态 | 说明 |
|-----------|------|------|
| **x86_64** (Intel/AMD) | ✅ 完全支持 | i386 兼容库已启用，Rockchip 32 位工具可运行 |
| **ARM64** (Mac M1/M2/M3, ARM 服务器) | ✅ 完全支持 | 跳过 i386 包，可选原生 GCC 加速编译 |

### ARM64 宿主机使用

```bash
# 方式一: 自动检测 (推荐)
docker compose build

# 方式二: 显式指定平台
DOCKER_PLATFORM=linux/arm64 docker compose build

# 方式三: ARM64 宿主机启用原生编译加速
USE_NATIVE_BUILD=yes make shell
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
| `MANIFEST` | (空) | 指定 manifest 文件名, 留空则交互选择 |
| `FETCH_ON_START` | `no` | 容器启动时自动拉取源码 |
| `JOBS` | `0` | 编译并行数 (0=自动检测) |
| `DEPTH` | `1` | Git 浅克隆深度 (0=完整克隆) |
| `EXTRA_COMPONENTS` | `no` | 拉取额外组件 (device-tree 等) |
| `CCACHE_MAXSIZE` | `10G` | ccache 最大缓存 |
| `DOCKER_PLATFORM` | (空) | Docker 运行平台: `linux/amd64` 或 `linux/arm64`, 空=自动 |
| `USE_NATIVE_BUILD` | `no` | ARM64 宿主机使用原生 GCC 加速 (仅 ARM64 有效) |
| `DOCKER_CPUS` | (空) | Docker CPU 限制, 空=不限制 |
| `DOCKER_MEMORY` | (空) | Docker 内存限制, 空=不限制 |
| `MAX_RETRIES` | `3` | repo sync 失败时最大重试次数 |

## 📦 支持的 BSP 来源

### Rockchip 官方 (推荐)

最通用的选择，包含 RK3588 官方驱动支持:

```bash
make fetch-510   # Linux 5.10 (Rockchip LTS, 推荐)
make fetch-61    # Linux 6.1
make fetch-66    # Linux 6.6
```

组件来源:
- kernel: https://github.com/rockchip-linux/kernel
- u-boot: https://github.com/rockchip-linux/u-boot
- rkbin:  https://github.com/rockchip-linux/rkbin
- buildroot: https://github.com/rockchip-linux/buildroot

### Firefly AIO-3588

较完整的 BSP，含构建脚本和文档:

```bash
make fetch-firefly
```

### Radxa Rock 5B

社区活跃，Debian 构建支持:

```bash
make fetch-radxa
```

### Orange Pi 5

```bash
make fetch-orangepi
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
#   arch/arm64/boot/Image                    - 内核镜像
#   arch/arm64/boot/dts/rockchip/*.dtb       - 设备树
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
#   u-boot.bin       - U-Boot 二进制
#   rk3588_spl.bin   - SPL
```

### 打包固件

```bash
# 使用 Makefile 一键打包 (会检查编译产物是否存在)
make pack

# 产物会复制到 /home/builder/sdk/output/ 目录:
#   Image            - 内核镜像
#   rk3588*.dtb      - 设备树
#   u-boot.bin       - U-Boot 二进制
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

## 🔒 闭源固件说明

RK3588 SDK 包含部分闭源内容，**不影响构建，不影响多架构支持**：

| 闭源内容 | 性质 | 影响构建？ | 说明 |
|---------|------|-----------|------|
| DDR init / TF-A (rkbin) | ARM64 二进制**文件** | ❌ 不影响 | 仅打包进固件，不在宿主机执行 |
| Mali GPU 驱动 (.so) | ARM64 二进制**文件** | ❌ 不影响 | 目标侧运行，与宿主机无关 |
| NPU 驱动 (.ko) | ARM64 二进制**文件** | ❌ 不影响 | 目标侧运行 |
| VPU 固件 | ARM64 二进制**文件** | ❌ 不影响 | 目标侧运行 |
| `upgrade_tool` (烧写) | x86_64 **可执行程序** | ❌ 不影响 | 仅烧写环节使用，不影响编译 |

### ARM64 宿主机烧写方案

`upgrade_tool` 是 x86_64 程序，在 ARM64 宿主机上无法直接运行，但烧写有替代方案：

| 方案 | 架构限制 | 说明 |
|------|---------|------|
| **SD 卡烧写** | 无限制 ✅ | `dd if=firmware.img of=/dev/sdX` 直接写入 |
| **fastboot** | 无限制 ✅ | U-Boot 进入 fastboot 模式，主机用开源 `fastboot` 命令刷写 |
| **TFTP/NFS** | 无限制 ✅ | U-Boot 通过网络加载固件，不依赖主机侧工具 |
| **QEMU 模拟** | 无限制 ✅ | 在 ARM64 上用 QEMU 运行 x86_64 的 `upgrade_tool` |

> 💡 大多数开发者用 **SD 卡** 或 **fastboot** 烧写，不需要 `upgrade_tool`。

## 💡 常用 Makefile 命令

```bash
make help            # 显示所有可用命令 (分类展示)

# 镜像管理
make build           # 构建 Docker 镜像
make build-nocache   # 构建 Docker 镜像 (无缓存)

# SDK 拉取
make fetch           # 交互式选择 SDK 版本
make update          # 一键更新当前已拉取的 SDK 仓库
make fetch-510       # Rockchip Linux 5.10
make fetch-61        # Rockchip Linux 6.1
make fetch-66        # Rockchip Linux 6.6
make fetch-firefly   # Firefly AIO-3588
make fetch-radxa     # Radxa Rock 5B
make fetch-orangepi  # OrangePi 5

# 编译
make build-kernel    # 编译 Kernel
make build-uboot     # 编译 U-Boot
make build-all       # 一键编译所有
make pack            # 打包固件

# 容器管理
make shell           # 进入容器 Shell
make status          # 查看容器和卷状态
make clean           # 清理所有容器/镜像/卷
```

## ⚠️ 注意事项

1. **网络要求**: 首次拉取源码需要稳定网络，Rockchip kernel 仓库较大 (~2GB)。拉取失败会自动重试最多 3 次
2. **磁盘空间**: 建议至少预留 **50GB** (源码 + 编译产物 + ccache)。拉取前会自动检查磁盘空间
3. **内存**: 编译 Kernel 建议至少 **8GB** 内存，16GB 更佳
4. **闭源固件**: `rkbin` 中的 DDR init / TF-A / GPU / NPU / VPU 固件为闭源预编译，**芯片级通用**，无需修改
5. **浅克隆**: 默认 `DEPTH=1` 加速拉取，如需 `git log / git blame` 请设为 `0`
6. **ccache**: 编译产物通过 Docker 卷持久化，重复编译会自动加速
7. **多架构**: Dockerfile 根据宿主机架构自动选择依赖，无需手动干预
8. **原生编译**: ARM64 宿主机可设置 `USE_NATIVE_BUILD=yes` 使用原生 GCC 加速编译

## 📋 许可证合规 (商用注意)

- **Kernel / U-Boot**: GPL-2.0，分发时**必须提供对应源码**
- **rkbin 闭源固件**: 需确认 Rockchip 分发条款
- **Mali GPU 驱动**: ARM 闭源，需确认 ARM EULA
- 商用量产建议使用 **Buildroot / Yocto** 从源码构建，便于许可证管理
