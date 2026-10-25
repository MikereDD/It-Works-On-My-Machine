#!/usr/bin/env bash
#--------------------------------------------
# file:    pi-fan.sh
# author:  Mike Redd
# version: 1.0
# desc:    Raspberry Pi 5 fan / cooling status. Shows fan RPM, temp,
#          and the active-cooler curve, and can edit the fan curve
#          in config.txt (with a backup).
#--------------------------------------------

LIB_DIR="${LIB_DIR:-$HOME/lib}"
if [[ -f "$LIB_DIR/core.sh" ]]; then
    # shellcheck source=/dev/null
    source <(sed 's/\r$//' "$LIB_DIR/core.sh")
else
    echo "Error: core.sh not found in $LIB_DIR" >&2; exit 1
fi
set +e +u 2>/dev/null || true

# config.txt location differs across distros; allow override.
CONFIG_TXT="${CONFIG_TXT:-}"
if [[ -z "$CONFIG_TXT" ]]; then
    for c in /boot/firmware/config.txt /boot/config.txt; do
        [[ -f "$c" ]] && { CONFIG_TXT="$c"; break; }
    done
fi
CONFIG_TXT="${CONFIG_TXT:-/boot/firmware/config.txt}"

read_temp() {
    if command -v vcgencmd >/dev/null 2>&1; then
        vcgencmd measure_temp 2>/dev/null | sed 's/temp=//'
    elif [[ -r /sys/class/thermal/thermal_zone0/temp ]]; then
        awk '{printf "%.1f'"'"'C\n", $1/1000}' /sys/class/thermal/thermal_zone0/temp
    else echo "n/a"; fi
}

fan_rpm() {
    local f
    for f in /sys/class/hwmon/hwmon*/fan1_input; do
        [[ -r "$f" ]] && { cat "$f"; return; }
    done
    echo "n/a"
}

show_status() {
    ui_header "PI FAN / COOLING"
    ui_row "Temp"     "$(read_temp)"   "$UI_CYN"
    ui_row "Fan RPM"  "$(fan_rpm)"     "$UI_CYN"

    # Cooling device level (kernel thermal governor)
    local cd
    for cd in /sys/class/thermal/cooling_device*/cur_state; do
        [[ -r "$cd" ]] || continue
        local n; n="$(dirname "$cd")"; n="$(basename "$n")"
        ui_row "$n" "level $(cat "$cd")/$(cat "$(dirname "$cd")/max_state" 2>/dev/null)" "$UI_GRY"
    done

    ui_section "Fan curve in $CONFIG_TXT"
    if [[ -r "$CONFIG_TXT" ]] && grep -qE 'dtparam=fan_temp[0-3]' "$CONFIG_TXT"; then
        grep -E 'dtparam=fan_temp[0-3]' "$CONFIG_TXT" | sed 's/^/  /'
    else
        printf '  %sNo custom fan curve set (kernel defaults in use).%s\n' "$UI_DIM" "$UI_R"
    fi
    echo
}

set_curve() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        printf '  %sEditing %s needs root. Re-run with sudo.%s\n' "$UI_YLW" "$CONFIG_TXT" "$UI_R"
        pause; return
    fi
    [[ -w "$CONFIG_TXT" ]] || { printf '  %sCannot write %s%s\n' "$UI_RED" "$CONFIG_TXT" "$UI_R"; pause; return; }

    printf '  Default Pi 5 curve: 50/60/67/75 C -> speed 75/125/175/250.\n'
    printf '  Enter four temperatures (C), low to high, space-separated [50 60 67 75]: '
    read -r t0 t1 t2 t3
    [[ -z "$t0" ]] && { t0=50 t1=60 t2=67 t3=75; }
    for t in "$t0" "$t1" "$t2" "$t3"; do
        [[ "$t" =~ ^[0-9]+$ ]] || { core_error "Non-numeric temperature: $t"; pause; return; }
    done
    local s0=75 s1=125 s2=175 s3=250

    local bak
    bak="${CONFIG_TXT}.bak.$(date +%Y%m%d_%H%M%S)"
    cp "$CONFIG_TXT" "$bak" || { core_error "Backup failed"; pause; return; }

    # Drop any existing fan_temp lines, then append the new curve.
    grep -vE 'dtparam=fan_temp[0-3]' "$CONFIG_TXT" > "${CONFIG_TXT}.tmp"
    {
        echo "# Fan curve set by pi-fan.sh $(date '+%Y-%m-%d %H:%M:%S')"
        echo "dtparam=fan_temp0=${t0}000,fan_temp0_hyst=5000,fan_temp0_speed=$s0"
        echo "dtparam=fan_temp1=${t1}000,fan_temp1_hyst=5000,fan_temp1_speed=$s1"
        echo "dtparam=fan_temp2=${t2}000,fan_temp2_hyst=5000,fan_temp2_speed=$s2"
        echo "dtparam=fan_temp3=${t3}000,fan_temp3_hyst=5000,fan_temp3_speed=$s3"
    } >> "${CONFIG_TXT}.tmp"
    mv "${CONFIG_TXT}.tmp" "$CONFIG_TXT"

    printf '  %sFan curve written. Backup: %s%s\n' "$UI_GRN" "$bak" "$UI_R"
    printf '  %sReboot for it to take effect.%s\n' "$UI_YLW" "$UI_R"
    pause
}

while true; do
    show_status
    ui_divider
    ui_option "1" "Refresh status"
    ui_option "2" "Set fan curve (edits config.txt)"
    ui_option "q" "Back"
    echo
    read -rp "Select option: " choice
    case "$choice" in
        1) ;;                       # loop redraws
        2) set_curve ;;
        q|Q) break ;;
        *) core_error "Invalid option"; sleep 1 ;;
    esac
done
