#!/bin/sh
# Per-board self-check hook for Rock 5C (sourced by scripts/check.sh).
# The core check.sh must not hardcode any board name; board contracts live here.
board_check() {
    local profile="${BOARD_DIR}/board.conf"
    local expected
    local -a markers=(
        'SOURCE_MANIFEST="rk3588-rock5c.xml"'
        'EXPECTED_KERNEL_REVISION="567401fe17185f0f4a65866158b775a364feb2d3"'
        'EXPECTED_UBOOT_REVISION="4218b05a597f458947f0f4706063b3bb8196e07c"'
        'EXPECTED_RKBIN_REVISION="ecb4fcbe954edf38b3ae037d5de6d9f5bccf81f4"'
        'EXPECTED_BUILDROOT_REVISION="c49ae7216786d3cb62a8e8de5556007b4b539233"'
        'UBOOT_PYTHON="python3"'
    )
    for expected in "${markers[@]}"; do
        grep -Fqx "${expected}" "${profile}" || return 1
    done

    # Pinned source revisions must match the manifest.
    manifest="${PROJECT_DIR}/manifests/rk3588-rock5c.xml"
    [ -f "${manifest}" ] || return 1
    grep -q 'revision="567401fe17185f0f4a65866158b775a364feb2d3"' "${manifest}" || return 1
    grep -q 'revision="4218b05a597f458947f0f4706063b3bb8196e07c"' "${manifest}" || return 1
    grep -q 'revision="ecb4fcbe954edf38b3ae037d5de6d9f5bccf81f4"' "${manifest}" || return 1
    grep -q 'revision="c49ae7216786d3cb62a8e8de5556007b4b539233"' "${manifest}" || return 1

    awk '
        /^  debian-rootfs:/ { in_service = 1; next }
        in_service && /^  [a-zA-Z0-9_-]+:/ { exit }
        in_service && /\.\/manifests:\/home\/builder\/manifests:ro/ { found = 1 }
        END { exit(found ? 0 : 1) }
    ' "${PROJECT_DIR}/docker-compose.yml" || return 1
    grep -Fq 'COPY manifests/ /home/builder/manifests/' "${PROJECT_DIR}/Dockerfile" || return 1
    grep -Eq '^[[:space:]]+git[[:space:]]' "${PROJECT_DIR}/Dockerfile" || return 1
    grep -Fq "git -c safe.directory=\"\${repo}\"" "${PROJECT_DIR}/scripts/lib/common.sh"
}
