# CI 与依赖更新

## GitHub Actions

`.github/workflows/docker-rk3588-build.yml` 分别在 x64 / ARM runner 上构建 `linux/amd64` 与 `linux/arm64`，合并为 multi-arch 清单后推送 `rk3588-build` 至 GHCR。

- `main` 上相关路径变更：构建并 push
- PR：只构建不 push
- 可手动 `workflow_dispatch`

发布的镜像：

```text
ghcr.io/lsy1291455142/rk3588-build:latest
ghcr.io/lsy1291455142/rk3588-build:main
ghcr.io/lsy1291455142/rk3588-build:sha-<short-sha>
```

## Dependabot

`.github/dependabot.yml` 跟踪 Docker 基础镜像与 Actions 版本。对 `ubuntu` / `debian` 的 **major** 升级已 ignore——builder 固定在 Ubuntu 22.04（Python 2、i386 兼容栈），大版本升级需单独评估，不宜直接合入。

## 文档站点

`.github/workflows/docs.yml` 在 `docs/**` 变更时构建 VitePress 站点，并部署到 GitHub Pages：

```text
https://lsy1291455142.github.io/rk3588-build/
```
