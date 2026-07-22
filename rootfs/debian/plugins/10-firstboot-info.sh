#!/usr/bin/env bash
# Optional first-boot board banner / MOTD plugin.
# Enabled by default. Set DEBIAN_FIRSTBOOT_INFO=no to skip.

plugin_apply() {
    local root_dir="$1"
    local enabled="${DEBIAN_FIRSTBOOT_INFO:-yes}"
    local plugin_dir
    plugin_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/firstboot-info"

    enabled="$(printf '%s' "${enabled}" | tr '[:upper:]' '[:lower:]')"
    case "${enabled}" in
        no|false|0|off|-)
            log_info "Plugin firstboot-info: disabled (DEBIAN_FIRSTBOOT_INFO=${DEBIAN_FIRSTBOOT_INFO:-})"
            return 0
            ;;
    esac

    log_info "Plugin firstboot-info: applying overlay"
    apply_rootfs_overlay_tree "${root_dir}" "${plugin_dir}/overlay"
}
