# 新增板型

目标：为新硬件增加一份可重复构建的 `configs/boards/<name>.conf`，并确认 SDK、DTB、U-Boot 与镜像布局匹配。

## 前置条件

1. 已有对应 SDK（`fetch-*` / `fetch-custom` / `import-local-sdk`）
2. SDK 根目录含 `kernel/`、`u-boot/`、`rkbin/`、`buildroot/`
3. 知道板级 DTB 文件名、U-Boot defconfig / board 名、串口

本仓库**不会**自动从硬件探测出这些字段。

## 步骤

### 1. 复制最近似 profile

```bash
cp configs/boards/rk3588s-rock-5c.conf configs/boards/rk3588-myboard.conf
```

`BOARD` 就是文件名去掉 `.conf`：`rk3588-myboard`。

### 2. 改必填字段

| 字段 | 说明 |
|---|---|
| `BOARD_DESCRIPTION` | 给人看的板名 |
| `KERNEL_DEFCONFIG` | BSP 内核 defconfig |
| `KERNEL_DTB` | **唯一**打进镜像的 DTB 文件名 |
| `UBOOT_DEFCONFIG` / `UBOOT_BOARD` | U-Boot 配置与 `make.sh` 板名 |
| `UBOOT_PYTHON` | `python2` 或 `python3`（必填，无默认） |
| `CONSOLE` | 写入 extlinux，如 `ttyFIQ0,1500000n8` |
| `EXTRA_KERNEL_ARGS` | 附加内核参数（earlycon 等） |

多数 Rockchip 板可保留：

```bash
UBOOT_BUILD_SYSTEM="rockchip-make-sh"
BOOTLOADER_LAYOUT="rockchip-gpt-idblock-extlinux-v1"
IDBLOCK_SECTOR=64
UBOOT_SECTOR=16384
IMAGE_SIZE_MIB=4096
BOOT_START_MIB=16
BOOT_SIZE_MIB=256
ROOTFS_SIZE_MIB=2048
```

### 3. 可选锁定与默认

- `SOURCE_MANIFEST` + `EXPECTED_KERNEL_REVISION` 等：公开可复现 SDK 时用（见 ROCK 5C）
- `DEBIAN_FEATURES_DEFAULT` / `ROOTFS_HOSTNAME_DEFAULT`：Debian bring-up 默认（见 MUSE）
- `DOWNLOAD_LOADER_GLOBS` / `UBOOT_IMAGE_NAMES`：BSP 产物名不标准时改匹配规则

### 4. 确认布局不打架

loader / U-Boot 必须落在 `BOOT_START_MIB`（默认 16 MiB）之前。脚本会检查 idblock、uboot 体积是否越界。不要随意把 FAT 起点挪到 sector 16384 之前而不改 `UBOOT_SECTOR`。

### 5. 构建与离线校验

```bash
make build-all \
  BOARD=rk3588-myboard \
  SDK_VOLUME=<your-volume> \
  ROOTFS=debian \
  DEBIAN_RELEASE=13
make verify-image BOARD=rk3588-myboard SDK_VOLUME=<your-volume> ROOTFS=debian
```

`image` 末尾会自动 `verify-image`。失败先修镜像结构，再上板。

### 6. 真机串口验收

按顺序看：

1. sector 64 的 IDBlock 是否打印 / DRAM 是否初始化
2. U-Boot 是否起来，能否读到 FAT 与 `extlinux`
3. 内核是否找到 `PARTLABEL=rootfs`
4. 串口能否登录

错 DTB 常见表现：卡在内核早期、无串口、存储/PMIC 异常。离线校验**不能**证明这些。

## 不要做的事

- 不要把板级差异堆进共享 `configs/kernel/rootfs-base.config`
- 不要依赖厂商 DTB 里的 `/chosen/bootargs`（打包会删掉）
- 不要把 `idblock.img`（`RKNS`）和 `download-loader.bin`（`LDR `）混用
- 不要为“方便”加默认 `BOARD`；错板比失败更糟

## 补丁与临时试验

`patches/` 可挂进容器，但**不会自动应用**。长期差异优先：

1. 锁定 SDK commit / 自有 fork
2. 写清 board profile
3. 必要时再维护可复现补丁

详见 [磁盘与启动契约](/how-it-works/boot-contract) 与 [构建流水线](/how-it-works/pipeline)。
