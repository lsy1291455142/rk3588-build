# 新增板型

本构建系统的核心设计：新增板型**不需要修改任何脚本或 Makefile**，只需在 `boards/` 下新增一个目录与配置文件，必要时加板级 overlay/plugin 与自检钩子。

## 步骤

### 1. 脚手架

```bash
make new-board BOARD=my-board
```

该命令从 `boards/TEMPLATE/` 复制 `board.conf`，并生成空的板级内核 fragment 模板 `boards/my-board/kernel.config`（含头注释，说明它由 `build_kernel.sh` 在共享 fragment 之后自动合并，可覆盖共享配置）。随后用 `make validate-board BOARD=my-board` 校验。

### 2. 编辑字段

打开 `boards/my-board/board.conf`，按注释填写。必填与常用字段见下方「字段参考」。关键是 `KERNEL_DEFCONFIG`/`KERNEL_DTB`/`UBOOT_DEFCONFIG`/`UBOOT_BOARD`/`CONSOLE` 必须设置；`KERNEL_DTB` 须以 `.dtb` 结尾。

### 3. 校验

```bash
make validate-board BOARD=my-board
```

内部调用 `load_board_profile` → `validate_board_profile`，校验必填字段、几何约束、枚举值（`ROOTFS_MODE`、`UBOOT_PYTHON`、`BOOTLOADER_LAYOUT`）、`KERNEL_DTB` 后缀，以及（当 `SOURCE_MANIFEST` 设置时）四个 `EXPECTED_*_REVISION` 为 40 位 SHA。

### 4. 添加 SDK manifest（如需要）

若板子从上游拉取 SDK，在 `manifests/` 下创建对应 `.xml`，并在 `board.conf` 设 `SOURCE_MANIFEST`。若用本地已下载 SDK，则留空 `SOURCE_MANIFEST`，改用 `make import-local-sdk`。

### 5. 构建钩子（可选）

如需在构建各阶段插入板级逻辑，创建 `boards/my-board/board.hooks.sh`，定义任一钩子函数（均可选）：`pre_build_kernel` / `post_build_kernel`、`pre_build_uboot` / `post_build_uboot`、`pre_build_rootfs` / `post_build_rootfs`、`pre_make_image` / `post_make_image`、`pre_fetch_sources` / `post_fetch_sources`。钩子由 `common.sh` 的 `run_hook` 在对应阶段前后调用（函数不存在则静默跳过）。

### 6. 板级 rootfs 附件（可选）

在 `boards/my-board/rootfs/` 下放 `plugin.sh`（定义 `board_plugin_apply`）或 `overlay/` 静态树，构建 Debian rootfs 时**先于**可选 overlay 应用且始终生效。详见 `boards/README.md` 与 [Debian 软件包与可选 Overlay](/usage/debian-features)。

### 7. 构建

```bash
make build-all BOARD=my-board ROOTFS=debian DEBIAN_RELEASE=13
```

## 字段参考

以下字段以 `boards/TEMPLATE/board.conf` 为权威来源。带 `[REQUIRED]` 为 `validate_board_profile` 强制；其余有默认值。

**必填（REQUIRED）**

- `BOARD_DESCRIPTION` — 可读描述。
- `KERNEL_DEFCONFIG` — `arch/arm64/configs/` 下 defconfig 名。
- `KERNEL_DTB` — 设备树名，须以 `.dtb` 结尾。
- `UBOOT_DEFCONFIG` — U-Boot defconfig 名。
- `UBOOT_BOARD` — U-Boot 构建系统使用的板级标识符。
- `CONSOLE` — 串口规格，格式 `<device>,<baud><parity><bits>`（如 `ttyFIQ0,1500000n8`）。

**标识与来源**

- `SOC` — 选 `configs/soc/<SOC>.conf` 加载平台特性（如 `rk3588`）。
- `SOURCE_MANIFEST` — `manifests/` 下 manifest 文件名；设置后要求四个 `EXPECTED_*_REVISION`。
- `EXPECTED_KERNEL_REVISION` / `EXPECTED_UBOOT_REVISION` / `EXPECTED_RKBIN_REVISION` / `EXPECTED_BUILDROOT_REVISION` — 40 位 SHA（设置 `SOURCE_MANIFEST` 时必填）。

**内核**

- `KERNEL_DTBO` — 空格分隔的 `.dtbo` 列表，经 extlinux `FDTOVERLAYS` 加载。
- `KERNEL_EXTRA_FRAGMENTS` — 额外共享 fragment（相对 `configs/`，空格分隔）。
- `DTB_STRIP_BOOTARGS` — 默认 `yes`；打包前从 DTB 删除 `/chosen/bootargs`，使 extlinux `APPEND` 权威。

**U-Boot / 启动链**

- `UBOOT_BUILD_SYSTEM` — 默认 `rockchip-make-sh`。
- `UBOOT_PYTHON` — 默认 `python3`（FIT 生成器需要 pyelftools）；CokePi 用 `python2`。
- `BOOTLOADER_LAYOUT` — 默认 `rockchip-gpt-idblock-extlinux-v1`（唯一支持值；旧 `rockchip-gpt-extlinux-v1` 会被归并为此值）。
- `DOWNLOAD_LOADER_GLOBS` — 默认 `rk3588*loader*.bin;MiniLoaderAll.bin`。
- `UBOOT_IMAGE_NAMES` — 默认 `uboot.img;u-boot.img`。
- `IDBLOCK_SECTOR` — 默认 `64`；须 `>= 34` 且不覆盖主 GPT，且 `< UBOOT_SECTOR`。
- `UBOOT_SECTOR` — 默认 `16384`；须在 boot 分区之前。

**控制台 / 磁盘几何**

- `EXTRA_KERNEL_ARGS` — 追加到 extlinux `APPEND` 的额外内核参数。
- `IMAGE_SIZE_MIB` — 默认 `2048`。
- `BOOT_START_MIB` — 默认 `16`（须 `>= 16`）。
- `BOOT_SIZE_MIB` — 默认 `256`（FAT32）。
- `ROOTFS_SIZE_MIB` — 默认 `1700`（rw-ext4 根分区初始大小；不超过剩余容量）。
- `ROOTFS_MODE_DEFAULT` — 默认无（回退 `rw-ext4`）；可设 `ro-overlay`。
- `DATA_SIZE_MIB_DEFAULT` — 默认无（回退 `0`，即占满剩余）；`ro-overlay` 数据分区大小。

**输出 / 标签**

- `OUTPUT_IMAGE_PREFIX` — 默认用 `BOARD`。
- `EXTLINUX_LABEL` — 默认用 `BOARD`。
- `ROOTFS_HOSTNAME_DEFAULT` — 默认回退 `BOARD`。

**Debian 默认**

- `ROOTFS_HOSTNAME_DEFAULT` — 见上。
- `DEBIAN_PACKAGES_DEFAULT` — 真实 apt 包名，逗号/空格分隔（无功能别名）。
- `DEBIAN_OVERLAYS_DEFAULT` — 默认 `base,console,firstboot,firstboot-info,network`；`none` 关闭、`all` 全开。

## 几何约束（validate_board_profile 强制）

- `BOOT_START_MIB >= 16`
- `IDBLOCK_SECTOR >= 34` 且 `IDBLOCK_SECTOR < UBOOT_SECTOR`
- `UBOOT_SECTOR < boot 分区起始扇区`（`BOOT_START_MIB * 2048`）
- 剩余根容量 `> 0` 且 `ROOTFS_SIZE_MIB <= 剩余容量`

任何违反都会在校验时 `die` 并给出具体字段。
