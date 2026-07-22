# 新增板型

新增一块开发板只需要创建一个板级配置文件（以及可选的构建钩子文件），不需要修改任何构建脚本或 Makefile。

## 步骤

### 1. 使用脚手架生成板型配置

使用 `make new-board` 命令自动生成配置模版：

```bash
make new-board BOARD=my-board
```

这会在 `configs/boards/` 下从 `TEMPLATE.conf` 创建 `my-board.conf`。

### 2. 编辑配置字段

打开 `configs/boards/my-board.conf`，按注释提示填入具体参数：

```bash
# 板子描述（显示在 make list-boards / make use-board 列表中）
BOARD_DESCRIPTION="My Board (RK3588)"

# 内核
KERNEL_DEFCONFIG="rockchip_linux_defconfig"    # BSP 内核 defconfig 文件名
KERNEL_DTB="my-board.dtb"                      # 设备树二进制文件名

# U-Boot
UBOOT_DEFCONFIG="rk3588_defconfig"             # U-Boot defconfig
UBOOT_BOARD="rk3588"                           # Rockchip make.sh 的板名参数
UBOOT_BUILD_SYSTEM="rockchip-make-sh"          # 启动链构建系统
UBOOT_PYTHON="python3"                         # python2 或 python3

# 引导布局
BOOTLOADER_LAYOUT="rockchip-gpt-idblock-extlinux-v1"
DOWNLOAD_LOADER_GLOBS="rk3588*loader*.bin;MiniLoaderAll.bin"
UBOOT_IMAGE_NAMES="uboot.img;u-boot.img"
IDBLOCK_SECTOR=64
UBOOT_SECTOR=16384

# 串口
CONSOLE="ttyFIQ0,1500000n8"
EXTRA_KERNEL_ARGS="earlycon=uart8250,mmio32,0xfeb50000 consoleblank=0"

# 磁盘尺寸
IMAGE_SIZE_MIB=4096      # 总镜像大小
BOOT_START_MIB=16        # boot 分区起始（必须 >= 16）
BOOT_SIZE_MIB=256        # boot 分区大小
ROOTFS_SIZE_MIB=2048     # rootfs 初始大小（首次启动会自动扩容）
```

### 3. 校验配置

使用 `make validate-board` 命令验证配置格式：

```bash
make validate-board BOARD=my-board
```

### 4. 可选：添加源码 Manifest

在 `manifests/` 目录创建 `my-board.xml`，并在 `my-board.conf` 中填入 `SOURCE_MANIFEST="my-board.xml"`。

拉取代码时使用：

```bash
make fetch BOARD=my-board
```

### 5. 可选：配置构建钩子（Hooks）

如果需要为该板型添加特殊的预处理或后处理逻辑，在 `configs/boards/` 下创建 `my-board.hooks.sh`：

```bash
pre_build_kernel()  { log_info "执行内核构建前钩子"; }
post_build_kernel() { log_info "执行内核构建后钩子"; }
pre_build_uboot()   { log_info "执行 U-Boot 构建前钩子"; }
post_build_uboot()  { log_info "执行 U-Boot 构建后钩子"; }
pre_build_rootfs()  { log_info "执行 rootfs 构建前钩子"; }
post_build_rootfs() { log_info "执行 rootfs 构建后钩子"; }
pre_make_image()    { log_info "执行镜像组装前钩子"; }
post_make_image()   { log_info "执行镜像组装后钩子"; }
```

### 6. 开始构建

```bash
make build-all BOARD=my-board ROOTFS=debian
```

## 字段参考

| 字段 | 必填 | 说明 |
|---|---|---|
| `BOARD_DESCRIPTION` | 是 | 板子描述文字 |
| `KERNEL_DEFCONFIG` | 是 | 内核 defconfig 文件名 |
| `KERNEL_DTB` | 是 | DTB 文件名，必须以 `.dtb` 结尾 |
| `UBOOT_DEFCONFIG` | 是 | U-Boot defconfig 文件名 |
| `UBOOT_BOARD` | 是 | Rockchip `make.sh` 的板名参数 |
| `UBOOT_BUILD_SYSTEM` | 否 | 引导程序构建方式（默认 `rockchip-make-sh`） |
| `UBOOT_PYTHON` | 否 | FIT 生成器 Python 版本（默认 `python3`） |
| `BOOTLOADER_LAYOUT` | 否 | 启动链布局格式（默认 `rockchip-gpt-idblock-extlinux-v1`） |
| `DOWNLOAD_LOADER_GLOBS` | 否 | loader 文件匹配模式（默认 `rk3588*loader*.bin;MiniLoaderAll.bin`） |
| `UBOOT_IMAGE_NAMES` | 否 | U-Boot 镜像匹配模式（默认 `uboot.img;u-boot.img`） |
| `CONSOLE` | 是 | 串口设备和波特率 |
| `EXTRA_KERNEL_ARGS` | 否 | 额外内核命令行参数 |
| `IMAGE_SIZE_MIB` | 否 | 总镜像大小（MiB，默认 `4096`） |
| `BOOT_START_MIB` | 否 | boot 分区起始（MiB，默认 `16`） |
| `BOOT_SIZE_MIB` | 否 | boot 分区大小（MiB，默认 `256`） |
| `ROOTFS_SIZE_MIB` | 否 | rootfs 初始大小（MiB，默认 `2048`） |
| `IDBLOCK_SECTOR` | 否 | IDBlock 扇区号（默认 `64`） |
| `UBOOT_SECTOR` | 否 | U-Boot 扇区号（默认 `16384`） |
| `SOURCE_MANIFEST` | 否 | 对应的 manifest 文件名 |
| `EXPECTED_*_REVISION` | 否 | 锁定源码 commit（需配合 SOURCE_MANIFEST） |
| `DEBIAN_PACKAGES_DEFAULT` | 否 | Debian 默认额外 APT 包名 |
| `ROOTFS_HOSTNAME_DEFAULT` | 否 | 默认主机名 |
| `DTB_STRIP_BOOTARGS` | 否 | 是否剥离 DTB 中的 /chosen/bootargs（默认 `yes`） |
| `WIFIBT_FIRMWARE_SYMLINKS` | 否 | WiFi 固件软链接策略（`rockchip-vendor` 或 `none`） |
