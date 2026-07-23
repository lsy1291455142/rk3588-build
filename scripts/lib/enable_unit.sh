#!/usr/bin/env bash
# Enable a systemd unit inside the staged Debian rootfs.
# Prefer `systemctl --root=... enable`; only fall back to hand-crafted
# [Install] symlinks when systemctl is unavailable (e.g. under x86_64 + QEMU
# binfmt where the linker may be missing). This is a LAST RESORT path, not the
# primary mechanism.

if [ -n "${_ENABLE_UNIT_SH_SOURCED:-}" ]; then
    return
fi
_ENABLE_UNIT_SH_SOURCED=1

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
