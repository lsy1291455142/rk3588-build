#!/usr/bin/env bash
# Bootloader layout abstraction layer.
# Each layout defines functions for writing bootloader components to disk images
# and verifying them. The active layout is selected by BOOTLOADER_LAYOUT from
# the board profile.

# Known layouts (extensible by adding new layout_*_ function sets):
#   rockchip-gpt-idblock-extlinux-v1

# ---------------------------------------------------------------------------
# Layout: rockchip-gpt-idblock-extlinux-v1
# Rockchip GPT disk with RKNS IDBlock at IDBLOCK_SECTOR, U-Boot at
# UBOOT_SECTOR, FAT32 /boot with extlinux.conf, ext4 rootfs.
# ---------------------------------------------------------------------------

layout_rockchip_gpt_idblock_extlinux_v1_validate_artifacts() {
    local common_output="$1"
    local idblock="${common_output}/idblock.img"
    local uboot="${common_output}/uboot.img"

    require_file "${idblock}" "Rockchip RKNS IDBlock; run build-uboot first"
    require_file "${uboot}" "U-Boot image; run build-uboot first"

    [ "$(dd if="${idblock}" bs=1 count=4 status=none)" = "RKNS" ] ||
        die "idblock.img is not a Rockchip RKNS IDBlock"

    local idblock_bytes uboot_bytes
    idblock_bytes="$(stat -c '%s' "${idblock}")"
    uboot_bytes="$(stat -c '%s' "${uboot}")"
    local boot_first_sector=$((BOOT_START_MIB * 2048))

    [ "${idblock_bytes}" -le "$(((UBOOT_SECTOR - IDBLOCK_SECTOR) * 512))" ] ||
        die "idblock.img exceeds the reserved IDBlock area"
    [ "${uboot_bytes}" -le "$(((boot_first_sector - UBOOT_SECTOR) * 512))" ] ||
        die "uboot.img exceeds the reserved U-Boot area"
}

layout_rockchip_gpt_idblock_extlinux_v1_write() {
    local disk_image="$1"
    local common_output="$2"
    local idblock="${common_output}/idblock.img"
    local uboot="${common_output}/uboot.img"

    dd if="${idblock}" of="${disk_image}" bs=512 seek="${IDBLOCK_SECTOR}" \
        conv=notrunc status=none
    dd if="${uboot}" of="${disk_image}" bs=512 seek="${UBOOT_SECTOR}" \
        conv=notrunc status=none
}

layout_rockchip_gpt_idblock_extlinux_v1_write_metadata() {
    local common_output="$1"
    local idblock="${common_output}/idblock.img"
    local uboot="${common_output}/uboot.img"

    printf 'idblock_sector=%s\n' "${IDBLOCK_SECTOR}"
    printf 'idblock_format=RKNS\n'
    printf 'idblock_sha256=%s\n' "$(sha256sum "${idblock}" | awk '{print $1}')"
    printf 'uboot_sector=%s\n' "${UBOOT_SECTOR}"
    printf 'uboot_sha256=%s\n' "$(sha256sum "${uboot}" | awk '{print $1}')"
}

layout_rockchip_gpt_idblock_extlinux_v1_verify() {
    local image_path="$1"
    local common_output="$2"
    local work_dir="$3"
    local idblock="${common_output}/idblock.img"
    local uboot="${common_output}/uboot.img"
    local download_loader="${common_output}/download-loader.bin"
    local uboot_build_info="${common_output}/uboot-build-info.txt"
    local image_build_info
    image_build_info="$(dirname "${common_output}")"
    # image_build_info is actually in variant_output, passed separately

    require_file "${download_loader}" "download-loader.bin"
    require_file "${idblock}" "idblock.img"
    require_file "${uboot}" "uboot.img"

    [ "$(dd if="${download_loader}" bs=1 count=4 status=none)" = "LDR " ] ||
        die "download-loader.bin is not an LDR container"
    [ "$(dd if="${idblock}" bs=1 count=4 status=none)" = "RKNS" ] ||
        die "idblock.img is not an RKNS image"
    [ "$(metadata_value "${uboot_build_info}" idblock_format)" = "RKNS" ] ||
        die "U-Boot metadata does not record an RKNS IDBlock"

    # Compare embedded bootloader data
    local idblock_bytes uboot_bytes
    idblock_bytes="$(stat -c '%s' "${idblock}")"
    uboot_bytes="$(stat -c '%s' "${uboot}")"

    dd if="${image_path}" of="${work_dir}/idblock.img" \
        bs=4M iflag=skip_bytes,count_bytes \
        skip="$((IDBLOCK_SECTOR * 512))" count="${idblock_bytes}" \
        conv=sparse status=none
    [ "$(dd if="${work_dir}/idblock.img" bs=1 count=4 status=none)" = "RKNS" ] ||
        die "Raw image does not contain an RKNS IDBlock at sector ${IDBLOCK_SECTOR}"
    cmp --silent "${idblock}" "${work_dir}/idblock.img" ||
        die "Embedded data does not match idblock.img"

    dd if="${image_path}" of="${work_dir}/uboot.img" \
        bs=4M iflag=skip_bytes,count_bytes \
        skip="$((UBOOT_SECTOR * 512))" count="${uboot_bytes}" \
        conv=sparse status=none
    cmp --silent "${uboot}" "${work_dir}/uboot.img" ||
        die "Embedded data does not match uboot.img"
}

# ---------------------------------------------------------------------------
# Dispatch functions
# ---------------------------------------------------------------------------

_bootloader_layout_func() {
    local action="$1"
    shift
    local layout="${BOOTLOADER_LAYOUT}"
    local func="layout_${layout//-/_}_${action}"
    if ! declare -F "${func}" >/dev/null 2>&1; then
        die "Unknown bootloader layout function: ${func} (BOOTLOADER_LAYOUT=${layout})"
    fi
    "${func}" "$@"
}

bootloader_layout_validate_artifacts() {
    _bootloader_layout_func validate_artifacts "$@"
}

bootloader_layout_write() {
    _bootloader_layout_func write "$@"
}

bootloader_layout_write_metadata() {
    _bootloader_layout_func write_metadata "$@"
}

bootloader_layout_verify() {
    _bootloader_layout_func verify "$@"
}
