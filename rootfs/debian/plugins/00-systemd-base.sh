#!/usr/bin/env bash
# Base systemd service setup plugin for SBC Debian images.

plugin_apply() {
    local root_dir="$1"
    enable_unit ssh.service
    enable_unit sbc-firstboot.service
    if [ -n "${CONSOLE_DEVICE:-}" ]; then
        enable_unit "serial-getty@${CONSOLE_DEVICE}.service"
    fi
    if [ "${DEBIAN_RELEASE:-13}" != "11" ]; then
        enable_unit systemd-resolved.service
    fi
}
