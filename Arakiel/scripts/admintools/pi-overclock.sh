#!/usr/bin/env bash
#--------------------------------------------
# file:    pi-overclock.sh
# author:  Mike Redd
# version: 1.0
# desc:    View and edit Raspberry Pi 5 performance settings in
#          config.txt (arm_freq, over_voltage, PCIe Gen 3) with a
#          backup and confirmation. Reboot required to apply.
#--------------------------------------------

LIB_DIR="${LIB_DIR:-$HOME/lib}"
if [[ -f "$LIB_DIR/core.sh" ]]; then
    # shellcheck source=/dev/null
    source <(sed 's/\r$//' "$LIB_DIR/core.sh")
else
    echo "Error: core.sh not found in $LIB_DIR" >&2; exit 1
fi
set +e +u 2>/dev/null || true

CONFIG_TXT="${CONFIG_TXT:-}"
if [[ -z "$CONFIG_TXT" ]]; then
    for c in /boot/firmware/config.txt /boot/config.txt; do
        [[ -f "$c" ]] && { CONFIG_TXT="$c"; break; }
    done
fi
CONFIG_TXT="${CONFIG_TXT:-/boot/firmware/config.txt}"


backup_config() {
    local bak
    bak="${CONFIG_TXT}.bak.$(date +%Y%m%d_%H%M%S)"
    cp "$CONFIG_TXT" "$bak" && { printf '%s' "$bak"; return 0; }
    return 1
}

# set_key KEY VALUE  — replace or append "KEY=VALUE" in config.txt
set_key() {
    local key="$1" val="$2"
    if grep -qE "^${key}=" "$CONFIG_TXT"; then
        sed -i "s|^${key}=.*|${key}=${val}|" "$CONFIG_TXT"
    else
        printf '%s=%s\n' "$key" "$val" >> "$CONFIG_TXT"
    fi
}

show_current() {
    ui_header "PI OVERCLOCK / PCIe"
    ui_row "config.txt" "$CONFIG_TXT" "$UI_GRY"
    ui_section "Current performance settings"
    local found=0 k
    for k in arm_freq gpu_freq over_voltage_delta over_voltage force_turbo 'dtparam=pciex1_gen' 'dtparam=pciex1'; do
        if [[ -r "$CONFIG_TXT" ]] && grep -qE "^${k}=" "$CONFIG_TXT"; then
            grep -E "^${k}=" "$CONFIG_TXT" | sed 's/^/  /'; found=1
        fi
    done
    (( found == 0 )) && printf '  %sAll stock (no overrides set).%s\n' "$UI_DIM" "$UI_R"
    echo
}

apply_preset() {   # <name> ; sets globals then writes
    local name="$1"
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        printf '  %sEditing %s needs root. Re-run with sudo.%s\n' "$UI_YLW" "$CONFIG_TXT" "$UI_R"; pause; return
    fi
    [[ -w "$CONFIG_TXT" ]] || { core_error "Cannot write $CONFIG_TXT"; pause; return; }

    printf '  %sPreset: %s%s\n' "$UI_CYN" "$name" "$UI_R"
    case "$name" in
        stock)   printf '  Removes arm_freq/gpu_freq/over_voltage_delta/force_turbo overrides.\n' ;;
        mild)    printf '  arm_freq=2600, over_voltage_delta=20000 (modest, needs good cooling).\n' ;;
        pcie3)   printf '  Enables PCIe Gen 3 for NVMe (dtparam=pciex1_gen=3).\n' ;;
    esac
    read -rp "  Proceed? (y/N): " ok
    [[ "${ok,,}" == "y" ]] || { printf '  Cancelled.\n'; pause; return; }

    local bak; bak="$(backup_config)" || { core_error "Backup failed; aborting"; pause; return; }

    case "$name" in
        stock)
            sed -i -E '/^(arm_freq|gpu_freq|over_voltage_delta|over_voltage|force_turbo)=/d' "$CONFIG_TXT"
            ;;
        mild)
            set_key arm_freq 2600
            set_key over_voltage_delta 20000
            ;;
        pcie3)
            set_key 'dtparam=pciex1_gen' 3
            ;;
    esac
    printf '  %sApplied. Backup: %s%s\n' "$UI_GRN" "$bak" "$UI_R"
    printf '  %sReboot to take effect. If it fails to boot, restore the backup.%s\n' "$UI_YLW" "$UI_R"
    pause
}

while true; do
    show_current
    ui_divider
    ui_option "1" "PCIe Gen 3 for NVMe (recommended)"
    ui_option "2" "Mild overclock (arm_freq 2600 + voltage)"
    ui_option "3" "Reset to stock"
    ui_option "4" "Refresh"
    ui_option "q" "Back"
    echo
    printf '  %sWarning: overclocking can cause instability or data loss.%s\n' "$UI_YLW" "$UI_R"
    read -rp "Select option: " choice
    case "$choice" in
        1) apply_preset pcie3 ;;
        2) apply_preset mild ;;
        3) apply_preset stock ;;
        4) ;;
        q|Q) break ;;
        *) core_error "Invalid option"; sleep 1 ;;
    esac
done
