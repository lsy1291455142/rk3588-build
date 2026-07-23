# Overlay 插件开发规范

可选 overlay 插件让 Debian rootfs 的核心构建逻辑（在 `scripts/build_debian.sh`）保持纯粹，把「可插拔的可选能力」外置为目录化的插件。插件由 `DEBIAN_OVERLAYS`（CLI / `.env` 或板级 `DEBIAN_OVERLAYS_DEFAULT`）选择，`run_debian_overlay_plugins` 按列表顺序应用。

## 目录结构约定

```text
rootfs/debian/overlays/<name>/
├── plugin.sh              # 必需入口：定义 plugin_apply(root_dir)
├── overlay/               # 可选静态文件树（* 拷贝到 root_dir 对应路径）
└── overlay-nm/            # 可选：NetworkManager 专属文件（network 插件使用）
```

### 命名规则

- `<name>` 即插件标识，对应 `DEBIAN_OVERLAYS` 中的一个条目（如 `base`、`console`、`firstboot`、`firstboot-info`、`network`）。
- `resolve_debian_overlays` 校验 `<name>/plugin.sh` 必须存在，未知名字直接报错。
- `all` 展开为 `debian_known_overlay_names()` 的全部（按目录名排序）；`none`/`off`/`-` 表示无插件。

### 固件说明

静态固件放 `overlay/lib/firmware/`；动态固件（如从 `.deb` 解包）在 `plugin_apply` 内写入 `root_dir`，不应进 git。板级硬件固件应放 `boards/<BOARD>/rootfs/`（始终应用），而非此处可选插件。

## plugin.sh 接口契约

```bash
#!/usr/bin/env bash
# 单行描述。

plugin_apply() {
    local root_dir="$1"
    # 拷贝静态树
    apply_rootfs_overlay_tree "${root_dir}" "$(dirname "${BASH_SOURCE[0]}")/overlay"
    # 启用 systemd unit（用 common.sh 的 enable_unit 或手写 [Install] 软链）
    # 写配置文件、展开模板等
}
```

规则：

- `plugin.sh` **必须**定义 `plugin_apply(root_dir)`；否则 `run_debian_overlay_plugins` 报错。
- 可调用 `common.sh` 的 `apply_rootfs_overlay_tree`、`expand_overlay_template_text`、`enable_unit`、`log_info`、`log_warn`。
- 静态 `overlay/` 内的 `*.in` 文件在拷贝时按 `@PLACEHOLDER@` 展开（见 `rootfs/debian/README.md` 的 Templates）。
- 符号链接会被保留（`apply_rootfs_overlay_tree` 区分文件/符号链接）。
- **不要**在插件里安装 APT 包——包只经 `DEBIAN_PACKAGES`。
- 构建容器以只读挂载 `rootfs/`：不要回写本目录。

## 新增插件 Checklist

1. 在 `rootfs/debian/overlays/<name>/` 建 `plugin.sh`（定义 `plugin_apply`）。
2. 需要静态文件则放 `overlay/`，需要模板则放 `*.in`。
3. 用 `make check`（其 `check_debian_packages` 会校验插件文件存在且网络/基础契约满足）验证。
4. 在 `DEBIAN_OVERLAYS` / `DEBIAN_OVERLAYS_DEFAULT` 中引用该名字。

## 现有插件索引

| 插件 | 作用 |
|---|---|
| `base` | SSH（`ssh.service` 启用、缺失 host key 自动生成）、udev、systemd-resolved（非 Debian 11）、基础权限 |
| `console` | 为板级串口（`CONSOLE` 设备段）写 `serial-getty@<dev>.service.d/10-baud.conf`（`--keep-baud <speed>,115200`）并 enable getty |
| `firstboot` | 安装 `sbc-firstboot` 与 `sbc-firstboot.service`，首启 `growpart` + `resize2fs` 扩容根分区 |
| `firstboot-info` | 安装 `sbc-firstboot-info`（由 `sbc-firstboot` 首启调用），打印 banner / MOTD |
| `network` | 按是否安装 `NetworkManager` 二进制自适应：有则启用 `NetworkManager.service` 并写 `10-sbc.conf`（含 `wifi.scan-rand-mac-address=no`），否则启用 `systemd-networkd.service`（写 `20-wired.network`）；二者互斥 |
