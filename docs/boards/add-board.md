# 新增板型

新增一块 RK3588/RK3588S 开发板只需要创建一个板级 profile 文件，不需要修改任何脚本。

## 步骤

### 1. 确定 SDK 来源

确认你的板子用哪个 SDK：

- 如果是 Rockchip 官方 BSP → `make fetch-510` / `fetch-61` / `fetch-66`
- 如果是厂商 fork → 用对应的 `fetch-*` 或 `fetch-custom`
- 如果是私有 SDK → `make import-local-sdk`

### 2. 创建板级 profile

复制最接近的现有 profile：

```bash
cp configs/boards/rk3588-evb1-lp4-v10-linux.conf \
   configs/boards/my-board.conf
```

### 3. 编辑字段

打开 `configs/boards/my-board.conf`，逐项修改：

```bash
# 板子描述（显示在 make use-board 列表中）
BOARD_DESCRIPTION="My Board (RK3588)"

# 内核
KERNEL_DEFCONFIG="rockchip_linux_defconfig"    # BSP 内核 defconfig 文件名
KERNEL_DTB="my-board.dtb"                      # 设备树二进制文件名

# U-Boot
UBOOT_DEFCONFIG="rk3588_defconfig"             # U-Boot defconfig
UBOOT_BOARD="rk3588"                           # Rockchip make.sh 的板名参数
UBOOT_BUILD_SYSTEM="rockchip-make-sh"          # 固定值
UBOOT_PYTHON="python3"                         # python2 或 python3

# 引导布局（固定值）
BOOTLOADER_LAYOUT="rockchip-gpt-idblock-extlinux-v1"
DOWNLOAD_LOADER_GLOBS="rk3588*loader*.bin;MiniLoaderAll.bin"
UBOOT_IMAGE_NAMES="uboot.img;u-boot.img"
IDBLOCK_SECTOR=64
UBOOT_SECTOR=16384

# 串口
CONSOLE="ttyFIQ0,1500000n8"
EXTRA_KERNEL_ARGS="earlycon=uart8250,mmio32,0xfeb50000 consoleblank=0"

# 磁盘几何
IMAGE_SIZE_MIB=4096      # 总镜像大小
BOOT_START_MIB=16        # boot 分区起始（必须 >= 16）
BOOT_SIZE_MIB=256        # boot 分区大小
ROOTFS_SIZE_MIB=2048     # rootfs 初始大小（首次启动会扩容）
```

### 4. 确认 DTB 文件名

DTB 文件名必须与内核源码中的 `.dts` 文件对应：

```bash
# 在 SDK kernel 目录中查找
ls sdk/kernel/arch/arm64/boot/dts/rockchip/my-board*.dts
```

`KERNEL_DTB` 填 `.dtb` 文件名（不含路径）。

### 5. 确认 U-Boot defconfig

```bash
ls sdk/u-boot/configs/ | grep my-board
```

如果板子没有专用 defconfig，用通用的 `rk3588_defconfig`。

### 6. 可选：锁定源码版本

如果需要可复现构建，在 profile 中添加：

```bash
SOURCE_MANIFEST="my-board.xml"
EXPECTED_KERNEL_REVISION="完整的40位commit SHA"
EXPECTED_UBOOT_REVISION="..."
EXPECTED_RKBIN_REVISION="..."
EXPECTED_BUILDROOT_REVISION="..."
```

同时在 `manifests/` 里创建对应的 manifest XML，revision 也用完整 SHA。

### 7. 可选：Debian 默认值

```bash
DEBIAN_FEATURES_DEFAULT="nm,hwdebug,firstboot-info"
ROOTFS_HOSTNAME_DEFAULT="myboard"
```

### 8. 验证

```bash
# 项目自检（会校验新 profile 的格式）
make check

# 构建
make build-all BOARD=my-board SDK_VOLUME=my-sdk ROOTFS=debian
```

## 字段参考

| 字段 | 必填 | 说明 |
|---|---|---|
| `BOARD_DESCRIPTION` | 是 | 板子描述文字 |
| `KERNEL_DEFCONFIG` | 是 | 内核 defconfig 文件名 |
| `KERNEL_DTB` | 是 | DTB 文件名，必须以 `.dtb` 结尾 |
| `UBOOT_DEFCONFIG` | 是 | U-Boot defconfig 文件名 |
| `UBOOT_BOARD` | 是 | Rockchip `make.sh` 的板名参数 |
| `UBOOT_BUILD_SYSTEM` | 是 | 当前只支持 `rockchip-make-sh` |
| `UBOOT_PYTHON` | 是 | `python2` 或 `python3` |
| `BOOTLOADER_LAYOUT` | 是 | 当前只支持 `rockchip-gpt-idblock-extlinux-v1` |
| `DOWNLOAD_LOADER_GLOBS` | 是 | loader 文件匹配模式，分号分隔 |
| `UBOOT_IMAGE_NAMES` | 是 | U-Boot 镜像匹配模式，分号分隔 |
| `CONSOLE` | 是 | 串口设备和波特率 |
| `EXTRA_KERNEL_ARGS` | 否 | 额外内核命令行参数 |
| `IMAGE_SIZE_MIB` | 是 | 总镜像大小（MiB） |
| `BOOT_START_MIB` | 是 | boot 分区起始（>= 16） |
| `BOOT_SIZE_MIB` | 是 | boot 分区大小 |
| `ROOTFS_SIZE_MIB` | 是 | rootfs 初始大小 |
| `IDBLOCK_SECTOR` | 是 | IDBlock 扇区号（>= 34） |
| `UBOOT_SECTOR` | 是 | U-Boot 扇区号 |
| `SOURCE_MANIFEST` | 否 | 对应的 manifest 文件名 |
| `EXPECTED_*_REVISION` | 否 | 锁定源码 commit（需配合 SOURCE_MANIFEST） |
| `DEBIAN_FEATURES_DEFAULT` | 否 | Debian 默认功能集 |
| `ROOTFS_HOSTNAME_DEFAULT` | 否 | 默认主机名 |
