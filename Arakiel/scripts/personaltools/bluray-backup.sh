#!/usr/bin/env bash
#--------------------------------------------
# file:    bluray-backup.sh
# author:  Mike Redd  (bash port)
# version: 2.2
# desc:    Blu-ray backup + decrypt wrapper for MakeMKV (Linux).
#          Keeps the decrypted backup and writes BRTrackMeta
#          JSON/TXT sidecars for brencoder.sh.
#--------------------------------------------

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Locate brlib.sh: $BRLIB override, else ~/lib, else alongside this script.
BRLIB="${BRLIB:-}"
if [[ -z "$BRLIB" ]]; then
    for cand in "$HOME/lib/brlib.sh" "$SCRIPT_DIR/brlib.sh"; do
        [[ -f "$cand" ]] && { BRLIB="$cand"; break; }
    done
fi
if [[ ! -f "$BRLIB" ]]; then
    echo "ERROR: cannot find brlib.sh (looked in ~/lib and beside this script). Set BRLIB=/path/to/brlib.sh" >&2
    exit 1
fi
# shellcheck source=/dev/null
source "$BRLIB"

SCRIPT_NAME="Blu-ray Backup"
SCRIPT_VERSION="2.2"
SCRIPT_AUTHOR="Mike Redd"

# ── Config (override via environment) ─────────────────────────
ROOT_PATH="${ROOT_PATH:-$HOME/Rip}"
OUTPUT_ROOT="${OUTPUT_ROOT:-$ROOT_PATH/bluray}"
META_ROOT="${META_ROOT:-$ROOT_PATH/meta}"
DRIVE="${DRIVE:-disc:0}"
MAKEMKV=""

show_header() {
    ui_clear
    show_title "$SCRIPT_NAME" "v$SCRIPT_VERSION  by $SCRIPT_AUTHOR"
    ui_row "Drive"  "$DRIVE"       "$UI_GRY"
    ui_row "Output" "$OUTPUT_ROOT" "$UI_GRY"
    ui_row "Meta"   "$META_ROOT"   "$UI_GRY"
    ui_blank
}

show_menu() {
    show_header
    ui_section "Options"
    printf '  1) Start Blu-ray backup\n'
    printf '  Q) Return\n'
    ui_blank
}

read_movie_name_with_year() {
    local name year
    read -rp "Movie name (Q to cancel): " name
    name="$(trim "$name")"
    [[ "$name" =~ ^[Qq]$ ]] && return 1
    [[ -z "$name" ]] && name="bluray_$(date +%Y%m%d_%H%M%S)"
    read -rp "Year (optional, Q to cancel): " year
    year="$(trim "$year")"
    [[ "$year" =~ ^[Qq]$ ]] && return 1
    [[ "$year" =~ ^[0-9]{4}$ ]] && name="$name [$year]"
    printf '%s' "$name"
}

start_backup() {
    show_header
    ui_section "Backup Setup"

    MAKEMKV="$(find_makemkv)" || { core_error "MakeMKV CLI (makemkvcon) was not found."; pause_return; return; }
    ui_row "MakeMKV" "$MAKEMKV" "$UI_GRY"; ui_blank

    local name; name="$(read_movie_name_with_year)" || return
    local safe dest metabase
    safe="$(safe_name "$name")"
    dest="$OUTPUT_ROOT/$safe"
    metabase="$META_ROOT/$safe"

    show_header
    ui_section "Backup Starting" "$UI_YLW"
    ui_row "Source" "$DRIVE" "$UI_GRY"
    ui_row "Dest"   "$dest"  "$UI_GRY"
    ui_blank

    printf '  %sDecrypting...%s\n' "$UI_CYN" "$UI_R"
    if ! makemkv_backup_progress "$MAKEMKV" "$DRIVE" "$dest"; then
        core_error "MakeMKV backup failed."
        pause_return; return
    fi

    ui_section "Backup Complete" "$UI_GRN"
    ui_row "Saved To" "$dest" "$UI_GRY"

    # Largest .m2ts (optional — metadata still works without it)
    local stream largest_name="" largest_path=""
    if stream="$(find_stream_dir "$dest")"; then
        local row; row="$(largest_m2ts "$stream")"
        if [[ -n "$row" ]]; then
            largest_path="${row#*$'\t'}"
            largest_name="$(basename -- "$largest_path")"
        fi
    fi

    # MakeMKV title/track metadata
    local infofile main ovfile
    infofile="$(mktemp)"; main="$(mktemp)"; ovfile="$(mktemp)"
    if ! makemkv_run_info "$MAKEMKV" "$DRIVE" "$infofile"; then
        core_error "makemkvcon info failed."
        rm -f "$infofile" "$main" "$ovfile"; pause_return; return
    fi
    br_py parse_main_title "$infofile" > "$main"
    if [[ "$(cat "$main")" == "null" ]]; then
        core_error "Could not determine main title metadata."
        rm -f "$infofile" "$main" "$ovfile"; pause_return; return
    fi

    resolve_track_languages "$main" "$ovfile"

    ensure_dirs "$META_ROOT"
    br_py write_meta "$metabase" "$name" "$largest_name" "$largest_path" \
          "$main" "$ovfile" "bluray-backup.sh v$SCRIPT_VERSION"

    ui_blank
    ui_section "Track Metadata Saved" "$UI_MAG"
    local jsonkey; jsonkey="$(basename -- "$metabase")"
    printf '  JSON : %s.json\n' "$metabase"
    printf '  TXT  : %s.tracks.txt\n' "$metabase"
    ui_blank
    printf '  +- Use this name in brencoder.sh --------------------------\n'
    printf '  |  %s\n' "$jsonkey"
    printf '  +----------------------------------------------------------\n'
    [[ -n "$largest_name" ]] && printf '\n  Largest .m2ts : %s\n' "$largest_name"

    rm -f "$infofile" "$main" "$ovfile"
    pause_return
}

# ── Main ──────────────────────────────────────────────────────
require_python || exit 1
ensure_dirs "$ROOT_PATH" "$OUTPUT_ROOT" "$META_ROOT"

while true; do
    show_menu
    read -rp "Choice: " choice
    case "$(trim "$choice" | tr '[:lower:]' '[:upper:]')" in
        1) start_backup ;;
        Q) exit 0 ;;
        *) printf '  Invalid selection.\n'; sleep 1 ;;
    esac
done
