#!/usr/bin/env bash
# Network stack overlay: detect packages already installed, apply matching conf + enables.

plugin_apply() {
    local root_dir="$1"
    local self_dir
    self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    if [ -f "${root_dir}/usr/sbin/NetworkManager" ]; then
        log_info "Overlay network: NetworkManager present"
        apply_rootfs_overlay_tree "${root_dir}" "${self_dir}/overlay-nm"
        enable_unit NetworkManager.service
        rm -f "${root_dir}/etc/systemd/system/multi-user.target.wants/systemd-networkd.service"
        rm -f "${root_dir}/etc/systemd/system/sockets.target.wants/systemd-networkd.socket"
    else
        log_info "Overlay network: using systemd-networkd"
        apply_rootfs_overlay_tree "${root_dir}" "${self_dir}/overlay-networkd"
        enable_unit systemd-networkd.service
    fi
}
