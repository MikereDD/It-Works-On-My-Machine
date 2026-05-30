#!/usr/bin/env bash
#
# file:    tool-menu.sh
# author:  Mike Redd
# version: 1.3
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

        ui_section "System & Storage"
        ui_option "1" "System Info"
        ui_option "2" "Pi 5 System Info"
        ui_option "3" "Log Viewer"
        ui_option "4" "Disk Cleanup"
        ui_option "5" "Backup"

        ui_section "Pi Hardware"
        ui_option "6"  "Throttle / Thermal"
        ui_option "7"  "Power / PMIC"
        ui_option "8"  "Fan / Cooling"
        ui_option "9"  "EEPROM / Bootloader"
        ui_option "10" "Overclock / PCIe"
        ui_option "11" "NVMe Health"

        ui_section "Packages"
        ui_option "12" "Update Manager"
        ui_option "13" "Package List Backup"

        ui_section "Network & Security"
        ui_option "14" "Net Monitor"
        ui_option "15" "Open Ports"
        ui_option "16" "Wi-Fi Menu"
        ui_option "17" "VPN Menu"
        ui_option "18" "Login Audit"
        ui_option "19" "Firewall (UFW)"
        echo
        ui_option "q" "Back"

        echo
        read -rp "Select option: " choice

        case "$choice" in
            1)  run_script "admintools/system-info.sh" ;;
            2)  run_script "admintools/rp5-systeminfo.sh" ;;
            3)  run_script "admintools/logview.sh" ;;
            4)  run_script "admintools/disk-cleanup.sh" ;;
            5)  run_script "admintools/backup.sh" ;;
            6)  run_script "admintools/pi-throttle.sh" ;;
            7)  run_script "admintools/pi-power.sh" ;;
            8)  run_script "admintools/pi-fan.sh" ;;
            9)  run_script "admintools/pi-eeprom.sh" ;;
            10) run_script "admintools/pi-overclock.sh" ;;
            11) run_script "admintools/nvme-health.sh" ;;
            12) run_script "admintools/update-manager.sh" ;;
            13) run_script "admintools/pkg-backup.sh" ;;
            14) run_script "admintools/net-monitor.sh" ;;
            15) run_script "admintools/open-ports.sh" ;;
            16) run_script "admintools/wifi-menu.sh" ;;
            17) run_script "admintools/vpn-menu.sh" ;;
            18) run_script "admintools/login-audit.sh" ;;
            19) run_script "admintools/pi-fw.sh" ;;
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
        ui_option "5" "Transcode Queue"
        ui_option "6" "MiNfoCreate (NFO/HTML)"
        ui_option "7" "IMDb Dump"
        ui_option "8" "IMDb Thumb Grab"

        ui_section "System / Network"
        ui_option "9"  "Infocat (Pi info)"
        ui_option "10" "Speedtest"
        ui_option "11" "Weather"
        echo
        ui_option "q" "Back"

        echo
        read -rp "Select option: " choice

        case "$choice" in
            1)  run_script "personaltools/bluray-backup.sh" ;;
            2)  run_script "personaltools/bluray-trackdump.sh" ;;
            3)  run_script "personaltools/brencoder.sh" ;;
            4)  run_script "personaltools/dvd-ripper-encoder.sh" ;;
            5)  run_script "personaltools/transcode-queue.sh" ;;
            6)  run_script "personaltools/minfocreate.sh" ;;
            7)  run_script "personaltools/imdbdump.sh" ;;
            8)  run_script "personaltools/imdbthumbgrab.sh" ;;
            9)  run_script "personaltools/infocat-pi.sh" ;;
            10) run_script "personaltools/speedtest.sh" ;;
            11) run_script "personaltools/weather.sh" ;;
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
