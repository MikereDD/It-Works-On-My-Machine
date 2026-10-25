#!/usr/bin/env bash
#
# File    : open-ports.sh
# Author  : Mike Redd
# Version : 1.3
# Created : 2026-05-25
# Updated : 2026-05-25
# Desc    : Show open/listening ports before something starts acting possessed.
#

# Load shared core + UI helpers.
# core.sh also loads ui.sh when present.
source "$HOME/lib/core.sh"
# core.sh enables errexit/nounset; relax for the interactive flow.
set +e +u 2>/dev/null || true

# Colors and ui_* helpers come from ui.sh (via core.sh).

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        if declare -F ui_error >/dev/null 2>&1; then
            ui_error "Missing required command: $1"
        else
            echo -e "${UI_RED}Missing:${UI_RST} $1"
        fi
        wait_for_quit
        exit 1
    }
}

section() {
    echo -e "${UI_GRN}$1${UI_RST}"

    if declare -F ui_divider >/dev/null 2>&1; then
        ui_divider
    else
        echo "──────────────────────────────────────────────"
    fi
}

notice() {
    echo -e "${UI_YLW}Notice:${UI_RST} $1"
}

wait_for_quit() {
    echo
    while true; do
        read -rp "[q] Quit: " choice

        case "$choice" in
            q|Q)
                break
                ;;
            *)
                echo "Invalid option. Press q to quit."
                ;;
        esac
    done
}

show_ports() {
    ui_header "OPEN PORT CHECKER"
    need_cmd ss

    if [[ "${EUID}" -ne 0 ]]; then
        notice "Not running as root."
        echo "Some process names may be hidden because Linux enjoys being dramatic."
        echo
    fi

    section "TCP Listening Ports"
    ss -tlpn || true
    echo

    section "UDP Listening Ports"
    ss -ulpn || true
    echo

    section "Publicly Bound Services"
    ss -tulpn | grep -E '0\.0\.0\.0|\[::\]|\*:' || echo "Nothing obvious bound to all interfaces. Nice."
    echo

    section "Common Gremlin Ports"
    ss -tulpn | grep -E ':22|:80|:443|:8080|:8081|:11434|:34001|:8123|:32400|:8096' || echo "No common gremlins found."
    echo

    if command -v nmap >/dev/null 2>&1; then
        section "Quick Localhost Scan"
        nmap -F localhost || true
    else
        section "Nmap"
        echo "nmap not installed."
        echo "Install on Arch:"
        echo "  sudo pacman -S nmap"
    fi

    echo
    echo -e "${UI_CYN}Done.${UI_RST}"
}

show_ports
wait_for_quit
