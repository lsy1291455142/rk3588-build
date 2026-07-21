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

require_cmd bash dd find sort stat git realpath grep ln mktemp \
    "${UBOOT_PYTHON}" "${UBOOT_CC}"
UBOOT_CC_PATH="$(command -v "${UBOOT_CC}")"
UBOOT_PYTHON_PATH="$(command -v "${UBOOT_PYTHON}")"
UBOOT_PYTHON_VERSION="$("${UBOOT_PYTHON}" -c \
    'import platform; print(platform.python_version())')"

"${UBOOT_PYTHON}" -c 'from elftools.elf.elffile import ELFFile' >/dev/null 2>&1 ||
    die "${UBOOT_PYTHON} pyelftools is required by the Rockchip FIT generator; rebuild the builder image"

# Some BSPs invoke bare `python`, while others use PYTHON or an explicit
# python2/python3 shebang. Scope the bare command to this U-Boot build only.
UBOOT_PYTHON_SHIM_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rk3588-uboot-python.XXXXXX")"
trap 'rm -rf -- "${UBOOT_PYTHON_SHIM_DIR}"' EXIT
ln -s "${UBOOT_PYTHON_PATH}" "${UBOOT_PYTHON_SHIM_DIR}/python"

require_dir "${UBOOT_DIR}" "U-Boot source"
require_dir "${RKBIN_DIR}" "rkbin source"
require_file "${UBOOT_DIR}/configs/${UBOOT_DEFCONFIG}" "U-Boot defconfig"
require_file "${UBOOT_DIR}/make.sh" "Rockchip U-Boot make.sh"

[ "${UBOOT_BUILD_SYSTEM}" = "rockchip-make-sh" ] ||
    die "Unsupported UBOOT_BUILD_SYSTEM=${UBOOT_BUILD_SYSTEM}"
[ "${BOOTLOADER_LAYOUT}" = "rockchip-gpt-idblock-extlinux-v1" ] ||
    die "Unsupported BOOTLOADER_LAYOUT=${BOOTLOADER_LAYOUT}"

# On ARM64 hosts, Rockchip's prebuilt x86-64 rkbin tools (boot_merger,
# trust_merger, etc.) cannot execute natively. Wrap them with qemu-x86_64.
# Every wrapped binary is recorded in RKBIN_WRAPPED so we can restore the
# rkbin working tree on exit (no dirty tree, no modified files for
# import-local-sdk users).
RKBIN_WRAPPED=()

wrap_rkbin_tools() {
    if [ "$(dpkg --print-architecture 2>/dev/null || echo unknown)" != "arm64" ]; then
        return 0
    fi
    local qemu bin
    qemu="$(command -v qemu-x86_64-static 2>/dev/null || true)"
    if [ -z "${qemu}" ]; then
        die "ARM64 host requires qemu-user-static for x86-64 rkbin tools"
    fi
    # Restore any previously wrapped binaries from .real backups (e.g. a prior
    # run that crashed before its exit trap could clean up).
    for bin in "${RKBIN_DIR}/tools"/*.real; do
        [ -f "${bin}" ] || continue
        mv -f "${bin}" "${bin%.real}"
    done
    # Wrap each x86-64 ELF binary with a qemu shim.
    for bin in "${RKBIN_DIR}/tools"/*; do
        [ -f "${bin}" ] && [ -x "${bin}" ] || continue
        file "${bin}" 2>/dev/null | grep -q 'ELF.*x86-64' || continue
        mv "${bin}" "${bin}.real"
        printf '#!/bin/sh\nexec %s %s.real "$@"\n' "${qemu}" "${bin}" >"${bin}"
        chmod 0755 "${bin}"
        RKBIN_WRAPPED+=("${bin}")
    done
    log_info "Wrapped x86-64 rkbin tools with qemu-x86_64-static"
}

# Reverse wrap_rkbin_tools: move each saved .real binary back over its shim so
# the rkbin working tree is left exactly as found. Runs on every script exit,
# including failures, so a build never leaves rkbin/tools dirty.
restore_rkbin_tools() {
    local bin
    [ "${#RKBIN_WRAPPED[@]}" -eq 0 ] && return 0
    for bin in "${RKBIN_WRAPPED[@]}"; do
        [ -f "${bin}.real" ] && mv -f "${bin}.real" "${bin}"
    done
}

trap restore_rkbin_tools EXIT

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
log_info "U-Boot Python: ${UBOOT_PYTHON_PATH} (${UBOOT_PYTHON_VERSION})"
(
    cd "${UBOOT_DIR}"
    export RKBIN="${RKBIN_DIR}"
    export MAKEFLAGS="-j${JOBS_RESOLVED}"
    export PYTHON="${UBOOT_PYTHON}"
    export PATH="${UBOOT_PYTHON_SHIM_DIR}:${PATH}"
    # Rockchip make.sh only selects an external toolchain through this argument.
    bash ./make.sh "${UBOOT_BOARD}" "CROSS_COMPILE=${CROSS_COMPILE}"

    log_step "Packing the Rockchip RKNS IDBlock"
    rm -f idblock.bin
    bash ./make.sh --idblock "CROSS_COMPILE=${CROSS_COMPILE}"
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

LOADER_PATH="$(find_newest_match "${DOWNLOAD_LOADER_GLOBS}" || true)"
UBOOT_IMAGE_PATH="$(find_newest_match "${UBOOT_IMAGE_NAMES}" || true)"
IDBLOCK_PATH="${UBOOT_DIR}/idblock.bin"

[ -n "${LOADER_PATH}" ] ||
    die "Rockchip make.sh completed but no download loader matched: ${DOWNLOAD_LOADER_GLOBS}"
[ -n "${UBOOT_IMAGE_PATH}" ] ||
    die "Rockchip make.sh completed but no uboot image matched: ${UBOOT_IMAGE_NAMES}"
require_file "${IDBLOCK_PATH}" "Rockchip RKNS IDBlock"

read_image_magic() {
    dd if="$1" bs=1 count=4 status=none
}

[ "$(read_image_magic "${LOADER_PATH}")" = "LDR " ] ||
    die "Download loader is not an LDR container: ${LOADER_PATH}"
[ "$(read_image_magic "${IDBLOCK_PATH}")" = "RKNS" ] ||
    die "Disk IDBlock is not an RKNS image: ${IDBLOCK_PATH}"

LOADER_SIZE="$(stat -c '%s' "${LOADER_PATH}")"
IDBLOCK_SIZE="$(stat -c '%s' "${IDBLOCK_PATH}")"
UBOOT_SIZE="$(stat -c '%s' "${UBOOT_IMAGE_PATH}")"
IDBLOCK_CAPACITY=$(((UBOOT_SECTOR - IDBLOCK_SECTOR) * 512))
UBOOT_CAPACITY=$(((BOOT_START_MIB * 2048 - UBOOT_SECTOR) * 512))

[ "${IDBLOCK_SIZE}" -le "${IDBLOCK_CAPACITY}" ] ||
    die "IDBlock exceeds its reserved area (${IDBLOCK_SIZE} > ${IDBLOCK_CAPACITY})"
[ "${UBOOT_SIZE}" -le "${UBOOT_CAPACITY}" ] ||
    die "uboot.img exceeds its reserved area (${UBOOT_SIZE} > ${UBOOT_CAPACITY})"

rm -f "${COMMON_OUTPUT}/loader.bin"
install -m 0644 "${LOADER_PATH}" "${COMMON_OUTPUT}/download-loader.bin"
install -m 0644 "${IDBLOCK_PATH}" "${COMMON_OUTPUT}/idblock.img"
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
    "download_loader_source=$(basename "${LOADER_PATH}")" \
    "download_loader_size=${LOADER_SIZE}" \
    "download_loader_format=LDR" \
    "idblock_source=$(basename "${IDBLOCK_PATH}")" \
    "idblock_size=${IDBLOCK_SIZE}" \
    "idblock_sector=${IDBLOCK_SECTOR}" \
    "idblock_format=RKNS" \
    "uboot_source=$(basename "${UBOOT_IMAGE_PATH}")" \
    "uboot_sector=${UBOOT_SECTOR}" \
    "uboot_python=${UBOOT_PYTHON}" \
    "uboot_python_path=${UBOOT_PYTHON_PATH}" \
    "uboot_python_version=${UBOOT_PYTHON_VERSION}" \
    "cross_compile=${CROSS_COMPILE}" \
    "compiler_path=${UBOOT_CC_PATH}" \
    "boot_flow=rockchip-gpt-idblock-extlinux-v1" \
    "boot_flow_validation=config-and-u-boot-bin" \
    "jobs=${JOBS_RESOLVED}"

log_info "U-Boot artifacts: ${COMMON_OUTPUT}"
