#!/usr/bin/env bash
# Optional first-boot board banner / MOTD (depends on firstboot helper if present).

plugin_apply() {
    local root_dir="$1"
    local self_dir
    self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    apply_rootfs_overlay_tree "${root_dir}" "${self_dir}/overlay"
}
