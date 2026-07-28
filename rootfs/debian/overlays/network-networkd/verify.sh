#!/usr/bin/env bash
# 'network-networkd' overlay verification. Sourced by scripts/verify_image.sh.
overlay_verify() {
    rf_exists /etc/systemd/system/multi-user.target.wants/systemd-networkd.service ||
        die "Debian rootfs does not enable systemd-networkd"
    if rf_exists /etc/systemd/system/multi-user.target.wants/NetworkManager.service; then
        die "Debian systemd-networkd rootfs must not enable NetworkManager"
    fi
}
