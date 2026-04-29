#!/usr/bin/env bash
# file:    tool-menu.sh
# version: 1.1
# desc:    Main launcher (Admin + Personal)

source "$HOME/scripts/lib/core.sh"

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
            q|Q) return ;;
            *) ui_error "Invalid option"; sleep 1 ;;
        esac
    done
}

personal_menu() {
    while true; do
        ui_header "PERSONAL TOOLS"

        ui_option "1" "Speedtest"
        ui_option "2" "Weather"
        echo
        ui_option "q" "Back"

        echo
        read -rp "Select option: " choice

        case "$choice" in
            1) run_script "personaltools/speedtest.sh" ;;
            2) run_script "personaltools/weather.sh" ;;
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
