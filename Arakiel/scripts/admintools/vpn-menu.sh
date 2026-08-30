#!/usr/bin/env bash
#--------------------------------------------
# file:    vpn-menu.sh
# author:  Mike Redd
# version: 1.0
# desc:    VPN control for Tailscale and/or WireGuard: status,
#          connect/up, disconnect/down, and show the VPN IP.
#--------------------------------------------

LIB_DIR="${LIB_DIR:-$HOME/lib}"
if [[ -f "$LIB_DIR/core.sh" ]]; then
    # shellcheck source=/dev/null
    source <(sed 's/\r$//' "$LIB_DIR/core.sh")
else
    echo "Error: core.sh not found in $LIB_DIR" >&2; exit 1
fi
set +e +u 2>/dev/null || true

have() { command -v "$1" >/dev/null 2>&1; }
SUDO=""; [[ "${EUID:-$(id -u)}" -ne 0 ]] && SUDO="sudo"
WG_IFACE="${WG_IFACE:-wg0}"

show_header() {
    ui_header "VPN MENU"
    if have tailscale; then
        local st; st="$(tailscale status --json 2>/dev/null | grep -o '"BackendState":"[^"]*"' | head -1 | cut -d'"' -f4)"
        ui_row "Tailscale" "${st:-installed}" "$UI_CYN"
    fi
    if have wg; then
        if $SUDO wg show "$WG_IFACE" >/dev/null 2>&1; then
            ui_row "WireGuard ($WG_IFACE)" "up" "$UI_GRN"
        else
            ui_row "WireGuard ($WG_IFACE)" "down" "$UI_GRY"
        fi
    fi
    if ! have tailscale && ! have wg; then
        ui_row "VPN" "neither tailscale nor wireguard found" "$UI_RED"
    fi
    echo
}

ts_status()  { have tailscale && tailscale status 2>&1 | sed 's/^/  /'; pause; }
ts_up()      { have tailscale && $SUDO tailscale up; pause; }
ts_down()    { have tailscale && $SUDO tailscale down; pause; }
ts_ip()      { have tailscale && { printf '  Tailscale IP: '; tailscale ip -4 2>/dev/null | head -1; }; pause; }
wg_up()      { have wg && $SUDO wg-quick up "$WG_IFACE"; pause; }
wg_down()    { have wg && $SUDO wg-quick down "$WG_IFACE"; pause; }
wg_status()  { have wg && $SUDO wg show 2>&1 | sed 's/^/  /'; pause; }

while true; do
    show_header
    if have tailscale; then
        ui_section "Tailscale"
        ui_option "1" "Status"
        ui_option "2" "Connect (up)"
        ui_option "3" "Disconnect (down)"
        ui_option "4" "Show VPN IP"
    fi
    if have wg; then
        ui_section "WireGuard ($WG_IFACE)"
        ui_option "5" "Bring up"
        ui_option "6" "Bring down"
        ui_option "7" "Show"
    fi
    echo
    ui_option "q" "Back"
    echo
    read -rp "Select option: " choice
    case "$choice" in
        1) ts_status ;;
        2) ts_up ;;
        3) ts_down ;;
        4) ts_ip ;;
        5) wg_up ;;
        6) wg_down ;;
        7) wg_status ;;
        q|Q) break ;;
        *) core_error "Invalid option"; sleep 1 ;;
    esac
done
