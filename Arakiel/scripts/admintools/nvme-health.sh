#!/usr/bin/env bash
#--------------------------------------------
# file:    nvme-health.sh
# author:  Mike Redd
# version: 1.0
# desc:    NVMe / SSD health report via smartctl and nvme-cli.
#          Shows temperature, wear, and SMART status.
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

ui_header "NVMe / SSD HEALTH"

# Discover NVMe namespaces and SATA disks.
mapfile -t DEVS < <(
    ls /dev/nvme?n? 2>/dev/null
    ls /dev/sd? 2>/dev/null
)

if [[ "${#DEVS[@]}" -eq 0 ]]; then
    ui_row "Devices" "none found" "$UI_YLW"
    printf '  %sNo /dev/nvme* or /dev/sd* devices present.%s\n' "$UI_DIM" "$UI_R"
    echo; pause; exit 0
fi

if ! have smartctl && ! have nvme; then
    ui_row "Tools" "smartctl / nvme-cli not installed" "$UI_RED"
    printf '  %sInstall: sudo pacman -S smartmontools nvme-cli%s\n' "$UI_DIM" "$UI_R"
    echo; pause; exit 0
fi

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    printf '  %sNot root — SMART reads usually need sudo; output may be empty.%s\n' "$UI_YLW" "$UI_R"
    echo
fi

for dev in "${DEVS[@]}"; do
    ui_section "$dev"

    if [[ "$dev" == /dev/nvme* ]] && have nvme; then
        # nvme smart-log: pull the most useful fields
        if log="$(nvme smart-log "$dev" 2>/dev/null)" && [[ -n "$log" ]]; then
            printf '%s\n' "$log" | grep -iE 'temperature|percentage_used|available_spare|data_units_(read|written)|power_on_hours|media_errors|critical_warning' \
                | sed 's/^/  /'
            continue
        fi
    fi

    if have smartctl; then
        smartctl -H "$dev" 2>/dev/null | grep -iE 'overall-health|SMART Health' | sed 's/^/  /'
        smartctl -A "$dev" 2>/dev/null \
            | grep -iE 'Temperature|Wear|Percentage|Power_On_Hours|Reallocated|Available_Spare|Media_Wearout' \
            | sed 's/^/  /'
    else
        printf '  %sNo reader for this device.%s\n' "$UI_DIM" "$UI_R"
    fi
done

echo
pause
