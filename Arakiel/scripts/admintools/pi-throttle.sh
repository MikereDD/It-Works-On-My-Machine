#!/usr/bin/env bash
#--------------------------------------------
# file:    pi-throttle.sh
# author:  Mike Redd
# version: 1.0
# desc:    Raspberry Pi 5 temperature / throttle / clock monitor.
#          Decodes vcgencmd get_throttled into plain English.
#          Pass --watch to refresh continuously.
#--------------------------------------------

LIB_DIR="${LIB_DIR:-$HOME/lib}"
if [[ -f "$LIB_DIR/core.sh" ]]; then
    # shellcheck source=/dev/null
    source <(sed 's/\r$//' "$LIB_DIR/core.sh")
else
    echo "Error: core.sh not found in $LIB_DIR" >&2; exit 1
fi
set +e +u 2>/dev/null || true

WATCH=0
[[ "${1:-}" == "--watch" || "${1:-}" == "-w" ]] && WATCH=1

have_vcgencmd() { command -v vcgencmd >/dev/null 2>&1; }

read_temp() {
    if have_vcgencmd; then
        vcgencmd measure_temp 2>/dev/null | sed 's/temp=//'
    elif [[ -r /sys/class/thermal/thermal_zone0/temp ]]; then
        awk '{printf "%.1f'"'"'C\n", $1/1000}' /sys/class/thermal/thermal_zone0/temp
    else
        echo "n/a"
    fi
}

# Decode the throttled bitmask (numeric) into a list of active flags.
decode_throttle() {   # <decimal value>
    local v="$1"
    local -a now=() past=()
    (( (v & 0x1)     )) && now+=("under-voltage")
    (( (v & 0x2)     )) && now+=("ARM freq capped")
    (( (v & 0x4)     )) && now+=("throttled")
    (( (v & 0x8)     )) && now+=("soft temp limit")
    (( (v & 0x10000) )) && past+=("under-voltage")
    (( (v & 0x20000) )) && past+=("ARM freq capped")
    (( (v & 0x40000) )) && past+=("throttled")
    (( (v & 0x80000) )) && past+=("soft temp limit")

    if [[ "${#now[@]}" -eq 0 ]]; then
        printf '  %sNow %s        %sOK%s\n' "$UI_DIM" "$UI_R" "$UI_GRN" "$UI_R"
    else
        local IFS=', '
        printf '  %sNow %s        %s%s%s\n' "$UI_DIM" "$UI_R" "$UI_RED" "${now[*]}" "$UI_R"
    fi
    if [[ "${#past[@]}" -eq 0 ]]; then
        printf '  %sSince boot %s  %snone%s\n' "$UI_DIM" "$UI_R" "$UI_GRN" "$UI_R"
    else
        local IFS=', '
        printf '  %sSince boot %s  %s%s%s\n' "$UI_DIM" "$UI_R" "$UI_YLW" "${past[*]}" "$UI_R"
    fi
}

clock_mhz() {   # <clock name>
    have_vcgencmd || { echo "n/a"; return; }
    local hz; hz="$(vcgencmd measure_clock "$1" 2>/dev/null | cut -d= -f2)"
    [[ "$hz" =~ ^[0-9]+$ ]] && awk "BEGIN{printf \"%d MHz\", $hz/1000000}" || echo "n/a"
}

snapshot() {
    ui_header "PI THROTTLE / THERMAL"
    ui_row "Temp" "$(read_temp)" "$UI_CYN"

    if have_vcgencmd; then
        local raw val
        raw="$(vcgencmd get_throttled 2>/dev/null | cut -d= -f2)"   # e.g. 0x50000
        if [[ "$raw" =~ ^0x[0-9a-fA-F]+$ ]]; then
            val=$(( raw ))
            ui_section "Throttle status ($raw)"
            decode_throttle "$val"
        else
            ui_section "Throttle status"
            printf '  %sget_throttled unavailable%s\n' "$UI_YLW" "$UI_R"
        fi

        ui_section "Clocks"
        ui_row "ARM"  "$(clock_mhz arm)"  "$UI_GRY"
        ui_row "Core" "$(clock_mhz core)" "$UI_GRY"
        ui_row "Volts" "$(vcgencmd measure_volts core 2>/dev/null | cut -d= -f2)" "$UI_GRY"
    else
        ui_section "Throttle status"
        printf '  %svcgencmd not found — is this a Raspberry Pi?%s\n' "$UI_YLW" "$UI_R"
        printf '  %sInstall raspberrypi-utils / libraspberrypi-bin.%s\n' "$UI_DIM" "$UI_R"
    fi
    echo
}

if [[ "$WATCH" -eq 1 ]]; then
    trap 'echo; exit 0' INT
    while true; do snapshot; printf '  %s(Ctrl-C to stop, refreshing every 2s)%s\n' "$UI_DIM" "$UI_R"; sleep 2; done
else
    snapshot
    pause
fi
