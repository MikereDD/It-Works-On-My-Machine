#!/usr/bin/env bash
# InfoCat Pi v2 — native Linux collectors.
# Read-only. Safe to source. Does not collect until called.

infocat_collect() {
    local os_name model temp_raw

    INFOCAT_HOST="$(cat /proc/sys/kernel/hostname 2>/dev/null || printf unknown)"
    INFOCAT_USER="${USER:-$(id -un)}"

    os_name=""
    if [[ -r /etc/os-release ]]; then
        os_name="$(
            . /etc/os-release
            printf '%s' "${PRETTY_NAME:-${NAME:-Linux}}"
        )"
    fi
    INFOCAT_OS="${os_name:-Linux}"

    INFOCAT_KERNEL="$(uname -r)"
    INFOCAT_ARCH="$(uname -m)"
    INFOCAT_CORES="$(nproc 2>/dev/null || printf unknown)"

    model=""
    if [[ -r /proc/device-tree/model ]]; then
        model="$(tr -d '\000' < /proc/device-tree/model)"
    fi
    INFOCAT_BOARD="${model:-Unknown}"

    INFOCAT_UPTIME="$(uptime -p 2>/dev/null || printf unknown)"
    INFOCAT_UPTIME="${INFOCAT_UPTIME#up }"

    INFOCAT_MEMORY="$(
        free -h 2>/dev/null |
        awk '$1 == "Mem:" {print $3 " / " $2}'
    )"
    INFOCAT_MEMORY="${INFOCAT_MEMORY:-Unknown}"

    INFOCAT_ROOT="$(
        df -hP / 2>/dev/null |
        awk 'NR == 2 {print $3 " / " $2 " (" $5 ")"}'
    )"
    INFOCAT_ROOT="${INFOCAT_ROOT:-Unknown}"

    INFOCAT_NVME="Not mounted"
    if mountpoint -q /mnt/nvme1 2>/dev/null; then
        INFOCAT_NVME="$(
            df -hP /mnt/nvme1 |
            awk 'NR == 2 {print $3 " / " $2 " (" $5 ")"}'
        )"
    fi

    INFOCAT_TEMPERATURE="Unknown"
    if [[ -r /sys/class/thermal/thermal_zone0/temp ]]; then
        IFS= read -r temp_raw < /sys/class/thermal/thermal_zone0/temp
        if [[ "$temp_raw" =~ ^[0-9]+$ ]]; then
            INFOCAT_TEMPERATURE="$(
                awk -v t="$temp_raw" \
                    'BEGIN {printf "%.1f°C", t / 1000}'
            )"
        fi
    fi

    INFOCAT_PACKAGES="Unknown"
    if command -v pacman >/dev/null 2>&1; then
        INFOCAT_PACKAGES="$(pacman -Qq 2>/dev/null | wc -l)"
        INFOCAT_PACKAGES="${INFOCAT_PACKAGES//[[:space:]]/}"
    fi

    INFOCAT_LAN="$(
        ip -4 -o addr show scope global 2>/dev/null |
        awk '$2 !~ /^(lo|docker|veth|br-|tun|tap)/ {
            split($4, a, "/")
            print a[1]
            exit
        }'
    )"
    INFOCAT_LAN="${INFOCAT_LAN:-None}"
}
