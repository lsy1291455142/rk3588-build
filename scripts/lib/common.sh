#!/usr/bin/env bash
# shellcheck disable=SC2034

COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$(cd "${COMMON_DIR}/../.." && pwd)}"
SDK_DIR="${SDK_DIR:-/home/builder/sdk}"
CONFIG_DIR="${CONFIG_DIR:-${PROJECT_DIR}/configs}"
ROOTFS_CONFIG_DIR="${ROOTFS_CONFIG_DIR:-${PROJECT_DIR}/rootfs}"
OUTPUT_DIR="${OUTPUT_DIR:-/home/builder/output}"
BUILD_BASE_DIR="${BUILD_BASE_DIR:-${SDK_DIR}/.sbc-build}"

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

# Source the bootloader layout abstraction layer.
# shellcheck source=bootloader_layouts.sh
source "${COMMON_DIR}/bootloader_layouts.sh"

# Board-specific hooks (optional). If configs/boards/<board>.hooks.sh exists,
# it is sourced after the board profile is loaded. Hook functions:
#   pre_build_kernel, post_build_kernel
#   pre_build_uboot, post_build_uboot
#   pre_build_rootfs, post_build_rootfs
#   pre_make_image, post_make_image
#   pre_fetch_sources, post_fetch_sources
_load_board_hooks() {
    local hooks_file="${CONFIG_DIR}/boards/${BOARD}.hooks.sh"
    if [ -f "${hooks_file}" ]; then
        log_info "Loading board hooks: ${hooks_file}"
        # shellcheck disable=SC1090
        source "${hooks_file}"
    fi
}

# Run a named hook if the function exists. Silent no-op otherwise.
run_hook() {
    local hook_name="$1"
    shift
    if declare -F "${hook_name}" >/dev/null 2>&1; then
        log_info "Running hook: ${hook_name}"
        "${hook_name}" "$@"
    fi
}

load_board_profile() {
    BOARD="${BOARD:-}"
    [ -n "${BOARD}" ] || die "BOARD is required. Use 'make list-boards' to see available boards, or set BOARD in .env"
    validate_token "BOARD" "${BOARD}"

    BOARD_PROFILE="${CONFIG_DIR}/boards/${BOARD}.conf"
    require_file "${BOARD_PROFILE}" "board profile '${BOARD}'. Available boards: $(ls -1 \"${CONFIG_DIR}/boards/\"*.conf 2>/dev/null | sed 's|.*/||; s|\.conf$||' | grep -v '^TEMPLATE$' | tr '\n' ' ')"

    # shellcheck disable=SC1090
    source "${BOARD_PROFILE}"
    validate_board_profile
    _load_board_hooks
}

validate_board_profile() {
    BOOTLOADER_LAYOUT="${BOOTLOADER_LAYOUT:-rockchip-gpt-idblock-extlinux-v1}"
    if [ "${BOOTLOADER_LAYOUT}" = "rockchip-gpt-extlinux-v1" ]; then
        BOOTLOADER_LAYOUT="rockchip-gpt-idblock-extlinux-v1"
    fi

    DOWNLOAD_LOADER_GLOBS="${DOWNLOAD_LOADER_GLOBS:-${LOADER_GLOBS:-rk3588*loader*.bin;MiniLoaderAll.bin;*loader*.bin}}"
    UBOOT_IMAGE_NAMES="${UBOOT_IMAGE_NAMES:-uboot.img;u-boot.img}"
    UBOOT_BUILD_SYSTEM="${UBOOT_BUILD_SYSTEM:-rockchip-make-sh}"
    UBOOT_PYTHON="${UBOOT_PYTHON:-python3}"
    IDBLOCK_SECTOR="${IDBLOCK_SECTOR:-${LOADER_SECTOR:-64}}"
    UBOOT_SECTOR="${UBOOT_SECTOR:-16384}"
    IMAGE_SIZE_MIB="${IMAGE_SIZE_MIB:-2048}"
    BOOT_START_MIB="${BOOT_START_MIB:-16}"
    BOOT_SIZE_MIB="${BOOT_SIZE_MIB:-256}"
    ROOTFS_SIZE_MIB="${ROOTFS_SIZE_MIB:-1700}"

    case "${BOOTLOADER_LAYOUT}" in
        rockchip-gpt-idblock-extlinux-v1) ;;
        *) die "Unsupported BOOTLOADER_LAYOUT=${BOOTLOADER_LAYOUT}. Known layouts: rockchip-gpt-idblock-extlinux-v1" ;;
    esac

    local required_fields=(
        BOARD_DESCRIPTION
        KERNEL_DEFCONFIG
        KERNEL_DTB
        UBOOT_DEFCONFIG
        UBOOT_BOARD
        CONSOLE
    )
    local field value

    for field in "${required_fields[@]}"; do
        value="${!field:-}"
        [ -n "${value}" ] || die "Board profile ${BOARD_PROFILE} is missing ${field}"
    done

    [[ "${KERNEL_DTB}" = *.dtb ]] || die "KERNEL_DTB must name one .dtb file"

    case "${UBOOT_PYTHON}" in
        python2|python3) ;;
        *) die "Unsupported UBOOT_PYTHON=${UBOOT_PYTHON}; expected python2 or python3" ;;
    esac

    for field in IMAGE_SIZE_MIB BOOT_START_MIB BOOT_SIZE_MIB ROOTFS_SIZE_MIB \
        IDBLOCK_SECTOR UBOOT_SECTOR; do
        value="${!field}"
        is_positive_integer "${value}" ||
            die "${field} must be a positive integer in ${BOARD_PROFILE}"
    done

    local boot_start_sector=$((BOOT_START_MIB * 2048))
    local root_start_mib=$((BOOT_START_MIB + BOOT_SIZE_MIB))
    local available_root_mib=$((IMAGE_SIZE_MIB - root_start_mib - 1))

    [ "${IDBLOCK_SECTOR}" -lt "${UBOOT_SECTOR}" ] ||
        die "IDBLOCK_SECTOR must be before UBOOT_SECTOR"
    [ "${IDBLOCK_SECTOR}" -ge 34 ] ||
        die "IDBLOCK_SECTOR overlaps the primary GPT"
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

    # Set defaults for optional configuration variables
    DTB_STRIP_BOOTARGS="${DTB_STRIP_BOOTARGS:-yes}"
    OUTPUT_IMAGE_PREFIX="${OUTPUT_IMAGE_PREFIX:-${BOARD}}"
    EXTLINUX_LABEL="${EXTLINUX_LABEL:-${BOARD}}"
    KERNEL_DTBO="${KERNEL_DTBO:-}"
    DEBIAN_EXTRA_PACKAGES="${DEBIAN_EXTRA_PACKAGES:-}"
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
    [ -n "${ROOTFS:-}" ] || die "ROOTFS is required; expected buildroot or debian"
    case "${ROOTFS}" in
        buildroot|debian) ;;
        *) die "Unsupported ROOTFS=${ROOTFS}; expected buildroot or debian" ;;
    esac
}

validate_rootfs_credentials() {
    ROOTFS_USERNAME="${ROOTFS_USERNAME:-user}"
    ROOTFS_PASSWORD="${ROOTFS_PASSWORD:-password}"

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

# Optional extra APT packages for Debian rootfs. Empty keeps minbase-only packages.
# Values are exact package names (comma/space separated). No feature aliases.
# Legacy aliases (nm, hwdebug, tools, firstboot-info, wifibt, all) are rejected.
# Optional attachments live in rootfs/debian/overlays/.
resolve_debian_packages() {
    local raw token pkg
    local -a requested=()
    local -A seen_pkgs=()
    local -a deduped=()
    DEBIAN_CUSTOM_PACKAGES=()

    # DEBIAN_PACKAGES is canonical; DEBIAN_FEATURES is accepted as a legacy alias.
    raw="${DEBIAN_PACKAGES:-${DEBIAN_FEATURES:-}}"
    raw="${raw//[[:space:]]/,}"
    raw="${raw//+/,}"
    raw="${raw//;/,}"
    while [[ "${raw}" == *,,* ]]; do
        raw="${raw//,,/,}"
    done
    raw="${raw#,}"
    raw="${raw%,}"
    case "${raw}" in
        none|minbase|off|-)
            raw=""
            ;;
    esac
    if [ -z "${raw}" ]; then
        DEBIAN_PACKAGES=""
        DEBIAN_FEATURES=""
        return 0
    fi

    IFS=',' read -r -a requested <<<"${raw}"
    for token in "${requested[@]}"; do
        token="${token//[[:space:]]/}"
        [ -n "${token}" ] || continue
        case "${token}" in
            nm|hwdebug|hw-debug|debug-hw|tools|devtools|firstboot-info|firstboot|motd|wifibt|wifi|wifi-bt|wifi_bt|all)
                die "DEBIAN_PACKAGES no longer accepts feature alias '${token}'. Use real apt package names (e.g. network-manager,wpasupplicant,i2c-tools). Optional policy lives in rootfs/debian/overlays/."
                ;;
            networkmanager)
                die "Use apt package name 'network-manager' (not '${token}')."
                ;;
            *[!a-zA-Z0-9.+~:_-]*)
                die "Invalid Debian package name: ${token}"
                ;;
            *)
                DEBIAN_CUSTOM_PACKAGES+=("${token}")
                ;;
        esac
    done

    for pkg in "${DEBIAN_CUSTOM_PACKAGES[@]}"; do
        [ -n "${pkg}" ] || continue
        [ -z "${seen_pkgs[${pkg}]+x}" ] || continue
        seen_pkgs["${pkg}"]=1
        deduped+=("${pkg}")
    done
    DEBIAN_CUSTOM_PACKAGES=("${deduped[@]}")
    DEBIAN_PACKAGES="$(IFS=,; printf '%s' "${DEBIAN_CUSTOM_PACKAGES[*]}")"
    # Keep debian_features metadata field populated with the package list.
    DEBIAN_FEATURES="${DEBIAN_PACKAGES}"
}

debian_package_list() {
    if [ "${#DEBIAN_CUSTOM_PACKAGES[@]}" -eq 0 ]; then
        return 0
    fi
    printf '%s\n' "${DEBIAN_CUSTOM_PACKAGES[@]}"
}

# Automatically install custom user firmware from assets/firmware/ and configs/boards/${BOARD}/firmware/
install_custom_firmware() {
    local root_dir="$1"
    local dest_fw="${root_dir}/lib/firmware"
    local fw_dir

    install -d "${dest_fw}"

    for fw_dir in "${PROJECT_DIR}/assets/firmware" \
                   "${CONFIG_DIR}/boards/${BOARD}/firmware"; do
        if [ -d "${fw_dir}" ] && [ -n "$(ls -A "${fw_dir}" 2>/dev/null)" ]; then
            log_info "Installing custom firmware from ${fw_dir}"
            cp -rpf "${fw_dir}"/* "${dest_fw}/"
        fi
    done
}

# Custom firmware blobs only (assets/firmware + board firmware).
install_firmware() {
    local root_dir="$1"
    install_custom_firmware "${root_dir}"
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


# ---------------------------------------------------------------------------
# Debian optional overlays (pure build core + selectable attachment plugins)
# Layout:
#   rootfs/debian/overlays/<name>/plugin.sh   required entry
#   rootfs/debian/overlays/<name>/overlay/    optional static files
#   rootfs/debian/boards/<board>/plugin.sh    board plugin (always if present)
#   rootfs/debian/boards/<board>/overlay/     board static files (always if present)
# Selection: DEBIAN_OVERLAYS / DEBIAN_OVERLAYS_DEFAULT (comma/space list).
# Special: none|off|- = no optional overlays; all = every overlays/*/plugin.sh
# ---------------------------------------------------------------------------
debian_rootfs_dir() {
    printf '%s\n' "${PROJECT_DIR}/rootfs/debian"
}

debian_overlays_dir() {
    printf '%s\n' "$(debian_rootfs_dir)/overlays"
}

# Known built-in overlay plugin names (discoverability / defaults).
debian_known_overlay_names() {
    local d name
    d="$(debian_overlays_dir)"
    [ -d "${d}" ] || return 0
    for name in "${d}"/*/plugin.sh; do
        [ -f "${name}" ] || continue
        basename "$(dirname "${name}")"
    done | sort
}

# Resolve DEBIAN_OVERLAYS into ordered unique list DEBIAN_OVERLAY_LIST / DEBIAN_OVERLAYS.
resolve_debian_overlays() {
    local raw token
    local -a requested=()
    local -a resolved=()
    local -A seen=()
    local d name

    raw="${DEBIAN_OVERLAYS:-}"
    raw="${raw//[[:space:]]/,}"
    raw="${raw//+/,}"
    raw="${raw//;/,}"
    while [[ "${raw}" == *,,* ]]; do
        raw="${raw//,,/,}"
    done
    raw="${raw#,}"
    raw="${raw%,}"

    case "${raw}" in
        none|off|-)
            raw=""
            ;;
        all)
            raw=""
            while IFS= read -r name; do
                [ -n "${name}" ] || continue
                raw="${raw:+${raw},}${name}"
            done < <(debian_known_overlay_names)
            ;;
    esac

    DEBIAN_OVERLAY_LIST=()
    if [ -z "${raw}" ]; then
        DEBIAN_OVERLAYS=""
        return 0
    fi

    IFS=',' read -r -a requested <<<"${raw}"
    d="$(debian_overlays_dir)"
    for token in "${requested[@]}"; do
        token="${token//[[:space:]]/}"
        [ -n "${token}" ] || continue
        [ -z "${seen[${token}]+x}" ] || continue
        if [ ! -f "${d}/${token}/plugin.sh" ]; then
            die "Unknown Debian overlay '${token}' (expected ${d}/${token}/plugin.sh). Available: $(debian_known_overlay_names | tr '\n' ' ')"
        fi
        seen["${token}"]=1
        resolved+=("${token}")
    done
    DEBIAN_OVERLAY_LIST=("${resolved[@]}")
    DEBIAN_OVERLAYS="$(IFS=,; printf '%s' "${DEBIAN_OVERLAY_LIST[*]}")"
}

debian_overlay_enabled() {
    local want="$1"
    local name
    for name in "${DEBIAN_OVERLAY_LIST[@]+"${DEBIAN_OVERLAY_LIST[@]}"}"; do
        [ "${name}" = "${want}" ] && return 0
    done
    return 1
}

# Expand @PLACEHOLDER@ tokens using current board/rootfs shell variables.
expand_overlay_template_text() {
    local content="$1"
    local packages_value="${DEBIAN_PACKAGES:-${DEBIAN_FEATURES:-none}}"
    local overlays_value="${DEBIAN_OVERLAYS:-none}"
    [ -n "${packages_value}" ] || packages_value="none"
    [ -n "${overlays_value}" ] || overlays_value="none"

    content="${content//@BOARD@/${BOARD:-}}"
    content="${content//@BOARD_DESCRIPTION@/${BOARD_DESCRIPTION:-}}"
    content="${content//@ROOTFS_HOSTNAME@/${ROOTFS_HOSTNAME:-${BOARD:-sbc}}}"
    content="${content//@KERNEL_DTB@/${KERNEL_DTB:-}}"
    content="${content//@DEBIAN_FEATURES@/${packages_value}}"
    content="${content//@DEBIAN_PACKAGES@/${packages_value}}"
    content="${content//@DEBIAN_OVERLAYS@/${overlays_value}}"
    content="${content//@CONSOLE_DEVICE@/${CONSOLE_DEVICE:-}}"
    content="${content//@CONSOLE_SPEED@/${CONSOLE_SPEED:-}}"
    content="${content//@ROOTFS_USERNAME@/${ROOTFS_USERNAME:-}}"
    printf '%s' "${content}"
}

# Copy one overlay tree into rootfs. Relative paths under src map to root_dir.
# - *.in templates are expanded and installed without the .in suffix
# - executable bit on source is preserved
apply_rootfs_overlay_tree() {
    local root_dir="$1"
    local overlay_src="$2"
    local src rel dest mode content target

    [ -n "${root_dir}" ] || die "apply_rootfs_overlay_tree: root_dir required"
    [ -n "${overlay_src}" ] || die "apply_rootfs_overlay_tree: overlay_src required"
    [ -d "${overlay_src}" ] || return 0

    # Files and symlinks (board overlays may ship Rockchip /vendor firmware links).
    while IFS= read -r -d '' src; do
        rel="${src#"${overlay_src}"/}"
        [ -n "${rel}" ] || continue
        if [ -L "${src}" ]; then
            dest="${root_dir}/${rel}"
            mkdir -p "$(dirname "${dest}")"
            target="$(readlink "${src}")"
            ln -sfn "${target}" "${dest}"
        elif [[ "${rel}" == *.in ]]; then
            dest="${root_dir}/${rel%.in}"
            mkdir -p "$(dirname "${dest}")"
            content="$(cat "${src}")"
            expand_overlay_template_text "${content}" >"${dest}"
            mode="$(stat -c '%a' "${src}" 2>/dev/null || printf '644')"
            chmod "${mode}" "${dest}"
        else
            dest="${root_dir}/${rel}"
            mkdir -p "$(dirname "${dest}")"
            cp -a "${src}" "${dest}"
        fi
    done < <(find "${overlay_src}" \( -type f -o -type l \) -print0 | sort -z)
}

# Apply board-local attachments when BOARD matches a boards/<BOARD>/ entry.
# Same spirit as optional overlays, but always-on for the active board:
#   boards/<BOARD>/plugin.sh  -> source and call board_plugin_apply(root_dir)
#   boards/<BOARD>/overlay/   -> static tree only (used when no plugin.sh)
# Core stays pure: no board product policy here, only dispatch.
apply_debian_board_overlay() {
    local root_dir="$1"
    local base board_dir board_plugin board_overlay

    [ -n "${root_dir}" ] || die "apply_debian_board_overlay: root_dir required"
    base="$(debian_rootfs_dir)"
    board_dir="${base}/boards/${BOARD}"
    board_plugin="${board_dir}/plugin.sh"
    board_overlay="${board_dir}/overlay"

    if [ -f "${board_plugin}" ]; then
        log_info "Running board plugin: ${BOARD}"
        # shellcheck disable=SC1090
        source "${board_plugin}"
        if declare -F board_plugin_apply >/dev/null 2>&1; then
            board_plugin_apply "${root_dir}"
            unset -f board_plugin_apply
        else
            die "Board plugin ${BOARD} does not define board_plugin_apply()"
        fi
        return 0
    fi

    if [ -d "${board_overlay}" ]; then
        log_info "Applying board overlay (static): ${BOARD}"
        apply_rootfs_overlay_tree "${root_dir}" "${board_overlay}"
    fi
}

# Run selected optional overlay plugins (order = DEBIAN_OVERLAY_LIST).
run_debian_overlay_plugins() {
    local root_dir="$1"
    local name plugin
    local d
    d="$(debian_overlays_dir)"

    [ -n "${root_dir}" ] || die "run_debian_overlay_plugins: root_dir required"
    # resolve_debian_overlays always initializes DEBIAN_OVERLAY_LIST.
    if [ "${#DEBIAN_OVERLAY_LIST[@]}" -eq 0 ]; then
        log_info "Debian overlays: (none)"
        return 0
    fi

    log_info "Debian overlays: ${DEBIAN_OVERLAYS}"
    for name in "${DEBIAN_OVERLAY_LIST[@]}"; do
        plugin="${d}/${name}/plugin.sh"
        [ -f "${plugin}" ] || die "Missing overlay plugin: ${plugin}"
        log_info "Running overlay plugin: ${name}"
        # shellcheck disable=SC1090
        source "${plugin}"
        if declare -F plugin_apply >/dev/null 2>&1; then
            plugin_apply "${root_dir}"
            unset -f plugin_apply
        else
            die "Overlay ${name} does not define plugin_apply()"
        fi
    done
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
