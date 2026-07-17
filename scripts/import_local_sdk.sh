#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
export PROJECT_DIR

# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

SDK_PATH="${SDK_PATH:-}"
SDK_VOLUME="${SDK_VOLUME:-}"

require_cmd docker realpath

[ -n "${SDK_PATH}" ] ||
    die "SDK_PATH is required. Use: make import-local-sdk SDK_PATH=/absolute/path SDK_VOLUME=rk3588-sdk-local"
[ -n "${SDK_VOLUME}" ] ||
    die "SDK_VOLUME is required. Use: make import-local-sdk SDK_PATH=/absolute/path SDK_VOLUME=rk3588-sdk-local"
validate_token "SDK_VOLUME" "${SDK_VOLUME}"

SDK_PATH="$(realpath -e -- "${SDK_PATH}" 2>/dev/null || true)"
if [ -z "${SDK_PATH}" ] || [ ! -d "${SDK_PATH}" ]; then
    die "SDK_PATH does not exist or is not a directory"
fi

for component in kernel u-boot rkbin buildroot; do
    require_dir "${SDK_PATH}/${component}" "SDK component ${component}"
done

if docker volume inspect "${SDK_VOLUME}" >/dev/null 2>&1; then
    volume_type="$(docker volume inspect --format \
        '{{with .Options}}{{index . "type"}}{{end}}' "${SDK_VOLUME}")"
    volume_options="$(docker volume inspect --format \
        '{{with .Options}}{{index . "o"}}{{end}}' "${SDK_VOLUME}")"
    volume_device="$(docker volume inspect --format \
        '{{with .Options}}{{index . "device"}}{{end}}' "${SDK_VOLUME}")"

    case ",${volume_options}," in
        *,bind,*) ;;
        *)
            die "Docker volume ${SDK_VOLUME} already exists and is not a bind-backed local SDK volume"
            ;;
    esac
    [ "${volume_type}" = "none" ] ||
        die "Docker volume ${SDK_VOLUME} has unexpected type: ${volume_type:-unset}"

    existing_path="$(realpath -e -- "${volume_device}" 2>/dev/null || true)"
    [ "${existing_path}" = "${SDK_PATH}" ] ||
        die "Docker volume ${SDK_VOLUME} already points to ${volume_device:-an unknown path}, not ${SDK_PATH}"

    log_info "Reusing ${SDK_VOLUME}, already bound to ${SDK_PATH}"
else
    log_step "Creating bind-backed Docker volume ${SDK_VOLUME}"
    docker volume create \
        --driver local \
        --opt type=none \
        --opt o=bind \
        --opt "device=${SDK_PATH}" \
        --label com.rk3588-build.sdk=local \
        "${SDK_VOLUME}" >/dev/null
fi

log_info "SDK source remains at ${SDK_PATH}; no SDK source copy was made"
log_info "Docker volume ready: ${SDK_VOLUME} -> ${SDK_PATH}"
