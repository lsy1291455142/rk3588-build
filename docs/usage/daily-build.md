# 日常构建

本页说明如何在不改源码的情况下切换板型/SDK/rootfs、做增量构建、进容器调试、更新 SDK 与清理。核心理念：环境变量（CLI 或 `.env`）驱动一切，脚本本身与具体板型解耦。

## 切换板型 / SDK / rootfs

`make use-*` 系列只写 `.env` 的对应键，不影响其它配置，便于交互式复用：

```bash
make use-board              # 交互选择板型（或 make use-board BOARD=rk3588s-rock-5c）
make use-volume             # 交互选择 rk3588-sdk-* 卷
make use-rootfs             # 交互选择 buildroot / debian / all
make use-current            # 查看当前三项
make info                   # 查看完整环境（含板型描述、manifest、Debian 发行版）
```

设置 `BOARD` 且其 `SOURCE_MANIFEST` 存在时，`use-board` 会在 `SDK_VOLUME` 为空时自动派生卷名；若已设置不同卷则保留并提示用 `make use-volume` 切换。

## 增量构建

各阶段独立，缺哪个就只构建哪个（均依赖 SDK 卷、BOARD 与前置产物）：

```bash
# 只改内核
make build-kernel BOARD=rk3588s-rock-5c SDK_VOLUME=rk3588-sdk-rock5c
make image BOARD=rk3588s-rock-5c SDK_VOLUME=rk3588-sdk-rock5c ROOTFS=debian DEBIAN_RELEASE=13

# 只改 U-Boot
make build-uboot BOARD=rk3588s-rock-5c SDK_VOLUME=rk3588-sdk-rock5c
make image ...

# 只改 rootfs 配置（overlay / 包）
make build-rootfs BOARD=rk3588s-rock-5c SDK_VOLUME=rk3588-sdk-rock5c ROOTFS=debian \
  DEBIAN_RELEASE=13 DEBIAN_OVERLAYS=base,console,network
make image ...

# 全部重来
make build-all BOARD=rk3588s-rock-5c SDK_VOLUME=rk3588-sdk-rock5c ROOTFS=debian DEBIAN_RELEASE=13
```

`image` 目标在组装后立即运行 `verify-image`（`_verify-one`），无需单独调用即可确认一致性。

## 进入构建容器调试

```bash
make shell SDK_VOLUME=rk3588-sdk-rock5c        # 主构建器（交叉编译 / U-Boot / 内核）
make debian-shell SDK_VOLUME=rk3588-sdk-rock5c # ARM64 Debian 构建器（mmdebstrap 调试）
```

容器内工作区为 `/home/builder`，SDK 在 `/home/builder/sdk`，脚本在 `/home/builder/scripts`，可直接手动运行各 `scripts/*.sh` 排查。

## 更新 SDK 源码

```bash
make update SDK_VOLUME=rk3588-sdk-rock5c
```

重新 init 并 `repo sync` 更新已有卷（清理 `.repo/manifests` 以避免 rebase 历史冲突）。若设置 `SOURCE_MANIFEST`，`fetch_sources.sh` 会比对锁定 commit；若变更了 manifest 内的 revision，需同步更新板级 `EXPECTED_*_REVISION` 后重新 `update`。

## 修改源码

导入的 SDK 源码在 Docker 卷中（`make import-local-sdk` 为 bind 挂载，直接是宿主机目录，可就地编辑；`make fetch` 的卷为容器内卷，需进容器或用 `make shell` 编辑）。修改后重新运行相应 `build-*` 与 `image` 即可，ccache（`rk3588-ccache` 卷）会加速重编译。

## 清理

```bash
make clean        # docker compose down --remove-orphans
make clean-all    # 同时 --volumes --rmi local（删除卷与本地镜像，谨慎）
make status       # 查看容器与 rk3588-* 卷
```

## 并行构建多个板型

每个板型使用独立的 `SDK_VOLUME` 与独立的 `output/<BOARD>/` 目录，互不干扰。可在不同终端分别 `make build-all BOARD=<a> SDK_VOLUME=<va> ...` 与 `make build-all BOARD=<b> SDK_VOLUME=<vb> ...` 并行（注意磁盘与 CPU 占用）。
