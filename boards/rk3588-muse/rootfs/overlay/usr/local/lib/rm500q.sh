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
# Set APN and establish data connection
# Args: $1 = APN (optional, defaults to RM500Q_APN)
# Returns: 0 on success, 1 on failure
# -----------------------------------------------------------------------------
rm500q_connect() {
    local apn="${1:-${RM500Q_APN}}"

    if ! rm500q_at_ready; then
        echo "ERROR: Modem AT port not available (${RM500Q_AT_PORT})" >&2
        return 1
    fi

    echo "Setting APN: ${apn}"
    rm500q_at_send "+CGDCONT=1,\"IP\",\"${apn}\"" || {
        echo "ERROR: Failed to set APN" >&2
        return 1
    }

    echo "Opening data connection..."
    rm500q_at_send "+QNETOPENCTL=1,1" 10 || {
        echo "ERROR: Failed to open data connection" >&2
        return 1
    }

    echo "Acquiring IP via DHCP on ${RM500Q_DATA_IFACE}..."
    if command -v udhcpc >/dev/null 2>&1; then
        udhcpc -i "${RM500Q_DATA_IFACE}" -q -n
    elif command -v dhclient >/dev/null 2>&1; then
        dhclient "${RM500Q_DATA_IFACE}"
    else
        echo "WARN: No DHCP client found, configure ${RM500Q_DATA_IFACE} manually" >&2
    fi

    # Verify connection
    if ip addr show "${RM500Q_DATA_IFACE}" 2>/dev/null | grep -q "inet "; then
        echo "Connected: $(ip addr show "${RM500Q_DATA_IFACE}" | grep "inet " | awk '{print $2}')"
        return 0
    else
        echo "ERROR: No IP address on ${RM500Q_DATA_IFACE}" >&2
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Disconnect data connection
# Returns: 0 on success, 1 on failure
# -----------------------------------------------------------------------------
rm500q_disconnect() {
    echo "Closing data connection..."
    rm500q_at_send "+QNETOPENCTL=0,0" 10 2>/dev/null || true

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
}
