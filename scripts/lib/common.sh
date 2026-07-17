#!/usr/bin/env bash
# shellcheck disable=SC2034

COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$(cd "${COMMON_DIR}/../.." && pwd)}"
SDK_DIR="${SDK_DIR:-/home/builder/sdk}"
CONFIG_DIR="${CONFIG_DIR:-${PROJECT_DIR}/configs}"
ROOTFS_CONFIG_DIR="${ROOTFS_CONFIG_DIR:-${PROJECT_DIR}/rootfs}"
OUTPUT_DIR="${OUTPUT_DIR:-/home/builder/output}"
BUILD_BASE_DIR="${BUILD_BASE_DIR:-${SDK_DIR}/.rk3588-build}"

log_info() {
    printf '[INFO] %s\n' "$*" >&2
}

log_warn() {
    printf '[WARN] %s\n' "$*" >&2
}

log_step() {
    printf '[STEP] %s\n' "$*" >&2
}

die() {
    printf '[ERROR] %s\n' "$*" >&2
    exit 1
}

require_cmd() {
    local cmd
    for cmd in "$@"; do
        command -v "${cmd}" >/dev/null 2>&1 || die "Required command not found: ${cmd}"
    done
}

require_file() {
    local path="$1"
    local description="${2:-file}"
    [ -f "${path}" ] || die "Missing ${description}: ${path}"
}

require_dir() {
    local path="$1"
    local description="${2:-directory}"
    [ -d "${path}" ] || die "Missing ${description}: ${path}"
}

resolve_jobs() {
    local jobs="${JOBS:-0}"
    if [ "${jobs}" = "0" ] || [ -z "${jobs}" ]; then
        jobs="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || printf '4')"
    fi
    [[ "${jobs}" =~ ^[1-9][0-9]*$ ]] || die "JOBS must be a positive integer: ${jobs}"
    printf '%s\n' "${jobs}"
}

validate_token() {
    local name="$1"
    local value="$2"
    [[ "${value}" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] ||
        die "${name} contains unsupported characters: ${value}"
}

is_positive_integer() {
    [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

load_board_profile() {
    BOARD="${BOARD:-}"
    [ -n "${BOARD}" ] || die "BOARD is required. Example: BOARD=rk3588s-rock-5c"
    validate_token "BOARD" "${BOARD}"

    BOARD_PROFILE="${CONFIG_DIR}/boards/${BOARD}.conf"
    require_file "${BOARD_PROFILE}" "board profile"

    # shellcheck disable=SC1090
    source "${BOARD_PROFILE}"
    validate_board_profile
}

validate_board_profile() {
    local required_fields=(
        BOARD_DESCRIPTION
        KERNEL_DEFCONFIG
        KERNEL_DTB
        UBOOT_DEFCONFIG
        UBOOT_BOARD
        UBOOT_BUILD_SYSTEM
        BOOTLOADER_LAYOUT
        LOADER_GLOBS
        UBOOT_IMAGE_NAMES
        CONSOLE
        IMAGE_SIZE_MIB
        BOOT_START_MIB
        BOOT_SIZE_MIB
        ROOTFS_SIZE_MIB
        LOADER_SECTOR
        UBOOT_SECTOR
    )
    local field value

    for field in "${required_fields[@]}"; do
        value="${!field:-}"
        [ -n "${value}" ] || die "Board profile ${BOARD_PROFILE} is missing ${field}"
    done

    [[ "${KERNEL_DTB}" = *.dtb ]] || die "KERNEL_DTB must name one .dtb file"

    for field in IMAGE_SIZE_MIB BOOT_START_MIB BOOT_SIZE_MIB ROOTFS_SIZE_MIB \
        LOADER_SECTOR UBOOT_SECTOR; do
        value="${!field}"
        is_positive_integer "${value}" ||
            die "${field} must be a positive integer in ${BOARD_PROFILE}"
    done

    local boot_start_sector=$((BOOT_START_MIB * 2048))
    local root_start_mib=$((BOOT_START_MIB + BOOT_SIZE_MIB))
    local available_root_mib=$((IMAGE_SIZE_MIB - root_start_mib - 1))

    [ "${LOADER_SECTOR}" -lt "${UBOOT_SECTOR}" ] ||
        die "LOADER_SECTOR must be before UBOOT_SECTOR"
    [ "${LOADER_SECTOR}" -ge 34 ] ||
        die "LOADER_SECTOR overlaps the primary GPT"
    [ "${UBOOT_SECTOR}" -lt "${boot_start_sector}" ] ||
        die "UBOOT_SECTOR must be before the boot partition"
    [ "${BOOT_START_MIB}" -ge 16 ] ||
        die "BOOT_START_MIB must reserve at least the first 16 MiB"
    [ "${available_root_mib}" -gt 0 ] ||
        die "IMAGE_SIZE_MIB is too small for the configured boot partition"
    [ "${ROOTFS_SIZE_MIB}" -le "${available_root_mib}" ] ||
        die "ROOTFS_SIZE_MIB exceeds the root partition capacity"

    if [ -n "${SOURCE_MANIFEST:-}" ]; then
        require_file "${PROJECT_DIR}/manifests/${SOURCE_MANIFEST}" \
            "source manifest for ${BOARD}"
        for field in EXPECTED_KERNEL_REVISION EXPECTED_UBOOT_REVISION \
            EXPECTED_RKBIN_REVISION EXPECTED_BUILDROOT_REVISION; do
            value="${!field:-}"
            [[ "${value}" =~ ^[0-9a-f]{40}$ ]] ||
                die "${field} must be a full Git commit SHA in ${BOARD_PROFILE}"
        done
    fi
}

validate_git_revision() {
    local repo="$1"
    local expected="$2"
    local description="$3"
    local actual

    require_cmd git
    require_dir "${repo}" "${description} source"
    actual="$(git -c safe.directory="${repo}" -C "${repo}" \
        rev-parse HEAD 2>/dev/null || true)"
    [ -n "${actual}" ] || die "Unable to read ${description} Git revision: ${repo}"
    [ "${actual}" = "${expected}" ] ||
        die "${description} revision mismatch: expected ${expected}, got ${actual}"
}

validate_board_source_revisions() {
    [ -n "${SOURCE_MANIFEST:-}" ] || return 0

    validate_git_revision "${SDK_DIR}/kernel" \
        "${EXPECTED_KERNEL_REVISION}" "kernel"
    validate_git_revision "${SDK_DIR}/u-boot" \
        "${EXPECTED_UBOOT_REVISION}" "U-Boot"
    validate_git_revision "${SDK_DIR}/rkbin" \
        "${EXPECTED_RKBIN_REVISION}" "rkbin"
    validate_git_revision "${SDK_DIR}/buildroot" \
        "${EXPECTED_BUILDROOT_REVISION}" "Buildroot"
}

validate_rootfs_choice() {
    ROOTFS="${ROOTFS:-buildroot}"
    case "${ROOTFS}" in
        buildroot|debian) ;;
        *) die "Unsupported ROOTFS=${ROOTFS}; expected buildroot or debian" ;;
    esac
}

validate_rootfs_selection() {
    ROOTFS="${ROOTFS:-buildroot}"
    case "${ROOTFS}" in
        buildroot|debian|all) ;;
        *) die "Unsupported ROOTFS=${ROOTFS}; expected buildroot, debian, or all" ;;
    esac
}

validate_rootfs_credentials() {
    ROOTFS_USERNAME="${ROOTFS_USERNAME:-rk3588}"
    ROOTFS_PASSWORD="${ROOTFS_PASSWORD:-rk3588}"

    [[ "${ROOTFS_USERNAME}" =~ ^[a-z_][a-z0-9_-]*$ ]] ||
        die "ROOTFS_USERNAME is not a valid Linux account name"
    [ "${ROOTFS_USERNAME}" != "root" ] ||
        die "ROOTFS_USERNAME cannot be root"
    [ -n "${ROOTFS_PASSWORD}" ] || die "ROOTFS_PASSWORD cannot be empty"
    case "${ROOTFS_PASSWORD}" in
        *:*|*$'\n'*|*$'\r'*)
            die "ROOTFS_PASSWORD cannot contain colon or newline characters"
            ;;
    esac
}

resolve_debian_release() {
    DEBIAN_RELEASE="${DEBIAN_RELEASE:-13}"
    case "${DEBIAN_RELEASE}" in
        11)
            DEBIAN_CODENAME="bullseye"
            DEBIAN_COMPONENTS="main contrib non-free"
            ;;
        12)
            DEBIAN_CODENAME="bookworm"
            DEBIAN_COMPONENTS="main contrib non-free non-free-firmware"
            ;;
        13)
            DEBIAN_CODENAME="trixie"
            DEBIAN_COMPONENTS="main contrib non-free non-free-firmware"
            ;;
        *)
            die "Unsupported DEBIAN_RELEASE=${DEBIAN_RELEASE}; expected 11, 12, or 13"
            ;;
    esac
}

rootfs_variant() {
    validate_rootfs_choice
    if [ "${ROOTFS}" = "buildroot" ]; then
        printf 'buildroot\n'
    else
        resolve_debian_release
        printf 'debian-%s\n' "${DEBIAN_RELEASE}"
    fi
}

board_common_output_dir() {
    printf '%s/%s/common\n' "${OUTPUT_DIR}" "${BOARD}"
}

variant_output_dir() {
    local variant
    variant="$(rootfs_variant)"
    printf '%s/%s/%s\n' "${OUTPUT_DIR}" "${BOARD}" "${variant}"
}

image_stem() {
    local variant
    variant="$(rootfs_variant)"
    printf '%s-%s\n' "${BOARD}" "${variant}"
}

board_build_dir() {
    local component="$1"
    validate_token "build component" "${component}"
    printf '%s/%s/%s\n' "${BUILD_BASE_DIR}" "${BOARD}" "${component}"
}

safe_reset_dir() {
    local target="$1"
    local allowed_parent="$2"
    local resolved_target resolved_parent

    mkdir -p "${allowed_parent}"
    resolved_target="$(realpath -m "${target}")"
    resolved_parent="$(realpath -m "${allowed_parent}")"

    case "${resolved_target}" in
        "${resolved_parent}"/*) ;;
        *) die "Refusing to reset path outside ${resolved_parent}: ${resolved_target}" ;;
    esac
    [ "${resolved_target}" != "${resolved_parent}" ] ||
        die "Refusing to reset the build root itself: ${resolved_target}"

    rm -rf -- "${resolved_target}"
    mkdir -p "${resolved_target}"
}

git_revision() {
    local repo="$1"
    git -c safe.directory="${repo}" -C "${repo}" \
        rev-parse HEAD 2>/dev/null || printf 'unknown\n'
}

metadata_value() {
    local metadata_file="$1"
    local key="$2"
    awk -F= -v wanted="${key}" '$1 == wanted {sub(/^[^=]*=/, ""); print; exit}' \
        "${metadata_file}"
}

write_common_metadata() {
    local destination="$1"
    shift
    {
        printf 'board=%s\n' "${BOARD}"
        printf 'board_description=%s\n' "${BOARD_DESCRIPTION}"
        printf 'generated_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf '%s\n' "$@"
    } >"${destination}"
}
