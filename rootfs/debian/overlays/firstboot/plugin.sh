#!/usr/bin/env bash
# First-boot rootfs grow/resize oneshot.

plugin_apply() {
    local root_dir="$1"
    local self_dir
    self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    apply_rootfs_overlay_tree "${root_dir}" "${self_dir}/overlay"
    if [ -f "${root_dir}/etc/systemd/system/sbc-firstboot.service" ]; then
        enable_unit sbc-firstboot.service
    fi
}
