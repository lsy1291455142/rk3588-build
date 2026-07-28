#!/usr/bin/env bash
# 'base' overlay verification.
# Sourced by scripts/verify_image.sh; defines overlay_verify() which must use
# only the generic rf_* helpers and must not assume any other overlay exists.
overlay_verify() {
    rf_cat /etc/systemd/system/ssh.service.d/10-hostkeys.conf | grep -Fq 'ExecStartPre=/usr/bin/ssh-keygen -A' ||
        die "Debian SSH service does not generate missing host keys"
    rf_exists /etc/systemd/system/multi-user.target.wants/ssh.service ||
        die "Debian rootfs does not enable ssh.service"
    if [ "${DEBIAN_RELEASE}" != "11" ]; then
        rf_exists /etc/systemd/system/sysinit.target.wants/systemd-resolved.service ||
            die "Debian rootfs does not enable systemd-resolved.service"
    fi
}
