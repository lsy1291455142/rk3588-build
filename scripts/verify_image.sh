#!/usr/bin/env bash
set -Eeuo pipefail

export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

load_board_profile
validate_board_source_revisions
validate_rootfs_choice
if [ "${ROOTFS}" = "debian" ]; then
    resolve_debian_release
fi

require_cmd sgdisk stat dd cmp mdir mcopy grep awk sed sha256sum \
    blkid e2fsck debugfs realpath fdtget

COMMON_OUTPUT="$(board_common_output_dir)"
VARIANT_OUTPUT="$(variant_output_dir)"
IMAGE_STEM="$(image_stem)"
IMAGE_PATH="${IMAGE_PATH:-${VARIANT_OUTPUT}/${IMAGE_STEM}.img}"
SHA256_PATH="${VARIANT_OUTPUT}/${IMAGE_STEM}.sha256"
KERNEL_IMAGE="${COMMON_OUTPUT}/Image"
DTB_IMAGE="${COMMON_OUTPUT}/${KERNEL_DTB}"
DOWNLOAD_LOADER_IMAGE="${COMMON_OUTPUT}/download-loader.bin"
IDBLOCK_IMAGE="${COMMON_OUTPUT}/idblock.img"
UBOOT_IMAGE="${COMMON_OUTPUT}/uboot.img"
ROOTFS_IMAGE="${VARIANT_OUTPUT}/rootfs.ext4"
KERNEL_RELEASE_FILE="${COMMON_OUTPUT}/kernel-release"
KERNEL_CONFIG="${COMMON_OUTPUT}/kernel.config"
KERNEL_BUILD_INFO="${COMMON_OUTPUT}/kernel-build-info.txt"
UBOOT_BUILD_INFO="${COMMON_OUTPUT}/uboot-build-info.txt"
ROOTFS_BUILD_INFO="${VARIANT_OUTPUT}/rootfs-build-info.txt"
IMAGE_BUILD_INFO="${VARIANT_OUTPUT}/image-build-info.txt"
ROOTFS_USERNAME="${ROOTFS_USERNAME:-rk3588}"

require_file "${IMAGE_PATH}" "raw disk image"
require_file "${SHA256_PATH}" "image checksum file"
require_file "${KERNEL_IMAGE}" "kernel Image"
require_file "${DTB_IMAGE}" "board DTB"
require_file "${DOWNLOAD_LOADER_IMAGE}" "download-loader.bin"
require_file "${IDBLOCK_IMAGE}" "idblock.img"
require_file "${UBOOT_IMAGE}" "uboot.img"
require_file "${ROOTFS_IMAGE}" "rootfs.ext4"
require_file "${KERNEL_RELEASE_FILE}" "kernel release"
require_file "${KERNEL_CONFIG}" "kernel configuration"
require_file "${KERNEL_BUILD_INFO}" "kernel build metadata"
require_file "${UBOOT_BUILD_INFO}" "U-Boot build metadata"
require_file "${ROOTFS_BUILD_INFO}" "rootfs build metadata"
require_file "${IMAGE_BUILD_INFO}" "image build metadata"

verify_extlinux_dtb() {
    local dtb="$1"
    local description="$2"

    fdtget -l "${dtb}" / >/dev/null ||
        die "${description} is not a valid DTB: ${dtb}"
    if fdtget -t s "${dtb}" /chosen bootargs >/dev/null 2>&1; then
        die "${description} defines /chosen/bootargs and can override extlinux"
    fi
}

verify_extlinux_dtb "${DTB_IMAGE}" "Board DTB artifact"
[ "$(metadata_value "${KERNEL_BUILD_INFO}" dtb_bootargs)" = \
    "extlinux-only-v1" ] ||
    die "Kernel metadata does not record the extlinux-only DTB contract"

if [ -n "${SOURCE_MANIFEST:-}" ]; then
    [ "$(metadata_value "${KERNEL_BUILD_INFO}" source_manifest)" = "${SOURCE_MANIFEST}" ] ||
        die "Kernel metadata does not identify ${SOURCE_MANIFEST}"
    [ "$(metadata_value "${KERNEL_BUILD_INFO}" kernel_revision)" = \
        "${EXPECTED_KERNEL_REVISION}" ] || die "Kernel metadata revision mismatch"
    [ "$(metadata_value "${UBOOT_BUILD_INFO}" uboot_revision)" = \
        "${EXPECTED_UBOOT_REVISION}" ] || die "U-Boot metadata revision mismatch"
    [ "$(metadata_value "${UBOOT_BUILD_INFO}" rkbin_revision)" = \
        "${EXPECTED_RKBIN_REVISION}" ] || die "rkbin metadata revision mismatch"
    [ "$(metadata_value "${IMAGE_BUILD_INFO}" buildroot_revision)" = \
        "${EXPECTED_BUILDROOT_REVISION}" ] || die "Buildroot metadata revision mismatch"
fi

for required_config in \
    CONFIG_AUTOFS_FS=y CONFIG_CGROUPS=y CONFIG_DEVTMPFS=y \
    CONFIG_DEVTMPFS_MOUNT=y CONFIG_EXT4_FS=y CONFIG_FHANDLE=y \
    CONFIG_HW_RANDOM_VIRTIO=y CONFIG_MEMCG=y CONFIG_MMC_BLOCK=y \
    CONFIG_NAMESPACES=y CONFIG_RTC_DRV_PL031=y CONFIG_SECCOMP=y \
    CONFIG_SERIAL_AMBA_PL011=y CONFIG_SERIAL_AMBA_PL011_CONSOLE=y \
    CONFIG_TMPFS=y CONFIG_TMPFS_POSIX_ACL=y CONFIG_TMPFS_XATTR=y \
    CONFIG_UNIX=y CONFIG_VIRTIO=y CONFIG_VIRTIO_BLK=y \
    CONFIG_VIRTIO_MMIO=y CONFIG_VIRTIO_NET=y; do
    grep -qx "${required_config}" "${KERNEL_CONFIG}" ||
        die "Kernel artifact lacks required configuration ${required_config}"
done

WORK_DIR="$(mktemp -d "${VARIANT_OUTPUT}/.image-verify.XXXXXX")"
trap 'rm -rf -- "${WORK_DIR}"' EXIT

IMAGE_SECTORS=$((IMAGE_SIZE_MIB * 2048))
BOOT_FIRST_EXPECTED=$((BOOT_START_MIB * 2048))
BOOT_LAST_EXPECTED=$((BOOT_FIRST_EXPECTED + BOOT_SIZE_MIB * 2048 - 1))
ROOT_FIRST_EXPECTED=$((BOOT_LAST_EXPECTED + 1))
ROOT_LAST_EXPECTED=$((IMAGE_SECTORS - 34))
IMAGE_BYTES_EXPECTED=$((IMAGE_SIZE_MIB * 1024 * 1024))

[ "$(stat -c '%s' "${IMAGE_PATH}")" -eq "${IMAGE_BYTES_EXPECTED}" ] ||
    die "Unexpected image size: ${IMAGE_PATH}"
sgdisk --verify "${IMAGE_PATH}" >/dev/null

partition_field() {
    local partition="$1"
    local field="$2"
    sgdisk --info="${partition}" "${IMAGE_PATH}" |
        awk -F: -v wanted="${field}" '
            $1 == wanted {
                value = $2
                sub(/^[[:space:]]+/, "", value)
                print value
                exit
            }'
}

first_sector() {
    partition_field "$1" "First sector" | awk '{print $1}'
}

last_sector() {
    partition_field "$1" "Last sector" | awk '{print $1}'
}

partition_code() {
    sgdisk -p "${IMAGE_PATH}" 2>/dev/null | awk -v n="$1" '$1 == n {print $6}'
}

partition_name() {
    partition_field "$1" "Partition name" | sed "s/^'//;s/'$//"
}

[ "$(first_sector 1)" = "${BOOT_FIRST_EXPECTED}" ] ||
    die "Boot partition starts at the wrong sector"
[ "$(last_sector 1)" = "${BOOT_LAST_EXPECTED}" ] ||
    die "Boot partition ends at the wrong sector"
[ "$(partition_code 1)" = "0700" ] ||
    die "Boot partition type is not 0700"
[ "$(partition_name 1)" = "boot" ] ||
    die "Boot partition name is not boot"
[ "$(first_sector 2)" = "${ROOT_FIRST_EXPECTED}" ] ||
    die "Root partition starts at the wrong sector"
[ "$(last_sector 2)" = "${ROOT_LAST_EXPECTED}" ] ||
    die "Root partition ends at the wrong sector"
[ "$(partition_code 2)" = "8300" ] ||
    die "Root partition type is not 8300"
[ "$(partition_name 2)" = "rootfs" ] ||
    die "Root partition name is not rootfs"

extract_bytes() {
    local source="$1"
    local destination="$2"
    local offset="$3"
    local count="$4"
    dd if="${source}" of="${destination}" bs=4M \
        iflag=skip_bytes,count_bytes skip="${offset}" count="${count}" \
        conv=sparse status=none
}

compare_embedded_file() {
    local expected="$1"
    local sector="$2"
    local extracted="$3"
    local size
    size="$(stat -c '%s' "${expected}")"
    extract_bytes "${IMAGE_PATH}" "${extracted}" "$((sector * 512))" "${size}"
    cmp --silent "${expected}" "${extracted}" ||
        die "Embedded data does not match $(basename "${expected}")"
}

read_image_magic() {
    dd if="$1" bs=1 count=4 status=none
}

bootloader_layout_verify "${IMAGE_PATH}" "${COMMON_OUTPUT}" "${WORK_DIR}"

BOOT_OFFSET=$((BOOT_FIRST_EXPECTED * 512))
MTOOLS_IMAGE="${IMAGE_PATH}@@${BOOT_OFFSET}"
mdir -i "${MTOOLS_IMAGE}" :: >/dev/null
mcopy -i "${MTOOLS_IMAGE}" ::/Image "${WORK_DIR}/Image"
mcopy -i "${MTOOLS_IMAGE}" "::/${KERNEL_DTB}" "${WORK_DIR}/${KERNEL_DTB}"
mcopy -i "${MTOOLS_IMAGE}" ::/extlinux/extlinux.conf "${WORK_DIR}/extlinux.conf"
cmp --silent "${KERNEL_IMAGE}" "${WORK_DIR}/Image" ||
    die "FAT Image does not match the kernel artifact"
cmp --silent "${DTB_IMAGE}" "${WORK_DIR}/${KERNEL_DTB}" ||
    die "FAT DTB does not match the board artifact"
verify_extlinux_dtb "${WORK_DIR}/${KERNEL_DTB}" "FAT DTB"
grep -Fqx "    FDT /${KERNEL_DTB}" "${WORK_DIR}/extlinux.conf" ||
    die "extlinux.conf does not select ${KERNEL_DTB}"
grep -Fq "root=PARTLABEL=rootfs rootwait rw" "${WORK_DIR}/extlinux.conf" ||
    die "extlinux.conf does not boot root=PARTLABEL=rootfs"
grep -Fq "console=${CONSOLE}" "${WORK_DIR}/extlinux.conf" ||
    die "extlinux.conf does not configure ${CONSOLE}"

ROOTFS_BYTES="$(stat -c '%s' "${ROOTFS_IMAGE}")"
extract_bytes "${IMAGE_PATH}" "${WORK_DIR}/rootfs.ext4" \
    "$((ROOT_FIRST_EXPECTED * 512))" "${ROOTFS_BYTES}"
cmp --silent "${ROOTFS_IMAGE}" "${WORK_DIR}/rootfs.ext4" ||
    die "Embedded rootfs does not match rootfs.ext4"
e2fsck -fn "${WORK_DIR}/rootfs.ext4" >/dev/null
[ "$(blkid -s LABEL -o value "${WORK_DIR}/rootfs.ext4")" = "rootfs" ] ||
    die "Embedded root filesystem label is not rootfs"

KERNEL_RELEASE="$(cat "${KERNEL_RELEASE_FILE}")"
if [ "${ROOTFS}" = "buildroot" ]; then
    MODULES_DIR="/lib/modules/${KERNEL_RELEASE}"
else
    debugfs -R "cat /etc/debian_version" "${WORK_DIR}/rootfs.ext4" 2>/dev/null |
        grep -Eq "^${DEBIAN_RELEASE}([.]|$)" ||
        die "Debian rootfs is not Debian ${DEBIAN_RELEASE}"
    MODULES_DIR="/usr/lib/modules/${KERNEL_RELEASE}"
fi
debugfs -R "stat ${MODULES_DIR}" "${WORK_DIR}/rootfs.ext4" 2>&1 |
    grep -q 'Inode:' || die "Embedded rootfs lacks modules for ${KERNEL_RELEASE}"
debugfs -R "stat ${MODULES_DIR}" "${WORK_DIR}/rootfs.ext4" 2>&1 |
    grep -Eq 'User:[[:space:]]+0[[:space:]]+Group:[[:space:]]+0' ||
    die "Embedded kernel modules are not owned by root"
debugfs -R "cat /etc/passwd" "${WORK_DIR}/rootfs.ext4" 2>/dev/null |
    grep -q "^${ROOTFS_USERNAME}:" ||
    die "Embedded rootfs lacks user ${ROOTFS_USERNAME}"
debugfs -R "cat /etc/shadow" "${WORK_DIR}/rootfs.ext4" 2>/dev/null |
    grep -Eq '^root:[^!*:][^:]*:' ||
    die "Embedded root account is not enabled"

if [ "${ROOTFS}" = "buildroot" ]; then
    debugfs -R "cat /etc/init.d/S02rootfs-resize" \
        "${WORK_DIR}/rootfs.ext4" 2>/dev/null |
        grep -Fq "resize2fs \"\$rootdev\"" ||
        die "Buildroot rootfs lacks the first-boot resize hook"
else
    debugfs -R "stat /lib" "${WORK_DIR}/rootfs.ext4" 2>&1 |
        grep -q 'Type: symlink' ||
        die "Debian rootfs lost the /lib usrmerge symlink"
    debugfs -R "stat /usr/lib/ld-linux-aarch64.so.1" \
        "${WORK_DIR}/rootfs.ext4" 2>&1 | grep -q 'Inode:' ||
        die "Debian rootfs lacks the AArch64 ELF interpreter"
    debugfs -R "stat /usr/lib/systemd/systemd" \
        "${WORK_DIR}/rootfs.ext4" 2>&1 | grep -q 'Inode:' ||
        die "Debian rootfs lacks systemd init"
    debugfs -R "cat /usr/local/sbin/sbc-firstboot" \
        "${WORK_DIR}/rootfs.ext4" 2>/dev/null |
        grep -Fq "sgdisk -e \"\$rootdisk\"" ||
        die "Debian rootfs lacks the first-boot GPT repair"
    debugfs -R "cat /usr/local/sbin/sbc-firstboot" \
        "${WORK_DIR}/rootfs.ext4" 2>/dev/null |
        grep -Fq "partnum=\"\$(cat \"\$sys_block/partition\")\"" ||
        die "Debian rootfs does not derive the root partition from sysfs"
    debugfs -R "cat /usr/local/sbin/sbc-firstboot" \
        "${WORK_DIR}/rootfs.ext4" 2>/dev/null |
        grep -Fq "growpart \"\$rootdisk\" \"\$partnum\"" ||
        die "Debian rootfs lacks the first-boot partition growth"
    debugfs -R "cat /usr/local/sbin/sbc-firstboot" \
        "${WORK_DIR}/rootfs.ext4" 2>/dev/null |
        grep -Fq "resize2fs \"\$rootdev\"" ||
        die "Debian rootfs lacks the first-boot filesystem growth"
    debugfs -R "cat /etc/systemd/system/sbc-firstboot.service" \
        "${WORK_DIR}/rootfs.ext4" 2>/dev/null |
        grep -Fq 'WantedBy=multi-user.target' ||
        die "Debian rootfs lacks the first-boot resize service"
    if debugfs -R "cat /etc/systemd/system/sbc-firstboot.service" \
        "${WORK_DIR}/rootfs.ext4" 2>/dev/null | grep -Fq 'Before=ssh.service'; then
        die "Debian first-boot resize must not block SSH startup"
    fi
    debugfs -R "cat /etc/systemd/system/sbc-firstboot.service" \
        "${WORK_DIR}/rootfs.ext4" 2>/dev/null |
        grep -Fq 'TimeoutStartSec=10min' ||
        die "Debian first-boot resize service lacks a startup timeout"
    debugfs -R "cat /etc/systemd/system/sbc-firstboot.service" \
        "${WORK_DIR}/rootfs.ext4" 2>/dev/null |
        grep -Fq 'ExecStart=-/usr/local/sbin/sbc-firstboot' ||
        die "Debian first-boot resize failure can degrade system startup"
    debugfs -R "cat /etc/systemd/system/ssh.service.d/10-hostkeys.conf" \
        "${WORK_DIR}/rootfs.ext4" 2>/dev/null |
        grep -Fq 'ExecStartPre=/usr/bin/ssh-keygen -A' ||
        die "Debian SSH service does not generate missing host keys"
    CONSOLE_SPEED="${CONSOLE#*,}"
    CONSOLE_SPEED="${CONSOLE_SPEED%%[!0-9]*}"
    debugfs -R "cat /etc/systemd/system/serial-getty@${CONSOLE%%,*}.service.d/10-baud.conf" \
        "${WORK_DIR}/rootfs.ext4" 2>/dev/null |
        grep -Fq -- "--keep-baud ${CONSOLE_SPEED},115200" ||
        die "Debian serial getty does not preserve the board console speed"
    debugfs -R "stat /usr/sbin/sgdisk" "${WORK_DIR}/rootfs.ext4" 2>&1 |
        grep -q 'Inode:' || die "Debian rootfs lacks sgdisk"
    debugfs -R "stat /usr/bin/growpart" "${WORK_DIR}/rootfs.ext4" 2>&1 |
        grep -q 'Inode:' || die "Debian rootfs lacks growpart"
    ROOTFS_META="${VARIANT_OUTPUT}/rootfs-build-info.txt"
    NETWORK_STACK="systemd-networkd"
    DEBIAN_FEATURES_META=""
    if [ -f "${ROOTFS_META}" ]; then
        NETWORK_STACK="$(metadata_value "${ROOTFS_META}" network_stack || true)"
        DEBIAN_FEATURES_META="$(metadata_value "${ROOTFS_META}" debian_packages || true)"
        if [ -z "${DEBIAN_FEATURES_META}" ]; then
            DEBIAN_FEATURES_META="$(metadata_value "${ROOTFS_META}" debian_features || true)"
        fi
        NETWORK_STACK="${NETWORK_STACK:-systemd-networkd}"
    fi
    if [ "${NETWORK_STACK}" = "NetworkManager" ]; then
        NET_UNIT_PATH=/etc/systemd/system/multi-user.target.wants/NetworkManager.service
        debugfs -R "stat ${NET_UNIT_PATH}" "${WORK_DIR}/rootfs.ext4" 2>&1 |
            grep -q 'Inode:' || die "Debian rootfs does not enable NetworkManager"
        debugfs -R "stat /usr/bin/nmtui" "${WORK_DIR}/rootfs.ext4" 2>&1 |
            grep -q 'Inode:' || die "Debian rootfs with nm feature lacks nmtui"
        if debugfs -R "stat /etc/systemd/system/multi-user.target.wants/systemd-networkd.service" \
            "${WORK_DIR}/rootfs.ext4" 2>&1 | grep -q 'Inode:'; then
            die "Debian NetworkManager rootfs must not enable systemd-networkd"
        fi
    else
        NET_UNIT_PATH=/etc/systemd/system/multi-user.target.wants/systemd-networkd.service
        debugfs -R "stat ${NET_UNIT_PATH}" "${WORK_DIR}/rootfs.ext4" 2>&1 |
            grep -q 'Inode:' || die "Debian rootfs does not enable systemd-networkd"
    fi
    for enabled_path in \
        /etc/systemd/system/sysinit.target.wants/systemd-resolved.service \
        /etc/systemd/system/multi-user.target.wants/ssh.service \
        /etc/systemd/system/multi-user.target.wants/sbc-firstboot.service \
        "/etc/systemd/system/getty.target.wants/serial-getty@${CONSOLE%%,*}.service"; do
        debugfs -R "stat ${enabled_path}" "${WORK_DIR}/rootfs.ext4" 2>&1 |
            grep -q 'Inode:' || die "Debian rootfs does not enable ${enabled_path##*/}"
    done
    # Package presence checks use the recorded apt package list (exact names).
    case ",${DEBIAN_FEATURES_META}," in
        *,i2c-tools,*)
            debugfs -R "stat /usr/sbin/i2cdetect" "${WORK_DIR}/rootfs.ext4" 2>&1 |
                grep -q 'Inode:' || die "Debian rootfs with i2c-tools lacks i2cdetect"
            ;;
    esac
    # firstboot-info is a plugin (default on); verify helper when present in image tree.
    if debugfs -R "stat /usr/local/sbin/sbc-firstboot" "${WORK_DIR}/rootfs.ext4" 2>&1 | grep -q 'Inode:'; then
        debugfs -R "cat /usr/local/sbin/sbc-firstboot" \
            "${WORK_DIR}/rootfs.ext4" 2>/dev/null |
            grep -Fq 'sbc-firstboot-info' ||
            die "Debian firstboot does not optionally invoke firstboot-info"
    fi
    if debugfs -R "stat /usr/local/sbin/sbc-firstboot-info" \
        "${WORK_DIR}/rootfs.ext4" 2>&1 | grep -q 'Inode:'; then
        :
    fi
    # WiFi firmware is driven by WIFIBT_* metadata, not package tokens.
    WIFIBT_SOURCE_META="$(metadata_value "${ROOTFS_META}" wifibt_source || true)"
    WIFIBT_FILES_META="$(metadata_value "${ROOTFS_META}" wifibt_files || true)"
    case "${WIFIBT_SOURCE_META}" in
        skipped|none|missing|empty|'')
            ;;
        *)
            debugfs -R "stat /lib/firmware" "${WORK_DIR}/rootfs.ext4" 2>&1 |
                grep -q 'Inode:' || die "Debian wifibt install lacks /lib/firmware"
            debugfs -R "stat /vendor" "${WORK_DIR}/rootfs.ext4" 2>&1 |
                grep -q 'Inode:' || die "Debian wifibt install lacks /vendor link"
            if [ -n "${WIFIBT_FILES_META}" ] && [ "${WIFIBT_FILES_META}" != "0" ]; then
                :
            else
                die "Debian wifibt metadata reports zero firmware files"
            fi
            ;;
    esac
    case ",${DEBIAN_FEATURES_META}," in
        *,wpasupplicant,*)
            debugfs -R "stat /usr/sbin/wpa_supplicant" "${WORK_DIR}/rootfs.ext4" 2>&1 |
                grep -q 'Inode:' || die "Debian rootfs with wpasupplicant lacks binary"
            ;;
    esac
fi

(
    cd "${VARIANT_OUTPUT}"
    sha256sum --check "$(basename "${SHA256_PATH}")"
)

log_info "Image verification passed: ${IMAGE_PATH}"
