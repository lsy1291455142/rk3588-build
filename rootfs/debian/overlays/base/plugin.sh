#!/usr/bin/env bash
# Optional lab/base convenience overlay: ssh password/root login, hostkey prep, udev GPU perms.

plugin_apply() {
    local root_dir="$1"
    local self_dir
    self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    apply_rootfs_overlay_tree "${root_dir}" "${self_dir}/overlay"

    if [ -f "${root_dir}/lib/systemd/system/ssh.service" ] ||
        [ -f "${root_dir}/usr/lib/systemd/system/ssh.service" ]; then
        enable_unit ssh.service
    fi
    if [ "${DEBIAN_RELEASE:-13}" != "11" ] &&
        { [ -f "${root_dir}/lib/systemd/system/systemd-resolved.service" ] ||
            [ -f "${root_dir}/usr/lib/systemd/system/systemd-resolved.service" ]; }; then
        enable_unit systemd-resolved.service
    fi
}
