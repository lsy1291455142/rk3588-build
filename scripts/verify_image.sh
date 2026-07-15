#!/usr/bin/env bash
set -Eeuo pipefail

export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

load_board_profile
validate_rootfs_choice
if [ "${ROOTFS}" = "debian" ]; then
    resolve_debian_release
fi

require_cmd sgdisk stat dd cmp mdir mcopy grep awk sed sha256sum \
    blkid e2fsck debugfs realpath

COMMON_OUTPUT="$(board_common_output_dir)"
VARIANT_OUTPUT="$(variant_output_dir)"
IMAGE_STEM="$(image_stem)"
IMAGE_PATH="${IMAGE_PATH:-${VARIANT_OUTPUT}/${IMAGE_STEM}.img}"
SHA256_PATH="${VARIANT_OUTPUT}/${IMAGE_STEM}.sha256"
KERNEL_IMAGE="${COMMON_OUTPUT}/Image"
DTB_IMAGE="${COMMON_OUTPUT}/${KERNEL_DTB}"
LOADER_IMAGE="${COMMON_OUTPUT}/loader.bin"
UBOOT_IMAGE="${COMMON_OUTPUT}/uboot.img"
ROOTFS_IMAGE="${VARIANT_OUTPUT}/rootfs.ext4"
KERNEL_RELEASE_FILE="${COMMON_OUTPUT}/kernel-release"
ROOTFS_USERNAME="${ROOTFS_USERNAME:-rk3588}"

require_file "${IMAGE_PATH}" "raw disk image"
require_file "${SHA256_PATH}" "image checksum file"
require_file "${KERNEL_IMAGE}" "kernel Image"
require_file "${DTB_IMAGE}" "board DTB"
require_file "${LOADER_IMAGE}" "loader.bin"
require_file "${UBOOT_IMAGE}" "uboot.img"
require_file "${ROOTFS_IMAGE}" "rootfs.ext4"
require_file "${KERNEL_RELEASE_FILE}" "kernel release"

WORK_DIR="$(mktemp -d "${VARIANT_OUTPUT}/.image-verify.XXXXXX")"
trap 'rm -rf -- "${WORK_DIR}"' EXIT

IMAGE_SECTORS=$((IMAGE_SIZE_MIB * 2048))
BOOT_FIRST_EXPECTED=$((BOOT_START_MIB * 2048))
BOOT_LAST_EXPECTED=$((BOOT_FIRST_EXPECTED + BOOT_SIZE_MIB * 2048 - 1))
ROOT_FIRST_EXPECTED=$((BOOT_LAST_EXPECTED + 1))
ROOT_LAST_EXPECTED=$((IMAGE_SECTORS - 34))
IMAGE_BYTES_EXPECTED=$((IMAGE_SIZE_MIB * 1024 * 1024))

[ "$(stat -c '%s' "${IMAGE_PATH}")" -eq "${IMAGE_BYTES_EXPECTED}" ] ||
    die "Unexpected image size: ${IMAGE_PATH}"
sgdisk --verify "${IMAGE_PATH}" >/dev/null

partition_field() {
    local partition="$1"
    local field="$2"
    sgdisk --info="${partition}" "${IMAGE_PATH}" |
        awk -F: -v wanted="${field}" '
            $1 == wanted {
                value = $2
                sub(/^[[:space:]]+/, "", value)
                print value
                exit
            }'
}

first_sector() {
    partition_field "$1" "First sector" | awk '{print $1}'
}

last_sector() {
    partition_field "$1" "Last sector" | awk '{print $1}'
}

partition_code() {
    partition_field "$1" "Partition GUID code" | awk '{print $1}'
}

partition_name() {
    partition_field "$1" "Partition name" | sed "s/^'//;s/'$//"
}

[ "$(first_sector 1)" = "${BOOT_FIRST_EXPECTED}" ] ||
    die "Boot partition starts at the wrong sector"
[ "$(last_sector 1)" = "${BOOT_LAST_EXPECTED}" ] ||
    die "Boot partition ends at the wrong sector"
[ "$(partition_code 1)" = "0700" ] ||
    die "Boot partition type is not 0700"
[ "$(partition_name 1)" = "boot" ] ||
    die "Boot partition name is not boot"
[ "$(first_sector 2)" = "${ROOT_FIRST_EXPECTED}" ] ||
    die "Root partition starts at the wrong sector"
[ "$(last_sector 2)" = "${ROOT_LAST_EXPECTED}" ] ||
    die "Root partition ends at the wrong sector"
[ "$(partition_code 2)" = "8300" ] ||
    die "Root partition type is not 8300"
[ "$(partition_name 2)" = "rootfs" ] ||
    die "Root partition name is not rootfs"

extract_bytes() {
    local source="$1"
    local destination="$2"
    local offset="$3"
    local count="$4"
    dd if="${source}" of="${destination}" bs=4M \
        iflag=skip_bytes,count_bytes skip="${offset}" count="${count}" \
        conv=sparse status=none
}

compare_embedded_file() {
    local expected="$1"
    local sector="$2"
    local extracted="$3"
    local size
    size="$(stat -c '%s' "${expected}")"
    extract_bytes "${IMAGE_PATH}" "${extracted}" "$((sector * 512))" "${size}"
    cmp --silent "${expected}" "${extracted}" ||
        die "Embedded data does not match $(basename "${expected}")"
}

compare_embedded_file "${LOADER_IMAGE}" "${LOADER_SECTOR}" "${WORK_DIR}/loader.bin"
compare_embedded_file "${UBOOT_IMAGE}" "${UBOOT_SECTOR}" "${WORK_DIR}/uboot.img"

BOOT_OFFSET=$((BOOT_FIRST_EXPECTED * 512))
MTOOLS_IMAGE="${IMAGE_PATH}@@${BOOT_OFFSET}"
mdir -i "${MTOOLS_IMAGE}" :: >/dev/null
mcopy -i "${MTOOLS_IMAGE}" ::/Image "${WORK_DIR}/Image"
mcopy -i "${MTOOLS_IMAGE}" "::/${KERNEL_DTB}" "${WORK_DIR}/${KERNEL_DTB}"
mcopy -i "${MTOOLS_IMAGE}" ::/extlinux/extlinux.conf "${WORK_DIR}/extlinux.conf"
cmp --silent "${KERNEL_IMAGE}" "${WORK_DIR}/Image" ||
    die "FAT Image does not match the kernel artifact"
cmp --silent "${DTB_IMAGE}" "${WORK_DIR}/${KERNEL_DTB}" ||
    die "FAT DTB does not match the board artifact"
grep -Fqx "    FDT /${KERNEL_DTB}" "${WORK_DIR}/extlinux.conf" ||
    die "extlinux.conf does not select ${KERNEL_DTB}"
grep -Fq "root=LABEL=rootfs rootwait rw" "${WORK_DIR}/extlinux.conf" ||
    die "extlinux.conf does not boot root=LABEL=rootfs"
grep -Fq "console=${CONSOLE}" "${WORK_DIR}/extlinux.conf" ||
    die "extlinux.conf does not configure ${CONSOLE}"

ROOTFS_BYTES="$(stat -c '%s' "${ROOTFS_IMAGE}")"
extract_bytes "${IMAGE_PATH}" "${WORK_DIR}/rootfs.ext4" \
    "$((ROOT_FIRST_EXPECTED * 512))" "${ROOTFS_BYTES}"
cmp --silent "${ROOTFS_IMAGE}" "${WORK_DIR}/rootfs.ext4" ||
    die "Embedded rootfs does not match rootfs.ext4"
e2fsck -fn "${WORK_DIR}/rootfs.ext4" >/dev/null
[ "$(blkid -s LABEL -o value "${WORK_DIR}/rootfs.ext4")" = "rootfs" ] ||
    die "Embedded root filesystem label is not rootfs"

KERNEL_RELEASE="$(cat "${KERNEL_RELEASE_FILE}")"
debugfs -R "stat /lib/modules/${KERNEL_RELEASE}" \
    "${WORK_DIR}/rootfs.ext4" 2>&1 | grep -q 'Inode:' ||
    die "Embedded rootfs lacks modules for ${KERNEL_RELEASE}"
debugfs -R "cat /etc/passwd" "${WORK_DIR}/rootfs.ext4" 2>/dev/null |
    grep -q "^${ROOTFS_USERNAME}:" ||
    die "Embedded rootfs lacks user ${ROOTFS_USERNAME}"
debugfs -R "cat /etc/shadow" "${WORK_DIR}/rootfs.ext4" 2>/dev/null |
    grep -Eq '^root:[!*]' ||
    die "Embedded root account is not locked"

if [ "${ROOTFS}" = "buildroot" ]; then
    debugfs -R "cat /etc/init.d/S02rootfs-resize" \
        "${WORK_DIR}/rootfs.ext4" 2>/dev/null |
        grep -Fq "resize2fs \"\$rootdev\"" ||
        die "Buildroot rootfs lacks the first-boot resize hook"
else
    debugfs -R "cat /usr/local/sbin/rk3588-firstboot" \
        "${WORK_DIR}/rootfs.ext4" 2>/dev/null |
        grep -Fq "resize2fs \"\$rootdev\"" ||
        die "Debian rootfs lacks the first-boot resize helper"
    debugfs -R "cat /etc/systemd/system/rk3588-firstboot.service" \
        "${WORK_DIR}/rootfs.ext4" 2>/dev/null |
        grep -Fq 'WantedBy=multi-user.target' ||
        die "Debian rootfs lacks the first-boot resize service"
fi

(
    cd "${VARIANT_OUTPUT}"
    sha256sum --check "$(basename "${SHA256_PATH}")"
)

log_info "Image verification passed: ${IMAGE_PATH}"
