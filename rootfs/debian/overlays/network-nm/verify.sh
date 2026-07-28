#!/usr/bin/env bash
# 'network-nm' overlay verification. Sourced by scripts/verify_image.sh.
overlay_verify() {
    rf_exists /etc/systemd/system/multi-user.target.wants/NetworkManager.service ||
        die "Debian rootfs does not enable NetworkManager"
    if rf_exists /etc/systemd/system/multi-user.target.wants/systemd-networkd.service; then
        die "Debian NetworkManager rootfs must not enable systemd-networkd"
    fi
}
