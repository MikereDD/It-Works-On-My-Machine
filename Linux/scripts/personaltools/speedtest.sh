#!/usr/bin/env bash
# file:    speedtest.sh
# author:  Mike Redd / typezero
# version: 1.0
# desc:    Run Ookla Speedtest CLI

source "$HOME/scripts/lib/core.sh"

ui_header "SPEEDTEST"

if ! command -v speedtest >/dev/null 2>&1; then
    ui_error "Ookla speedtest CLI is not installed."
    echo
    echo "Install it first, then rerun this script."
    echo
    echo "Arch:"
    echo "  yay -S speedtest"
    echo
    echo "Debian/Raspberry Pi OS:"
    echo "  sudo apt install speedtest-cli"
    echo
    pause
    exit 1
fi

echo -e "${UI_CYN}Running Ookla Speedtest...${UI_RST}"
echo

speedtest

echo
pause
