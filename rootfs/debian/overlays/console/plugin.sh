#!/usr/bin/env bash
# Serial console: baud drop-in + enable serial-getty@CONSOLE_DEVICE.

plugin_apply() {
    local root_dir="$1"
    local self_dir template dest content
    self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    [ -n "${CONSOLE_DEVICE:-}" ] || {
        log_warn "Overlay console: CONSOLE_DEVICE empty; skip"
        return 0
    }
    [ -n "${CONSOLE_SPEED:-}" ] || {
        log_warn "Overlay console: CONSOLE_SPEED empty; skip"
        return 0
    }

    template="${self_dir}/overlay/serial-getty-baud.conf.in"
    if [ -f "${template}" ]; then
        dest="${root_dir}/etc/systemd/system/serial-getty@${CONSOLE_DEVICE}.service.d/10-baud.conf"
        mkdir -p "$(dirname "${dest}")"
        content="$(cat "${template}")"
        expand_overlay_template_text "${content}" >"${dest}"
        chmod 0644 "${dest}"
    fi
    enable_unit "serial-getty@${CONSOLE_DEVICE}.service"
}
