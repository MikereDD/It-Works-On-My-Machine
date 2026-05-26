#!/usr/bin/env bash
#
# File    : open-ports.sh
# Author  : Mike Redd
# Version : 1.1
# Created : 2026-05-25
# Updated : 2026-05-25
# Desc    : Show open/listening ports before something starts acting possessed.
#

set -euo pipefail

RED="\e[31m"
GREEN="\e[32m"
CYAN="\e[36m"
YELLOW="\e[33m"
RESET="\e[0m"

show_header() {
    clear
    echo -e "${CYAN}"
    echo "┌────────────────────────────────────────────┐"
    echo "│              OPEN PORT CHECKER             │"
    echo "└────────────────────────────────────────────┘"
    echo -e "${RESET}"
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo -e "${RED}Missing:${RESET} $1"
        exit 1
    }
}

section() {
    echo -e "${GREEN}$1${RESET}"
    echo "──────────────────────────────────────────────"
}

show_header
need_cmd ss

if [[ $EUID -ne 0 ]]; then
    echo -e "${YELLOW}Notice:${RESET} Not running as root."
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
echo -e "${CYAN}Done.${RESET}"