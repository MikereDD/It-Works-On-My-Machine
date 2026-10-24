#!/usr/bin/env bash
# InfoCat Pi v2 — isolated preview renderer.
# Read-only. Does not invoke or replace production InfoCat.

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/collectors.sh"

mode="full"
color="auto"

usage() {
    printf 'Usage: %s [--compact|--full] [--no-color]\n' "$0"
}

while (($#)); do
    case "$1" in
        --compact) mode="compact" ;;
        --full)    mode="full" ;;
        --no-color) color="off" ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2
           usage >&2
           exit 2 ;;
    esac
    shift
done

infocat_collect

columns="${INFOCAT_COLUMNS:-${COLUMNS:-}}"
if [[ ! "$columns" =~ ^[0-9]+$ ]] || (( columns == 0 )); then
    columns="$(tput cols 2>/dev/null || printf 80)"
fi
[[ "$columns" =~ ^[0-9]+$ ]] || columns=80

reset="" title="" label="" value=""
if [[ "$color" != off && -t 1 && "${TERM:-dumb}" != dumb ]]; then
    reset=$'\e[0m'
    title=$'\e[1;36m'
    label=$'\e[37m'
    value=$'\e[36m'
fi

row() {
    local name="$1" data="$2"
    if (( columns < 60 )); then
        printf '%s%s%s\n' "$label" "$name" "$reset"
        printf '  %s%s%s\n' "$value" "$data" "$reset"
    else
        printf '%s%-14s%s %s%s%s\n' \
            "$label" "$name" "$reset" \
            "$value" "$data" "$reset"
    fi
}

printf '%sInfoCat v2 — %s@%s%s\n' \
    "$title" "$INFOCAT_USER" "$INFOCAT_HOST" "$reset"
printf '%s\n' '--------------------------------'

row 'OS' "$INFOCAT_OS"
row 'Board' "$INFOCAT_BOARD"
row 'Kernel' "$INFOCAT_KERNEL"
row 'Architecture' "$INFOCAT_ARCH"
row 'Uptime' "$INFOCAT_UPTIME"
row 'CPU' "$INFOCAT_CORES cores"
row 'Temperature' "$INFOCAT_TEMPERATURE"
row 'Memory' "$INFOCAT_MEMORY"
row 'Root' "$INFOCAT_ROOT"
row 'NVMe' "$INFOCAT_NVME"

if [[ "$mode" == full ]]; then
    row 'Packages' "$INFOCAT_PACKAGES"
    row 'LAN' "$INFOCAT_LAN"
fi
