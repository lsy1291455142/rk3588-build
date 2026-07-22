# Overlay 插件开发规范

本目录包含 Debian rootfs 的可选功能插件。每个插件由 `DEBIAN_OVERLAYS`
选择，按列表顺序执行。

## 目录结构约定

```
overlays/<name>/
├── plugin.sh              # 必须：导出 plugin_apply(root_dir)
├── overlay/               # 推荐：静态文件树（自动复制到 rootfs 对应路径）
│   ├── etc/...            #   支持 *.in 模板（@BOARD@ 等占位符自动展开）
│   └── lib/firmware/...   #   硬件固件存放点（自动安装到 /lib/firmware/）
├── lib.sh                 # 可选：复杂逻辑拆分到库文件
└── README.md              # 可选：插件说明
```

### 命名规则与固件说明

| 情况 | 目录名 | 说明 |
|------|--------|------|
| 默认文件 | `overlay/` | 静态文件树，用 `apply_rootfs_overlay_tree` 应用 |
| 条件分支 | `overlay-<variant>/` | 运行时选择不同子树（如 `network` 的 NM vs networkd） |
| 硬件固件 | `overlay/lib/firmware/` | 任何静态固件文件（`.bin` / `.fw` 等）直接放入此路径 |

**不要**使用 `templates/`、`files/` 等非标准目录名放静态文件。模板文件（`.in`
后缀）直接放在 `overlay/` 中即可——`apply_rootfs_overlay_tree` 会自动检测并展开。例如自定义驱动固件可直接放置于 `overlay/lib/firmware/my_driver.bin`。

## plugin.sh 接口契约

```bash
#!/usr/bin/env bash
# 一行描述插件功能。

plugin_apply() {
    local root_dir="$1"
    local self_dir
    self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # 1. 应用静态文件树
    apply_rootfs_overlay_tree "${root_dir}" "${self_dir}/overlay"

    # 2. 启用 systemd 服务（如需要）
    enable_unit my-service.service

    # 3. 其他运行时逻辑
}
```

**规则：**
- 必须定义 `plugin_apply()` 函数（调用者会 `source plugin.sh` 后检查）
- 可调用 `apply_rootfs_overlay_tree`、`expand_overlay_template_text`、
  `enable_unit`、`log_info`、`log_warn` 等 `common.sh` 中的公共函数
- **不要**在插件中安装 APT 包——包管理只通过 `DEBIAN_PACKAGES`
- 复杂逻辑拆分到 `lib.sh`（通过 `source "${self_dir}/lib.sh"` 引入）

## 新增插件 Checklist

1. 创建 `overlays/<name>/plugin.sh`（实现 `plugin_apply`）
2. 如需静态文件，放入 `overlays/<name>/overlay/` 目录
3. 在板级配置 `DEBIAN_OVERLAYS_DEFAULT` 中按需添加
4. 在 `docs/usage/debian-features.md` 的插件表格中添加说明
5. 在 `check.sh` 中添加对应测试用例

## 现有插件索引

| 插件 | 功能 | 静态文件 |
|------|------|----------|
| `base` | SSH 配置、udev GPU 权限、resolved | `overlay/` |
| `console` | 串口 getty 波特率 drop-in | `overlay/` (模板) |
| `firstboot` | 首次启动 rootfs 扩容 | `overlay/` |
| `firstboot-info` | MOTD / 首次启动 banner | `overlay/` (模板) |
| `network` | NM / networkd 自适应网络配置 | `overlay-nm/`, `overlay-networkd/` |
