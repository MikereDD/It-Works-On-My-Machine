#!/usr/bin/env bash
#--------------------------------------------
# file:     rp5-systeminfo-menu.sh
# author:   Mike Redd
# version:  1.1
# desc:     Compact Raspberry Pi 5 status view for the Arakiel Tool Menu
#--------------------------------------------

LIB_DIR="${LIB_DIR:-$HOME/lib}"

if [[ -f "$LIB_DIR/core.sh" ]]; then
    # shellcheck source=/dev/null
    source <(sed 's/\r$//' "$LIB_DIR/core.sh")
fi

# Reports should tolerate unavailable optional sensors/tools.
set +e +u 2>/dev/null || true

# Run vcgencmd without prompting. Arakiel exposes /dev/vcio_gencmd as
# root-only, so normal-user access may require the existing sudo rule.
vcgencmd_read() {
    local output

    command -v vcgencmd >/dev/null 2>&1 || return 1

    output="$(vcgencmd "$@" 2>/dev/null)"

    if [[ "$output" == "Can't open device file:"* || -z "$output" ]]; then
        output="$(sudo -n vcgencmd "$@" 2>/dev/null)" || return 1
    fi

    [[ -n "$output" ]] || return 1
    printf '%s\n' "$output"
}

host="$(uname -n)"
kernel="$(uname -r)"
uptime_text="$(uptime -p 2>/dev/null || printf 'N/A')"

model="$(tr -d '\0' </proc/device-tree/model 2>/dev/null)"
[[ -n "$model" ]] || model="Raspberry Pi"

cpu_temp="N/A"
if [[ -r /sys/class/thermal/thermal_zone0/temp ]]; then
    temp_raw="$(< /sys/class/thermal/thermal_zone0/temp)"
    if [[ "$temp_raw" =~ ^[0-9]+$ ]]; then
        printf -v cpu_temp '%d.%d°C' \
            "$((temp_raw / 1000))" \
            "$(((temp_raw % 1000) / 100))"
    fi
fi

cpu_freq="N/A"
if [[ -r /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ]]; then
    freq_khz="$(< /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)"
    [[ "$freq_khz" =~ ^[0-9]+$ ]] &&
        cpu_freq="$((freq_khz / 1000)) MHz"
fi

governor="N/A"
if [[ -r /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]]; then
    governor="$(< /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
fi

throttle="N/A"
if throttle_raw="$(vcgencmd_read get_throttled)"; then
    case "$throttle_raw" in
        throttled=0x0)
            throttle="Clear"
            ;;
        throttled=*)
            throttle="${throttle_raw#throttled=}"
            ;;
    esac
fi

voltage="N/A"
if voltage_raw="$(vcgencmd_read measure_volts core)"; then
    case "$voltage_raw" in
        volt=*)
            voltage="${voltage_raw#volt=}"
            ;;
    esac
fi

mem_line="$(free -h 2>/dev/null | awk '/^Mem:/ {
    printf "%s used / %s total (%s available)", $3, $2, $7
}')"
[[ -n "$mem_line" ]] || mem_line="N/A"

root_line="$(df -h / 2>/dev/null | awk 'NR==2 {
    printf "%s used / %s total (%s)", $3, $2, $5
}')"
[[ -n "$root_line" ]] || root_line="N/A"

nvme_line="Not mounted"
if mountpoint -q /mnt/nvme1 2>/dev/null; then
    nvme_line="$(df -h /mnt/nvme1 2>/dev/null | awk 'NR==2 {
        printf "%s used / %s total (%s)", $3, $2, $5
    }')"
fi

ipv4="$(ip -4 route get 1.1.1.1 2>/dev/null |
    awk '{for (i=1; i<=NF; i++) if ($i=="src") {print $(i+1); exit}}')"
[[ -n "$ipv4" ]] || ipv4="N/A"

failed_services="$(
    systemctl --failed --no-legend --plain 2>/dev/null |
        awk 'NF {count++} END {print count+0}'
)"

ui_header "PI 5 SYSTEM INFO"

ui_section "System"
ui_row "Model"    "$model"
ui_row "Host"     "$host"
ui_row "Kernel"   "$kernel"
ui_row "Uptime"   "$uptime_text"

ui_section "CPU / Thermal"
ui_row "CPU Temp" "$cpu_temp"
ui_row "CPU Freq" "$cpu_freq"
ui_row "Governor" "$governor"
ui_row "Throttle" "$throttle"
ui_row "Voltage"  "$voltage"

ui_section "Memory / Storage"
ui_row "Memory" "$mem_line"
ui_row "Root"   "$root_line"
ui_row "NVMe"   "$nvme_line"

ui_section "Network / Services"
ui_row "IPv4"            "$ipv4"
ui_row "Failed Services" "$failed_services"

echo
pause_return "Press Enter to return to Admin Tools..."
