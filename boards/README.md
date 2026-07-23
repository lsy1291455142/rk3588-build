# Board Debian plugins

板级 Debian rootfs 附件，与 `rootfs/debian/overlays/` 的「可选 overlay 插件」同源但**始终应用**：只要 `BOARD` 匹配 `boards/<BOARD>/` 目录（不论 `DEBIAN_OVERLAYS` 如何选择），就在构建 Debian rootfs 时生效。

## 目录结构

```text
boards/<BOARD>/
├── board.conf            # 板型配置（必需）
├── kernel.config         # 板级内核 fragment（build_kernel.sh 自动合并，可选）
├── board.hooks.sh        # 构建各阶段钩子（可选）
├── check.sh              # 板级自检钩子 board_check()（可选）
├── rootfs/
│   ├── plugin.sh         # 可选：定义 board_plugin_apply(root_dir)
│   ├── overlay/          # 可选：静态文件树
│   │   ├── lib/firmware/...   # 板级静态固件
│   │   └── etc/...            # 支持 *.in 模板；符号链接保留
│   ├── lib-*.sh          # 可选：板级辅助脚本
│   ├── packages/         # 可选：本地 .deb 缓存（建议 gitignore）
│   └── README.md         # 可选：板级说明
└── ...
```

静态固件（`.bin` / `.fw` 等）直接放 `overlay/lib/firmware/`；动态固件（如从 `.deb` 解包）在 `board_plugin_apply()` 内从 `packages/` 或运行期生成。

`<BOARD>` 必须与 `boards/<BOARD>/board.conf` 及当前 `BOARD` 一致。

## plugin.sh 契约

```bash
#!/usr/bin/env bash
# 单行描述。

board_plugin_apply() {
    local root_dir="$1"
    local self_dir
    self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # 1. 先应用静态树（只读板级 checkout 即可）
    if [ -d "${self_dir}/overlay" ]; then
        apply_rootfs_overlay_tree "${root_dir}" "${self_dir}/overlay"
    fi

    # 2. 可选：仅写入 root_dir 的预处理（解包本地 deb 等）
    # install_something_into_rootfs "${root_dir}" "${self_dir}"

    # 3. 可选：enable_unit / 其它布局调整
}
```

规则：

- 存在 `plugin.sh` 则**必须**定义 `board_plugin_apply()`；否则核心自动拷贝 `overlay/` 静态树。
- 可调用 `common.sh` 的 `apply_rootfs_overlay_tree`、`expand_overlay_template_text`、`enable_unit`、`log_info`、`log_warn`。
- **不得**在 plugin 内安装 APT 包——包只经 `DEBIAN_PACKAGES`。
- 优先板级逻辑而非新增核心 Makefile 旋钮。
- 大二进制不进 git（`packages/*.deb` 或 gitignored 的 overlay blob）。
- 构建容器以只读挂载 `rootfs/`：永远不要从 `board_plugin_apply` 回写板级树。

## 应用顺序

1. 板级 plugin / 板级静态 overlay（始终）
2. 选中的可选 overlay（`DEBIAN_OVERLAYS` 列表顺序）

相同相对路径的后续文件覆盖先前文件。

## 现有板级 plugin

| 板型 | 说明 |
|---|---|
| `rk3588s-cokepi-model-lp4-v10` | AIC8800D80 固件从 `packages/` 安装 + vendor 固件符号链接（需先 `stage-aic8800-firmware.sh`） |

## 新增板级 plugin 检查清单

1. 创建与 profile 同名的 `boards/<BOARD>/`。
2. 添加 `plugin.sh` 和/或 `overlay/`。
3. 大二进制移出 git；在板级 `README.md` 说明 staged/cache 方式。
4. 若板级需要契约测试，扩展 `scripts/check.sh` 的板级 `check.sh` 钩子（`board_check`）。
