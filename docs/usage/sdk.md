# SDK 从哪来

本仓库**不包含**厂商 BSP 源码。SDK 进 Docker volume 后，容器里挂到 `/home/builder/sdk`。

SDK 根目录必须直接有：

```text
kernel/
u-boot/
rkbin/
buildroot/
```

## 公开拉取（repo + manifest）

| 命令 | Volume |
|---|---|
| `make fetch-rock5c` | `rk3588-sdk-rock5c` |
| `make fetch-510` | `rk3588-sdk-rockchip-5.10` |
| `make fetch-61` | `rk3588-sdk-rockchip-6.1` |
| `make fetch-66` | `rk3588-sdk-rockchip-6.6` |
| `make fetch-radxa` | `rk3588-sdk-radxa` |
| `make fetch-firefly` | `rk3588-sdk-firefly` |
| `make fetch-orangepi` | `rk3588-sdk-orangepi` |
| `make fetch-muse` | `rk3588-sdk-muse-5.10` |

manifest 在 `manifests/`。ROCK 5C 会额外锁定 profile 里的 commit。

自定义：

```bash
make fetch-custom SDK_VOLUME=rk3588-sdk-custom MANIFEST=my-board.xml
make fetch-custom \
  SDK_VOLUME=rk3588-sdk-custom \
  CUSTOM_MANIFEST_URL=https://example.com/manifests.git \
  CUSTOM_MANIFEST_NAME=board.xml
```

更新已有 volume：

```bash
make update SDK_VOLUME=rk3588-sdk-rock5c
```

## 本地导入

大体积或无法公开的 SDK（如 CokePi）：

```bash
make import-local-sdk \
  SDK_PATH=/absolute/path/to/sdk \
  SDK_VOLUME=rk3588-sdk-cokepi-rkr9
make verify-sdk-volume SDK_VOLUME=rk3588-sdk-cokepi-rkr9
make verify-cokepi-sdk SDK_VOLUME=rk3588-sdk-cokepi-rkr9
```

要点：

- volume 是 **bind**，不复制源码
- 构建缓存写在 SDK 下的 `.rk3588-build/`
- 移动宿主机路径会使 volume 失效
- Docker daemon 必须能访问 `SDK_PATH`

本地 volume 只解决“源码在哪”。板级字段仍要有对应 `configs/boards/*.conf`。

## 一个 volume 对应一个 SDK

不同 BSP 用不同 volume，避免交叉污染。  
同一 CokePi SDK 可以给 Plus / Model 共用，但 **BOARD profile 不能混**（DTB 不同）。
