#!/usr/bin/env bash
# 'console' overlay verification. Sourced by scripts/verify_image.sh.
overlay_verify() {
    local cs
    cs="${CONSOLE#*,}"
    cs="${cs%%[!0-9]*}"
    rf_cat /etc/systemd/system/serial-getty@"${CONSOLE%%,*}".service.d/10-baud.conf |
        grep -Fq -- "--keep-baud ${cs},115200" ||
        die "Debian serial getty does not preserve the board console speed"
    rf_exists /etc/systemd/system/getty.target.wants/serial-getty@"${CONSOLE%%,*}".service ||
        die "Debian rootfs does not enable serial-getty@${CONSOLE%%,*}.service"
}
