#!/usr/bin/env bash
# Lightweight status and full system-information view.

set -u

temperature_c() {
    local raw
    if [[ -r /sys/class/thermal/thermal_zone0/temp ]]; then
        read -r raw </sys/class/thermal/thermal_zone0/temp
        awk -v t="$raw" 'BEGIN { printf "%.0f", t / 1000 }'
    else
        printf "?"
    fi
}

load_one() {
    awk '{print $1}' /proc/loadavg 2>/dev/null || printf "?"
}

root_usage() {
    df -P / 2>/dev/null | awk 'NR == 2 {gsub("%","",$5); print $5}' || printf "?"
}

work_usage() {
    if mountpoint -q /mnt/work 2>/dev/null; then
        df -P /mnt/work | awk 'NR == 2 {gsub("%","",$5); print $5}'
    else
        printf "-"
    fi
}

status_line() {
    printf '#[fg=colour245]load %s #[fg=colour245]temp %s°C #[fg=colour245]/ %s%%' \
        "$(load_one)" "$(temperature_c)" "$(root_usage)"
}

full_view() {
    local host kernel uptime_text memory root work
    host="$(hostname -s)"
    kernel="$(uname -sr)"
    uptime_text="$(uptime -p 2>/dev/null || uptime)"
    memory="$(free -h 2>/dev/null | awk '/^Mem:/ {print $3 " / " $2}')"
    root="$(df -h / 2>/dev/null | awk 'NR == 2 {print $3 " / " $2 " (" $5 ")"}')"

    if mountpoint -q /mnt/work 2>/dev/null; then
        work="$(df -h /mnt/work | awk 'NR == 2 {print $3 " / " $2 " (" $5 ")"}')"
    else
        work="not mounted"
    fi

    printf 'ARAKIEL SYSTEM\n'
    printf '───────────────\n\n'
    printf 'Host:          %s\n' "$host"
    printf 'Kernel:        %s\n' "$kernel"
    printf 'Uptime:        %s\n' "$uptime_text"
    printf 'Load:          %s\n' "$(cat /proc/loadavg 2>/dev/null || printf '?')"
    printf 'Temperature:   %s°C\n' "$(temperature_c)"
    printf 'Memory:        %s\n' "${memory:-unknown}"
    printf 'Root disk:     %s\n' "${root:-unknown}"
    printf '/mnt/work:     %s\n' "$work"
    printf '\nNetwork:\n'
    ip -brief address 2>/dev/null || true
    printf '\nTop processes:\n'
    ps -eo pid,comm,%cpu,%mem --sort=-%cpu 2>/dev/null | head -n 8
}

case "${1:-}" in
    --status) status_line ;;
    *) full_view ;;
esac
