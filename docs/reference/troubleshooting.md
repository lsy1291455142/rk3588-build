# 排错

## Docker 相关

### `SDK_VOLUME is required`

没有指定 SDK volume。先运行 `make fetch-*` 拉取一个 SDK，或在命令行加上 `SDK_VOLUME=...`。

### `Cannot run the linux/arm64 Debian builder`

x86_64 宿主机没有注册 ARM64 binfmt 模拟。运行：

```bash
make register-arm64-binfmt
```

这会自动执行 `docker run --privileged --rm tonistiigi/binfmt --install arm64`。之后重新构建。

### Docker 磁盘空间不足

```bash
# 清理不用的镜像和容器
docker system prune

# 清理不用的 SDK volume
docker volume ls --filter name=rk3588-sdk
docker volume rm rk3588-sdk-不需要的
```

## SDK 拉取

### `repo sync` 失败

网络问题最常见。`fetch_sources.sh` 自带 3 次重试，重试间隔递增。如果持续失败：

- 检查网络连接和代理设置
- 尝试减少并行数：`make fetch-rock5c JOBS=2`
- 手动进入容器重试：`make shell SDK_VOLUME=... && cd /home/builder/sdk && repo sync -j2`

### 磁盘空间不足

SDK 源码 + 编译产物通常需要 30-50 GB。确认 Docker 数据目录所在分区有足够空间。

## 编译错误

### 内核编译失败：`O= build` 相关错误

某些厂商内核在 Git 里跟踪了 Kbuild 生成文件（`.config`、`include/config`、`arch/arm64/include/generated`），导致外源构建失败。`build_kernel.sh` 通过符号链接视图自动处理这个问题。如果仍然报错，检查内核源码是否有非标准的生成文件。

### U-Boot 编译失败：Python 相关错误

Rockchip 的 `make.sh` 和 FIT 生成器可能需要 Python 2。检查板级 profile 中的 `UBOOT_PYTHON` 设置：

- 大多数新 BSP 用 `python3`
- CokePi 等老 BSP 用 `python2`

Docker 镜像内置了 Python 2.7 + pyelftools，不需要额外安装。

### U-Boot 编译失败：`pyelftools` 缺失

确保 Docker 镜像是用最新的 `Dockerfile` 构建的。重新运行 `make build`。

## 镜像校验失败

### `Kernel configuration did not retain ...`

共享 fragment `configs/kernel/rootfs-base.config` 中的某个选项没有被板级 defconfig 保留。检查板级 defconfig 是否显式禁用了该选项。

### `Built board DTB is invalid`

DTB 编译失败或文件损坏。检查内核编译日志。

### `Packaged DTB still defines /chosen/bootargs`

`fdtput -d` 删除 bootargs 失败。可能是 dtc 版本问题。重新构建 Docker 镜像。

### `idblock.img exceeds the reserved IDBlock area`

IDBlock 太大，超过了 IDBLOCK_SECTOR 到 UBOOT_SECTOR 之间的空间。这通常意味着 rkbin 版本不兼容。

### `Embedded rootfs lacks modules for ...`

rootfs 中没有找到内核模块。确认 `build-kernel` 在 `build-rootfs` 之前成功完成。

## QEMU 测试失败

### `fatal boot message matched: Kernel panic`

内核在 QEMU virt 里崩溃。常见原因：

- DTB 不兼容（QEMU virt 不需要真实硬件的 DTB，测试直接用 `-kernel` 加载 Image）
- 内核缺少 virtio 支持。确认 `configs/kernel/rootfs-base.config` 中的 `CONFIG_VIRTIO*` 选项都在最终 `.config` 里

### `serial password login failed`

镜像中的用户名密码不匹配。确认构建时用的 `ROOTFS_USERNAME` 和 `ROOTFS_PASSWORD` 与测试时传入的一致。

### `Debian guest checks failed: firstboot`

首次启动扩容没有完成。可能是 QEMU 磁盘太小或超时太短。尝试增加 `QEMU_TIMEOUT=900`。

## 首次启动问题

### 串口没有输出

- 确认波特率是 1500000（不是 115200）
- 确认 USB 转串口线接线正确（TX/RX 交叉）
- 某些板子需要按住 recovery 键再上电

### 无法 SSH 登录

- 首次启动需要 30-60 秒生成 SSH host key，稍等再试
- 确认 IP 地址正确：`ip addr show`
- 确认密码是 `rk3588`（或构建时设置的值）

### 根分区没有扩容

- Buildroot：检查 `/var/lib/rk3588-rootfs-expanded` 标记是否存在
- Debian：检查 `/var/lib/rk3588-firstboot.done` 标记
- 手动执行：`sudo resize2fs /dev/mmcblkXp2`
