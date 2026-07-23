#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

load_board_profile
validate_board_source_revisions
ROOTFS=debian
resolve_debian_release

require_cmd cp python3 qemu-system-aarch64 realpath

COMMON_OUTPUT="$(board_common_output_dir)"
VARIANT_OUTPUT="$(variant_output_dir)"
IMAGE_PATH="${VARIANT_OUTPUT}/$(image_stem).img"
KERNEL_IMAGE="${COMMON_OUTPUT}/Image"
KERNEL_RELEASE_FILE="${COMMON_OUTPUT}/kernel-release"
IMAGE_METADATA="${VARIANT_OUTPUT}/image-build-info.txt"
QEMU_OUTPUT="${VARIANT_OUTPUT}/qemu-smoke"
QEMU_DISK="${QEMU_OUTPUT}/disk.img"
ROOTFS_USERNAME="${ROOTFS_USERNAME:-rk3588}"
ROOTFS_PASSWORD="${ROOTFS_PASSWORD:-rk3588}"
QEMU_TIMEOUT="${QEMU_TIMEOUT:-600}"
QEMU_MEMORY_MIB="${QEMU_MEMORY_MIB:-1024}"
QEMU_CPUS="${QEMU_CPUS:-2}"

validate_rootfs_credentials
for value_name in QEMU_TIMEOUT QEMU_MEMORY_MIB QEMU_CPUS; do
    value="${!value_name}"
    is_positive_integer "${value}" || die "${value_name} must be a positive integer"
done

require_file "${IMAGE_PATH}" "Debian disk image; run make build-all first"
require_file "${KERNEL_IMAGE}" "kernel Image"
require_file "${KERNEL_RELEASE_FILE}" "kernel release"
require_file "${IMAGE_METADATA}" "image build metadata"

[ "$(metadata_value "${IMAGE_METADATA}" rootfs)" = "debian" ] ||
    die "Image metadata is not for Debian"
[ "$(metadata_value "${IMAGE_METADATA}" debian_release)" = "${DEBIAN_RELEASE}" ] ||
    die "Image metadata is not for Debian ${DEBIAN_RELEASE}"

ROOTFS_MODE="$(metadata_value "${IMAGE_METADATA}" rootfs_mode)"
ROOTFS_MODE="${ROOTFS_MODE:-rw-ext4}"
INITRD_IMAGE="${VARIANT_OUTPUT}/initrd.img"
if [ "${ROOTFS_MODE}" = "ro-overlay" ]; then
    require_file "${INITRD_IMAGE}" "initramfs; run make build-all first"
fi

safe_reset_dir "${QEMU_OUTPUT}" "${VARIANT_OUTPUT}"
trap 'rm -f -- "${QEMU_DISK}"' EXIT
cp --reflink=auto --sparse=always "${IMAGE_PATH}" "${QEMU_DISK}"

QEMU_EXTRA_ARGS=()
if [ "${ROOTFS_MODE}" = "ro-overlay" ]; then
    QEMU_EXTRA_ARGS+=(--initrd "${INITRD_IMAGE}")
fi
QEMU_EXTRA_ARGS+=(--rootfs-mode "${ROOTFS_MODE}")

log_step "Booting Debian ${DEBIAN_RELEASE} (${ROOTFS_MODE}) with the built kernel and full GPT image"
python3 "${SCRIPT_DIR}/lib/qemu_smoke.py" \
    --qemu qemu-system-aarch64 \
    --kernel "${KERNEL_IMAGE}" \
    --disk "${QEMU_DISK}" \
    "${QEMU_EXTRA_ARGS[@]}" \
    --kernel-release "$(cat "${KERNEL_RELEASE_FILE}")" \
    --debian-release "${DEBIAN_RELEASE}" \
    --username "${ROOTFS_USERNAME}" \
    --password "${ROOTFS_PASSWORD}" \
    --timeout "${QEMU_TIMEOUT}" \
    --memory-mib "${QEMU_MEMORY_MIB}" \
    --cpus "${QEMU_CPUS}" \
    --serial-log "${QEMU_OUTPUT}/serial.log" \
    --ssh-log "${QEMU_OUTPUT}/ssh.log" \
    --result "${QEMU_OUTPUT}/result.txt"

log_info "QEMU Debian smoke test passed: ${QEMU_OUTPUT}/result.txt"
