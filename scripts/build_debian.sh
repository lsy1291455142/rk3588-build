#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

load_board_profile
validate_board_source_revisions
ROOTFS=debian
resolve_debian_release
# Board profile may set DEBIAN_PACKAGES_DEFAULT / ROOTFS_HOSTNAME_DEFAULT.
# Empty DEBIAN_PACKAGES means "use board default if any".
# Force minbase with DEBIAN_PACKAGES=none (or minbase/off).
# DEBIAN_PACKAGES is canonical; board default comes from DEBIAN_PACKAGES_DEFAULT.
# Explicit DEBIAN_PACKAGES wins; fall back to the board default; empty means
# "use board default if any". resolve_debian_packages below handles the
# none|minbase|off|- sentinels, so no pre-normalization is needed here.
DEBIAN_PACKAGES="${DEBIAN_PACKAGES:-${DEBIAN_PACKAGES_DEFAULT:-}}"
if [ -z "${ROOTFS_HOSTNAME:-}" ]; then
    ROOTFS_HOSTNAME="${ROOTFS_HOSTNAME_DEFAULT:-${BOARD:-sbc}}"
fi
resolve_debian_packages

# Optional overlay plugins (pure attachments). Empty uses board default if any.
DEBIAN_OVERLAYS="${DEBIAN_OVERLAYS:-}"
case "${DEBIAN_OVERLAYS}" in
    '')
        if [ -n "${DEBIAN_OVERLAYS_DEFAULT:-}" ]; then
            DEBIAN_OVERLAYS="${DEBIAN_OVERLAYS_DEFAULT}"
        fi
        ;;
    none|off|-)
        DEBIAN_OVERLAYS=""
        ;;
esac
resolve_debian_overlays

require_cmd mmdebstrap dpkg chroot systemctl tar truncate mkfs.ext4 \
    tune2fs e2fsck blkid debugfs depmod realpath
if [ "${ROOTFS_MODE}" = "ro-overlay" ]; then
    require_cmd mksquashfs
fi

[ "$(id -u)" -eq 0 ] || die "Debian rootfs build must run as root"
[ "$(dpkg --print-architecture)" = "arm64" ] ||
    die "Debian rootfs builder must run as linux/arm64; enable Docker binfmt emulation"

COMMON_OUTPUT="$(board_common_output_dir)"
VARIANT_OUTPUT="$(variant_output_dir)"
DEBIAN_BUILD="$(board_build_dir "debian-${DEBIAN_RELEASE}")"
ROOT_DIR="${DEBIAN_BUILD}/root"
MODULES_TAR="${COMMON_OUTPUT}/modules.tar"
KERNEL_RELEASE_FILE="${COMMON_OUTPUT}/kernel-release"
# ROOTFS_USERNAME / ROOTFS_PASSWORD defaults are applied by
# validate_rootfs_credentials() below; do not preset them here.
ROOTFS_HOSTNAME="${ROOTFS_HOSTNAME:-${BOARD:-sbc}}"
CONSOLE_DEVICE="${CONSOLE%%,*}"
CONSOLE_SPEED="${CONSOLE#*,}"
CONSOLE_SPEED="${CONSOLE_SPEED%%[!0-9]*}"
DEBIAN_MIRROR="${DEBIAN_MIRROR:-http://deb.debian.org/debian}"
DEBIAN_SECURITY_MIRROR="${DEBIAN_SECURITY_MIRROR:-http://security.debian.org/debian-security}"
DEBIAN_ALLOW_ARCHIVE_FALLBACK="${DEBIAN_ALLOW_ARCHIVE_FALLBACK:-yes}"

require_file "${MODULES_TAR}" "kernel modules archive; run build-kernel first"
require_file "${KERNEL_RELEASE_FILE}" "kernel release; run build-kernel first"
validate_rootfs_credentials
[ -n "${CONSOLE_SPEED}" ] || die "Unable to derive console speed from ${CONSOLE}"

if [ "${DEBIAN_RELEASE}" = "11" ]; then
    log_warn "Debian 11 LTS ends on 2026-08-31."
    log_warn "Archive fallback remains buildable but receives no security support after that date."
fi

safe_reset_dir "${DEBIAN_BUILD}" "${BUILD_BASE_DIR}/${BOARD}"
mkdir -p "${ROOT_DIR}" "${VARIANT_OUTPUT}"
# The primary image builder runs as uid 1000 and consumes this root-owned output.
chmod 0777 "${VARIANT_OUTPUT}"

PACKAGES=(
    ca-certificates
    cloud-guest-utils
    curl
    dbus
    e2fsprogs
    ethtool
    gdisk
    iproute2
    iputils-ping
    kmod
    less
    net-tools
    openssh-server
    passwd
    procps
    psmisc
    sudo
    systemd-sysv
    udev
    util-linux
    vim-tiny
    wget
)
if [ "${DEBIAN_RELEASE}" != "11" ]; then
    PACKAGES+=(systemd-resolved)
fi
# ro-overlay boots through an initramfs that assembles the SquashFS+overlay root.
if [ "${ROOTFS_MODE}" = "ro-overlay" ]; then
    PACKAGES+=(initramfs-tools busybox)
fi
mapfile -t EXTRA_PACKAGES < <(debian_package_list)
if [ "${#EXTRA_PACKAGES[@]}" -gt 0 ]; then
    PACKAGES+=("${EXTRA_PACKAGES[@]}")
fi

# Deduplicate while preserving order.
declare -A PACKAGE_SEEN=()
DEDUPED_PACKAGES=()
for pkg in "${PACKAGES[@]}"; do
    [ -n "${pkg}" ] || continue
    [ -z "${PACKAGE_SEEN[${pkg}]+x}" ] || continue
    PACKAGE_SEEN["${pkg}"]=1
    DEDUPED_PACKAGES+=("${pkg}")
done
PACKAGES=("${DEDUPED_PACKAGES[@]}")
PACKAGE_LIST="$(IFS=,; printf '%s' "${PACKAGES[*]}")"
if [ -n "${DEBIAN_PACKAGES}" ]; then
    log_info "Debian packages: ${DEBIAN_PACKAGES}"
else
    log_info "Debian packages: (none; minbase only)"
fi

APT_CACHE_DIR="${APT_CACHE_DIR:-/var/cache/apt/archives}"

run_mmdebstrap() {
    local -a sources=("$@")
    local -a apt_opts=('--aptopt=Acquire::Languages "none"')
    if [ -d "${APT_CACHE_DIR}" ] && [ -w "${APT_CACHE_DIR}" ]; then
        log_info "Using persistent APT cache: ${APT_CACHE_DIR}"
        apt_opts+=("--aptopt=Dir::Cache::Archives=\"${APT_CACHE_DIR}\"")
    fi
    mmdebstrap \
        --architectures=arm64 \
        --variant=minbase \
        "--components=${DEBIAN_COMPONENTS// /,}" \
        "--include=${PACKAGE_LIST}" \
        "${apt_opts[@]}" \
        "${DEBIAN_CODENAME}" "${ROOT_DIR}" "${sources[@]}"
}

REGULAR_SOURCES=(
    "deb ${DEBIAN_MIRROR} ${DEBIAN_CODENAME} ${DEBIAN_COMPONENTS}"
    "deb ${DEBIAN_MIRROR} ${DEBIAN_CODENAME}-updates ${DEBIAN_COMPONENTS}"
    "deb ${DEBIAN_SECURITY_MIRROR} ${DEBIAN_CODENAME}-security ${DEBIAN_COMPONENTS}"
)

# mmdebstrap does not populate /dev inside the staged rootfs, but several
# chrooted steps (systemd-analyze verify, sshd -t) and the ro-overlay initramfs
# generator expect /dev/null and friends to exist. Create the minimal device
# nodes/symlinks when missing so those commands do not fail with
# "Couldn't open /dev/null".
ensure_chroot_dev() {
    local d="${ROOT_DIR}/dev"
    mkdir -p "${d}"
    [ -e "${d}/null" ]   || mknod -m 666 "${d}/null"   c 1 3 2>/dev/null || true
    [ -e "${d}/zero" ]   || mknod -m 666 "${d}/zero"   c 1 5 2>/dev/null || true
    [ -e "${d}/full" ]   || mknod -m 666 "${d}/full"   c 1 7 2>/dev/null || true
    [ -e "${d}/stdin" ]  || ln -sf /proc/self/fd/0 "${d}/stdin" 2>/dev/null || true
    [ -e "${d}/stdout" ] || ln -sf /proc/self/fd/1 "${d}/stdout" 2>/dev/null || true
    [ -e "${d}/stderr" ] || ln -sf /proc/self/fd/2 "${d}/stderr" 2>/dev/null || true
    [ -e "${d}/fd" ]     || ln -sf /proc/self/fd "${d}/fd" 2>/dev/null || true
}

log_step "Building Debian ${DEBIAN_RELEASE} (${DEBIAN_CODENAME}) rootfs"
run_hook pre_build_rootfs
if ! run_mmdebstrap "${REGULAR_SOURCES[@]}"; then
    if [ "${DEBIAN_RELEASE}" != "11" ] ||
        [ "${DEBIAN_ALLOW_ARCHIVE_FALLBACK}" != "yes" ]; then
        die "mmdebstrap failed for Debian ${DEBIAN_RELEASE}"
    fi

    log_warn "Regular Debian 11 mirrors failed; retrying archive.debian.org without Valid-Until checks."
    safe_reset_dir "${ROOT_DIR}" "${DEBIAN_BUILD}"
    ARCHIVE_SOURCES=(
        "deb [check-valid-until=no] http://archive.debian.org/debian bullseye main contrib non-free"
        "deb [check-valid-until=no] http://archive.debian.org/debian-security bullseye-security main contrib non-free"
    )
    run_mmdebstrap "${ARCHIVE_SOURCES[@]}" ||
        die "Debian 11 archive fallback failed"
fi

# Populate /dev inside the staged rootfs now that it exists, so every chrooted
# step below (and the systemd-analyze verify / sshd -t checks) can open
# /dev/null instead of failing with "Couldn't open /dev/null".
ensure_chroot_dev

case "${ROOTFS_HOSTNAME}" in
    ''|*[!a-zA-Z0-9._-]*)
        die "ROOTFS_HOSTNAME is invalid: ${ROOTFS_HOSTNAME}"
        ;;
esac
printf '%s\n' "${ROOTFS_HOSTNAME}" >"${ROOT_DIR}/etc/hostname"
printf '127.0.0.1 localhost\n127.0.1.1 %s\n' "${ROOTFS_HOSTNAME}" >"${ROOT_DIR}/etc/hosts"

# Early guard: confirm the staged Debian userspace can actually execute under
# binfmt/qemu before any write chroot. On x86_64 hosts this fails fast with a
# clear message instead of an obscure exec-format error deep in useradd/chpasswd.
chroot "${ROOT_DIR}" /bin/true ||
    die "Debian userspace is not executable (is ARM64 binfmt/qemu registered?)"

chroot "${ROOT_DIR}" useradd -m -s /bin/bash -G sudo "${ROOTFS_USERNAME}"
printf '%s:%s\n' "${ROOTFS_USERNAME}" "${ROOTFS_PASSWORD}" |
    chroot "${ROOT_DIR}" chpasswd
printf 'root:%s\n' "${ROOTFS_PASSWORD}" |
    chroot "${ROOT_DIR}" chpasswd
chroot "${ROOT_DIR}" passwd -u root

# Board plugin/overlay (optional package overlays run later as plugins).
apply_debian_board_overlay "${ROOT_DIR}"

rm -f "${ROOT_DIR}"/etc/ssh/ssh_host_* "${ROOT_DIR}/etc/machine-id"
: >"${ROOT_DIR}/etc/machine-id"
if debian_overlay_enabled base || [ -f "${ROOT_DIR}/lib/systemd/system/systemd-resolved.service" ] ||
    [ -f "${ROOT_DIR}/usr/lib/systemd/system/systemd-resolved.service" ]; then
    ln -snf /run/systemd/resolve/stub-resolv.conf "${ROOT_DIR}/etc/resolv.conf"
fi

if [ ! -L "${ROOT_DIR}/lib" ] ||
    [ "$(readlink "${ROOT_DIR}/lib")" != "usr/lib" ]; then
    die "Debian usrmerge layout is missing /lib -> usr/lib"
fi
install -d "${ROOT_DIR}/usr/lib"
tar --no-same-owner --strip-components=1 -xpf "${MODULES_TAR}" \
    -C "${ROOT_DIR}/usr/lib"
KERNEL_RELEASE="$(cat "${KERNEL_RELEASE_FILE}")"
depmod -b "${ROOT_DIR}" "${KERNEL_RELEASE}"


# Optional overlay plugins (network/firstboot/console/...).
run_debian_overlay_plugins "${ROOT_DIR}"

VERIFY_UNITS=(multi-user.target)
if [ -e "${ROOT_DIR}/etc/systemd/system/multi-user.target.wants/sbc-firstboot.service" ] ||
    [ -f "${ROOT_DIR}/etc/systemd/system/sbc-firstboot.service" ]; then
    if [ -e "${ROOT_DIR}/etc/systemd/system/multi-user.target.wants/sbc-firstboot.service" ]; then
        VERIFY_UNITS+=(sbc-firstboot.service)
    fi
fi
if [ -e "${ROOT_DIR}/etc/systemd/system/getty.target.wants/serial-getty@${CONSOLE_DEVICE}.service" ]; then
    VERIFY_UNITS+=("serial-getty@${CONSOLE_DEVICE}.service")
fi
if [ -e "${ROOT_DIR}/etc/systemd/system/multi-user.target.wants/ssh.service" ]; then
    VERIFY_UNITS+=(ssh.service)
fi
if [ -e "${ROOT_DIR}/etc/systemd/system/sysinit.target.wants/systemd-resolved.service" ]; then
    VERIFY_UNITS+=(systemd-resolved.service)
fi
if [ -e "${ROOT_DIR}/etc/systemd/system/multi-user.target.wants/NetworkManager.service" ]; then
    VERIFY_UNITS+=(NetworkManager.service)
elif [ -e "${ROOT_DIR}/etc/systemd/system/multi-user.target.wants/systemd-networkd.service" ]; then
    VERIFY_UNITS+=(systemd-networkd.service)
fi
chroot "${ROOT_DIR}" systemd-analyze verify --man=no "${VERIFY_UNITS[@]}"
if [ -x "${ROOT_DIR}/usr/sbin/sshd" ] || [ -x "${ROOT_DIR}/usr/bin/sshd" ]; then
    chroot "${ROOT_DIR}" ssh-keygen -A
    install -d -m 0755 "${ROOT_DIR}/run/sshd"
    chroot "${ROOT_DIR}" sshd -t
    rm -rf "${ROOT_DIR}/run/sshd"
    rm -f "${ROOT_DIR}"/etc/ssh/ssh_host_*
fi

rm -rf "${ROOT_DIR}/var/lib/apt/lists/"* \
    "${ROOT_DIR}/var/cache/apt/archives/"*.deb \
    "${ROOT_DIR}/tmp/"* "${ROOT_DIR}/var/tmp/"*

INITRD_IMAGE="${VARIANT_OUTPUT}/initrd.img"
ROOTFS_TAR="${VARIANT_OUTPUT}/rootfs.tar"
rm -f "${INITRD_IMAGE}" "${ROOTFS_TAR}"

# ro-overlay boots via an initramfs that assembles the SquashFS + overlay root.
if [ "${ROOTFS_MODE}" = "ro-overlay" ]; then
    log_step "Generating initramfs (initramfs-tools) for ro-overlay root"
    if [ ! -x "${ROOT_DIR}/usr/sbin/update-initramfs" ] &&
        [ ! -x "${ROOT_DIR}/usr/bin/update-initramfs" ]; then
        die "ro-overlay requires the initramfs-tools package in the rootfs"
    fi
    mode_overlay="$(rootfs_mode_overlay_dir)"
    if [ -n "${mode_overlay}" ]; then
        apply_rootfs_overlay_tree "${ROOT_DIR}" "${mode_overlay}"
    fi
    chmod 0755 "${ROOT_DIR}/etc/initramfs-tools/scripts/local-bottom/overlayroot"
    mkdir -p "${ROOT_DIR}/boot"
    chroot "${ROOT_DIR}" update-initramfs -c -k "${KERNEL_RELEASE}"
    require_file "${ROOT_DIR}/boot/initrd.img-${KERNEL_RELEASE}" "generated initramfs"
    install -m 0644 "${ROOT_DIR}/boot/initrd.img-${KERNEL_RELEASE}" "${INITRD_IMAGE}"
fi

tar --numeric-owner --xattrs --acls -C "${ROOT_DIR}" -cpf "${ROOTFS_TAR}" .
chmod 0644 "${ROOTFS_TAR}"

if [ "${ROOTFS_MODE}" = "ro-overlay" ]; then
    ROOTFS_IMAGE="${VARIANT_OUTPUT}/rootfs.squashfs"
    rm -f "${ROOTFS_IMAGE}"
    log_step "Packing read-only SquashFS root filesystem"
    mksquashfs "${ROOT_DIR}" "${ROOTFS_IMAGE}" \
        -comp zstd -noappend -no-progress
    chmod 0644 "${ROOTFS_IMAGE}"

    # Content checks against the staged tree (equivalent to the ext4 checks).
    [ -d "${ROOT_DIR}/usr/lib/modules/${KERNEL_RELEASE}" ] ||
        die "Debian rootfs does not contain modules for ${KERNEL_RELEASE}"
    [ -L "${ROOT_DIR}/lib" ] ||
        die "Debian rootfs lost the /lib usrmerge symlink"
    [ -e "${ROOT_DIR}/usr/lib/ld-linux-aarch64.so.1" ] ||
        die "Debian rootfs lacks the AArch64 ELF interpreter"
    [ -e "${ROOT_DIR}/usr/lib/systemd/systemd" ] ||
        die "Debian rootfs lacks systemd init"
    grep -Eq '^root:[^!*:][^:]*:' "${ROOT_DIR}/etc/shadow" ||
        die "Debian root account is not enabled"
else
    ROOTFS_IMAGE="${VARIANT_OUTPUT}/rootfs.ext4"
    rm -f "${ROOTFS_IMAGE}"
    truncate -s "${ROOTFS_SIZE_MIB}M" "${ROOTFS_IMAGE}"
    mkfs.ext4 -F -L rootfs -d "${ROOT_DIR}" "${ROOTFS_IMAGE}"
    tune2fs -m 0 "${ROOTFS_IMAGE}"
    e2fsck -fn "${ROOTFS_IMAGE}"
    chmod 0644 "${ROOTFS_IMAGE}"

    [ "$(blkid -s LABEL -o value "${ROOTFS_IMAGE}")" = "rootfs" ] ||
        die "Debian rootfs label is not rootfs"
    debugfs -R "stat /usr/lib/modules/${KERNEL_RELEASE}" "${ROOTFS_IMAGE}" 2>&1 |
        grep -q 'Inode:' ||
        die "Debian rootfs does not contain modules for ${KERNEL_RELEASE}"
    debugfs -R "stat /usr/lib/modules/${KERNEL_RELEASE}" "${ROOTFS_IMAGE}" 2>&1 |
        grep -Eq 'User:[[:space:]]+0[[:space:]]+Group:[[:space:]]+0' ||
        die "Debian kernel modules are not owned by root"
    debugfs -R "stat /lib" "${ROOTFS_IMAGE}" 2>&1 |
        grep -q 'Type: symlink' ||
        die "Debian rootfs lost the /lib usrmerge symlink"
    debugfs -R "stat /usr/lib/ld-linux-aarch64.so.1" "${ROOTFS_IMAGE}" 2>&1 |
        grep -q 'Inode:' ||
        die "Debian rootfs lacks the AArch64 ELF interpreter"
    debugfs -R "stat /usr/lib/systemd/systemd" "${ROOTFS_IMAGE}" 2>&1 |
        grep -q 'Inode:' ||
        die "Debian rootfs lacks systemd init"
    debugfs -R "cat /etc/shadow" "${ROOTFS_IMAGE}" 2>/dev/null |
        grep -Eq '^root:[^!*:][^:]*:' ||
        die "Debian root account is not enabled"
fi

run_hook post_build_rootfs

# Determine the active network stack for metadata (NetworkManager wins over
# systemd-networkd; default to none). Computed once into a variable so the
# write_common_metadata call below stays readable.
if [ -e "${ROOT_DIR}/etc/systemd/system/multi-user.target.wants/NetworkManager.service" ]; then
    NETWORK_STACK=NetworkManager
elif [ -e "${ROOT_DIR}/etc/systemd/system/multi-user.target.wants/systemd-networkd.service" ]; then
    NETWORK_STACK=systemd-networkd
else
    NETWORK_STACK=none
fi

write_common_metadata "${VARIANT_OUTPUT}/rootfs-build-info.txt" \
    "source_manifest=${SOURCE_MANIFEST:-}" \
    "kernel_revision=$(git_revision "${SDK_DIR}/kernel")" \
    "rootfs=debian" \
    "rootfs_arch=arm64" \
    "debian_release=${DEBIAN_RELEASE}" \
    "debian_codename=${DEBIAN_CODENAME}" \
    "debian_packages=${DEBIAN_PACKAGES:-}" \
    "debian_overlays=${DEBIAN_OVERLAYS:-}" \
    "rootfs_mode=${ROOTFS_MODE}" \
    "hostname=${ROOTFS_HOSTNAME}" \
    "network_stack=${NETWORK_STACK}" \
    "kernel_release=${KERNEL_RELEASE}" \
    "username=${ROOTFS_USERNAME}" \
    "root_login=enabled" \
    "rootfs_size_mib=${ROOTFS_SIZE_MIB}"

log_info "Debian rootfs: ${ROOTFS_IMAGE}"
