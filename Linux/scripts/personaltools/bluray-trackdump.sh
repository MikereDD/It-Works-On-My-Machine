#!/usr/bin/env bash
#--------------------------------------------
# file:    bluray-trackdump.sh
# author:  Mike Redd  (bash port)
# version: 1.4
# desc:    Blu-ray track metadata dumper (Linux).
#          Makes a temp decrypted backup, finds the largest .m2ts,
#          reads MakeMKV title/track metadata, saves shared-schema
#          .json and .tracks.txt for brencoder.sh, then removes the
#          temp backup.
#--------------------------------------------

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Locate brlib.sh: $BRLIB override, else ../lib (default layout), else alongside.
BRLIB="${BRLIB:-}"
if [[ -z "$BRLIB" ]]; then
    for cand in "$SCRIPT_DIR/../lib/brlib.sh" "$SCRIPT_DIR/brlib.sh"; do
        [[ -f "$cand" ]] && { BRLIB="$cand"; break; }
    done
fi
if [[ ! -f "$BRLIB" ]]; then
    echo "ERROR: cannot find brlib.sh (tried ../lib and ./). Set BRLIB=/path/to/brlib.sh" >&2
    exit 1
fi
# shellcheck source=/dev/null
source "$BRLIB"

SCRIPT_NAME="Blu-ray Track Dump"
SCRIPT_VERSION="1.4"
SCRIPT_AUTHOR="Mike Redd"

# ── Config (override via environment) ─────────────────────────
ROOT_PATH="${ROOT_PATH:-$HOME/Rip}"
BACKUP_ROOT="${BACKUP_ROOT:-$ROOT_PATH/bluray}"
META_ROOT="${META_ROOT:-$ROOT_PATH/meta}"
DRIVE="${DRIVE:-disc:0}"
MAKEMKV=""

show_header() {
    ui_clear
    show_title "$SCRIPT_NAME" "v$SCRIPT_VERSION by $SCRIPT_AUTHOR"
    ui_row "Drive"  "$DRIVE"     "$UI_GRY"
    ui_row "Output" "$META_ROOT" "$UI_GRY"
    ui_blank
}

show_menu() {
    show_header
    ui_section "Actions"
    printf '  1) Dump track metadata for largest .m2ts\n'
    ui_divider
    printf '  Q) Return\n'
}

start_trackdump() {
    show_header

    MAKEMKV="$(find_makemkv)" || { core_error "MakeMKV (makemkvcon) not found"; pause_return; return; }

    local name year
    read -rp "Movie name: " name
    name="$(trim "$name")"
    [[ -z "$name" ]] && name="bluray_$(date +%Y%m%d_%H%M%S)"
    read -rp "Year (optional): " year
    year="$(trim "$year")"
    [[ "$year" =~ ^[0-9]{4}$ ]] && name="$name [$year]"

    local safe backup metabase
    safe="$(safe_name "$name")"
    backup="$BACKUP_ROOT/$safe"
    metabase="$META_ROOT/$safe"

    ui_section "MakeMKV"
    printf '  Decrypting...\n'

    # Always clean up the temp backup, even on error.
    local cleaned=0
    cleanup() { [[ "$cleaned" -eq 0 ]] && { rm -rf -- "$backup" 2>/dev/null; cleaned=1; }; }

    if ! makemkv_backup_progress "$MAKEMKV" "$DRIVE" "$backup"; then
        core_error "MakeMKV backup failed"; cleanup; pause_return; return
    fi

    local stream
    if ! stream="$(find_stream_dir "$backup")"; then
        core_error "No STREAM folder found"; cleanup; pause_return; return
    fi

    local row largest_path largest_name
    row="$(largest_m2ts "$stream")"
    if [[ -z "$row" ]]; then
        core_error "No M2TS found"; cleanup; pause_return; return
    fi
    largest_path="${row#*$'\t'}"
    largest_name="$(basename -- "$largest_path")"
    local bytes="${row%%$'\t'*}"

    ui_section "Largest File"
    printf '  %s\n' "$largest_name"
    printf '  %s GB\n' "$(awk "BEGIN{printf \"%.2f\", $bytes/1073741824}")"

    local infofile main ovfile
    infofile="$(mktemp)"; main="$(mktemp)"; ovfile="$(mktemp)"
    if ! makemkv_run_info "$MAKEMKV" "$DRIVE" "$infofile"; then
        core_error "makemkvcon info failed"
        rm -f "$infofile" "$main" "$ovfile"; cleanup; pause_return; return
    fi
    br_py parse_main_title "$infofile" > "$main"
    if [[ "$(cat "$main")" == "null" ]]; then
        core_error "Could not determine main title"
        rm -f "$infofile" "$main" "$ovfile"; cleanup; pause_return; return
    fi

    resolve_track_languages "$main" "$ovfile"

    ensure_dirs "$META_ROOT"
    br_py write_meta "$metabase" "$name" "$largest_name" "$largest_path" \
          "$main" "$ovfile" "bluray-trackdump.sh v$SCRIPT_VERSION"

    ui_section "Track Dump Saved"
    printf '  JSON : %s.json\n' "$metabase"
    printf '  TXT  : %s.tracks.txt\n' "$metabase"

    local jsonkey; jsonkey="$(basename -- "$metabase")"
    ui_blank
    printf '  +- Use this name in brencoder.sh --------------------------\n'
    printf '  |  %s\n' "$jsonkey"
    printf '  +----------------------------------------------------------\n'
    ui_blank
    printf '  Title source: %s\n' "$(br_py json_get "$main" SourceFile)"

    rm -f "$infofile" "$main" "$ovfile"
    cleanup
    pause_return
}

# ── Main ──────────────────────────────────────────────────────
require_python || exit 1
ensure_dirs "$ROOT_PATH" "$BACKUP_ROOT" "$META_ROOT"

while true; do
    show_menu
    read -rp "Choice: " c
    case "$(trim "$c" | tr '[:lower:]' '[:upper:]')" in
        1) start_trackdump ;;
        Q) exit 0 ;;
        *) ;;
    esac
done
