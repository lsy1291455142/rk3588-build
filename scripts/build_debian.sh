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
# nodes/symlinks so those commands do not fail with "Couldn't open /dev/null".
ensure_chroot_dev() {
    local d="${ROOT_DIR}/dev"
    mkdir -p "${d}"

    # Force-recreate when the path is missing or not a real char device.
    # mmdebstrap / prior failed runs can leave empty files or wrong node types;
    # opening those under qemu-user yields
    # "Couldn't open /dev/null: Permission denied".
    _ensure_char_dev() {
        local name="$1" mode="$2"
        local path="${d}/${name}"
        if [ -c "${path}" ]; then
            chmod "${mode}" "${path}" 2>/dev/null || true
            return 0
        fi
        rm -f "${path}" 2>/dev/null || true
        # Copy the host's device node: `cp -a` does NOT require CAP_MKNOD, so
        # this works in unprivileged environments (e.g. GitHub Codespaces)
        # where mknod/mount --bind are blocked. There is no mknod fallback by
        # design — every Docker container has a working /dev/null etc., so the
        # only failure mode is a broken build host, which should surface loudly.
        if [ -c "/dev/${name}" ]; then
            cp -a "/dev/${name}" "${path}" 2>/dev/null && return 0
        fi
        log_warn "cannot create /dev/${name} in staged rootfs (host lacks the node)"
        return 1
    }
    _ensure_char_dev null    666
    _ensure_char_dev zero    666
    _ensure_char_dev full    666
    _ensure_char_dev random  666
    _ensure_char_dev urandom 666
    _ensure_char_dev tty     666
    _ensure_char_dev ptmx    666
    # /dev/console as a real char device so mkinitramfs can copy it into the
    # initramfs; without it update-initramfs prints
    # "W: skipping creation of ./dev/console because ./dev/console does not
    # exist on the outside". Copied from the host when present.
    _ensure_char_dev console 600
    [ -e "${d}/stdin" ]  || ln -sf /proc/self/fd/0 "${d}/stdin" 2>/dev/null || true
    [ -e "${d}/stdout" ] || ln -sf /proc/self/fd/1 "${d}/stdout" 2>/dev/null || true
    [ -e "${d}/stderr" ] || ln -sf /proc/self/fd/2 "${d}/stderr" 2>/dev/null || true
    [ -e "${d}/fd" ]     || ln -sf /proc/self/fd "${d}/fd" 2>/dev/null || true
    # Sanity: a working /dev/null is required by almost every later chroot step.
    if ! chroot "${ROOT_DIR}" /bin/sh -c ': > /dev/null' 2>/dev/null; then
        log_warn "Staged /dev/null is not usable; chroot verify steps may warn"
    fi
}

# Run a command with host runtime mounts over the staged rootfs.
# Tools such as systemd-analyze verify, sshd -t and update-initramfs need
# /proc, /sys and /run inside the chroot. /dev nodes are provided by
# ensure_chroot_dev (copied from the host via cp -a, no privileges needed),
# so there is NO mount --bind of /dev — this project targets unprivileged
# environments (e.g. GitHub Codespaces) by default and never relies on
# CAP_SYS_ADMIN. proc/sys/run are mounted (when permitted) and unmounted
# afterwards so the final rootfs tar/squashfs never captures host trees.
with_host_dev() {
    local -a mounted=()
    local mp

    _mount_one() {
        local src="$1" dst="$2" type="$3" opts="${4:-}"
        mkdir -p "${dst}"
        if [ -n "${opts}" ]; then
            mount -t "${type}" -o "${opts}" "${src}" "${dst}" 2>/dev/null
        else
            mount -t "${type}" "${src}" "${dst}" 2>/dev/null
        fi && mounted+=("${dst}")
    }

    _mount_one proc  "${ROOT_DIR}/proc" proc  || true
    _mount_one sysfs "${ROOT_DIR}/sys"  sysfs || true
    _mount_one tmpfs "${ROOT_DIR}/run"  tmpfs "mode=0755,size=64m" || true

    # tmpfs over /run hides any pre-created paths under the staged root.
    # OpenSSH's sshd -t requires the privilege-separation directory.
    install -d -m 0755 "${ROOT_DIR}/run/sshd" 2>/dev/null || true
    install -d -m 1777 "${ROOT_DIR}/run/lock" 2>/dev/null || true
    install -d -m 0755 "${ROOT_DIR}/run/systemd" 2>/dev/null || true
    install -d -m 0755 "${ROOT_DIR}/tmp" 2>/dev/null || true

    if [ ! -c "${ROOT_DIR}/dev/console" ] && [ -c /dev/console ]; then
        cp -a /dev/console "${ROOT_DIR}/dev/console" 2>/dev/null || true
    fi

    set +e
    "$@"
    local rc=$?
    set -e

    # Unmount in reverse order.
    if [ "${#mounted[@]}" -gt 0 ]; then
        local i
        for ((i = ${#mounted[@]} - 1; i >= 0; i--)); do
            mp="${mounted[i]}"
            umount "${mp}" 2>/dev/null || umount -l "${mp}" 2>/dev/null || true
        done
    fi
    # Restore staged /dev nodes after the host bind is gone.
    ensure_chroot_dev
    return "${rc}"
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
# Point resolv.conf at systemd-resolved's stub resolver whenever the
# resolved unit is installed (Debian >=12 ships it in the systemd package).
# This is a system-package check, not tied to any overlay.
if [ -f "${ROOT_DIR}/lib/systemd/system/systemd-resolved.service" ] ||
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

# Verify every enabled unit: scan all *.target.wants directories and pick
# symlinks whose unit file exists. The build core stays free of hard-coded
# service names; whatever overlays enable is verified generically.
VERIFY_UNITS=(multi-user.target)
while IFS= read -r u; do
    VERIFY_UNITS+=("${u}")
done < <(collect_enabled_units "${ROOT_DIR}")
set +e
verify_out="$(
    with_host_dev chroot "${ROOT_DIR}" \
        env SYSTEMD_SECCOMP=0 SYSTEMD_OFFLINE=1 \
        systemd-analyze verify --man=no "${VERIFY_UNITS[@]}" 2>&1
)"
verify_rc=$?
set -e
if [ "${verify_rc}" -ne 0 ]; then
    # Under qemu-user/binfmt, systemd-analyze can still fail while creating a
    # private /dev for sandboxed units even with host mounts. Unit files are
    # still installed; treat known /dev/null failures as non-fatal so the
    # image build can proceed, but keep real unit syntax errors hard.
    if printf '%s\n' "${verify_out}" | grep -Eq "Couldn't open /dev/null|Permission denied|/dev/console|Operation not permitted|Failed to (create|open).*dev"; then
        log_warn "systemd-analyze verify failed under build env (non-fatal):"
        printf '%s\n' "${verify_out}" | sed 's/^/[WARN] /' >&2
    else
        printf '%s\n' "${verify_out}" >&2
        die "systemd-analyze verify failed (rc=${verify_rc})"
    fi
fi
if [ -x "${ROOT_DIR}/usr/sbin/sshd" ] || [ -x "${ROOT_DIR}/usr/bin/sshd" ]; then
    chroot "${ROOT_DIR}" ssh-keygen -A
    # /run/sshd is recreated inside with_host_dev after the tmpfs mount on /run;
    # creating it only on the staged tree would be hidden by that mount.
    with_host_dev chroot "${ROOT_DIR}" \
        /bin/sh -c 'install -d -m 0755 /run/sshd && sshd -t'
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
    with_host_dev chroot "${ROOT_DIR}" update-initramfs -c -k "${KERNEL_RELEASE}"
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
    "kernel_release=${KERNEL_RELEASE}" \
    "username=${ROOTFS_USERNAME}" \
    "root_login=enabled" \
    "rootfs_size_mib=${ROOTFS_SIZE_MIB}"

log_info "Debian rootfs: ${ROOTFS_IMAGE}"
