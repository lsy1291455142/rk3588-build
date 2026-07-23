#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

load_board_profile
validate_board_source_revisions
validate_rootfs_choice
if [ "${ROOTFS}" = "debian" ]; then
    resolve_debian_release
fi

require_cmd sgdisk truncate mkfs.vfat mmd mcopy dd stat zstd sha256sum \
    install realpath

COMMON_OUTPUT="$(board_common_output_dir)"
VARIANT_OUTPUT="$(variant_output_dir)"
IMAGE_STEM="$(image_stem)"
KERNEL_IMAGE="${COMMON_OUTPUT}/Image"
DTB_IMAGE="${COMMON_OUTPUT}/${KERNEL_DTB}"
if [ "${ROOTFS_MODE}" = "ro-overlay" ]; then
    ROOTFS_IMAGE="${VARIANT_OUTPUT}/rootfs.squashfs"
    INITRD_IMAGE="${VARIANT_OUTPUT}/initrd.img"
else
    ROOTFS_IMAGE="${VARIANT_OUTPUT}/rootfs.ext4"
    INITRD_IMAGE=""
fi
KERNEL_RELEASE_FILE="${COMMON_OUTPUT}/kernel-release"
ZSTD_LEVEL="${ZSTD_LEVEL:-6}"

require_file "${KERNEL_IMAGE}" "kernel Image; run build-kernel first"
require_file "${DTB_IMAGE}" "board DTB; run build-kernel first"
require_file "${ROOTFS_IMAGE}" "root filesystem; run build-rootfs first"
require_file "${KERNEL_RELEASE_FILE}" "kernel release"
if [ "${ROOTFS_MODE}" = "ro-overlay" ]; then
    require_file "${INITRD_IMAGE}" "initramfs; run build-rootfs first"
    require_cmd mkfs.ext4
fi
if ! [[ "${ZSTD_LEVEL}" =~ ^[1-9][0-9]*$ ]] ||
    [ "${ZSTD_LEVEL}" -gt 19 ]; then
    die "ZSTD_LEVEL must be an integer from 1 to 19"
fi

mkdir -p "${VARIANT_OUTPUT}"
WORK_DIR="$(mktemp -d "${VARIANT_OUTPUT}/.image-build.XXXXXX")"
trap 'rm -rf -- "${WORK_DIR}"' EXIT

DISK_IMAGE="${WORK_DIR}/${IMAGE_STEM}.img"
BOOT_IMAGE="${WORK_DIR}/boot.fat"
EXTLINUX_DIR="${WORK_DIR}/extlinux"
EXTLINUX_CONF="${EXTLINUX_DIR}/extlinux.conf"
FINAL_IMAGE="${VARIANT_OUTPUT}/${IMAGE_STEM}.img"
FINAL_ZSTD="${FINAL_IMAGE}.zst"
FINAL_SHA256="${VARIANT_OUTPUT}/${IMAGE_STEM}.sha256"
FINAL_METADATA="${VARIANT_OUTPUT}/image-build-info.txt"

IMAGE_SECTORS=$((IMAGE_SIZE_MIB * 2048))
BOOT_FIRST_SECTOR=$((BOOT_START_MIB * 2048))
BOOT_SECTORS=$((BOOT_SIZE_MIB * 2048))
BOOT_LAST_SECTOR=$((BOOT_FIRST_SECTOR + BOOT_SECTORS - 1))
ROOT_FIRST_SECTOR=$((BOOT_LAST_SECTOR + 1))
ROOTFS_BYTES="$(stat -c '%s' "${ROOTFS_IMAGE}")"
# Leave 33 sectors for secondary GPT (LBA-1 header + 32-sector table).
DISK_LAST_USABLE_SECTOR=$((IMAGE_SECTORS - 34))

if [ "${ROOTFS_MODE}" = "ro-overlay" ]; then
    # SquashFS root partition sized to the image plus 1 MiB slack; the rest of
    # the disk becomes the ext4 data partition (overlay upper + user data).
    ROOT_MIB=$(((ROOTFS_BYTES + 1048575) / 1048576 + 1))
    ROOT_SECTORS=$((ROOT_MIB * 2048))
    ROOT_LAST_SECTOR=$((ROOT_FIRST_SECTOR + ROOT_SECTORS - 1))
    DATA_FIRST_SECTOR=$((ROOT_LAST_SECTOR + 1))
    if [ "${DATA_SIZE_MIB}" -gt 0 ]; then
        DATA_LAST_SECTOR=$((DATA_FIRST_SECTOR + DATA_SIZE_MIB * 2048 - 1))
    else
        DATA_LAST_SECTOR="${DISK_LAST_USABLE_SECTOR}"
    fi
    [ "${ROOT_LAST_SECTOR}" -lt "${DATA_FIRST_SECTOR}" ] ||
        die "SquashFS root geometry invalid"
    [ "${DATA_FIRST_SECTOR}" -lt "${DATA_LAST_SECTOR}" ] ||
        die "Data partition geometry invalid (increase IMAGE_SIZE_MIB or lower DATA_SIZE_MIB)"
    [ "${DATA_LAST_SECTOR}" -le "${DISK_LAST_USABLE_SECTOR}" ] ||
        die "Data partition exceeds the disk image (increase IMAGE_SIZE_MIB)"
    ROOT_PARTITION_BYTES=$(((ROOT_LAST_SECTOR - ROOT_FIRST_SECTOR + 1) * 512))
    [ "${ROOTFS_BYTES}" -le "${ROOT_PARTITION_BYTES}" ] ||
        die "rootfs.squashfs exceeds root partition (${ROOTFS_BYTES} > ${ROOT_PARTITION_BYTES})"
else
    ROOT_LAST_SECTOR="${DISK_LAST_USABLE_SECTOR}"
    [ "${ROOT_FIRST_SECTOR}" -lt "${ROOT_LAST_SECTOR}" ] ||
        die "Boot partition geometry invalid (BOOT_START_MIB + BOOT_SIZE_MIB exceeds IMAGE_SIZE_MIB)"
    ROOT_PARTITION_BYTES=$(((ROOT_LAST_SECTOR - ROOT_FIRST_SECTOR + 1) * 512))
    [ "${ROOTFS_BYTES}" -le "${ROOT_PARTITION_BYTES}" ] ||
        die "rootfs.ext4 exceeds root partition (${ROOTFS_BYTES} > ${ROOT_PARTITION_BYTES})"
fi
bootloader_layout_validate_artifacts "${COMMON_OUTPUT}"

mkdir -p "${EXTLINUX_DIR}"
{
    printf 'DEFAULT %s\n' "${EXTLINUX_LABEL}"
    printf 'TIMEOUT 10\n\n'
    printf 'LABEL %s\n' "${EXTLINUX_LABEL}"
    printf '    LINUX /Image\n'
    printf '    FDT /%s\n' "${KERNEL_DTB}"
    if [ -n "${KERNEL_DTBO:-}" ]; then
        dtbo_line="    FDTOVERLAYS"
        for dtbo in ${KERNEL_DTBO}; do
            dtbo_line="${dtbo_line} /overlays/${dtbo}"
        done
        printf '%s\n' "${dtbo_line}"
    fi
    if [ "${ROOTFS_MODE}" = "ro-overlay" ]; then
        printf '    INITRD /initrd.img\n'
        printf '    APPEND root=PARTLABEL=rootfs rootwait ro overlayroot=PARTLABEL=data console=%s %s\n' \
            "${CONSOLE}" "${EXTRA_KERNEL_ARGS:-}"
    else
        printf '    APPEND root=PARTLABEL=rootfs rootwait rw console=%s %s\n' \
            "${CONSOLE}" "${EXTRA_KERNEL_ARGS:-}"
    fi
} >"${EXTLINUX_CONF}"

run_hook pre_make_image
log_step "Creating GPT image ${IMAGE_STEM}.img"
truncate -s "${IMAGE_SIZE_MIB}M" "${DISK_IMAGE}"
SGDISK_ARGS=(
    --clear --set-alignment=1
    --new="1:${BOOT_FIRST_SECTOR}:${BOOT_LAST_SECTOR}"
    --typecode=1:0700 --change-name=1:boot
    --new="2:${ROOT_FIRST_SECTOR}:${ROOT_LAST_SECTOR}"
    --typecode=2:8300 --change-name=2:rootfs
)
if [ "${ROOTFS_MODE}" = "ro-overlay" ]; then
    SGDISK_ARGS+=(
        --new="3:${DATA_FIRST_SECTOR}:${DATA_LAST_SECTOR}"
        --typecode=3:8300 --change-name=3:data
    )
fi
sgdisk "${SGDISK_ARGS[@]}" "${DISK_IMAGE}" >/dev/null

truncate -s "${BOOT_SIZE_MIB}M" "${BOOT_IMAGE}"
mkfs.vfat -F 32 -n BOOT "${BOOT_IMAGE}" >/dev/null
mmd -i "${BOOT_IMAGE}" ::/extlinux
mcopy -i "${BOOT_IMAGE}" "${KERNEL_IMAGE}" ::/Image
mcopy -i "${BOOT_IMAGE}" "${DTB_IMAGE}" "::/${KERNEL_DTB}"
mcopy -i "${BOOT_IMAGE}" "${EXTLINUX_CONF}" ::/extlinux/extlinux.conf
if [ "${ROOTFS_MODE}" = "ro-overlay" ]; then
    mcopy -i "${BOOT_IMAGE}" "${INITRD_IMAGE}" ::/initrd.img
fi

if [ -n "${KERNEL_DTBO:-}" ]; then
    mmd -i "${BOOT_IMAGE}" ::/overlays
    for dtbo in ${KERNEL_DTBO}; do
        if [ -f "${COMMON_OUTPUT}/overlays/${dtbo}" ]; then
            mcopy -i "${BOOT_IMAGE}" "${COMMON_OUTPUT}/overlays/${dtbo}" "::/overlays/${dtbo}"
            log_info "Copied DTBO to boot partition: ${dtbo}"
        else
            log_warn "KERNEL_DTBO file missing from artifacts: ${dtbo}"
        fi
    done
fi

log_step "Writing boot chain and filesystems"
bootloader_layout_write "${DISK_IMAGE}" "${COMMON_OUTPUT}"
dd if="${BOOT_IMAGE}" of="${DISK_IMAGE}" bs=1M seek="${BOOT_START_MIB}" \
    conv=notrunc status=none
dd if="${ROOTFS_IMAGE}" of="${DISK_IMAGE}" bs=1M \
    seek="$((BOOT_START_MIB + BOOT_SIZE_MIB))" conv=notrunc,sparse status=none
if [ "${ROOTFS_MODE}" = "ro-overlay" ]; then
    DATA_IMAGE="${WORK_DIR}/data.ext4"
    DATA_BYTES=$(((DATA_LAST_SECTOR - DATA_FIRST_SECTOR + 1) * 512))
    truncate -s "${DATA_BYTES}" "${DATA_IMAGE}"
    mkfs.ext4 -F -L data -E lazy_itable_init=1,lazy_journal_init=1 \
        "${DATA_IMAGE}" >/dev/null
    dd if="${DATA_IMAGE}" of="${DISK_IMAGE}" bs=512 seek="${DATA_FIRST_SECTOR}" \
        conv=notrunc,sparse status=none
fi
sync

rm -f "${FINAL_IMAGE}" "${FINAL_ZSTD}" "${FINAL_SHA256}"
mv "${DISK_IMAGE}" "${FINAL_IMAGE}"

log_step "Compressing image with zstd level ${ZSTD_LEVEL}"
zstd -T0 "-${ZSTD_LEVEL}" -f "${FINAL_IMAGE}" -o "${FINAL_ZSTD}.tmp"
mv "${FINAL_ZSTD}.tmp" "${FINAL_ZSTD}"

IMAGE_SHA256="$(sha256sum "${FINAL_IMAGE}" | awk '{print $1}')"
ZSTD_SHA256="$(sha256sum "${FINAL_ZSTD}" | awk '{print $1}')"
(
    cd "${VARIANT_OUTPUT}"
    printf '%s  %s\n' "${IMAGE_SHA256}" "$(basename "${FINAL_IMAGE}")"
    printf '%s  %s\n' "${ZSTD_SHA256}" "$(basename "${FINAL_ZSTD}")"
) >"${FINAL_SHA256}"

if [ "${ROOTFS_MODE}" = "ro-overlay" ]; then
    ROOT_PART_META="root_partition=2:${ROOT_FIRST_SECTOR}:${ROOT_LAST_SECTOR}:squashfs:rootfs"
    DATA_PART_META="data_partition=3:${DATA_FIRST_SECTOR}:${DATA_LAST_SECTOR}:ext4:data"
else
    ROOT_PART_META="root_partition=2:${ROOT_FIRST_SECTOR}:${ROOT_LAST_SECTOR}:ext4:rootfs"
    DATA_PART_META=""
fi

write_common_metadata "${FINAL_METADATA}.tmp" \
    "source_manifest=${SOURCE_MANIFEST:-}" \
    "rootfs_mode=${ROOTFS_MODE}" \
    "kernel_revision=$(git_revision "${SDK_DIR}/kernel")" \
    "uboot_revision=$(git_revision "${SDK_DIR}/u-boot")" \
    "rkbin_revision=$(git_revision "${SDK_DIR}/rkbin")" \
    "buildroot_revision=$(git_revision "${SDK_DIR}/buildroot")" \
    "rootfs=${ROOTFS}" \
    "debian_release=${DEBIAN_RELEASE:-}" \
    "image=$(basename "${FINAL_IMAGE}")" \
    "image_size_mib=${IMAGE_SIZE_MIB}" \
    "image_sha256=${IMAGE_SHA256}" \
    "compressed_image=$(basename "${FINAL_ZSTD}")" \
    "compressed_sha256=${ZSTD_SHA256}" \
    "boot_partition=1:${BOOT_FIRST_SECTOR}:${BOOT_LAST_SECTOR}:fat32:BOOT" \
    "${ROOT_PART_META}" \
    ${DATA_PART_META:+"${DATA_PART_META}"} \
    $(bootloader_layout_write_metadata "${COMMON_OUTPUT}") \
    "kernel_release=$(cat "${KERNEL_RELEASE_FILE}")" \
    "kernel_dtb=${KERNEL_DTB}" \
    "rootfs_source_sha256=$(sha256sum "${ROOTFS_IMAGE}" | awk '{print $1}')"
mv "${FINAL_METADATA}.tmp" "${FINAL_METADATA}"

log_info "Raw image: ${FINAL_IMAGE}"
log_info "Compressed image: ${FINAL_ZSTD}"
log_info "Checksums: ${FINAL_SHA256}"
run_hook post_make_image
