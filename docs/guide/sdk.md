# SDK 管理

每个 BSP 源码对应独立 volume，互不污染。

## 公开源 fetch

| 命令 | Volume |
|---|---|
| `make fetch-510` | `rk3588-sdk-rockchip-5.10` |
| `make fetch-61` | `rk3588-sdk-rockchip-6.1` |
| `make fetch-66` | `rk3588-sdk-rockchip-6.6` |
| `make fetch-firefly` | `rk3588-sdk-firefly` |
| `make fetch-radxa` | `rk3588-sdk-radxa` |
| `make fetch-rock5c` | `rk3588-sdk-rock5c` |
| `make fetch-orangepi` | `rk3588-sdk-orangepi` |
| `make fetch-muse` | `rk3588-sdk-muse-5.10` |

自定义：

```bash
make fetch-custom SDK_VOLUME=rk3588-sdk-custom MANIFEST=my-board.xml
make fetch-custom \
  SDK_VOLUME=rk3588-sdk-custom \
  CUSTOM_MANIFEST_URL=https://example.com/manifests.git \
  CUSTOM_MANIFEST_NAME=board.xml
make update SDK_VOLUME=rk3588-sdk-radxa
docker volume ls --filter name=rk3588
```

## 本地导入（大体积 SDK）

```bash
make import-local-sdk \
  SDK_PATH=/absolute/path/to/sdk \
  SDK_VOLUME=rk3588-sdk-local
make verify-sdk-volume SDK_VOLUME=rk3588-sdk-local
# CokePi 可用：
make verify-cokepi-sdk SDK_VOLUME=rk3588-sdk-cokepi-rkr9
```

要求 SDK 根目录直接包含：

```text
kernel/
u-boot/
rkbin/
buildroot/
```

容器内 `/home/builder/sdk` 直接映射该目录；构建缓存写在 SDK 下的 `.rk3588-build/`。删除 Docker volume **不会**删除宿主机源码；移动宿主机路径会使 volume 失效。Docker daemon 须能访问传入的绝对路径。

本地 volume 只解决源码接入；新硬件仍须增加 board profile。

## 切换当前 volume

```bash
make use-volume-rock5c
make use-volume-muse
make use-volume SDK_VOLUME=rk3588-sdk-local
make use-current
```
