#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

load_board_profile
validate_board_source_revisions
ROOTFS=debian
resolve_debian_release
require_cmd mmdebstrap dpkg chroot systemctl tar truncate mkfs.ext4 \
    tune2fs e2fsck blkid debugfs depmod realpath

[ "$(id -u)" -eq 0 ] || die "Debian rootfs build must run as root"
[ "$(dpkg --print-architecture)" = "arm64" ] ||
    die "Debian rootfs builder must run as linux/arm64; enable Docker binfmt emulation"

COMMON_OUTPUT="$(board_common_output_dir)"
VARIANT_OUTPUT="$(variant_output_dir)"
DEBIAN_BUILD="$(board_build_dir "debian-${DEBIAN_RELEASE}")"
ROOT_DIR="${DEBIAN_BUILD}/root"
MODULES_TAR="${COMMON_OUTPUT}/modules.tar"
KERNEL_RELEASE_FILE="${COMMON_OUTPUT}/kernel-release"
ROOTFS_USERNAME="${ROOTFS_USERNAME:-rk3588}"
ROOTFS_PASSWORD="${ROOTFS_PASSWORD:-rk3588}"
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
PACKAGE_LIST="$(IFS=,; printf '%s' "${PACKAGES[*]}")"

run_mmdebstrap() {
    local -a sources=("$@")
    mmdebstrap \
        --architectures=arm64 \
        --variant=minbase \
        "--components=${DEBIAN_COMPONENTS// /,}" \
        "--include=${PACKAGE_LIST}" \
        --aptopt='Acquire::Languages "none"' \
        "${DEBIAN_CODENAME}" "${ROOT_DIR}" "${sources[@]}"
}

REGULAR_SOURCES=(
    "deb ${DEBIAN_MIRROR} ${DEBIAN_CODENAME} ${DEBIAN_COMPONENTS}"
    "deb ${DEBIAN_MIRROR} ${DEBIAN_CODENAME}-updates ${DEBIAN_COMPONENTS}"
    "deb ${DEBIAN_SECURITY_MIRROR} ${DEBIAN_CODENAME}-security ${DEBIAN_COMPONENTS}"
)

log_step "Building Debian ${DEBIAN_RELEASE} (${DEBIAN_CODENAME}) rootfs"
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

printf 'rk3588\n' >"${ROOT_DIR}/etc/hostname"
printf '127.0.0.1 localhost\n127.0.1.1 rk3588\n' >"${ROOT_DIR}/etc/hosts"

chroot "${ROOT_DIR}" useradd -m -s /bin/bash -G sudo "${ROOTFS_USERNAME}"
printf '%s:%s\n' "${ROOTFS_USERNAME}" "${ROOTFS_PASSWORD}" |
    chroot "${ROOT_DIR}" chpasswd
printf 'root:%s\n' "${ROOTFS_PASSWORD}" |
    chroot "${ROOT_DIR}" chpasswd
chroot "${ROOT_DIR}" passwd -u root

install -d "${ROOT_DIR}/etc/systemd/network" \
    "${ROOT_DIR}/etc/systemd/system/ssh.service.d" \
    "${ROOT_DIR}/etc/ssh/sshd_config.d"
cat >"${ROOT_DIR}/etc/systemd/network/20-wired.network" <<'EOF'
[Match]
Name=en* eth*

[Network]
DHCP=yes
IPv6AcceptRA=yes
EOF
cat >"${ROOT_DIR}/etc/ssh/sshd_config.d/10-rk3588.conf" <<'EOF'
PasswordAuthentication yes
PermitRootLogin yes
EOF
cat >"${ROOT_DIR}/etc/systemd/system/ssh.service.d/10-hostkeys.conf" <<'EOF'
[Service]
ExecStartPre=
ExecStartPre=/usr/bin/ssh-keygen -A
ExecStartPre=/usr/sbin/sshd -t
EOF

rm -f "${ROOT_DIR}"/etc/ssh/ssh_host_* "${ROOT_DIR}/etc/machine-id"
: >"${ROOT_DIR}/etc/machine-id"
ln -snf /run/systemd/resolve/stub-resolv.conf "${ROOT_DIR}/etc/resolv.conf"

if [ ! -L "${ROOT_DIR}/lib" ] ||
    [ "$(readlink "${ROOT_DIR}/lib")" != "usr/lib" ]; then
    die "Debian usrmerge layout is missing /lib -> usr/lib"
fi
install -d "${ROOT_DIR}/usr/lib"
tar --no-same-owner --strip-components=1 -xpf "${MODULES_TAR}" \
    -C "${ROOT_DIR}/usr/lib"
KERNEL_RELEASE="$(cat "${KERNEL_RELEASE_FILE}")"
depmod -b "${ROOT_DIR}" "${KERNEL_RELEASE}"
chroot "${ROOT_DIR}" /bin/true ||
    die "Debian userspace is not executable after installing kernel modules"

install -d "${ROOT_DIR}/usr/local/sbin" "${ROOT_DIR}/etc/systemd/system" \
    "${ROOT_DIR}/etc/systemd/system/serial-getty@${CONSOLE_DEVICE}.service.d"
cat >"${ROOT_DIR}/etc/systemd/system/serial-getty@${CONSOLE_DEVICE}.service.d/10-baud.conf" <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-- \\\\u' --noreset --noclear --keep-baud ${CONSOLE_SPEED},115200,57600,38400,9600 - \${TERM}
EOF
cat >"${ROOT_DIR}/usr/local/sbin/rk3588-firstboot" <<'EOF'
#!/bin/sh
set -eu

MARKER=/var/lib/rk3588-firstboot.done
[ ! -e "$MARKER" ] || exit 0

rootdev="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
rootdev="$(readlink -f "$rootdev" 2>/dev/null || true)"
if [ -z "$rootdev" ] || [ ! -b "$rootdev" ]; then
    rootdev="$(findfs PARTLABEL=rootfs 2>/dev/null || true)"
fi
if [ -z "$rootdev" ] || [ ! -b "$rootdev" ]; then
    echo "Unable to locate rootfs block device" >&2
    exit 1
fi

rootdev_name="${rootdev#/dev/}"
sys_block="/sys/class/block/$rootdev_name"
if [ ! -r "$sys_block/partition" ]; then
    echo "Unable to locate partition metadata for $rootdev" >&2
    exit 1
fi
partnum="$(cat "$sys_block/partition")"
rootdisk_name="$(basename "$(dirname "$(readlink -f "$sys_block")")")"
case "$partnum" in
    ''|*[!0-9]*)
        echo "Unable to determine root partition number for $rootdev" >&2
        exit 1
        ;;
esac
rootdisk="/dev/$rootdisk_name"
if [ -z "$rootdisk_name" ] || [ ! -b "$rootdisk" ]; then
    echo "Unable to determine parent disk for $rootdev" >&2
    exit 1
fi

sgdisk -e "$rootdisk"
if ! grow_output="$(growpart "$rootdisk" "$partnum" 2>&1)"; then
    case "$grow_output" in
        *NOCHANGE*) printf '%s\n' "$grow_output" ;;
        *)
            printf '%s\n' "$grow_output" >&2
            exit 1
            ;;
    esac
else
    printf '%s\n' "$grow_output"
fi
partx -u --nr "$partnum" "$rootdisk"
udevadm settle
resize2fs "$rootdev"

mkdir -p "$(dirname "$MARKER")"
touch "$MARKER"
systemctl disable rk3588-firstboot.service >/dev/null 2>&1 || true
EOF
chmod 0755 "${ROOT_DIR}/usr/local/sbin/rk3588-firstboot"

cat >"${ROOT_DIR}/etc/systemd/system/rk3588-firstboot.service" <<'EOF'
[Unit]
Description=Expand RK3588 root filesystem on first boot
After=local-fs.target
ConditionPathExists=!/var/lib/rk3588-firstboot.done

[Service]
Type=oneshot
ExecStart=-/usr/local/sbin/rk3588-firstboot
RemainAfterExit=yes
TimeoutStartSec=10min

[Install]
WantedBy=multi-user.target
EOF

enable_unit() {
    local unit="$1"
    local unit_file target wants_dir
    # Try systemctl first; on x86_64+QEMU it may fail due to missing linker.
    if systemctl --root="${ROOT_DIR}" enable "${unit}" 2>/dev/null; then
        return 0
    fi
    # Fall back: create the [Install] symlink(s) manually.
    # Check both /lib and /usr/lib for the unit file.
    for unit_file in "${ROOT_DIR}/lib/systemd/system/${unit}" \
                     "${ROOT_DIR}/usr/lib/systemd/system/${unit}"; do
        if [ -f "${unit_file}" ]; then
            break
        fi
        unit_file=""
    done
    # Handle template instances: serial-getty@ttyFIQ0.service -> serial-getty@.service
    if [ -z "${unit_file}" ]; then
        local template="${unit%%@*}@.service"
        for unit_file in "${ROOT_DIR}/lib/systemd/system/${template}" \
                         "${ROOT_DIR}/usr/lib/systemd/system/${template}"; do
            if [ -f "${unit_file}" ]; then
                break
            fi
            unit_file=""
        done
    fi
    # Match the [Install] target used by the Debian unit.
    case "${unit}" in
        *.socket) target="sockets.target.wants" ;;
        serial-getty@*.service) target="getty.target.wants" ;;
        systemd-resolved.service) target="sysinit.target.wants" ;;
        *) target="multi-user.target.wants" ;;
    esac
    wants_dir="${ROOT_DIR}/etc/systemd/system/${target}"
    mkdir -p "${wants_dir}"
    if [ -n "${unit_file}" ]; then
        ln -sf "${unit_file#"${ROOT_DIR}"}" "${wants_dir}/${unit}"
        return 0
    fi
    die "Unable to enable Debian systemd unit: ${unit}"
}

enable_unit systemd-networkd.service
enable_unit systemd-resolved.service
enable_unit ssh.service
enable_unit rk3588-firstboot.service
enable_unit "serial-getty@${CONSOLE_DEVICE}.service"

chroot "${ROOT_DIR}" systemd-analyze verify --man=no \
    multi-user.target rk3588-firstboot.service \
    "serial-getty@${CONSOLE_DEVICE}.service" ssh.service \
    systemd-networkd.service systemd-resolved.service
chroot "${ROOT_DIR}" ssh-keygen -A
install -d -m 0755 "${ROOT_DIR}/run/sshd"
chroot "${ROOT_DIR}" sshd -t
rm -rf "${ROOT_DIR}/run/sshd"
rm -f "${ROOT_DIR}"/etc/ssh/ssh_host_*

rm -rf "${ROOT_DIR}/var/lib/apt/lists/"* \
    "${ROOT_DIR}/var/cache/apt/archives/"*.deb \
    "${ROOT_DIR}/tmp/"* "${ROOT_DIR}/var/tmp/"*

ROOTFS_IMAGE="${VARIANT_OUTPUT}/rootfs.ext4"
ROOTFS_TAR="${VARIANT_OUTPUT}/rootfs.tar"
rm -f "${ROOTFS_IMAGE}" "${ROOTFS_TAR}"
truncate -s "${ROOTFS_SIZE_MIB}M" "${ROOTFS_IMAGE}"
mkfs.ext4 -F -L rootfs -d "${ROOT_DIR}" "${ROOTFS_IMAGE}"
tune2fs -m 0 "${ROOTFS_IMAGE}"
e2fsck -fn "${ROOTFS_IMAGE}"
tar --numeric-owner --xattrs --acls -C "${ROOT_DIR}" -cpf "${ROOTFS_TAR}" .
chmod 0644 "${ROOTFS_IMAGE}" "${ROOTFS_TAR}"

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

write_common_metadata "${VARIANT_OUTPUT}/rootfs-build-info.txt" \
    "source_manifest=${SOURCE_MANIFEST:-}" \
    "kernel_revision=$(git_revision "${SDK_DIR}/kernel")" \
    "rootfs=debian" \
    "debian_release=${DEBIAN_RELEASE}" \
    "debian_codename=${DEBIAN_CODENAME}" \
    "kernel_release=${KERNEL_RELEASE}" \
    "username=${ROOTFS_USERNAME}" \
    "root_login=enabled" \
    "rootfs_size_mib=${ROOTFS_SIZE_MIB}"

log_info "Debian rootfs: ${ROOTFS_IMAGE}"
