# 架构与目录

## 三层东西

```text
┌─────────────────────────────────────────────┐
│ 宿主机：Makefile / docker compose / .env    │
├─────────────────────────────────────────────┤
│ builder 镜像：交叉工具、Python2/3、打包工具  │
│ debian-rootfs 镜像：ARM64 mmdebstrap（可选） │
├─────────────────────────────────────────────┤
│ SDK volume：kernel / u-boot / rkbin / br     │
│ 工作区挂载：configs scripts rootfs manifests │
│ 输出挂载：./output                          │
└─────────────────────────────────────────────┘
```

| 层 | 变不变 | 说明 |
|---|---|---|
| builder 镜像 | 工具链变了才重建 | CI 推到 GHCR |
| SDK volume | 按板卡 / 厂商切换 | `fetch-*` 或 `import-local-sdk` |
| 仓库文件 | 日常改这里 | board profile、脚本、rootfs 定制 |

## 仓库目录

| 路径 | 作用 |
|---|---|
| `Makefile` | 对外接口：fetch / build / image / test |
| `docker-compose.yml` | 主 builder 与 debian-rootfs 服务 |
| `configs/boards/*.conf` | 板级：DTB、U-Boot、串口、镜像几何 |
| `configs/kernel/rootfs-base.config` | 所有板共用的内核 fragment |
| `scripts/` | 容器内真实构建步骤 |
| `rootfs/buildroot/` | Buildroot external tree |
| `manifests/` | `repo` 用的 XML |
| `output/` | 产物（默认 gitignore） |

## 容器里怎么挂

主 builder（简化）：

```text
sdk volume          -> /home/builder/sdk
./scripts           -> /home/builder/scripts  (ro)
./configs           -> /home/builder/configs  (ro)
./rootfs            -> /home/builder/rootfs   (ro)
./manifests         -> /home/builder/manifests(ro)
./output            -> /home/builder/output
ccache volume       -> /home/builder/.ccache
```

所以：改 board conf 或脚本，宿主机保存后下一次 `make build-*` 就会用到；不必为改配置重建镜像。

## 三个必需变量

| 变量 | 选的是什么 |
|---|---|
| `SDK_VOLUME` | 哪份源码 |
| `BOARD` | 哪份 `configs/boards/<name>.conf` |
| `ROOTFS` | `buildroot` / `debian` / `all` |

Compose 里 `SDK_VOLUME` 是 external volume 名。没有它，容器起不来。

## 为什么不用“默认板”

错板意味着错 DTB / 错 U-Boot defconfig。强制显式指定，是为了避免 silent wrong image。
