#!/usr/bin/env bash
# Disk partition geometry for the GPT image.
# Both make_image.sh (writer) and verify_image.sh (checker) must agree on the
# exact on-disk layout, so the formulas live here as a single source of truth.
# Source this file and call compute_partition_layout(); it reads the board
# profile globals and sets the *_SECTOR / *_MIB variables used downstream.

if [ -n "${_DISK_GEOMETRY_SH_SOURCED:-}" ]; then
    return
fi
_DISK_GEOMETRY_SH_SOURCED=1

# Compute partition layout from board-profile globals:
#   IMAGE_SIZE_MIB, BOOT_START_MIB, BOOT_SIZE_MIB, ROOTFS_MODE, ROOTFS_BYTES, DATA_SIZE_MIB
# Sets globals:
#   IMAGE_SECTORS, BOOT_FIRST_SECTOR, BOOT_SECTORS, BOOT_LAST_SECTOR,
#   ROOT_FIRST_SECTOR, ROOT_MIB, ROOT_SECTORS, ROOT_LAST_SECTOR,
#   DATA_FIRST_SECTOR, DATA_LAST_SECTOR, DISK_LAST_USABLE_SECTOR
compute_partition_layout() {
    IMAGE_SECTORS=$((IMAGE_SIZE_MIB * 2048))
    BOOT_FIRST_SECTOR=$((BOOT_START_MIB * 2048))
    BOOT_SECTORS=$((BOOT_SIZE_MIB * 2048))
    BOOT_LAST_SECTOR=$((BOOT_FIRST_SECTOR + BOOT_SECTORS - 1))
    ROOT_FIRST_SECTOR=$((BOOT_LAST_SECTOR + 1))
    # Leave 33 sectors for the secondary GPT (LBA-1 header + 32-sector table).
    DISK_LAST_USABLE_SECTOR=$((IMAGE_SECTORS - 34))

    if [ "${ROOTFS_MODE}" = "ro-overlay" ]; then
        # SquashFS root partition sized to the image plus 1 MiB slack; the rest
        # of the disk becomes the ext4 data partition (overlay upper + data).
        ROOT_MIB=$(((ROOTFS_BYTES + 1048575) / 1048576 + 1))
        ROOT_SECTORS=$((ROOT_MIB * 2048))
        ROOT_LAST_SECTOR=$((ROOT_FIRST_SECTOR + ROOT_SECTORS - 1))
        DATA_FIRST_SECTOR=$((ROOT_LAST_SECTOR + 1))
        if [ "${DATA_SIZE_MIB}" -gt 0 ]; then
            DATA_LAST_SECTOR=$((DATA_FIRST_SECTOR + DATA_SIZE_MIB * 2048 - 1))
        else
            DATA_LAST_SECTOR="${DISK_LAST_USABLE_SECTOR}"
        fi
    else
        ROOT_LAST_SECTOR="${DISK_LAST_USABLE_SECTOR}"
        DATA_FIRST_SECTOR=""
        DATA_LAST_SECTOR=""
    fi
}
