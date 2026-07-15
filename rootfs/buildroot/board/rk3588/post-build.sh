#!/usr/bin/env bash
set -Eeuo pipefail

TARGET_DIR="${1:?target directory is required}"
KERNEL_MODULES_TAR="${KERNEL_MODULES_TAR:?kernel modules archive is required}"
TARGET_USERNAME="${TARGET_USERNAME:?target username is required}"

tar --no-same-owner -xf "${KERNEL_MODULES_TAR}" -C "${TARGET_DIR}"

install -d "${TARGET_DIR}/etc/sudoers.d" "${TARGET_DIR}/var/lib"
printf '%s ALL=(ALL) ALL\n' "${TARGET_USERNAME}" \
    >"${TARGET_DIR}/etc/sudoers.d/90-rk3588"
chmod 0440 "${TARGET_DIR}/etc/sudoers.d/90-rk3588"
chmod 0755 "${TARGET_DIR}/etc/init.d/S02rootfs-resize"
chmod 0755 "${TARGET_DIR}/etc/init.d/S40network"
