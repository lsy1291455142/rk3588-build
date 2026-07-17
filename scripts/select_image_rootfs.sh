#!/usr/bin/env bash
set -Eeuo pipefail

OUTPUT_DIR="${1:?output directory is required}"
BOARD="${2:?board is required}"
DEBIAN_RELEASE="${3:?Debian release is required}"

BUILDROOT_IMAGE="${OUTPUT_DIR}/${BOARD}/buildroot/rootfs.ext4"
DEBIAN_IMAGE="${OUTPUT_DIR}/${BOARD}/debian-${DEBIAN_RELEASE}/rootfs.ext4"

if [ -f "${BUILDROOT_IMAGE}" ] && [ -f "${DEBIAN_IMAGE}" ]; then
    printf '%s\n' \
        "ERROR: Both Buildroot and Debian ${DEBIAN_RELEASE} root filesystems exist for ${BOARD}." \
        "Specify ROOTFS=buildroot or ROOTFS=debian explicitly." >&2
    exit 2
fi

if [ -f "${BUILDROOT_IMAGE}" ]; then
    printf '%s\n' buildroot
    exit 0
fi

if [ -f "${DEBIAN_IMAGE}" ]; then
    printf '%s\n' debian
    exit 0
fi

printf '%s\n' \
    "ERROR: No root filesystem is available for ${BOARD}." \
    "Expected one of:" \
    "  ${BUILDROOT_IMAGE}" \
    "  ${DEBIAN_IMAGE}" \
    "Run 'make build-rootfs ROOTFS=buildroot' or 'make build-rootfs ROOTFS=debian' first." >&2
exit 1
