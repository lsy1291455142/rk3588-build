# 日常构建

第一次完整构建之后，日常工作流围绕「改代码 → 增量编译 → 重新出镜像」展开。

## 切换板型 / SDK / rootfs

项目用 `.env` 文件记住当前选择，避免每次都敲一长串变量。

```bash
# 交互式选择
make use-board        # 列出所有板级 profile，选编号
make use-volume       # 列出所有 SDK volume，选编号
make use-rootfs       # 选 buildroot / debian / all

# 或直接指定
make use-board-rock5c
make use-volume-rock5c
make use-rootfs-debian

# 查看当前选择
make use-current
```

设置之后就可以省略变量直接构建：

```bash
make build-all
```

`.env` 里的值始终可以被命令行覆盖：

```bash
make build-all DEBIAN_RELEASE=12
```

## 增量构建

### 只改内核

```bash
make build-kernel
make image          # 重新打包镜像（会用新内核）
```

内核编译用 ccache 加速，改一个驱动文件通常 1-2 分钟。

### 只改 U-Boot

```bash
make build-uboot
make image
```

### 只改 rootfs 配置

```bash
make build-rootfs
make image
```

Buildroot 会增量编译；Debian 每次都从头跑 mmdebstrap（因为是确定性的）。

### 全部重来

```bash
make build-all
```

## 进入构建容器调试

```bash
make shell SDK_VOLUME=rk3588-sdk-rock5c
```

这会进入一个交互式 Bash，SDK 源码挂载在 `/home/builder/sdk`，可以手动执行任何编译命令。容器退出后改动保留在 volume 里。

进入 Debian rootfs 构建容器：

```bash
make debian-shell SDK_VOLUME=rk3588-sdk-rock5c
```

## 更新 SDK 源码

```bash
make update SDK_VOLUME=rk3588-sdk-rock5c
```

这会重新执行 `repo sync`，拉取 manifest 中各仓库的最新提交。如果 manifest 里锁的是具体 commit SHA（如 ROCK 5C），update 不会变更版本。

## 修改源码

SDK 源码在 Docker volume 里，不直接暴露在宿主机文件系统。两种修改方式：

**方式一：容器内直接改**

```bash
make shell SDK_VOLUME=rk3588-sdk-rock5c
cd /home/builder/sdk/kernel
# 用 vim/nano 改文件，或 git apply 补丁
```

**方式二：本地补丁目录**

把 `.patch` 文件放进 `patches/` 目录，容器内挂载为 `/home/builder/patches/`（只读）：

```bash
make shell SDK_VOLUME=rk3588-sdk-rock5c
cd /home/builder/sdk/kernel
git am /home/builder/patches/kernel/0001-my-fix.patch
```

## 清理

```bash
make clean           # 停止并删除容器
make clean-all       # 同时删除 volume 和镜像（谨慎）
```

清理某个板型的构建中间产物（不影响 SDK 源码）：

```bash
# 构建中间产物在 SDK volume 的 .rk3588-build/ 目录
docker run --rm -v rk3588-sdk-rock5c:/sdk alpine rm -rf /sdk/.rk3588-build
```

## 并行构建多个板型

每个 SDK volume 是独立的，可以在不同终端窗口同时构建不同板型：

```bash
# 终端 1
make build-all BOARD=rk3588s-rock-5c SDK_VOLUME=rk3588-sdk-rock5c ROOTFS=debian

# 终端 2
make build-all BOARD=rk3588-evb1-lp4-v10-linux SDK_VOLUME=rk3588-sdk-rockchip-6.6 ROOTFS=buildroot
```

产物在 `output/` 下按板型名分目录，不会互相覆盖。
