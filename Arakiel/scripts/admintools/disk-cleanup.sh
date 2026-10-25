#!/usr/bin/env bash
#--------------------------------------------
# file:    disk-cleanup.sh
# author:  Mike Redd
# version: 1.0
# desc:    Reclaim disk space: vacuum the journal, trim the pacman
#          cache, remove orphans, and find the biggest files.
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
SUDO=""; [[ "${EUID:-$(id -u)}" -ne 0 ]] && SUDO="sudo"

show_header() {
    ui_header "DISK CLEANUP"
    ui_row "Root usage" "$(df -h / 2>/dev/null | awk 'NR==2{print $3" used / "$2" ("$5")"}')" "$UI_CYN"
    echo
}

vacuum_journal() {
    show_header
    have journalctl || { core_error "journalctl not found"; pause; return; }
    printf '  Current journal size:\n'
    journalctl --disk-usage 2>/dev/null | sed 's/^/    /'
    read -rp "  Vacuum journal to 200M? (y/N): " ok
    [[ "${ok,,}" == "y" ]] && $SUDO journalctl --vacuum-size=200M
    pause
}

trim_cache() {
    show_header
    if have paccache; then
        printf '  Trimming pacman cache (keep last 2)...\n'
        $SUDO paccache -rk2
        $SUDO paccache -ruk0
    else
        printf '  %spaccache not found (install pacman-contrib).%s\n' "$UI_DIM" "$UI_R"
    fi
    pause
}

drop_orphans() {
    show_header
    have pacman || { core_error "pacman not found"; pause; return; }
    local orphans; orphans="$(pacman -Qtdq 2>/dev/null)"
    if [[ -z "$orphans" ]]; then
        printf '  %sNo orphaned packages.%s\n' "$UI_GRN" "$UI_R"
    else
        printf '%s\n' "$orphans" | sed 's/^/    /'
        read -rp "  Remove these orphans? (y/N): " ok
        # shellcheck disable=SC2086
        [[ "${ok,,}" == "y" ]] && $SUDO pacman -Rns $orphans
    fi
    pause
}

big_files() {
    show_header
    local dir="${1:-$HOME}"
    read -rp "  Scan which directory? [$dir]: " d
    d="${d:-$dir}"
    printf '  %sTop 15 largest files under %s:%s\n' "$UI_CYN" "$d" "$UI_R"
    find "$d" -xdev -type f -printf '%s\t%p\n' 2>/dev/null \
        | sort -rn | head -15 \
        | awk -F'\t' '{ s=$1; u="B"; if(s>=1073741824){s/=1073741824;u="GB"} else if(s>=1048576){s/=1048576;u="MB"} else if(s>=1024){s/=1024;u="KB"} printf "    %8.1f %s  %s\n", s, u, $2 }'
    pause
}

while true; do
    show_header
    ui_option "1" "Vacuum systemd journal"
    ui_option "2" "Trim pacman cache"
    ui_option "3" "Remove orphaned packages"
    ui_option "4" "Find biggest files"
    ui_option "q" "Back"
    echo
    read -rp "Select option: " choice
    case "$choice" in
        1) vacuum_journal ;;
        2) trim_cache ;;
        3) drop_orphans ;;
        4) big_files ;;
        q|Q) break ;;
        *) core_error "Invalid option"; sleep 1 ;;
    esac
done
