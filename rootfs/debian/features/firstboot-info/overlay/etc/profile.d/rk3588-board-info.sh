# Show board summary once per interactive login until dismissed.
if [ -n "${PS1:-}" ] && [ -r /var/lib/rk3588-board-info ] &&
    [ ! -e "$HOME/.rk3588-board-info.seen" ]; then
    echo
    echo "RK3588 board info:"
    sed 's/^/  /' /var/lib/rk3588-board-info
    if command -v nmtui >/dev/null 2>&1; then
        echo "  network: use nmtui or nmcli"
    fi
    echo
    touch "$HOME/.rk3588-board-info.seen" 2>/dev/null || true
fi
