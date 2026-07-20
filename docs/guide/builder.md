# Builder 镜像

## 本地构建

```bash
make build                 # 构建 rk3588-build:latest
make build-debian-builder  # Debian rootfs 用 ARM64 builder（按需）
```

Debian rootfs 在独立 `linux/arm64` 容器中构建（`mmdebstrap`，privileged）。选择 `ROOTFS=debian` 时，`build-rootfs` / `build-all` 会自动准备该 builder。仅在可信主机与可信代码上执行。

Builder 基于 Ubuntu 22.04，同时提供 Python 2/3，供不同 U-Boot BSP 使用。`UBOOT_PYTHON` 在 board profile 中显式指定；全局 `python` 仍指向 Python 3。

## 从 GHCR 拉取

CI 只发布 **`rk3588-build` 工具链镜像**，不包含厂商 SDK、板级 `.img`，也不推送 `debian-rootfs`。

镜像为 **multi-arch**：`linux/amd64` 与 `linux/arm64` 同一 tag。Docker 会按宿主机架构自动拉取对应变体。

```text
ghcr.io/lsy1291455142/rk3588-build:latest
ghcr.io/lsy1291455142/rk3588-build:main
ghcr.io/lsy1291455142/rk3588-build:sha-<short-sha>
```

触发：`main` 上与 builder 相关路径变更自动构建并 push；PR 只构建不 push；也可在 Actions 中手动运行 `docker-rk3588-build`。

```bash
# 私有 package 时先登录（需 read:packages）
echo "$GHCR_TOKEN" | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin

docker pull ghcr.io/lsy1291455142/rk3588-build:latest
docker tag ghcr.io/lsy1291455142/rk3588-build:latest rk3588-build:latest
```

Makefile / Compose 默认使用本地名 `rk3588-build:latest`，拉取后需打上述 tag。
