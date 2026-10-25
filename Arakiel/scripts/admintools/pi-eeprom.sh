#!/usr/bin/env bash
#--------------------------------------------
# file:    pi-eeprom.sh
# author:  Mike Redd
# version: 1.0
# desc:    Raspberry Pi 5 EEPROM/bootloader manager: show version,
#          update, view config, and set the boot order.
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
need_root() { [[ "${EUID:-$(id -u)}" -eq 0 ]]; }

show_header() {
    ui_header "PI EEPROM / BOOTLOADER"
    if ! have rpi-eeprom-update; then
        ui_row "rpi-eeprom" "not installed" "$UI_RED"
        printf '  %sInstall rpi-eeprom (Pi OS) or the equivalent for your distro.%s\n' "$UI_DIM" "$UI_R"
    fi
    echo
}

status() {
    show_header
    if have rpi-eeprom-update; then
        ui_section "Bootloader status"
        rpi-eeprom-update 2>&1 | sed 's/^/  /'
    fi
    ui_section "Current boot order"
    if have rpi-eeprom-config; then
        rpi-eeprom-config 2>/dev/null | grep -i 'BOOT_ORDER' | sed 's/^/  /' \
            || printf '  %sBOOT_ORDER not set (using default)%s\n' "$UI_DIM" "$UI_R"
    fi
    echo; pause
}

do_update() {
    show_header
    need_root || { printf '  %sUpdating the EEPROM needs root. Re-run with sudo.%s\n' "$UI_YLW" "$UI_R"; pause; return; }
    have rpi-eeprom-update || { core_error "rpi-eeprom-update not found"; pause; return; }
    printf '  %sApplying latest bootloader (takes effect next reboot)...%s\n' "$UI_CYN" "$UI_R"
    rpi-eeprom-update -a
    echo; pause
}

set_boot_order() {
    show_header
    need_root || { printf '  %sSetting boot order needs root. Re-run with sudo.%s\n' "$UI_YLW" "$UI_R"; pause; return; }
    have rpi-eeprom-config || { core_error "rpi-eeprom-config not found"; pause; return; }

    ui_section "Boot order presets"
    printf '  BOOT_ORDER is read right-to-left. Common values:\n'
    ui_option "1" "NVMe, then SD, then USB   (0xf416)"
    ui_option "2" "USB, then SD              (0xf41)"
    ui_option "3" "SD, then USB              (0xf14)"
    ui_option "q" "Cancel"
    echo
    read -rp "Select option: " c
    local order=""
    case "$c" in
        1) order="0xf416" ;;
        2) order="0xf41"  ;;
        3) order="0xf14"  ;;
        q|Q) return ;;
        *) core_error "Invalid option"; sleep 1; return ;;
    esac

    local tmp; tmp="$(mktemp)"
    rpi-eeprom-config > "$tmp" 2>/dev/null
    if grep -q '^BOOT_ORDER=' "$tmp"; then
        sed -i "s/^BOOT_ORDER=.*/BOOT_ORDER=$order/" "$tmp"
    else
        echo "BOOT_ORDER=$order" >> "$tmp"
    fi
    printf '  Applying BOOT_ORDER=%s ...\n' "$order"
    rpi-eeprom-config --apply "$tmp" && printf '  %sDone. Reboot to apply.%s\n' "$UI_GRN" "$UI_R" \
        || core_error "Failed to apply config"
    rm -f "$tmp"
    pause
}

while true; do
    show_header
    ui_option "1" "Status (bootloader + boot order)"
    ui_option "2" "Update bootloader to latest"
    ui_option "3" "Set boot order"
    ui_option "q" "Back"
    echo
    read -rp "Select option: " choice
    case "$choice" in
        1) status ;;
        2) do_update ;;
        3) set_boot_order ;;
        q|Q) break ;;
        *) core_error "Invalid option"; sleep 1 ;;
    esac
done
