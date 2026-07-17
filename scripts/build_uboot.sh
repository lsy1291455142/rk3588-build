#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

load_board_profile
validate_board_source_revisions

UBOOT_DIR="${SDK_DIR}/u-boot"
RKBIN_DIR="${SDK_DIR}/rkbin"
COMMON_OUTPUT="$(board_common_output_dir)"
JOBS_RESOLVED="$(resolve_jobs)"
CROSS_COMPILE="${CROSS_COMPILE-aarch64-linux-gnu-}"
UBOOT_CC="${CROSS_COMPILE}gcc"

require_cmd bash find sort stat git realpath grep "${UBOOT_CC}"
UBOOT_CC_PATH="$(command -v "${UBOOT_CC}")"

require_dir "${UBOOT_DIR}" "U-Boot source"
require_dir "${RKBIN_DIR}" "rkbin source"
require_file "${UBOOT_DIR}/configs/${UBOOT_DEFCONFIG}" "U-Boot defconfig"
require_file "${UBOOT_DIR}/make.sh" "Rockchip U-Boot make.sh"

[ "${UBOOT_BUILD_SYSTEM}" = "rockchip-make-sh" ] ||
    die "Unsupported UBOOT_BUILD_SYSTEM=${UBOOT_BUILD_SYSTEM}"
[ "${BOOTLOADER_LAYOUT}" = "rockchip-gpt-extlinux-v1" ] ||
    die "Unsupported BOOTLOADER_LAYOUT=${BOOTLOADER_LAYOUT}"

# On ARM64 hosts, Rockchip's prebuilt x86-64 rkbin tools (boot_merger,
# trust_merger, etc.) cannot execute natively. Wrap them with qemu-x86_64.
wrap_rkbin_tools() {
    if [ "$(dpkg --print-architecture 2>/dev/null || echo unknown)" != "arm64" ]; then
        return 0
    fi
    local qemu bin
    qemu="$(command -v qemu-x86_64-static 2>/dev/null || true)"
    if [ -z "${qemu}" ]; then
        die "ARM64 host requires qemu-user-static for x86-64 rkbin tools"
    fi
    # Restore any previously wrapped binaries from .real backups
    for bin in "${RKBIN_DIR}/tools"/*.real; do
        if [ ! -f "${bin}" ]; then
            continue
        fi
        local orig="${bin%.real}"
        mv -f "${bin}" "${orig}"
    done
    # Wrap each x86-64 ELF binary with a qemu shim
    for bin in "${RKBIN_DIR}/tools"/*; do
        if [ ! -f "${bin}" ] || [ ! -x "${bin}" ]; then
            continue
        fi
        file "${bin}" 2>/dev/null | grep -q 'ELF.*x86-64' || continue
        mv "${bin}" "${bin}.real"
        printf '#!/bin/sh\nexec %s %s.real "$@"\n' "${qemu}" "${bin}" >"${bin}"
        chmod 0755 "${bin}"
    done
    log_info "Wrapped x86-64 rkbin tools with qemu-x86_64-static"
}

wrap_rkbin_tools

mkdir -p "${COMMON_OUTPUT}"

validate_extlinux_boot_contract() {
    local config="${UBOOT_DIR}/.config"
    local binary="${UBOOT_DIR}/u-boot.bin"
    local option
    local -a required_options=(
        CONFIG_DISTRO_DEFAULTS
        CONFIG_CMD_MMC
        CONFIG_CMD_FAT
        CONFIG_CMD_FS_GENERIC
        CONFIG_CMD_PXE
        CONFIG_CMD_BOOTI
    )
    local -a forbidden_options=(
        CONFIG_FIT_SIGNATURE
        CONFIG_AVB_VBMETA_PUBLIC_KEY_VALIDATE
    )

    require_file "${config}" "generated U-Boot configuration"
    require_file "${binary}" "plain U-Boot binary"

    for option in "${required_options[@]}"; do
        grep -Fqx "${option}=y" "${config}" ||
            die "U-Boot extlinux contract requires ${option}=y"
    done
    for option in "${forbidden_options[@]}"; do
        if grep -Fqx "${option}=y" "${config}"; then
            die "U-Boot extlinux contract rejects ${option}=y"
        fi
    done

    grep -aFq 'run distro_bootcmd;' "${binary}" ||
        die "U-Boot binary does not contain the distro boot fallback"
    grep -aFq 'extlinux/extlinux.conf' "${binary}" ||
        die "U-Boot binary does not contain the extlinux configuration path"
}

log_step "Building Rockchip boot chain for ${BOARD}"
log_info "U-Boot compiler: ${UBOOT_CC_PATH}"
(
    cd "${UBOOT_DIR}"
    export RKBIN="${RKBIN_DIR}"
    export MAKEFLAGS="-j${JOBS_RESOLVED}"
    # Rockchip make.sh only selects an external toolchain through this argument.
    bash ./make.sh "${UBOOT_BOARD}" "CROSS_COMPILE=${CROSS_COMPILE}"
)

log_step "Validating the GPT/extlinux boot contract"
validate_extlinux_boot_contract

find_newest_match() {
    local patterns="$1"
    local pattern match
    local -a pattern_list=() found=()

    IFS=';' read -r -a pattern_list <<<"${patterns}"
    for pattern in "${pattern_list[@]}"; do
        mapfile -d '' found < <(
            find "${UBOOT_DIR}" -maxdepth 3 -type f -name "${pattern}" \
                -printf '%T@ %p\0' | sort -zrn
        )
        if [ "${#found[@]}" -gt 0 ]; then
            match="${found[0]#* }"
            printf '%s\n' "${match}"
            return 0
        fi
    done
    return 1
}

LOADER_PATH="$(find_newest_match "${LOADER_GLOBS}" || true)"
UBOOT_IMAGE_PATH="$(find_newest_match "${UBOOT_IMAGE_NAMES}" || true)"

[ -n "${LOADER_PATH}" ] ||
    die "Rockchip make.sh completed but no loader matched: ${LOADER_GLOBS}"
[ -n "${UBOOT_IMAGE_PATH}" ] ||
    die "Rockchip make.sh completed but no uboot image matched: ${UBOOT_IMAGE_NAMES}"

LOADER_SIZE="$(stat -c '%s' "${LOADER_PATH}")"
UBOOT_SIZE="$(stat -c '%s' "${UBOOT_IMAGE_PATH}")"
LOADER_CAPACITY=$(((UBOOT_SECTOR - LOADER_SECTOR) * 512))
UBOOT_CAPACITY=$(((BOOT_START_MIB * 2048 - UBOOT_SECTOR) * 512))

[ "${LOADER_SIZE}" -le "${LOADER_CAPACITY}" ] ||
    die "Loader exceeds its reserved area (${LOADER_SIZE} > ${LOADER_CAPACITY})"
[ "${UBOOT_SIZE}" -le "${UBOOT_CAPACITY}" ] ||
    die "uboot.img exceeds its reserved area (${UBOOT_SIZE} > ${UBOOT_CAPACITY})"

install -m 0644 "${LOADER_PATH}" "${COMMON_OUTPUT}/loader.bin"
install -m 0644 "${UBOOT_IMAGE_PATH}" "${COMMON_OUTPUT}/uboot.img"

for optional in trust.img u-boot.itb; do
    if [ -f "${UBOOT_DIR}/${optional}" ]; then
        install -m 0644 "${UBOOT_DIR}/${optional}" "${COMMON_OUTPUT}/${optional}"
    fi
done

write_common_metadata "${COMMON_OUTPUT}/uboot-build-info.txt" \
    "source_manifest=${SOURCE_MANIFEST:-}" \
    "uboot_revision=$(git_revision "${UBOOT_DIR}")" \
    "rkbin_revision=$(git_revision "${RKBIN_DIR}")" \
    "uboot_defconfig=${UBOOT_DEFCONFIG}" \
    "uboot_board=${UBOOT_BOARD}" \
    "loader_source=$(basename "${LOADER_PATH}")" \
    "loader_sector=${LOADER_SECTOR}" \
    "uboot_source=$(basename "${UBOOT_IMAGE_PATH}")" \
    "uboot_sector=${UBOOT_SECTOR}" \
    "cross_compile=${CROSS_COMPILE}" \
    "compiler_path=${UBOOT_CC_PATH}" \
    "boot_flow=rockchip-gpt-extlinux-v1" \
    "boot_flow_validation=config-and-u-boot-bin" \
    "jobs=${JOBS_RESOLVED}"

log_info "U-Boot artifacts: ${COMMON_OUTPUT}"
