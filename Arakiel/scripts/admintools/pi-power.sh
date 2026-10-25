#!/usr/bin/env bash
#--------------------------------------------
# file:    pi-power.sh
# author:  Mike Redd
# version: 1.0
# desc:    Raspberry Pi 5 power / PMIC monitor. Shows rail voltages
#          and currents from the PMIC and flags under-voltage.
#--------------------------------------------

LIB_DIR="${LIB_DIR:-$HOME/lib}"
if [[ -f "$LIB_DIR/core.sh" ]]; then
    # shellcheck source=/dev/null
    source <(sed 's/\r$//' "$LIB_DIR/core.sh")
else
    echo "Error: core.sh not found in $LIB_DIR" >&2; exit 1
fi
set +e +u 2>/dev/null || true

have_vcgencmd() { command -v vcgencmd >/dev/null 2>&1; }

ui_header "PI POWER / PMIC"

if ! have_vcgencmd; then
    ui_row "Status" "vcgencmd not found" "$UI_RED"
    printf '  %sThis tool needs the Raspberry Pi firmware utils.%s\n' "$UI_DIM" "$UI_R"
    echo; pause; exit 0
fi

# Under-voltage flag from the throttle bitmask.
raw="$(vcgencmd get_throttled 2>/dev/null | cut -d= -f2)"
if [[ "$raw" =~ ^0x[0-9a-fA-F]+$ ]]; then
    val=$(( raw ))
    if (( val & 0x1 )); then
        ui_row "Under-voltage" "DETECTED NOW" "$UI_RED"
    elif (( val & 0x10000 )); then
        ui_row "Under-voltage" "occurred since boot" "$UI_YLW"
    else
        ui_row "Under-voltage" "none" "$UI_GRN"
    fi
fi

ui_section "Core voltages"
for d in core sdram_c sdram_i sdram_p; do
    v="$(vcgencmd measure_volts "$d" 2>/dev/null | cut -d= -f2)"
    ui_row "$d" "${v:-n/a}" "$UI_GRY"
done

ui_section "PMIC rails (ADC)"
# pmic_read_adc prints lines like:  3V7_WL_SW_A current(7)=0.00A  /  ...volt(0)=...V
if pmic="$(vcgencmd pmic_read_adc 2>/dev/null)" && [[ -n "$pmic" ]]; then
    printf '%s\n' "$pmic" | sed 's/^ */  /'
else
    printf '  %sPMIC ADC not available on this model/firmware.%s\n' "$UI_YLW" "$UI_R"
fi

echo
pause
