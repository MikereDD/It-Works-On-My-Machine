#!/usr/bin/env bash
#
# file:    tool-menu.sh
# author:  Mike Redd
# version: 1.2
# desc:    Main launcher (Admin + Personal)
#

source "$HOME/lib/core.sh"
# core.sh enables errexit/nounset; relax so the menu survives a child script
# that exits non-zero (e.g. a tool whose dependency is missing).
set +e +u 2>/dev/null || true

main_menu() {
    while true; do
        ui_header "TOOLS MENU"

        ui_option "1" "Admin Tools"
        ui_option "2" "Personal Tools"
        echo
        ui_option "q" "Quit"

        echo
        read -rp "Select option: " choice

        case "$choice" in
            1) admin_menu ;;
            2) personal_menu ;;
            q|Q) clear; exit 0 ;;
            *) ui_error "Invalid option"; sleep 1 ;;
        esac
    done
}

admin_menu() {
    while true; do
        ui_header "ADMIN TOOLS"

        ui_option "1" "System Info"
        ui_option "2" "Updates"
        ui_option "3" "Network"
        ui_option "4" "Disk"
        ui_option "5" "Services"
        ui_option "6" "Processes"
        ui_option "7" "Wi-Fi Menu"
        ui_option "8" "Open Ports"
        echo
        ui_option "q" "Back"

        echo
        read -rp "Select option: " choice

        case "$choice" in
            1) run_script "admintools/system-info.sh" ;;
            2) run_script "admintools/updates.sh" ;;
            3) run_script "admintools/network.sh" ;;
            4) run_script "admintools/disk.sh" ;;
            5) run_script "admintools/services.sh" ;;
            6) run_script "admintools/processes.sh" ;;
            7) run_script "admintools/wifi-menu.sh" ;;
            8) run_script "admintools/open-ports.sh" ;;
            q|Q) return ;;
            *) ui_error "Invalid option"; sleep 1 ;;
        esac
    done
}

personal_menu() {
    while true; do
        ui_header "PERSONAL TOOLS"

        ui_section "Media / Disc"
        ui_option "1" "Blu-ray Backup"
        ui_option "2" "Blu-ray Track Dump"
        ui_option "3" "Blu-ray Encoder"
        ui_option "4" "DVD Ripper Encoder"
        ui_option "5" "MiNfoCreate (NFO/HTML)"
        ui_option "6" "IMDb Dump"
        ui_option "7" "IMDb Thumb Grab"

        ui_section "System / Network"
        ui_option "8"  "Infocat (Pi info)"
        ui_option "9"  "Speedtest"
        ui_option "10" "Weather"
        echo
        ui_option "q" "Back"

        echo
        read -rp "Select option: " choice

        case "$choice" in
            1)  run_script "personaltools/bluray-backup.sh" ;;
            2)  run_script "personaltools/bluray-trackdump.sh" ;;
            3)  run_script "personaltools/brencoder.sh" ;;
            4)  run_script "personaltools/dvd-ripper-encoder.sh" ;;
            5)  run_script "personaltools/minfocreate.sh" ;;
            6)  run_script "personaltools/imdbdump.sh" ;;
            7)  run_script "personaltools/imdbthumbgrab.sh" ;;
            8)  run_script "personaltools/infocat-pi.sh" ;;
            9)  run_script "personaltools/speedtest.sh" ;;
            10) run_script "personaltools/weather.sh" ;;
            q|Q) return ;;
            *) ui_error "Invalid option"; sleep 1 ;;
        esac
    done
}

run_script() {
    local script="$HOME/scripts/$1"

    if [[ -x "$script" ]]; then
        "$script"
    else
        ui_error "Script not found or not executable: $1"
        sleep 1
    fi
}

main_menu
