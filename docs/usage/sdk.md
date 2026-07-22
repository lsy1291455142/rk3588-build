# SDK 从哪来

SDK 指构建所需的四件套源码：`kernel`、`u-boot`、`rkbin`、`buildroot`。每个 SDK 存放在一个独立的 Docker volume 里，通过 `SDK_VOLUME` 变量引用。

## 拉取模型（当前）

已不再提供 `make fetch-rock5c` / `fetch-510` 这类专用目标。统一为：

| 方式 | 命令 | 适用 |
|---|---|---|
| 板型 manifest | `make fetch BOARD=<board>` | board conf 中配置了 `SOURCE_MANIFEST` |
| 自定义本地 manifest | `make fetch-custom SDK_VOLUME=... MANIFEST=...` | `manifests/` 下任意 XML |
| 自定义远程 manifest | `make fetch-custom SDK_VOLUME=... CUSTOM_MANIFEST_URL=... CUSTOM_MANIFEST_NAME=...` | 远程 repo 仓库 |
| 本地已有 SDK | `make import-local-sdk SDK_PATH=... SDK_VOLUME=...` | CokePi 等私有/本地树 |

`make fetch` 会：

1. 读取 `configs/boards/<BOARD>.conf` 的 `SOURCE_MANIFEST`
2. 决定目标 volume：
   - 命令行显式 `SDK_VOLUME=...` 时用该值
   - 否则**始终**从 manifest 名推导（如 `rk3588-rock5c.xml` → `rk3588-sdk-rock5c`），不复用 `.env` 里无关 volume
3. 用 `repo` 拉取到该 Docker volume，并写回 `.env` 的 `SDK_VOLUME`

示例：

```bash
make fetch BOARD=rk3588s-rock-5c
make fetch BOARD=rk3588-muse
make fetch BOARD=rk3588-evb1-lp4-v10-linux
```

## 内置 manifest 与板型映射

| Manifest | 推导 Volume | 典型板型 / 用途 | 内核 |
|---|---|---|---|
| `rk3588-rock5c.xml` | `rk3588-sdk-rock5c` | `rk3588s-rock-5c` | Radxa 锁定 commit |
| `rk3588-muse-5.10.xml` | `rk3588-sdk-muse-5.10` | `rk3588-muse` | MUSE fork develop-5.10 |
| `rk3588-linux-5.10.xml` | `rk3588-sdk-linux-5.10` | `rk3588-evb1-lp4-v10-linux`（默认） | Rockchip develop-5.10 |
| `rk3588-linux-6.1.xml` | `rk3588-sdk-linux-6.1` | 自定义 / EVB 换 6.1 | Rockchip develop-6.1 |
| `rk3588-linux-6.6.xml` | `rk3588-sdk-linux-6.6` | 自定义 / EVB 换 6.6 | Rockchip develop-6.6 |
| `rk3588-firefly.xml` | `rk3588-sdk-firefly` | 自定义 | Firefly 分支 |
| `rk3588-radxa.xml` | `rk3588-sdk-radxa` | 自定义 | Radxa Rock 5B 系 |
| `rk3588-orangepi.xml` | `rk3588-sdk-orangepi` | 自定义 | OrangePi 5 系 |

无 `SOURCE_MANIFEST` 的板型（CokePi）**不能** `make fetch`，应使用 `import-local-sdk`。

## 版本锁定

大多数 manifest 跟踪分支（如 `develop-5.10`），每次 `make update` 可能拉到不同的代码。

ROCK 5C 的 manifest（`rk3588-rock5c.xml`）把四个组件全部锁定到具体 commit SHA，同时板级 profile `rk3588s-rock-5c.conf` 里声明了 `EXPECTED_*_REVISION`。构建前会强制校验实际 commit 是否匹配，不匹配直接报错退出。这保证了 ROCK 5C 的构建是完全可复现的。

## 导入本地 SDK

如果已经有下载好的 SDK 源码（比如 CokePi 的私有 SDK），不需要重新拉取：

```bash
make import-local-sdk \
  SDK_PATH=/absolute/path/to/sdk \
  SDK_VOLUME=rk3588-sdk-cokepi-rkr9
```

SDK 目录必须包含 `kernel/`、`u-boot/`、`rkbin/`、`buildroot/` 四个子目录。

这会创建一个 bind-backed Docker volume，直接挂载本地目录，不复制数据。本地对源码的修改立即反映到构建中。

验证导入的 SDK：

```bash
make verify-sdk-volume SDK_VOLUME=rk3588-sdk-cokepi-rkr9
```

## 自定义 manifest

### 本地 manifest 文件

把自定义 XML 放进 `manifests/` 目录，然后：

```bash
make fetch-custom SDK_VOLUME=my-sdk MANIFEST=my-custom.xml
```

EVB 若要用 6.1/6.6 而不是默认 5.10：

```bash
make fetch-custom SDK_VOLUME=rk3588-sdk-linux-6.1 MANIFEST=rk3588-linux-6.1.xml
make use-volume   # 或编辑 .env 选中该 volume
make use-board BOARD=rk3588-evb1-lp4-v10-linux
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

# 交互选择并写入 .env
make use-volume

# 查看 volume 大小
docker system df -v | grep rk3588

# 删除不再需要的 volume
docker volume rm rk3588-sdk-linux-5.10

# 更新某个 SDK 到最新
make update SDK_VOLUME=rk3588-sdk-linux-5.10
```

## 浅克隆与完整克隆

默认 `DEPTH=1`，浅克隆节省空间。如果需要完整 Git 历史（比如要 `git log` 或 `git bisect`）：

```bash
make fetch BOARD=rk3588s-rock-5c DEPTH=0
```
