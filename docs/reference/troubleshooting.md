# 排错

本页按症状归类常见问题，给出原因与修复步骤。所有命令均在仓库根目录执行，且前提是已运行过 `make build`。

## Docker 相关

**`docker compose config` 报告 "refers to undefined volume"**：`SDK_VOLUME` 在 `docker-compose.yml` 中声明为 `external: true`，运行期由 `make fetch`/`make import-local-sdk` 创建。这是预期提示，只要错误列表中不含 `error`/`invalid`/`syntax` 即为正常（`check.sh` 的 `check_compose` 即据此判定）。先 `make fetch` 或 `make import-local-sdk` 再继续。

**x86_64 宿主构建 Debian rootfs 报架构错误**：Debian rootfs 必须在 `linux/arm64` 容器中以原生方式构建。`make _debian-rootfs` 会先 `debian-preflight` 探测架构。若未自动注册 binfmt，手动 `make register-arm64-binfmt`（x86_64 宿主）。ARM64 宿主（如 Apple Silicon）原生运行，无需注册。

**`RK3588 Builder` 容器挂载失败 / 权限问题**：SDK 卷需可被 builder 用户（uid 1000）写入。`make verify-sdk-volume` 会检查四组件目录与可写性。本地导入 SDK 请用 `make import-local-sdk`，它会创建 bind 卷并保持源码原位。

## SDK 拉取

**`make fetch` 报 "Board does not define SOURCE_MANIFEST"**：该板型（如 CokePi 系列）期望本地 SDK 导入。改用 `make import-local-sdk SDK_PATH=/abs SDK_VOLUME=<v>`，或 `make fetch-custom MANIFEST=<file.xml>`。

**`repo sync` 多次重试失败**：网络不稳或 manifest 远程不可达。`fetch_sources.sh` 默认重试 3 次（`MAX_RETRIES`）。检查 `MANIFEST`/`CUSTOM_MANIFEST_URL` 与网络；确认 `MIN_DISK_GB`（默认 10GB）余量充足。

**更新后 "invalid upstream" / rebase 历史不一致**：`make update` 在重新 init 前会清理 `.repo/manifests` 与 `.repo/manifests.git`，避免该问题。若仍出现，删除 `.repo` 后重新 `make fetch`。

## 编译错误

**内核 "configuration did not retain CONFIG_..."**：`build_kernel.sh` 在合并 fragment 后强制校验一批必需内核选项（`CONFIG_OVERLAY_FS`、`CONFIG_SQUASHFS`、`CONFIG_VIRTIO_*` 等）。通常因板级 `kernel.config` 或 `KERNEL_EXTRA_FRAGMENTS` 覆盖了共享 fragment。检查板级 fragment 是否意外 unset 了这些选项。

**`/chosen/bootargs` 仍存在于打包 DTB**：`DTB_STRIP_BOOTARGS=yes`（默认）会从编译出的 DTB 删除 `/chosen/bootargs`，确保 extlinux 的 `APPEND` 权威。若板子需要保留，设 `DTB_STRIP_BOOTARGS=no`。

**U-Boot "extlinux contract requires CONFIG_DISTRO_DEFAULTS=y" 等**：`build_uboot.sh` 校验 U-Boot 配置含 `CONFIG_DISTRO_DEFAULTS`、`CONFIG_CMD_MMC/FAT/FS_GENERIC/PXE/BOOTI`，且拒绝 `CONFIG_FIT_SIGNATURE`/`CONFIG_AVB_VBMETA_PUBLIC_KEY_VALIDATE`（避免覆盖 extlinux 启动）。同时校验二进制含 `run distro_bootcmd;` 与 `extlinux/extlinux.conf`。请使用符合 Rockchip extlinux 规范的 defconfig。

**ARM64 宿主报 "requires qemu-x86_64-static"**：Rockchip rkbin 工具链为 x86-64 预编译。`build_uboot.sh` 会在 ARM64 宿主用 `qemu-x86_64-static` 包装这些工具，并在退出时还原。请确保构建器镜像含 `qemu-user-static`（Dockerfile 在 arm64 分支已安装）。

## 镜像校验失败

**`verify_image.sh` 报错（几何 / 嵌入组件 / rootfs 内容）**：校验是端到端一致性检查。`make verify-image` 以 root 身份运行（`_verify-one` 用 `-u 0`，因 ro-overlay 需 `unsquashfs` 保留设备节点与属主）。常见原因：

- 镜像尺寸与 `IMAGE_SIZE_MIB` 不符 → 确认 `make image` 用了相同的 `IMAGE_SIZE_MIB`/`DATA_SIZE_MIB`。
- 分区起止扇区错误 → 确认 `BOOT_START_MIB`/`BOOT_SIZE_MIB` 约束：须 `BOOT_START_MIB >= 16`、`IDBLOCK_SECTOR < UBOOT_SECTOR` 且在 GTP 之后、`ROOTFS_SIZE_MIB` 不超过剩余容量。
- Debian rootfs 缺模块/`/lib` usrmerge 丢失/systemd 缺失 → 通常是 rootfs 构建阶段异常，回到 `make build-rootfs` 排查。

**ro-overlay 的 embedded SquashFS 不是 `hsqs` 魔术字**：`rootfs.squashfs` 由 `mksquashfs` 以 `zstd` 压缩生成；若 `.img` 中该分区内容与 `rootfs.squashfs` 不符，说明 `make image` 与 `build-rootfs` 的 `ROOTFS_MODE` 不一致。务必全程统一 `ROOTFS_MODE=ro-overlay`。

## QEMU 测试失败

**`make test-debian-qemu` 超时或卡在登录**：QEMU `virt` 并非真实 RK3588——无 ATF/EL3、FiQ 串口未建模。测试驱动 `qemu_smoke.py` 会自动注入 `initcall_blacklist`（来自 `configs/soc/rk3588.conf`，如 `rockchip_drm_init,system_heap_create` 等）并 mask `serial-getty@ttyFIQ0.service`。若仍失败：

- 增大 `QEMU_TIMEOUT`（默认 600s）、`QEMU_MEMORY_MIB`（默认 1024）、`QEMU_CPUS`（默认 2）。
- 确认 rootfs 是 Debian 且 `ROOTFS_MODE` 与镜像元数据一致（`test_debian_qemu.sh` 从 `image-build-info.txt` 读取 `rootfs_mode`）。
- 串口/TTY 异常通常源于 `console=` 与镜像 `extlinux.conf` 不一致；确认 `CONSOLE` 在板级 profile 中正确设置。

**SSH 密码登录失败**：测试用 `ROOTFS_USERNAME`/`ROOTFS_PASSWORD`（Debian 默认 `user`/`password`；注意 `test_debian_qemu.sh` 内置回退为 `rk3588`/`rk3588`，应以实际传入为准）。确认 `base` overlay 已启用（`ssh.service` 被 enable 且 `10-hostkeys.conf` 生成缺失 host key）。

## 首次启动问题

**根分区未自动扩容 / 卡在 resize**：Debian 的 `sbc-firstboot` 服务（来自 `firstboot` overlay）负责首次启动 `growpart` + `resize2fs`。确保 `DEBIAN_OVERLAYS` 含 `firstboot`（默认包含）。Buildroot 由 `S02rootfs-resize` init 脚本扩容。

**ro-overlay 数据分区未挂载 `/data`**：确认 initramfs `overlayroot` hook 生效（镜像 `extlinux.conf` 含 `overlayroot=PARTLABEL=data`），且 `make image` 生成了第 3 分区。

## Debian / 软件包

**`DEBIAN_PACKAGES` 报 "no longer accepts feature alias"**：旧文档/命令中的 `nm`、`hwdebug`、`wifibt`、`all` 等别名已被移除。请使用真实 apt 包名（如 `network-manager`、`wpasupplicant`、`i2c-tools`）。

**WiFi/BT 固件**：不再有 `wifibt` overlay。固件通过板级 plugin（`boards/<BOARD>/rootfs/`）的 `overlay/lib/firmware/` 静态放置，或 `board_plugin_apply()` 从本地 `.deb` 解包。详见 [Debian 软件包与可选 Overlay](/usage/debian-features)。

## 最小 SDK 没有特定组件

`fetch_sources.sh` 校验 `kernel`/`u-boot`/`rkbin`/`buildroot` 四目录。若本地 SDK 缺某组件，`import-local-sdk` 与 `verify-sdk-volume` 都会直接报错，需补全后重新导入。
