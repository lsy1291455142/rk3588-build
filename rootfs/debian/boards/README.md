# Board Debian plugins

Board-local attachments for Debian rootfs. Same spirit as
`rootfs/debian/overlays/`, but **always applied** when `BOARD` matches a
directory here (no `DEBIAN_OVERLAYS` selection).

## Directory structure

```text
boards/<BOARD>/
├── plugin.sh              # optional: export board_plugin_apply(root_dir)
├── overlay/               # optional: static file tree
│   └── ...                #   supports *.in templates; symlinks preserved
├── lib-*.sh               # optional: board-local helpers
├── packages/              # optional: local .deb cache (gitignored)
└── README.md              # optional: board notes
```

`<BOARD>` must match `configs/boards/<BOARD>.conf` / the active `BOARD` value.

## plugin.sh contract

```bash
#!/usr/bin/env bash
# One-line description.

board_plugin_apply() {
    local root_dir="$1"
    local self_dir
    self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # 1. Optional prep (extract/remap local debs into overlay/, etc.)
    # stage_something "${self_dir}"

    # 2. Apply static tree
    if [ -d "${self_dir}/overlay" ]; then
        apply_rootfs_overlay_tree "${root_dir}" "${self_dir}/overlay"
    fi

    # 3. Optional enable_unit / other layout tweaks
}
```

**Rules:**
- If `plugin.sh` exists, it **must** define `board_plugin_apply()`
- May call `apply_rootfs_overlay_tree`, `expand_overlay_template_text`,
  `enable_unit`, `log_info`, `log_warn` from `common.sh`
- **Do not** install APT packages here — packages only via `DEBIAN_PACKAGES`
- Prefer board-local logic over new core Makefile knobs
- Large binaries stay out of git (stage/cache under `packages/` or gitignore)

## Static-only boards

If the board only needs static files, omit `plugin.sh` and provide `overlay/`.
Core copies that tree automatically.

## Apply order

1. Board plugin / board static overlay
2. Selected optional overlays (`DEBIAN_OVERLAYS` list order)

Later files at the same relative path overwrite earlier ones.

## Existing boards

| Board | Notes |
|---|---|
| `rk3588s-cokepi-model-lp4-v10` | AIC8800D80 firmware stage + vendor links |

## Checklist for a new board plugin

1. Create `boards/<BOARD>/` matching the profile name
2. Add `plugin.sh` and/or `overlay/`
3. Keep blobs out of git; document stage/cache in board `README.md`
4. Extend `scripts/check.sh` if the board needs contract tests
