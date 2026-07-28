#!/usr/bin/env bash
# 'firstboot-info' overlay verification. Sourced by scripts/verify_image.sh.
overlay_verify() {
    rf_exists /usr/local/sbin/sbc-firstboot-info ||
        die "Debian rootfs with the firstboot-info overlay lacks sbc-firstboot-info"
}
