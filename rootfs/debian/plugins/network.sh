#!/usr/bin/env bash
# Network stack setup plugin. Automatically handles NetworkManager vs systemd-networkd.

plugin_apply() {
    local root_dir="$1"
    if [ "${DEBIAN_HAS_NM:-0}" = "1" ] || [ -f "${root_dir}/usr/sbin/NetworkManager" ]; then
        log_info "Plugin network: Enabling NetworkManager.service"
        enable_unit NetworkManager.service
        # Disable systemd-networkd to avoid IP/interface conflict
        rm -f "${root_dir}/etc/systemd/system/multi-user.target.wants/systemd-networkd.service"
    else
        log_info "Plugin network: Enabling systemd-networkd.service"
        enable_unit systemd-networkd.service
    fi
}
