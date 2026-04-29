#!/usr/bin/env bash
# file:    wifi-menu.sh
# author:  Mike Redd / typezero
# version: 1.1
# desc:    Wi-Fi control menu using nmcli with optional config file

source "$HOME/scripts/lib/core.sh"

CONFIG_FILE="$HOME/.config/wifi-menu/wifirc"

# Load config if it exists
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

# Auto-detect Wi-Fi interface if not set in config
if [[ -z "${WIFI_IFACE:-}" ]]; then
    WIFI_IFACE="$(iw dev 2>/dev/null | awk '$1=="Interface"{print $2; exit}')"
fi

# Fallback if detection fails
WIFI_IFACE="${WIFI_IFACE:-wlan0}"

require_nmcli() {
    if ! command -v nmcli >/dev/null 2>&1; then
        ui_error "nmcli not found. Install NetworkManager."
        pause
        exit 1
    fi
}

wifi_status() {
    ui_header "WIFI STATUS"

    echo -e "${UI_CYN}Interface:${UI_RST} $WIFI_IFACE"
    echo

    echo -e "${UI_YLW}Radio:${UI_RST}"
    nmcli radio wifi
    echo

    echo -e "${UI_YLW}Devices:${UI_RST}"
    nmcli device status
    echo

    echo -e "${UI_YLW}Current Wi-Fi:${UI_RST}"
    nmcli -f ACTIVE,SSID,SIGNAL,RATE,SECURITY dev wifi | grep -E '^\*|SSID' || true
    echo

    echo -e "${UI_YLW}Route Check:${UI_RST}"
    ip route get 1.1.1.1 2>/dev/null || true
    echo

    if command -v iw >/dev/null 2>&1; then
        echo -e "${UI_YLW}Link Info:${UI_RST}"
        iw dev "$WIFI_IFACE" link 2>/dev/null || true
        echo
    fi

    pause
}

wifi_scan() {
    ui_header "WIFI SCAN"

    nmcli device wifi rescan ifname "$WIFI_IFACE" 2>/dev/null || true
    nmcli -f SSID,SIGNAL,RATE,SECURITY device wifi list ifname "$WIFI_IFACE"

    echo
    pause
}

wifi_enable() {
    ui_header "ENABLE WIFI"

    nmcli radio wifi on
    nmcli device set "$WIFI_IFACE" managed yes 2>/dev/null || true

    echo -e "${UI_GRN}Wi-Fi enabled.${UI_RST}"
    echo
    pause
}

wifi_disable() {
    ui_header "DISABLE WIFI"

    nmcli device disconnect "$WIFI_IFACE" 2>/dev/null || true
    nmcli radio wifi off

    echo -e "${UI_YLW}Wi-Fi disabled.${UI_RST}"
    echo
    pause
}

wifi_connect() {
    ui_header "CONNECT WIFI"

    local ssid="${WIFI_SSID:-}"
    local password="${WIFI_PASSWORD:-}"
    local iface="$WIFI_IFACE"

    echo -e "${UI_CYN}Interface:${UI_RST} $iface"
    echo

    if [[ -z "$ssid" ]]; then
        read -rp "SSID: " ssid
    else
        echo -e "${UI_CYN}SSID:${UI_RST} $ssid"
    fi

    if [[ -z "$ssid" ]]; then
        ui_error "SSID required"
        sleep 1
        return
    fi

    if [[ -z "$password" ]]; then
        read -rsp "Password: " password
        echo
    fi

    echo
    echo -e "${UI_CYN}Connecting to:${UI_RST} $ssid"
    echo

    if [[ -z "$password" ]]; then
        nmcli device wifi connect "$ssid" ifname "$iface"
    else
        nmcli device wifi connect "$ssid" password "$password" ifname "$iface"
    fi

    echo
    pause
}

wifi_disconnect() {
    ui_header "DISCONNECT WIFI"

    nmcli device disconnect "$WIFI_IFACE" || true

    echo
    echo -e "${UI_YLW}Wi-Fi disconnected.${UI_RST}"
    echo
    pause
}

wifi_saved() {
    ui_header "SAVED WIFI CONNECTIONS"

    nmcli connection show | grep -i wifi || echo "No saved Wi-Fi connections found."

    echo
    pause
}

wifi_connect_saved() {
    ui_header "CONNECT SAVED WIFI"

    nmcli connection show | grep -i wifi || {
        echo "No saved Wi-Fi connections found."
        pause
        return
    }

    echo
    read -rp "Connection name: " conn

    if [[ -z "$conn" ]]; then
        ui_error "Connection name required"
        sleep 1
        return
    fi

    nmcli connection up "$conn"

    echo
    pause
}

wifi_restart_nm() {
    ui_header "RESTART NETWORKMANAGER"

    echo -e "${UI_YLW}Restarting NetworkManager...${UI_RST}"
    sudo systemctl restart NetworkManager

    echo
    echo -e "${UI_GRN}NetworkManager restarted.${UI_RST}"
    echo
    pause
}

wifi_power_save_off() {
    ui_header "DISABLE WIFI POWER SAVE"

    if ! command -v iw >/dev/null 2>&1; then
        ui_error "iw not found. Install iw."
        pause
        return
    fi

    sudo iw dev "$WIFI_IFACE" set power_save off

    echo
    echo -e "${UI_GRN}Wi-Fi power save disabled for $WIFI_IFACE.${UI_RST}"
    echo

    iw dev "$WIFI_IFACE" get power_save 2>/dev/null || true
    echo

    pause
}

wifi_show_config() {
    ui_header "WIFI CONFIG"

    echo -e "${UI_CYN}Config file:${UI_RST} $CONFIG_FILE"
    echo

    if [[ -f "$CONFIG_FILE" ]]; then
        echo -e "${UI_GRN}Config found.${UI_RST}"
        echo
        echo -e "${UI_CYN}SSID:${UI_RST} ${WIFI_SSID:-not set}"
        echo -e "${UI_CYN}Password:${UI_RST} $([[ -n "${WIFI_PASSWORD:-}" ]] && echo "set" || echo "not set")"
        echo -e "${UI_CYN}Interface:${UI_RST} $WIFI_IFACE"
    else
        echo -e "${UI_YLW}No config file found.${UI_RST}"
        echo
        echo "Create it with:"
        echo "  mkdir -p ~/.config/wifi-menu"
        echo "  nano ~/.config/wifi-menu/wifirc"
        echo "  chmod 600 ~/.config/wifi-menu/wifirc"
        echo
        echo "Example:"
        echo '  WIFI_SSID="YourWifiName"'
        echo '  WIFI_PASSWORD="YourWifiPassword"'
        echo '  # WIFI_IFACE="wlan0"'
    fi

    echo
    pause
}

main_menu() {
    require_nmcli

    while true; do
        ui_header "WIFI MENU"

        ui_option "1"  "Status"
        ui_option "2"  "Scan Networks"
        ui_option "3"  "Enable Wi-Fi"
        ui_option "4"  "Disable Wi-Fi"
        ui_option "5"  "Connect to Wi-Fi"
        ui_option "6"  "Disconnect Wi-Fi"
        ui_option "7"  "Show Saved Connections"
        ui_option "8"  "Connect Saved Connection"
        ui_option "9"  "Restart NetworkManager"
        ui_option "10" "Disable Wi-Fi Power Save"
        ui_option "11" "Show Config"
        echo
        ui_option "q" "Back"

        echo
        read -rp "Select option: " choice

        case "$choice" in
            1)  wifi_status ;;
            2)  wifi_scan ;;
            3)  wifi_enable ;;
            4)  wifi_disable ;;
            5)  wifi_connect ;;
            6)  wifi_disconnect ;;
            7)  wifi_saved ;;
            8)  wifi_connect_saved ;;
            9)  wifi_restart_nm ;;
            10) wifi_power_save_off ;;
            11) wifi_show_config ;;
            q|Q) return ;;
            *)  ui_error "Invalid option"; sleep 1 ;;
        esac
    done
}

main_menu
