#!/usr/bin/env bash
# =============================================================================
# MUSE RK3588 — RM500Q-GL 5G modem helper library
# =============================================================================
# Used by rm500q-connect.sh and rootfs plugin.sh.
#
# Modem:  Quectel RM500Q-GL (5G NR Sub-6GHz, Qualcomm SDX55)
# Bus:    PCIe 2.0 x1 (pcie2x1l2, combphy0_ps PCIe mode)
# Driver: Quectel PCIe MHI Driver V1.4 (self-contained pcie_mhi.ko)
#         Does NOT use mainline MHI bus — has its own MHI core.
#
# Device nodes (PCIe/MHI mode, V1.4 driver):
#   AT command channel:  /dev/mhi_DUN
#   QMI channel:         /dev/mhi_QMI0
#   MBIM channel:        /dev/mhi_MBIM
#   DIAG channel:        /dev/mhi_DIAG
#   Data network iface:  rmnet_mhi0 + rmnet_mhi0.1 (QMAP multiplex)
#
# Connection manager: quectel-CM V1.6.8 (QConnectManager_Linux)
#   Source: https://github.com/QuectelWB/q_drivers
#   Detects MHI devices via /sys/bus/mhi_q/devices/
#   Establishes PDN via QMI, configures QMAP, obtains IP via udhcpc
#   AT commands used only for status/signal/registration queries
#
# GPIO control (from DTS rk3588-muse.dts):
#   Power:  GPIO0_C6 → Q21 level shifter → FULL_CARD_POWER_OFF#
#           HIGH = power ON, LOW = power OFF
#   Reset:  GPIO0_B2 (4G_5G_RSTn)
#           HIGH = out of reset, LOW = in reset
#   PERST#: GPIO4_C1 (PCIe reset, managed by PCIe controller)
# =============================================================================
# Environment overrides:
#   RM500Q_AT_PORT    — AT command char device (default: /dev/mhi_DUN)
#   RM500Q_DATA_IFACE — data network interface  (default: rmnet_mhi0.1)
#   RM500Q_APN        — APN for data connection (default: cmnet)
#   RM500Q_AT_TIMEOUT — AT command timeout sec  (default: 5)
# =============================================================================

RM500Q_AT_PORT="${RM500Q_AT_PORT:-/dev/mhi_DUN}"
RM500Q_DATA_IFACE="${RM500Q_DATA_IFACE:-rmnet_mhi0.1}"
RM500Q_APN="${RM500Q_APN:-cmnet}"
RM500Q_AT_TIMEOUT="${RM500Q_AT_TIMEOUT:-5}"

# quectel-CM binary path
RM500Q_CM_BIN="${RM500Q_CM_BIN:-/usr/local/sbin/quectel-CM}"
# quectel-CM log file (empty = stderr only)
RM500Q_CM_LOG="${RM500Q_CM_LOG:-/var/log/quectel-CM.log}"
# quectel-CM PID file
RM500Q_CM_PID="${RM500Q_CM_PID:-/var/run/quectel-CM.pid}"

# GPIO paths (sysfs)
_RM500Q_GPIO_POWER="/sys/class/gpio/gpio14/value"   # GPIO0_C6 = 0*32+2*8+6 = 22
_RM500Q_GPIO_RESET="/sys/class/gpio/gpio10/value"   # GPIO0_B2 = 0*32+1*8+2 = 10

# -----------------------------------------------------------------------------
# Detect modem presence on PCIe bus
# Returns: 0 if found, 1 if not found
# -----------------------------------------------------------------------------
rm500q_detect() {
    if lspci -nn 2>/dev/null | grep -q "17cb:"; then
        return 0
    fi
    # Also check MHI device nodes
    if [ -e "${RM500Q_AT_PORT}" ]; then
        return 0
    fi
    return 1
}

# -----------------------------------------------------------------------------
# Check if AT port is available
# Returns: 0 if available, 1 if not
# -----------------------------------------------------------------------------
rm500q_at_ready() {
    [ -c "${RM500Q_AT_PORT}" ] || [ -e "${RM500Q_AT_PORT}" ]
}

# -----------------------------------------------------------------------------
# Send AT command and return response
# Args: $1 = AT command (without trailing \r)
# Outputs: response lines (stripped of AT echo and OK/ERROR)
# Returns: 0 on OK, 1 on ERROR or timeout
# -----------------------------------------------------------------------------
rm500q_at_send() {
    local cmd="$1"
    local timeout="${2:-${RM500Q_AT_TIMEOUT}}"

    if ! rm500q_at_ready; then
        echo "ERROR: AT port ${RM500Q_AT_PORT} not available" >&2
        return 1
    fi

    # Send command with CR, read response with timeout
    local resp
    resp=$(echo -e "AT${cmd}\r" | timeout "${timeout}" cat "${RM500Q_AT_PORT}" 2>/dev/null)

    if echo "${resp}" | grep -q "OK"; then
        # Return response lines excluding echo, OK, and empty lines
        echo "${resp}" | grep -v -E "^AT${cmd}|^OK$|^$" || true
        return 0
    elif echo "${resp}" | grep -q "ERROR"; then
        echo "${resp}" | grep -v -E "^AT${cmd}|^$" >&2 || true
        return 1
    else
        echo "ERROR: timeout or no response" >&2
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Check network registration status
# Outputs: registration state string
# Returns: 0 if registered, 1 if not
# -----------------------------------------------------------------------------
rm500q_check_registration() {
    local resp
    resp=$(rm500q_at_send "+CEREG?" 2>/dev/null) || true

    # +CEREG: <n>,<stat>
    # 0=not registered, 1=registered(home), 2=searching, 3=denied
    # 4=unknown, 5=registered(roaming), 6=registered(home,5G), 7=registered(roaming,5G)
    local stat
    stat=$(echo "${resp}" | grep -o "+CEREG: [0-9],[0-9]" | awk -F, '{print $2}')
    stat="${stat:-0}"

    case "${stat}" in
        1|5) echo "registered (LTE)" ;;
        6|7) echo "registered (5G)" ;;
        2)   echo "searching" ;;
        3)   echo "denied" ;;
        *)   echo "not registered" ;;
    esac

    [ "${stat}" = "1" ] || [ "${stat}" = "5" ] || \
    [ "${stat}" = "6" ] || [ "${stat}" = "7" ]
}

# -----------------------------------------------------------------------------
# Get signal quality
# Outputs: signal info
# -----------------------------------------------------------------------------
rm500q_signal_quality() {
    rm500q_at_send "+QCSQ" 2>/dev/null || echo "unknown"
}

# -----------------------------------------------------------------------------
# Get current serving cell info (5G/LTE band, RSRP, etc.)
# Outputs: serving cell info
# -----------------------------------------------------------------------------
rm500q_serving_cell() {
    rm500q_at_send '+QENG="servingcell"' 2>/dev/null || echo "unknown"
}

# -----------------------------------------------------------------------------
# Check if quectel-CM is available
# Returns: 0 if available, 1 if not
# -----------------------------------------------------------------------------
rm500q_cm_available() {
    [ -x "${RM500Q_CM_BIN}" ]
}

# -----------------------------------------------------------------------------
# Check if quectel-CM is currently running
# Returns: 0 if running, 1 if not
# -----------------------------------------------------------------------------
rm500q_cm_running() {
    if [ -f "${RM500Q_CM_PID}" ]; then
        local pid
        pid=$(cat "${RM500Q_CM_PID}" 2>/dev/null) || return 1
        [ -n "${pid}" ] && kill -0 "${pid}" 2>/dev/null
    else
        pgrep -x "$(basename "${RM500Q_CM_BIN}")" >/dev/null 2>&1
    fi
}

# -----------------------------------------------------------------------------
# Establish data connection using quectel-CM (QMI over PCIe/MHI)
#
# quectel-CM handles the full connection sequence:
#   1. Detect MHI device via /sys/bus/mhi_q/devices/
#   2. Open QMI channel (/dev/mhi_QMI0)
#   3. Establish PDN connection via QMI protocol
#   4. Configure QMAP multiplexing on rmnet_mhi0.1
#   5. Obtain IP address via udhcpc
#
# Args: $1 = APN (optional, defaults to RM500Q_APN)
# Returns: 0 on success, 1 on failure
# -----------------------------------------------------------------------------
rm500q_connect() {
    local apn="${1:-${RM500Q_APN}}"

    if ! rm500q_cm_available; then
        echo "ERROR: quectel-CM not found at ${RM500Q_CM_BIN}" >&2
        echo "       Install quectel-CM to establish PCIe/MHI data connections" >&2
        return 1
    fi

    if rm500q_cm_running; then
        echo "quectel-CM already running (connection active)"
        return 0
    fi

    if ! rm500q_detect; then
        echo "ERROR: RM500Q-GL modem not detected on PCIe bus" >&2
        return 1
    fi

    echo "Starting quectel-CM (APN: ${apn}, iface: ${RM500Q_DATA_IFACE})..."

    # Build quectel-CM command
    # -s <apn>           : set APN
    # -i <iface>         : specify network interface
    # -f <logfile>       : log to file
    # -4                 : IPv4 data call (default)
    local cm_args=(-s "${apn}" -i "${RM500Q_DATA_IFACE}" -4)
    if [ -n "${RM500Q_CM_LOG}" ]; then
        cm_args+=(-f "${RM500Q_CM_LOG}")
    fi

    # Start quectel-CM in background
    mkdir -p "$(dirname "${RM500Q_CM_PID}")" 2>/dev/null || true
    "${RM500Q_CM_BIN}" "${cm_args[@]}" &
    local cm_pid=$!
    echo "${cm_pid}" > "${RM500Q_CM_PID}"

    # Wait for connection (quectel-CM sets up interface within ~5-15s)
    local waited=0
    local timeout=30
    while [ "${waited}" -lt "${timeout}" ]; do
        if ! kill -0 "${cm_pid}" 2>/dev/null; then
            echo "ERROR: quectel-CM exited prematurely" >&2
            rm -f "${RM500Q_CM_PID}"
            return 1
        fi
        if ip addr show "${RM500Q_DATA_IFACE}" 2>/dev/null | grep -q "inet "; then
            local ip_addr
            ip_addr=$(ip addr show "${RM500Q_DATA_IFACE}" | grep "inet " | awk '{print $2}')
            echo "Connected: ${ip_addr} on ${RM500Q_DATA_IFACE}"
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done

    echo "ERROR: Connection timeout after ${timeout}s" >&2
    echo "       Check log: ${RM500Q_CM_LOG}" >&2
    return 1
}

# -----------------------------------------------------------------------------
# Disconnect data connection (stop quectel-CM)
# Returns: 0 on success, 1 on failure
# -----------------------------------------------------------------------------
rm500q_disconnect() {
    if ! rm500q_cm_running; then
        echo "quectel-CM not running (already disconnected)"
        # Still try to bring interface down
        ip link set "${RM500Q_DATA_IFACE}" down 2>/dev/null || true
        return 0
    fi

    echo "Stopping quectel-CM..."

    local pid=""
    if [ -f "${RM500Q_CM_PID}" ]; then
        pid=$(cat "${RM500Q_CM_PID}" 2>/dev/null) || true
    fi
    if [ -z "${pid}" ]; then
        pid=$(pgrep -x "$(basename "${RM500Q_CM_BIN}")" 2>/dev/null | head -1) || true
    fi

    if [ -n "${pid}" ]; then
        kill -INT "${pid}" 2>/dev/null || true
        # Wait for clean exit
        local waited=0
        while [ "${waited}" -lt 10 ]; do
            kill -0 "${pid}" 2>/dev/null || break
            sleep 1
            waited=$((waited + 1))
        done
        kill -9 "${pid}" 2>/dev/null || true
    fi

    rm -f "${RM500Q_CM_PID}"
    ip link set "${RM500Q_DATA_IFACE}" down 2>/dev/null || true
    echo "Disconnected"
    return 0
}

# -----------------------------------------------------------------------------
# Show full modem status
# -----------------------------------------------------------------------------
rm500q_status() {
    echo "=== RM500Q-GL Modem Status ==="
    echo

    # PCIe detection
    if rm500q_detect; then
        echo "[PCIe] Modem detected:"
        lspci -nn 2>/dev/null | grep "17cb:" | sed 's/^/  /'
    else
        echo "[PCIe] Modem NOT detected"
        return 1
    fi
    echo

    # AT port
    if rm500q_at_ready; then
        echo "[AT] Port: ${RM500Q_AT_PORT} (ready)"

        # Model info
        local model
        model=$(rm500q_at_send "I" 2>/dev/null) || true
        echo "[Model] ${model:-unknown}"

        # Registration
        local reg
        reg=$(rm500q_check_registration 2>/dev/null) || true
        echo "[Network] ${reg:-unknown}"

        # Signal
        local sig
        sig=$(rm500q_signal_quality 2>/dev/null) || true
        echo "[Signal] ${sig:-unknown}"

        # Serving cell
        local cell
        cell=$(rm500q_serving_cell 2>/dev/null) || true
        echo "[Cell] ${cell:-unknown}"
    else
        echo "[AT] Port ${RM500Q_AT_PORT} not available"
        echo "       (modem may still be booting or MHI driver not loaded)"
    fi
    echo

    # Data interface
    if ip link show "${RM500Q_DATA_IFACE}" >/dev/null 2>&1; then
        echo "[Data] Interface: ${RM500Q_DATA_IFACE} (exists)"
        if ip addr show "${RM500Q_DATA_IFACE}" 2>/dev/null | grep -q "inet "; then
            echo "  IP: $(ip addr show "${RM500Q_DATA_IFACE}" | grep "inet " | awk '{print $2}')"
            echo "  State: CONNECTED"
        else
            echo "  State: disconnected (no IP)"
        fi
    else
        echo "[Data] Interface ${RM500Q_DATA_IFACE} not found"
    fi
    echo

    # quectel-CM status
    if rm500q_cm_available; then
        echo "[CM] quectel-CM: ${RM500Q_CM_BIN}"
        if rm500q_cm_running; then
            echo "  State: running"
        else
            echo "  State: not running"
        fi
    else
        echo "[CM] quectel-CM not installed"
    fi
}

# =============================================================================
# Build-time firmware installation (used by plugin.sh)
# =============================================================================
# RM500Q-GL modem firmware is NOT publicly downloadable. It must be obtained
# from Quectel (FAE / customer portal). The plugin supports:
#   1. Pre-staged overlay: overlay/lib/firmware/sdx55m/*.mbn
#   2. Package cache:      packages/rm500q-gl-firmware*.tar.gz
#   3. URL download:       RM500Q_FIRMWARE_URL env var
#   4. Skip with warning   (build succeeds, modem won't boot without firmware)
#
# Firmware path in rootfs: /lib/firmware/sdx55m/
# Expected files: sbl1.mbn, amss.mbn, boot1.mbn (names may vary by release)
# NOTE: V1.4 driver uses /lib/firmware/sdx55m/ (NOT /lib/firmware/qcom/sdx55m/)
# =============================================================================

RM500Q_FW_DIR="sdx55m"

# Check if firmware blobs exist in a directory (excluding SOURCE.txt)
_rm500q_has_blobs() {
    local dir="$1"
    [ -d "${dir}" ] || return 1
    [ -n "$(find "${dir}" -type f ! -name 'SOURCE.txt' ! -name '.gitkeep' 2>/dev/null | head -n 1)" ]
}

# Default firmware URL (empty — Quectel does not publish public downloads)
_rm500q_default_url() {
    printf '%s\n' "${RM500Q_FIRMWARE_URL:-}"
}

# Download firmware package to cache dir
_rm500q_download_to() {
    local url="$1" dest="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "${dest}.partial" "${url}"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "${dest}.partial" "${url}"
    else
        echo "ERROR: need curl or wget" >&2
        return 1
    fi
    mv "${dest}.partial" "${dest}"
}

# Resolve firmware source: local file, packages/ cache, or URL download
# Args: board_dir [src_path_or_url] [writable_cache_dir]
# Returns: path to firmware package file (prints to stdout)
_rm500q_resolve_pkg() {
    local board_dir="$1"
    local src="${2:-}"
    local cache_dir="${3:-}"
    local pkg_dir name dest

    pkg_dir="${board_dir}/packages"
    if [ -z "${cache_dir}" ]; then
        if [ -d "${pkg_dir}" ] && [ -w "${pkg_dir}" ]; then
            cache_dir="${pkg_dir}"
        else
            cache_dir="$(mktemp -d)"
        fi
    fi
    install -d "${cache_dir}" 2>/dev/null || true

    # If no explicit source, search packages/ for rm500q firmware
    if [ -z "${src}" ]; then
        if [ -d "${pkg_dir}" ]; then
            dest="$(find "${pkg_dir}" -maxdepth 1 -type f \( -name 'rm500q*firmware*' -o -name 'RM500Q*' \) 2>/dev/null | sort | tail -n 1 || true)"
            if [ -n "${dest}" ]; then
                printf '%s\n' "${dest}"
                return 0
            fi
        fi
        src="$(_rm500q_default_url)"
        if [ -z "${src}" ]; then
            return 1  # No source available
        fi
    fi

    # URL download
    if [[ "${src}" =~ ^https?:// ]]; then
        name="$(basename "${src%%\?*}")"
        if [ -f "${pkg_dir}/${name}" ]; then
            printf '%s\n' "${pkg_dir}/${name}"
            return 0
        fi
        dest="${cache_dir}/${name}"
        if [ ! -f "${dest}" ]; then
            if declare -F log_info >/dev/null 2>&1; then
                log_info "Downloading ${src} -> ${dest}"
            else
                echo "Downloading ${src} -> ${dest}"
            fi
            _rm500q_download_to "${src}" "${dest}" || return 1
        fi
        printf '%s\n' "${dest}"
        return 0
    fi

    # Local file
    [ -f "${src}" ] || { echo "ERROR: not a file: ${src}" >&2; return 1; }
    printf '%s\n' "${src}"
}

# Extract firmware files from package into dest_dir
# Supports: .tar.gz, .tar.xz, .tar.zst, .deb, or raw .mbn files
# Args: pkg_file dest_dir
_rm500q_extract_to() {
    local pkg="$1"
    local dest_dir="$2"
    local work extract src_dir count

    [ -f "${pkg}" ] || { echo "ERROR: package not found: ${pkg}" >&2; return 1; }
    [ -n "${dest_dir}" ] || { echo "ERROR: dest_dir required" >&2; return 1; }

    work="$(mktemp -d)"
    extract="${work}/extract"
    mkdir -p "${extract}"

    case "${pkg}" in
        *.deb)
            if command -v dpkg-deb >/dev/null 2>&1; then
                dpkg-deb -x "${pkg}" "${extract}"
            else
                (cd "${work}" && ar x "${pkg}" && \
                    (tar -C "${extract}" -xJf data.tar.xz 2>/dev/null || \
                     tar -C "${extract}" -xzf data.tar.gz 2>/dev/null || \
                     tar -C "${extract}" --zstd -xf data.tar.zst 2>/dev/null))
            fi
            # Search for firmware files in extracted tree
            src_dir="$(find "${extract}" -type f -name '*.mbn' -exec dirname {} \; 2>/dev/null | head -n 1 || true)"
            ;;
        *.tar.gz|*.tgz)
            tar -C "${extract}" -xzf "${pkg}"
            src_dir="${extract}"
            ;;
        *.tar.xz|*.txz)
            tar -C "${extract}" -xJf "${pkg}"
            src_dir="${extract}"
            ;;
        *.tar.zst)
            tar -C "${extract}" --zstd -xf "${pkg}"
            src_dir="${extract}"
            ;;
        *.mbn)
            # Raw firmware file
            cp "${pkg}" "${extract}/"
            src_dir="${extract}"
            ;;
        *)
            echo "ERROR: unsupported package format: ${pkg}" >&2
            rm -rf "${work}"
            return 1
            ;;
    esac

    if [ -z "${src_dir}" ] || [ ! -d "${src_dir}" ]; then
        echo "ERROR: no firmware files found in ${pkg}" >&2
        rm -rf "${work}"
        return 1
    fi

    # Copy .mbn files (and any other firmware blobs) to dest
    install -d "${dest_dir}"
    local fw_files=0
    while IFS= read -r -d '' f; do
        cp -a "${f}" "${dest_dir}/"
        fw_files=$((fw_files + 1))
    done < <(find "${src_dir}" -type f \( -name '*.mbn' -o -name '*.bin' -o -name '*.elf' \) -print0 2>/dev/null)

    rm -rf "${work}"

    if [ "${fw_files}" -eq 0 ]; then
        echo "ERROR: zero firmware files extracted from ${pkg}" >&2
        return 1
    fi
    if declare -F log_info >/dev/null 2>&1; then
        log_info "Extracted ${fw_files} RM500Q-GL firmware files into ${dest_dir}"
    else
        echo "Extracted ${fw_files} files into ${dest_dir}"
    fi
}

# Install RM500Q-GL firmware into rootfs (build-time; no writes to board dir)
# Args: root_dir board_dir [pkg_path_or_url]
install_rm500q_firmware_into_rootfs() {
    local root_dir="$1"
    local board_dir="$2"
    local src="${3:-}"
    local fw_dest pkg work_cache extract_dir

    [ -n "${root_dir}" ] || { echo "ERROR: root_dir required" >&2; return 1; }
    [ -n "${board_dir}" ] || { echo "ERROR: board_dir required" >&2; return 1; }

    fw_dest="${root_dir}/lib/firmware/${RM500Q_FW_DIR}"

    # Already installed in rootfs?
    if _rm500q_has_blobs "${fw_dest}"; then
        if declare -F log_info >/dev/null 2>&1; then
            log_info "RM500Q-GL firmware already present in rootfs"
        fi
        return 0
    fi

    # Pre-staged in board overlay?
    if _rm500q_has_blobs "${board_dir}/overlay/lib/firmware/${RM500Q_FW_DIR}"; then
        if declare -F log_info >/dev/null 2>&1; then
            log_info "Using pre-staged board overlay RM500Q-GL firmware"
        fi
        install -d "${fw_dest}"
        cp -a "${board_dir}/overlay/lib/firmware/${RM500Q_FW_DIR}/."* "${fw_dest}/" 2>/dev/null
        return 0
    fi

    # Try to resolve and install from package
    work_cache="$(mktemp -d)"
    extract_dir="$(mktemp -d)"
    pkg="$(_rm500q_resolve_pkg "${board_dir}" "${src}" "${work_cache}")" || {
        rm -rf "${work_cache}" "${extract_dir}"
        if declare -F log_warn >/dev/null 2>&1; then
            log_warn "RM500Q-GL firmware not found (no package/URL/overlay)"
            log_warn "Modem will not boot without firmware. Obtain from Quectel and:"
            log_warn "  - Place in ${board_dir}/packages/ and rebuild, or"
            log_warn "  - Pre-stage in overlay/lib/firmware/${RM500Q_FW_DIR}/, or"
            log_warn "  - Set RM500Q_FIRMWARE_URL env var"
        else
            echo "WARN: RM500Q-GL firmware not found — modem won't boot"
        fi
        return 0  # Don't fail the build
    }

    if declare -F log_info >/dev/null 2>&1; then
        log_info "Installing RM500Q-GL firmware from ${pkg}"
    else
        echo "Package: ${pkg}"
    fi
    _rm500q_extract_to "${pkg}" "${extract_dir}" || {
        rm -rf "${work_cache}" "${extract_dir}"
        return 1
    }
    install -d "${fw_dest}"
    cp -a "${extract_dir}/"* "${fw_dest}/" 2>/dev/null
    rm -rf "${work_cache}" "${extract_dir}"
}
