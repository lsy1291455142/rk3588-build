# Overlay 插件开发规范

可选 overlay 让 Debian rootfs 的核心构建逻辑（在 `scripts/build_debian.sh`）保持纯粹，把「可插拔的可选能力」外置为目录化的静态文件树。overlay 由 `DEBIAN_OVERLAYS`（CLI / `.env` 或板级 `DEBIAN_OVERLAYS_DEFAULT`）选择，`run_debian_overlay_plugins` 按列表顺序应用。

## 目录结构约定

```text
rootfs/debian/overlays/<name>/
└── overlay/               # 必需：静态文件树（拷贝到 root_dir 对应路径）
    ├── etc/...             # 普通文件
    ├── *.in                # 模板文件（@TOKEN@ 展开）
    └── etc/systemd/system/<target>.wants/<unit>  # 符号链接 → 启用服务
```

每个 overlay 就是一个 `overlay/` 目录——放文件进去即可，不需要写任何脚本。

### 命名规则

- `<name>` 即 overlay 标识，对应 `DEBIAN_OVERLAYS` 中的一个条目（如 `base`、`console`、`firstboot`、`firstboot-info`、`network`）。
- `resolve_debian_overlays` 校验 `<name>/overlay/` 目录必须存在，未知名字直接报错；`none`/`off`/`-` 表示无 overlay。

### 启用 systemd 服务

在 `overlay/` 内放一个 wants 符号链接即可启用服务。`apply_rootfs_overlay_tree` 会保留符号链接（`readlink` + `ln -sfn`）。例如启用 `ssh.service`：

```
overlay/etc/systemd/system/multi-user.target.wants/ssh.service → /usr/lib/systemd/system/ssh.service
```

常见 wants 目标目录：

| 服务类型 | wants 目录 |
|---|---|
| 普通服务 | `etc/systemd/system/multi-user.target.wants/` |
| sysinit 阶段服务（如 resolved） | `etc/systemd/system/sysinit.target.wants/` |
| getty 服务 | `etc/systemd/system/getty.target.wants/` |
| socket 服务 | `etc/systemd/system/sockets.target.wants/` |

符号链接 target 指向 unit 文件在 rootfs 中的绝对路径。包安装的 unit 在 `/usr/lib/systemd/system/`；overlay 自带的 unit 在 `/etc/systemd/system/`。

对于互斥的网络栈（NetworkManager 与 systemd-networkd），拆成 `network-nm` 与 `network-networkd` 两个独立 overlay，由 `DEBIAN_OVERLAYS` 选其一——不要在同一个 overlay 里放两套 wants 软链（`systemd-networkd.service` 的 unit 文件由 systemd 包提供、总存在，两个软链共存会让装了 NM 的镜像同时启用 networkd）。

### 模板文件

`overlay/` 内的 `*.in` 文件在拷贝时展开 `@PLACEHOLDER@` 标记（见 `rootfs/debian/README.md` 的 Templates）。展开后的文件去掉 `.in` 后缀，权限沿用源文件。

### 路径变量插值

文件路径中的 `%VAR%` 会被替换为同名 shell 变量值。例如 console 插件的 getty 配置：

```
overlay/etc/systemd/system/serial-getty@%CONSOLE_DEVICE%.service.d/10-baud.conf.in
```

`%CONSOLE_DEVICE%` 在构建时替换为实际设备名（如 `ttyFIQ0`）。若变量为空，该文件被跳过。

符号链接名同样支持 `%VAR%` 插值：

```
overlay/etc/systemd/system/getty.target.wants/serial-getty@%CONSOLE_DEVICE%.service → /usr/lib/systemd/system/serial-getty@.service
```

注意：`%VAR%` 仅作用于文件/符号链接的**路径**，不作用于符号链接的 **target**（target 是系统路径，不需要插值）。`@TOKEN@` 用于文件**内容**展开，两者作用于不同层。

### 固件说明

静态固件放 `overlay/lib/firmware/`。动态固件（如从 `.deb` 解包）需在板级 `plugin.sh` 中处理。板级硬件固件应放 `boards/<BOARD>/rootfs/`（始终应用），而非此处可选 overlay。

## 新增 overlay Checklist

1. 创建 `rootfs/debian/overlays/<name>/overlay/` 目录。
2. 放入要拷贝到 rootfs 的文件（路径对应 rootfs 内的路径）。
3. 需要启用服务则在 `etc/systemd/system/<target>.wants/` 下放符号链接。
4. 需要模板则放 `*.in` 文件。
5. 用 `make check`（其 `check_debian_packages` 会校验 overlay 目录存在）验证。
6. 在 `DEBIAN_OVERLAYS` / `DEBIAN_OVERLAYS_DEFAULT` 中引用该名字。

不需要编写任何脚本。板级插件（`boards/<BOARD>/rootfs/plugin.sh`）仍保留脚本机制用于固件安装等需要逻辑的场景。

## 现有 overlay 索引

| overlay | 作用 |
|---|---|
| `base` | SSH 配置（`ssh.service` 启用）、udev 权限、systemd-resolved（通过 wants 软链启用，包未安装时 dangling 无害）、基础权限规则 |
| `console` | 串口 getty 波特率配置（`serial-getty@%CONSOLE_DEVICE%.service` 启用，`@CONSOLE_SPEED@` 模板展开） |
| `firstboot` | `sbc-firstboot` 脚本与 `sbc-firstboot.service`（wants 软链启用），首启 `growpart` + `resize2fs` 扩容根分区 |
| `firstboot-info` | `sbc-firstboot-info`（由 `sbc-firstboot` 首启调用），打印 banner / MOTD |
| `network-nm` | NetworkManager 配置（`10-sbc.conf`，含 `wifi.scan-rand-mac-address=no`）+ `NetworkManager.service` wants 软链。与 `network-networkd` 互斥，按装的包二选一 |
| `network-networkd` | systemd-networkd 配置（`20-wired.network`）+ `systemd-networkd.service` wants 软链。与 `network-nm` 互斥，按装的包二选一 |
