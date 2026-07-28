#!/usr/bin/env bash
# 'firstboot' overlay verification. Sourced by scripts/verify_image.sh.
overlay_verify() {
    rf_cat /usr/local/sbin/sbc-firstboot | grep -Fq "sgdisk -e \"\$rootdisk\"" ||
        die "Debian rootfs lacks the first-boot GPT repair"
    rf_cat /usr/local/sbin/sbc-firstboot | grep -Fq "partnum=\"\$(cat \"\$sys_block/partition\")\"" ||
        die "Debian rootfs does not derive the root partition from sysfs"
    rf_cat /usr/local/sbin/sbc-firstboot | grep -Fq "growpart \"\$rootdisk\" \"\$partnum\"" ||
        die "Debian rootfs lacks the first-boot partition growth"
    rf_cat /usr/local/sbin/sbc-firstboot | grep -Fq "resize2fs \"\$rootdev\"" ||
        die "Debian rootfs lacks the first-boot filesystem growth"
    rf_cat /etc/systemd/system/sbc-firstboot.service | grep -Fq 'WantedBy=multi-user.target' ||
        die "Debian rootfs lacks the first-boot resize service"
    if rf_cat /etc/systemd/system/sbc-firstboot.service | grep -Fq 'Before=ssh.service'; then
        die "Debian first-boot resize must not block SSH startup"
    fi
    rf_cat /etc/systemd/system/sbc-firstboot.service | grep -Fq 'TimeoutStartSec=10min' ||
        die "Debian first-boot resize service lacks a startup timeout"
    rf_cat /etc/systemd/system/sbc-firstboot.service | grep -Fq 'ExecStart=-/usr/local/sbin/sbc-firstboot' ||
        die "Debian first-boot resize failure can degrade system startup"
    rf_exists /etc/systemd/system/multi-user.target.wants/sbc-firstboot.service ||
        die "Debian rootfs does not enable sbc-firstboot.service"
    rf_exists /usr/sbin/sgdisk || die "Debian rootfs lacks sgdisk"
    rf_exists /usr/bin/growpart || die "Debian rootfs lacks growpart"
    # The firstboot script may optionally invoke firstboot-info; only assert
    # the linkage when firstboot-info is also part of the built image.
    if overlay_enabled firstboot-info || rf_exists /usr/local/sbin/sbc-firstboot-info; then
        rf_cat /usr/local/sbin/sbc-firstboot | grep -Fq 'sbc-firstboot-info' ||
            die "Debian firstboot does not optionally invoke firstboot-info"
    fi
}
