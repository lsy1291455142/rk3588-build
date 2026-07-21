# SDK 从哪来

SDK 指构建所需的四件套源码：`kernel`、`u-boot`、`rkbin`、`buildroot`。每个 SDK 存放在一个独立的 Docker volume 里，通过 `SDK_VOLUME` 变量引用。

## 内置 SDK 来源

项目内置了 8 个 manifest，对应不同的开发板或内核分支：

| Make 目标 | Volume 名 | 来源 | 内核分支 |
|---|---|---|---|
| `fetch-510` | `rk3588-sdk-rockchip-5.10` | Rockchip 官方 | linux-5.10 |
| `fetch-61` | `rk3588-sdk-rockchip-6.1` | Rockchip 官方 | linux-6.1 |
| `fetch-66` | `rk3588-sdk-rockchip-6.6` | Rockchip 官方 | linux-6.6 |
| `fetch-firefly` | `rk3588-sdk-firefly` | Firefly AIO-3588 | 厂商分支 |
| `fetch-radxa` | `rk3588-sdk-radxa` | Radxa Rock 5B | 厂商分支 |
| `fetch-rock5c` | `rk3588-sdk-rock5c` | Radxa Rock 5C | 锁定 commit |
| `fetch-orangepi` | `rk3588-sdk-orangepi` | OrangePi 5 | 厂商分支 |
| `fetch-muse` | `rk3588-sdk-muse-5.10` | MUSE fork | develop-5.10 |

拉取方式统一：

```bash
make fetch-rock5c
```

## 版本锁定

大多数 manifest 跟踪分支（如 `develop-5.10`），每次 `make update` 可能拉到不同的代码。

ROCK 5C 的 manifest（`rk3588-rock5c.xml`）把四个组件全部锁定到具体 commit SHA，同时板级 profile `rk3588s-rock-5c.conf` 里声明了 `EXPECTED_*_REVISION`。构建前会强制校验实际 commit 是否匹配，不匹配直接报错退出。这保证了 ROCK 5C 的构建是完全可复现的。

## 导入本地 SDK

如果已经有下载好的 SDK 源码（比如 CokePi 的私有 SDK），不需要重新拉取：

```bash
make import-local-sdk \
  SDK_PATH=/absolute/path/to/sdk \
  SDK_VOLUME=rk3588-sdk-cokepi
```

SDK 目录必须包含 `kernel/`、`u-boot/`、`rkbin/`、`buildroot/` 四个子目录。

这会创建一个 bind-backed Docker volume，直接挂载本地目录，不复制数据。本地对源码的修改立即反映到构建中。

验证导入的 SDK：

```bash
make verify-sdk-volume SDK_VOLUME=rk3588-sdk-cokepi
```

CokePi SDK 额外验证：

```bash
make verify-cokepi-sdk SDK_VOLUME=rk3588-sdk-cokepi
```

## 自定义 manifest

### 本地 manifest 文件

把自定义 XML 放进 `manifests/` 目录，然后：

```bash
make fetch-custom SDK_VOLUME=my-sdk MANIFEST=my-custom.xml
```

### 远程 manifest URL

```bash
make fetch-custom \
  SDK_VOLUME=my-sdk \
  CUSTOM_MANIFEST_URL=https://github.com/example/manifests \
  CUSTOM_MANIFEST_NAME=my-board.xml
```

### manifest 格式

参考 `manifests/rk3588-rock5c.xml`：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <remote name="rockchip" fetch="https://github.com/rockchip-linux" />
  <remote name="buildroot" fetch="https://gitlab.com/buildroot.org" />
  <default remote="rockchip" sync-j="4" />

  <project name="kernel"    path="kernel"    revision="develop-5.10" />
  <project name="u-boot"    path="u-boot"    revision="next-dev" />
  <project name="rkbin"     path="rkbin"     revision="master" />
  <project name="buildroot" path="buildroot" remote="buildroot"
           revision="refs/tags/2025.02.15" />
</manifest>
```

四个组件缺一不可。`revision` 可以是分支名、tag 或完整 commit SHA。

## 管理 SDK volume

```bash
# 列出所有 SDK volume
docker volume ls --filter name=rk3588-sdk

# 查看 volume 大小
docker system df -v | grep rk3588

# 删除不再需要的 volume
docker volume rm rk3588-sdk-rockchip-5.10

# 更新某个 SDK 到最新
make update SDK_VOLUME=rk3588-sdk-rockchip-5.10
```

## 浅克隆与完整克隆

默认 `DEPTH=1`，浅克隆节省空间。如果需要完整 Git 历史（比如要 `git log` 或 `git bisect`）：

```bash
make fetch-rock5c DEPTH=0
```
