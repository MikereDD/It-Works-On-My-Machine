#!/usr/bin/env bash
# InfoCat Pi v2 — artwork layout preview.
# Development-only, read-only.

set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

source "$root/lib/collectors.sh"
infocat_collect

logo="cat"

while (($#)); do
    case "$1" in
        --logo)
            (($# >= 2)) || { echo 'Missing logo name' >&2; exit 2; }
            logo="$2"
            shift
            ;;
        --no-color) ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

case "$logo" in
    cat|arch|windows|rpi-arch|none) ;;
    *) echo "Unsupported preview logo: $logo" >&2; exit 2 ;;
esac

columns="${INFOCAT_COLUMNS:-}"
if [[ ! "$columns" =~ ^[0-9]+$ ]] || (( columns == 0 )); then
    columns="$(tput cols 2>/dev/null || printf 80)"
fi
[[ "$columns" =~ ^[0-9]+$ ]] || columns=80

info=(
    "InfoCat v2 — $INFOCAT_USER@$INFOCAT_HOST"
    "OS           $INFOCAT_OS"
    "Board        $INFOCAT_BOARD"
    "Kernel       $INFOCAT_KERNEL"
    "Architecture $INFOCAT_ARCH"
    "Uptime       $INFOCAT_UPTIME"
    "CPU          $INFOCAT_CORES cores"
    "Temperature  $INFOCAT_TEMPERATURE"
    "Memory       $INFOCAT_MEMORY"
    "Root         $INFOCAT_ROOT"
    "NVMe         $INFOCAT_NVME"
    "Packages     $INFOCAT_PACKAGES"
    "LAN          $INFOCAT_LAN"
)

if [[ "$logo" == none || "$columns" -lt 60 ]]; then
    # Wrap complete words in information-only mode.
    # Fold operates on rendered text, not artwork or ANSI sequences.
    printf '%s\n' "${info[@]}" | fold -s -w "$columns"
    exit 0
fi

art_file="$root/art/$logo.txt"
[[ -f "$art_file" ]] || {
    echo "Missing artwork: $art_file" >&2
    exit 1
}

mapfile -t art < "$art_file"

art_width=0
for line in "${art[@]}"; do
    if (( ${#line} > art_width )); then
        art_width=${#line}
    fi
done
gap=4
info_width=0

for line in "${info[@]}"; do
    (( ${#line} > info_width )) && info_width=${#line}
done

if (( columns >= art_width + gap + info_width )); then
    # Side-by-side layout.
    count=${#art[@]}
    (( ${#info[@]} > count )) && count=${#info[@]}

    for ((i=0; i<count; i++)); do
        printf '%-*s    %s\n' \
            "$art_width" \
            "${art[i]:-}" \
            "${info[i]:-}"
    done
else
    # Stacked layout.
    printf '%s\n' "${art[@]}"
    printf '\n'
    printf '%s\n' "${info[@]}"
fi
