#!/usr/bin/env bash
#--------------------------------------------
# file:     dvd-ripper-encoder.sh
# author:   Mike Redd  (bash port)
# version:  3.1
# desc:     Encode DVDs directly with HandBrakeCLI on Linux
#           using high-quality x265 defaults. Lets you pick
#           audio/subtitle tracks (shown with their languages).
#--------------------------------------------

set -o pipefail

SCRIPT_NAME="DVD Ripper Encoder"
SCRIPT_VERSION="3.1"
SCRIPT_AUTHOR="Mike Redd"

# ── Config (override via environment) ─────────────────────────
ROOT_PATH="${ROOT_PATH:-$HOME/Rip}"
OUTPUT_ROOT="${OUTPUT_ROOT:-$ROOT_PATH/dvdarchive}"
NFO_ROOT="${NFO_ROOT:-$ROOT_PATH/nfo}"
DEFAULT_DEVICE="${DEFAULT_DEVICE:-/dev/sr0}"
HANDBRAKE_CLI="${HANDBRAKE_CLI:-}"

DEFAULT_CONTAINER="mkv"
DEFAULT_ENCODER="x265_10bit"
DEFAULT_RF=20
DEFAULT_PRESET="slower"
MIN_TITLE_SECONDS=900   # 15 min

DRY_RUN=0

# ── Scan result state (populated by hb_scan) ──────────────────
SCAN_TITLES=()
declare -A SCAN_DURATION
declare -A SCAN_SIZE
declare -A SCAN_ACOUNT
declare -A SCAN_AUDIO     # [title] = lines of "num<TAB>label"
declare -A SCAN_SUBS      # [title] = lines of "num<TAB>label"

# ── Colors / UI helpers (replaces ui.ps1 + core.ps1) ──────────
if [[ -t 1 ]]; then
    UI_R=$'\e[0m';   UI_GRN=$'\e[32m'; UI_CYN=$'\e[36m'; UI_MAG=$'\e[35m'
    UI_YLW=$'\e[33m'; UI_GRY=$'\e[90m'; UI_DIM=$'\e[2m';  UI_RED=$'\e[31m'
else
    UI_R=""; UI_GRN=""; UI_CYN=""; UI_MAG=""; UI_YLW=""; UI_GRY=""; UI_DIM=""; UI_RED=""
fi

ui_blank()   { printf '\n'; }
ui_divider() { printf '  %s%s%s\n' "$UI_GRY" "------------------------------------------------------------" "$UI_R"; }
ui_row()     { printf '  %s%-13s%s %s\n' "${3:-}" "$1" "$UI_R" "$2"; }
core_error() { printf '  %sERROR:%s %s\n' "$UI_RED" "$UI_R" "$1" >&2; }
pause_script() { read -rp "  Press Enter to return to menu... " _; }

ui_header() {
    local title="$1" subtitle="$2"
    ui_blank
    printf '  %s== %s ==%s\n' "$UI_CYN" "$title" "$UI_R"
    printf '  %s%s%s\n' "$UI_GRY" "$subtitle" "$UI_R"
    ui_blank
}

# ── Small utilities ───────────────────────────────────────────
trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

in_array() {
    local needle="$1"; shift
    local x
    for x in "$@"; do [[ "$x" == "$needle" ]] && return 0; done
    return 1
}

# Strip filesystem-hostile characters but keep [ ] (naming convention).
safe_name() {
    local name="$1" safe
    safe="$(printf '%s' "$name" | sed -e 's#[\\/:*?"<>|]#_#g')"
    safe="$(trim "$safe")"
    [[ -z "$safe" ]] && safe="dvd_encode_$(date +%Y%m%d_%H%M%S)"
    printf '%s' "$safe"
}

duration_seconds() {
    local d="$1"
    local re='^([0-9]{2}):([0-9]{2}):([0-9]{2})$'
    if [[ "$d" =~ $re ]]; then
        echo $(( 10#${BASH_REMATCH[1]} * 3600 + 10#${BASH_REMATCH[2]} * 60 + 10#${BASH_REMATCH[3]} ))
    else
        echo 0
    fi
}

# ── HandBrakeCLI discovery ────────────────────────────────────
find_handbrake() {
    if [[ -n "$HANDBRAKE_CLI" && -x "$HANDBRAKE_CLI" ]]; then return 0; fi
    local c
    for c in HandBrakeCLI handbrakecli; do
        if command -v "$c" >/dev/null 2>&1; then
            HANDBRAKE_CLI="$(command -v "$c")"
            return 0
        fi
    done
    for c in /usr/bin/HandBrakeCLI /usr/local/bin/HandBrakeCLI /snap/bin/handbrake.cli; do
        if [[ -x "$c" ]]; then HANDBRAKE_CLI="$c"; return 0; fi
    done
    return 1
}

ensure_directories() {
    local p
    for p in "$ROOT_PATH" "$OUTPUT_ROOT" "$NFO_ROOT"; do
        [[ -d "$p" ]] || mkdir -p -- "$p"
    done
}

# ── Input resolution ──────────────────────────────────────────
# Accepts a block device (/dev/sr0), a VIDEO_TS folder, or its parent.
resolve_input() {
    local p="$1"
    if [[ -b "$p" ]]; then printf '%s' "$p"; return 0; fi
    if [[ -e "$p" ]]; then
        local rp
        rp="$(realpath -- "$p" 2>/dev/null || printf '%s' "$p")"
        printf '%s' "$rp"
        return 0
    fi
    return 1
}

get_dvd_source() {
    local dev="$1"
    if [[ -b "$dev" ]]; then printf '%s' "$dev"; return 0; fi
    if [[ -d "$dev" ]]; then
        if [[ -d "$dev/VIDEO_TS" || "$(basename -- "$dev")" == "VIDEO_TS" ]]; then
            printf '%s' "$dev"; return 0
        fi
    fi
    return 1
}

# ── Language parsing (port of Get-TrackLangFromDesc) ──────────
# Parses a HandBrake track tail like:
#   "English (AC3) (2.0 ch) (iso639-2: eng), 48000Hz, 192000bps"
#   "English (iso639-2: eng) (Bitmap)(VOBSUB)"
# and prints a label such as "English (eng)".
track_lang_label() {
    local desc="$1" name="" code="" label
    local re_name='^[[:space:]]*([^(,]+)'
    [[ "$desc" =~ $re_name ]] && name="$(trim "${BASH_REMATCH[1]}")"
    local re_code='iso639-2:[[:space:]]*([A-Za-z]+)'
    [[ "$desc" =~ $re_code ]] && code="$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')"

    if   [[ -n "$name" && -n "$code" ]]; then label="$name ($code)"
    elif [[ -n "$name" ]];               then label="$name"
    elif [[ -n "$code" ]];               then label="$code"
    else                                      label="unknown"
    fi
    printf '%s' "$label"
}

# ── Scan ──────────────────────────────────────────────────────
hb_scan() {
    local input="$1" resolved
    if ! resolved="$(resolve_input "$input")"; then
        core_error "Input path not found: $input"; return 1
    fi

    ui_blank
    printf '  %sScanning titles with HandBrakeCLI...%s\n' "$UI_GRN" "$UI_R"
    printf '  %sUsing%s  %s\n' "$UI_DIM" "$UI_R" "$HANDBRAKE_CLI"
    printf '  %sInput%s  %s\n' "$UI_DIM" "$UI_R" "$resolved"
    ui_blank

    local scan_output
    scan_output="$("$HANDBRAKE_CLI" --input "$resolved" --title 0 --scan \
                   --min-duration "$MIN_TITLE_SECONDS" 2>&1)"

    # reset state
    SCAN_TITLES=()
    SCAN_DURATION=(); SCAN_SIZE=(); SCAN_ACOUNT=(); SCAN_AUDIO=(); SCAN_SUBS=()

    local cur="" section=""
    local re_title='^\+ title ([0-9]+):'
    local re_dur='^[[:space:]]*\+ duration: (.+)$'
    local re_size='^[[:space:]]*\+ size: (.+)$'
    local re_ahdr='^[[:space:]]*\+ audio tracks:[[:space:]]*$'
    local re_shdr='^[[:space:]]*\+ subtitle tracks:[[:space:]]*$'
    local re_other='^[[:space:]]*\+ [A-Za-z][A-Za-z ]*:[[:space:]]*$'
    local re_track='^[[:space:]]*\+ ([0-9]+), (.+)$'

    local line
    while IFS= read -r line; do
        if [[ "$line" =~ $re_title ]]; then
            cur="${BASH_REMATCH[1]}"
            SCAN_TITLES+=("$cur")
            SCAN_DURATION[$cur]=""
            SCAN_SIZE[$cur]=""
            SCAN_ACOUNT[$cur]=0
            SCAN_AUDIO[$cur]=""
            SCAN_SUBS[$cur]=""
            section=""
            continue
        fi
        [[ -z "$cur" ]] && continue

        if [[ "$line" =~ $re_dur ]]; then
            SCAN_DURATION[$cur]="$(trim "${BASH_REMATCH[1]}")"
        elif [[ "$line" =~ $re_size ]]; then
            SCAN_SIZE[$cur]="$(trim "${BASH_REMATCH[1]}")"
        elif [[ "$line" =~ $re_ahdr ]]; then
            section="audio"
        elif [[ "$line" =~ $re_shdr ]]; then
            section="subtitle"
        elif [[ "$line" =~ $re_other ]]; then
            section=""
        elif [[ "$line" =~ $re_track ]]; then
            local num="${BASH_REMATCH[1]}" desc label
            desc="$(trim "${BASH_REMATCH[2]}")"
            label="$(track_lang_label "$desc")"
            if [[ "$section" == "audio" ]]; then
                SCAN_ACOUNT[$cur]=$(( SCAN_ACOUNT[$cur] + 1 ))
                SCAN_AUDIO[$cur]+="${num}"$'\t'"${label}"$'\n'
            elif [[ "$section" == "subtitle" ]]; then
                SCAN_SUBS[$cur]+="${num}"$'\t'"${label}"$'\n'
            fi
        fi
    done <<< "$scan_output"

    if [[ "${#SCAN_TITLES[@]}" -eq 0 ]]; then
        core_error "No titles detected."
        printf '%s\n' "$scan_output"
        return 0
    fi

    printf '  %sDetected titles:%s\n' "$UI_MAG" "$UI_R"
    printf '    %-6s %-10s %-12s %s\n' "Title" "Duration" "Size" "Audio"
    local t
    for t in "${SCAN_TITLES[@]}"; do
        # SCAN_SIZE holds e.g. "720x480, pixel aspect: ..." — show just the resolution.
        printf '    %-6s %-10s %-12s %s\n' \
            "$t" "${SCAN_DURATION[$t]:-}" "${SCAN_SIZE[$t]%%,*}" "${SCAN_ACOUNT[$t]:-0}"
    done
}

get_main_title() {
    local best="" best_secs=-1 t secs
    for t in "${SCAN_TITLES[@]}"; do
        secs="$(duration_seconds "${SCAN_DURATION[$t]:-}")"
        if (( secs > best_secs )); then best_secs="$secs"; best="$t"; fi
    done
    printf '%s' "$best"
}

# ── Auto-tune (port of Get-AutoTune) ──────────────────────────
TUNE=""; TUNE_NOTE=""
auto_tune() {
    local name
    name="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    if [[ "$name" =~ (anime|animation|animated|cartoon|pixar|disney|dreamworks|ghibli|miyazaki) ]]; then
        TUNE="animation"; TUNE_NOTE="detected animation keywords"
    elif [[ "$name" =~ (19[0-7][0-9]|198[0-5]) ]]; then
        TUNE="grain"; TUNE_NOTE="older film/grain-friendly content"
    else
        TUNE=""; TUNE_NOTE="default x265 live-action profile"
    fi
}

# ── Encode settings prompt ────────────────────────────────────
RF_SEL=0; PRESET_SEL=""; CONTAINER_SEL=""
get_encode_settings() {
    ui_blank
    printf '  %sPress Enter to accept defaults shown in [brackets].%s\n' "$UI_GRY" "$UI_R"
    ui_blank

    local rf_in preset_in container_in
    read -rp "RF quality [$DEFAULT_RF]  (18=larger, 22=smaller): " rf_in
    rf_in="$(trim "$rf_in")"
    if [[ -z "$rf_in" ]]; then
        RF_SEL="$DEFAULT_RF"
    elif [[ "$rf_in" =~ ^[0-9]+$ ]]; then
        if (( rf_in < 16 || rf_in > 28 )); then
            printf '  %sRF out of safe range — clamping to 18-22%s\n' "$UI_YLW" "$UI_R"
            (( rf_in < 18 )) && rf_in=18
            (( rf_in > 22 )) && rf_in=22
        fi
        RF_SEL="$rf_in"
    else
        printf '  %sNon-numeric RF — using default.%s\n' "$UI_YLW" "$UI_R"
        RF_SEL="$DEFAULT_RF"
    fi

    read -rp "Preset [$DEFAULT_PRESET]  (slow / slower / veryslow): " preset_in
    preset_in="$(trim "$preset_in")"
    if [[ -z "$preset_in" ]]; then
        PRESET_SEL="$DEFAULT_PRESET"
    elif [[ "$preset_in" == "slow" || "$preset_in" == "slower" || "$preset_in" == "veryslow" ]]; then
        PRESET_SEL="$preset_in"
    else
        printf '  %sUnknown preset — using default.%s\n' "$UI_YLW" "$UI_R"
        PRESET_SEL="$DEFAULT_PRESET"
    fi

    read -rp "Container [$DEFAULT_CONTAINER]  (mkv / mp4): " container_in
    container_in="$(trim "$container_in")"
    if [[ -z "$container_in" ]]; then
        CONTAINER_SEL="$DEFAULT_CONTAINER"
    elif [[ "$container_in" == "mkv" || "$container_in" == "mp4" ]]; then
        CONTAINER_SEL="$container_in"
    else
        printf '  %sUnknown container — using default.%s\n' "$UI_YLW" "$UI_R"
        CONTAINER_SEL="$DEFAULT_CONTAINER"
    fi
}

# ── Track selection (port of Select-Tracks) ───────────────────
# Sets global SEL to 'all' | 'none' | 'N,M'. $2 is newline list of "num<TAB>label".
SEL="all"
select_tracks() {
    local kind="$1" list="$2"
    SEL="all"

    if [[ -z "$list" ]]; then
        printf '  %sNo %s tracks detected — including all available.%s\n' "$UI_YLW" "$kind" "$UI_R"
        SEL="all"; return
    fi

    ui_blank
    printf '  %s%s tracks:%s\n' "$UI_MAG" "${kind^}" "$UI_R"
    local nums=() num label
    while IFS=$'\t' read -r num label; do
        [[ -z "$num" ]] && continue
        printf '    %s%s%s  %s\n' "$UI_DIM" "$num" "$UI_R" "$label"
        nums+=("$num")
    done <<< "$list"

    local choice
    while true; do
        read -rp "  Include $kind tracks (e.g. 1,3) [all]: " choice
        choice="$(trim "$choice")"
        if [[ -z "$choice" || "${choice,,}" == "all" ]]; then SEL="all"; return; fi
        if [[ "${choice,,}" == "none" ]]; then SEL="none"; return; fi

        local ok=1 picked=() p parts
        IFS=',' read -ra parts <<< "$choice"
        for p in "${parts[@]}"; do
            p="$(trim "$p")"
            if [[ "$p" =~ ^[0-9]+$ ]] && in_array "$p" "${nums[@]}"; then
                picked+=("$p")
            else
                printf "  %s'%s' is not a listed track number — try again.%s\n" "$UI_YLW" "$p" "$UI_R"
                ok=0; break
            fi
        done
        if [[ "$ok" -eq 1 && "${#picked[@]}" -gt 0 ]]; then
            local IFS=','; SEL="${picked[*]}"; return
        fi
    done
}

# ── NFO stub ──────────────────────────────────────────────────
write_nfo_stub() {
    local movie="$1" out="$2" tune="$3" rf="$4" preset="$5"
    local safe nfo now tune_disp
    safe="$(safe_name "$movie")"
    nfo="$NFO_ROOT/$safe.nfo"
    now="$(date '+%Y-%m-%d %H:%M:%S')"
    tune_disp="${tune:-(none)}"

    if cat > "$nfo" <<EOF
Movie    : $movie
Encoded  : $now
Source   : DVD
Output   : $out
Encoder  : $DEFAULT_ENCODER
RF       : $rf
Preset   : $preset
Tune     : $tune_disp
Script   : $SCRIPT_NAME v$SCRIPT_VERSION
EOF
    then
        printf '  %sNFO written: %s%s\n' "$UI_GRY" "$nfo" "$UI_R"
    else
        printf '  %sCould not write NFO: %s%s\n' "$UI_YLW" "$nfo" "$UI_R"
    fi
}

# ── Encode ────────────────────────────────────────────────────
encode_dvd_title() {
    local input="$1" title="$2" movie="$3" tune="$4" container="$5"
    local rf="$6" preset="$7" audio_sel="$8" sub_sel="$9"

    local resolved
    if ! resolved="$(resolve_input "$input")"; then
        core_error "Input path not found: $input"; return 1
    fi

    local safe out
    safe="$(safe_name "$movie")"
    out="$OUTPUT_ROOT/$safe.$container"

    if [[ -e "$out" ]]; then
        ui_blank
        printf '  %sOutput file already exists:%s %s\n' "$UI_YLW" "$UI_R" "$out"
        local ov
        read -rp "Overwrite? (Y/N) " ov
        if ! [[ "$ov" =~ ^[Yy]$ ]]; then
            out="$OUTPUT_ROOT/${safe}_$(date +%Y%m%d_%H%M%S).$container"
            printf '  %sWriting to:%s %s\n' "$UI_GRY" "$UI_R" "$out"
        fi
    fi

    local audio_disp sub_disp
    case "$audio_sel" in
        all)  audio_disp="all tracks" ;;
        none) audio_disp="none" ;;
        *)    audio_disp="tracks $audio_sel" ;;
    esac
    case "$sub_sel" in
        all)  sub_disp="all tracks" ;;
        none) sub_disp="none" ;;
        *)    sub_disp="tracks $sub_sel" ;;
    esac

    ui_blank
    printf '  %sEncoding title %s...%s\n' "$UI_GRN" "$title" "$UI_R"
    printf '  %sInput  %s %s\n' "$UI_DIM" "$UI_R" "$resolved"
    printf '  %sOutput %s %s\n' "$UI_DIM" "$UI_R" "$out"
    printf '  %sCodec  %s %s\n' "$UI_DIM" "$UI_R" "$DEFAULT_ENCODER"
    printf '  %sRF     %s %s\n' "$UI_DIM" "$UI_R" "$rf"
    printf '  %sPreset %s %s\n' "$UI_DIM" "$UI_R" "$preset"
    printf '  %sTune   %s %s\n' "$UI_DIM" "$UI_R" "${tune:-(none)}"
    printf '  %sAudio  %s %s\n' "$UI_DIM" "$UI_R" "$audio_disp"
    printf '  %sSubs   %s %s\n' "$UI_DIM" "$UI_R" "$sub_disp"
    printf '  %sUsing  %s %s\n' "$UI_DIM" "$UI_R" "$HANDBRAKE_CLI"
    ui_blank

    local args=(
        --input          "$resolved"
        --title          "$title"
        --output         "$out"
        --format         "av_$container"
        --encoder        "$DEFAULT_ENCODER"
        --quality        "$rf"
        --encoder-preset "$preset"
        --markers
        --cfr
        --crop-mode      auto
        --anamorphic     loose
        --modulus        2
        --comb-detect
        --decomb
        --aencoder       copy
        --audio-fallback eac3
    )

    # Audio selection: language tags carry through from the DVD either way.
    if [[ "$audio_sel" == "all" ]]; then
        args+=( --all-audio )
    elif [[ "$audio_sel" != "none" ]]; then
        args+=( --audio "$audio_sel" )
    fi

    # Subtitle selection: VOBSUB bitmaps carry into MKV with their languages.
    if [[ "$sub_sel" == "all" ]]; then
        args+=( --all-subtitles )
    elif [[ "$sub_sel" == "none" ]]; then
        :   # no subtitle tracks
    else
        args+=( --subtitle "$sub_sel" )
    fi

    [[ -n "$tune" ]] && args+=( --encoder-tune "$tune" )

    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf '  %s[DRY RUN] Would execute:%s\n' "$UI_YLW" "$UI_R"
        printf '  %q' "$HANDBRAKE_CLI"
        printf ' %q' "${args[@]}"
        printf '\n'
        ui_blank
        return 0
    fi

    "$HANDBRAKE_CLI" "${args[@]}"

    if [[ ! -e "$out" ]]; then
        core_error "Encode appears to have failed. Output file not found."
        return 1
    fi

    ui_blank
    printf '  %sEncode complete:%s %s\n' "$UI_GRN" "$UI_R" "$out"
    write_nfo_stub "$movie" "$out" "$tune" "$rf" "$preset"
}

# ── Encode flow ───────────────────────────────────────────────
read_movie_name_with_year() {
    local movie year
    read -rp "Movie name: " movie
    movie="$(trim "$movie")"
    [[ -z "$movie" ]] && movie="dvd_encode_$(date +%Y%m%d_%H%M%S)"

    read -rp "Year (optional, 4 digits): " year
    year="$(trim "$year")"
    if [[ "$year" =~ ^[0-9]{4}$ ]]; then
        movie="$movie [$year]"
    fi
    printf '%s' "$movie"
}

invoke_encode_flow() {
    local input="$1" movie="$2"

    hb_scan "$input" || return 1
    if [[ "${#SCAN_TITLES[@]}" -eq 0 ]]; then
        core_error "Could not find any titles to encode."; return 1
    fi

    local main
    main="$(get_main_title)"

    ui_blank
    printf '  %sSuggested main title:%s %s  Duration: %s\n' \
        "$UI_YLW" "$UI_R" "$main" "${SCAN_DURATION[$main]:-}"

    local tc sel_title
    read -rp "Title to encode [$main]: " tc
    tc="$(trim "$tc")"
    sel_title="${tc:-$main}"
    if ! [[ "$sel_title" =~ ^[0-9]+$ ]] || [[ -z "${SCAN_DURATION[$sel_title]+x}" ]]; then
        core_error "Title $sel_title is not in the detected list."; return 1
    fi

    local audio_sel sub_sel
    select_tracks "audio"    "${SCAN_AUDIO[$sel_title]:-}";  audio_sel="$SEL"
    select_tracks "subtitle" "${SCAN_SUBS[$sel_title]:-}";   sub_sel="$SEL"

    auto_tune "$movie"
    printf '  %sAuto-selected tune:%s %s  %s(%s)%s\n' \
        "$UI_MAG" "$UI_R" "${TUNE:-(none)}" "$UI_GRY" "$TUNE_NOTE" "$UI_R"

    get_encode_settings

    encode_dvd_title "$input" "$sel_title" "$movie" "$TUNE" \
        "$CONTAINER_SEL" "$RF_SEL" "$PRESET_SEL" "$audio_sel" "$sub_sel"
}

# ── Menu actions ──────────────────────────────────────────────
encode_direct_from_dvd() {
    ui_blank
    local dev movie src
    read -rp "DVD device or path [$DEFAULT_DEVICE]: " dev
    dev="$(trim "$dev")"; dev="${dev:-$DEFAULT_DEVICE}"

    movie="$(read_movie_name_with_year)"

    if src="$(get_dvd_source "$dev")"; then
        invoke_encode_flow "$src" "$movie" || true
    else
        ui_blank
        core_error "No DVD found at: $dev (expected a block device or a VIDEO_TS folder)"
    fi
    pause_script
}

scan_dvd_only() {
    ui_blank
    local dev src
    read -rp "DVD device or path [$DEFAULT_DEVICE]: " dev
    dev="$(trim "$dev")"; dev="${dev:-$DEFAULT_DEVICE}"

    if src="$(get_dvd_source "$dev")"; then
        hb_scan "$src" || true
    else
        ui_blank
        core_error "No DVD found at: $dev (expected a block device or a VIDEO_TS folder)"
    fi
    pause_script
}

encode_from_existing_folder() {
    ui_blank
    local path movie
    read -rp "Path to VIDEO_TS folder or parent folder: " path
    path="$(trim "$path")"

    if [[ ! -e "$path" ]]; then
        ui_blank
        core_error "Path not found."
        pause_script
        return
    fi

    movie="$(read_movie_name_with_year)"
    invoke_encode_flow "$path" "$movie" || true
    pause_script
}

show_config() {
    ui_blank
    ui_row "RootPath"     "$ROOT_PATH"         "$UI_GRY"
    ui_row "OutputRoot"   "$OUTPUT_ROOT"       "$UI_GRY"
    ui_row "NfoRoot"      "$NFO_ROOT"          "$UI_GRY"
    ui_row "DefaultDev"   "$DEFAULT_DEVICE"    "$UI_GRY"
    ui_row "Container"    "$DEFAULT_CONTAINER" "$UI_GRY"
    ui_row "Encoder"      "$DEFAULT_ENCODER"   "$UI_GRY"
    ui_row "RF"           "$DEFAULT_RF"        "$UI_GRY"
    ui_row "Preset"       "$DEFAULT_PRESET"    "$UI_GRY"
    ui_row "HandBrakeCLI" "$HANDBRAKE_CLI"     "$UI_GRY"
    ui_row "DryRun"       "$([[ "$DRY_RUN" -eq 1 ]] && echo Yes || echo No)" "$UI_GRY"
    pause_script
}

# ── Header / menu ─────────────────────────────────────────────
show_header() {
    clear 2>/dev/null || printf '\033c'
    ui_header "$SCRIPT_NAME" "v$SCRIPT_VERSION  by $SCRIPT_AUTHOR"
    ui_row "User"     "$(id -un)@$(hostname)"
    ui_row "Defaults" "$DEFAULT_ENCODER / RF $DEFAULT_RF / $DEFAULT_PRESET / $DEFAULT_CONTAINER" "$UI_GRY"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        ui_row "Mode" "DRY RUN — no files will be written" "$UI_YLW"
    fi
    ui_blank
}

show_menu() {
    ui_divider
    printf '  %s  1)%s  Encode directly from DVD\n'      "$UI_GRN" "$UI_R"
    printf '  %s  2)%s  Scan DVD titles only\n'          "$UI_GRN" "$UI_R"
    printf '  %s  3)%s  Encode from existing folder\n'   "$UI_GRN" "$UI_R"
    ui_divider
    printf '  %s  4)%s  Show config\n'                   "$UI_CYN" "$UI_R"
    ui_divider
    printf '  %s  Q)%s  Quit\n'                          "$UI_GRY" "$UI_R"
    ui_blank
}

# ── Startup ───────────────────────────────────────────────────
usage() {
    printf 'Usage: %s [--dry-run]\n' "$(basename -- "$0")"
    printf '  --dry-run, -n   Print the HandBrake command instead of running it\n'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--dry-run) DRY_RUN=1 ;;
        -h|--help)    usage; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; usage; exit 1 ;;
    esac
    shift
done

if ! find_handbrake; then
    core_error "HandBrakeCLI was not found. Install it (e.g. 'sudo apt install handbrake-cli') or set HANDBRAKE_CLI."
    exit 1
fi
ensure_directories

while true; do
    show_header
    show_menu
    read -rp "Choose: " choice
    choice="$(trim "$choice")"; choice="${choice^^}"
    case "$choice" in
        1) encode_direct_from_dvd ;;
        2) scan_dvd_only ;;
        3) encode_from_existing_folder ;;
        4) show_config ;;
        Q) ui_blank; printf '  %sGoodbye.%s\n' "$UI_CYN" "$UI_R"; ui_blank; exit 0 ;;
        *) core_error "Invalid choice."; sleep 1 ;;
    esac
done
