#!/usr/bin/env bash
# Network stack plugin: detect installed packages and apply matching overlay + enables.
# No feature tokens. If NetworkManager is present, prefer it; else systemd-networkd.

plugin_apply() {
    local root_dir="$1"
    local plugin_dir
    plugin_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/network"

    if [ -f "${root_dir}/usr/sbin/NetworkManager" ]; then
        log_info "Plugin network: NetworkManager present; applying NM overlay"
        apply_rootfs_overlay_tree "${root_dir}" "${plugin_dir}/overlay-nm"
        log_info "Plugin network: enabling NetworkManager.service"
        enable_unit NetworkManager.service
        # Avoid dual-stack IP conflicts with networkd.
        rm -f "${root_dir}/etc/systemd/system/multi-user.target.wants/systemd-networkd.service"
        rm -f "${root_dir}/etc/systemd/system/sockets.target.wants/systemd-networkd.socket"
    else
        log_info "Plugin network: no NetworkManager; applying systemd-networkd overlay"
        apply_rootfs_overlay_tree "${root_dir}" "${plugin_dir}/overlay-networkd"
        log_info "Plugin network: enabling systemd-networkd.service"
        enable_unit systemd-networkd.service
    fi
}
