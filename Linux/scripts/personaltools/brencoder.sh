#!/usr/bin/env bash
#--------------------------------------------
# file:    brencoder.sh
# author:  Mike Redd  (bash port)
# version: 2.5.2
# desc:    Encode Blu-ray .m2ts files to H.265/HEVC on Linux using
#          ffmpeg (HDR/SDR auto-detected), create a sample clip from
#          the finished MKV, apply track metadata from sidecar JSON /
#          .tracks.txt when available, and verify/repair language,
#          default and forced tags via mkvpropedit.
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

SCRIPT_NAME="Blu-ray Encoder"
SCRIPT_VERSION="2.5.2"
SCRIPT_AUTHOR="Mike Redd"

# ── Config (override via environment) ─────────────────────────
ROOT_PATH="${ROOT_PATH:-$HOME/Rip}"
INPUT_ROOT="${INPUT_ROOT:-$ROOT_PATH/bluray}"
OUTPUT_ROOT="${OUTPUT_ROOT:-$ROOT_PATH/raw265}"
DONE_ROOT="${DONE_ROOT:-$ROOT_PATH/done}"
SAMPLE_ROOT="${SAMPLE_ROOT:-$ROOT_PATH/sample}"
SUBTITLE_ROOT="${SUBTITLE_ROOT:-$ROOT_PATH/subtitles}"
META_ROOT="${META_ROOT:-$ROOT_PATH/meta}"
TXT_ROOT="${TXT_ROOT:-$ROOT_PATH/txt}"

CRF_HDR="${CRF_HDR:-18}"
CRF_SDR="${CRF_SDR:-19}"
DEFAULT_PRESET="${DEFAULT_PRESET:-slow}"
DEFAULT_AUDIO="${DEFAULT_AUDIO:-copy}"
DEFAULT_EXT="mkv"
DEFAULT_START="00:10:00"
DEFAULT_LENGTH=60
X265_PSY_PARAMS="rd=3:psy-rd=1.5:psy-rdoq=1.0:aq-mode=3:deblock=-1,-1:pools=*"
M2TS_PROBESIZE="100000000"
M2TS_ANALYZEDUR="300000000"
METADATA_SCAN_LIMIT=200

FFMPEG=""; FFPROBE=""; MKVPROPEDIT=""; MKVMERGE=""
DRY_RUN="${DRY_RUN:-0}"

# ── Header / menu ─────────────────────────────────────────────
show_header() {
    ui_clear
    show_title "$SCRIPT_NAME" "v$SCRIPT_VERSION  by $SCRIPT_AUTHOR"
    ui_row "User"   "$(id -un)@$(hostname)"
    ui_row "Input"  "$INPUT_ROOT" "$UI_GRY"
    ui_row "Meta"   "$META_ROOT"  "$UI_GRY"
    ui_row "Preset" "$DEFAULT_PRESET  -  10-bit yuv420p10le" "$UI_GRY"
    ui_row "CRF"    "HDR=$CRF_HDR / SDR=$CRF_SDR (auto)" "$UI_GRY"
    ui_row "Audio"  "copy (lossless passthrough)" "$UI_GRY"
    [[ "$DRY_RUN" -eq 1 ]] && ui_row "Mode" "DRY RUN — commands printed, not run" "$UI_YLW"
    ui_blank
}

show_menu() {
    ui_divider
    printf '  %s  1)%s  Encode all .m2ts files\n'                "$UI_GRN" "$UI_R"
    printf '  %s  2)%s  Encode single file\n'                    "$UI_GRN" "$UI_R"
    printf '  %s  3)%s  Show source files\n'                     "$UI_GRN" "$UI_R"
    ui_divider
    printf '  %s  5)%s  Repair language tags on finished MKV\n'  "$UI_YLW" "$UI_R"
    ui_divider
    printf '  %s  4)%s  Show config\n'                           "$UI_CYN" "$UI_R"
    ui_divider
    printf '  %s  Q)%s  Quit\n'                                  "$UI_GRY" "$UI_R"
    ui_blank
}

# ── Dependencies ──────────────────────────────────────────────
ensure_dependencies() {
    local missing=()
    FFMPEG="$(find_tool ffmpeg)";          [[ -z "$FFMPEG" ]]      && missing+=(ffmpeg)
    FFPROBE="$(find_tool ffprobe)";        [[ -z "$FFPROBE" ]]     && missing+=(ffprobe)
    MKVPROPEDIT="$(find_tool mkvpropedit)";[[ -z "$MKVPROPEDIT" ]] && missing+=(mkvpropedit)
    MKVMERGE="$(find_tool mkvmerge)";      [[ -z "$MKVMERGE" ]]    && missing+=(mkvmerge)
    if [[ "${#missing[@]}" -gt 0 ]]; then
        core_error "Missing required tools: ${missing[*]}"
        return 1
    fi
}

# ── Source discovery ──────────────────────────────────────────
# Populates SRC_FILES (array of paths) sorted largest-first.
SRC_FILES=()
get_m2ts_files() {
    SRC_FILES=()
    [[ -d "$INPUT_ROOT" ]] || return 0
    local row
    while IFS= read -r row; do
        SRC_FILES+=("${row#*$'\t'}")
    done < <(find "$INPUT_ROOT" -type f -iname '*.m2ts' -printf '%s\t%p\n' 2>/dev/null | sort -rn)
}

human_gb() { awk "BEGIN{printf \"%.2f\", $1/1073741824}"; }

show_source_files() {
    get_m2ts_files
    ui_blank
    if [[ "${#SRC_FILES[@]}" -eq 0 ]]; then
        core_error "No .m2ts files found in $INPUT_ROOT"; pause_return; return
    fi
    printf '  %sAvailable source files:%s\n' "$UI_MAG" "$UI_R"
    local f sz
    for f in "${SRC_FILES[@]}"; do
        sz="$(stat -c '%s' "$f" 2>/dev/null || echo 0)"
        printf '    %s  [%s GB]\n' "$(basename -- "$f")" "$(human_gb "$sz")"
    done
    pause_return
}

# Blu-ray streams are often 00004.m2ts; fall back to the backup folder name.
default_movie_name() {
    local file="$1" base dir
    base="$(basename -- "${file%.*}")"
    if [[ "$base" =~ ^[0-9]{5}$ ]]; then
        dir="$(dirname -- "$file")"
        while [[ -n "$dir" && "$dir" != "$INPUT_ROOT" && "$dir" != "/" ]]; do
            local n; n="$(basename -- "$dir")"
            if [[ -n "$n" && "$n" != "STREAM" && "$n" != "BDMV" ]]; then
                printf '%s' "$n"; return
            fi
            dir="$(dirname -- "$dir")"
        done
    fi
    printf '%s' "$base"
}

read_movie_name_with_year() {
    local def="$1" name year
    read -rp "Movie name [$def]: " name
    name="$(trim "$name")"; [[ -z "$name" ]] && name="$def"
    read -rp "Year (optional, 4 digits): " year
    year="$(trim "$year")"
    [[ "$year" =~ ^[0-9]{4}$ ]] && name="$name [$year]"
    printf '%s' "$name"
}

# ── ffprobe helpers ───────────────────────────────────────────
get_video_duration() {   # <path> -> seconds (float) or 0
    local out
    out="$("$FFPROBE" -v error -probesize "$M2TS_PROBESIZE" -analyzeduration "$M2TS_ANALYZEDUR" \
            -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$1" 2>/dev/null)"
    [[ "$out" =~ ^[0-9.]+$ ]] && printf '%s' "$out" || printf '0'
}

# Sets VP_* globals describing the source video profile.
VP_ISHDR=0; VP_CRF=0; VP_PIXFMT=""; VP_PRIM=""; VP_TRC=""; VP_SPACE=""
VP_MASTER=""; VP_MAXCLL=""; VP_PROFILE=""
get_source_video_profile() {   # <path>
    local sfile ffile
    sfile="$(mktemp)"; ffile="$(mktemp)"
    "$FFPROBE" -v error -probesize "$M2TS_PROBESIZE" -analyzeduration "$M2TS_ANALYZEDUR" \
        -select_streams v:0 \
        -show_entries stream=color_transfer,color_primaries,color_space,pix_fmt \
        -of json "$1" > "$sfile" 2>/dev/null
    # one-frame side-data probe for mastering display / maxcll
    "$FFPROBE" -v error -probesize "$M2TS_PROBESIZE" -analyzeduration "$M2TS_ANALYZEDUR" \
        -read_intervals '%+#1' -select_streams v:0 -show_frames -of json "$1" > "$ffile" 2>/dev/null

    local pj; pj="$(br_py video_profile "$sfile" "$ffile" "$CRF_HDR" "$CRF_SDR")"
    rm -f "$sfile" "$ffile"

    VP_ISHDR="$(printf '%s' "$pj" | br_py_json IsHDR)"
    VP_CRF="$(printf '%s' "$pj"   | br_py_json CRF)"
    VP_PIXFMT="$(printf '%s' "$pj"| br_py_json PixFmt)"
    VP_PRIM="$(printf '%s' "$pj"  | br_py_json ColorPrimaries)"
    VP_TRC="$(printf '%s' "$pj"   | br_py_json ColorTrc)"
    VP_SPACE="$(printf '%s' "$pj" | br_py_json Colorspace)"
    VP_MASTER="$(printf '%s' "$pj"| br_py_json MasterDisplay)"
    VP_MAXCLL="$(printf '%s' "$pj"| br_py_json MaxCLL)"
    VP_PROFILE="$(printf '%s' "$pj"|br_py_json Profile)"
    [[ "$VP_ISHDR" == "True" || "$VP_ISHDR" == "true" ]] && VP_ISHDR=1 || VP_ISHDR=0
}

# tiny stdin JSON field reader
br_py_json() { python3 -c 'import sys,json; d=json.load(sys.stdin); v=d.get(sys.argv[1]); print("" if v is None else (v if isinstance(v,str) else json.dumps(v)))' "$1"; }

# ── Output paths ──────────────────────────────────────────────
get_output_path()  { printf '%s/%s.%s' "$OUTPUT_ROOT" "$(safe_name "$1")" "$DEFAULT_EXT"; }

get_sample_output_path() {
    local safe out; safe="$(safe_name "$1")"
    out="$SAMPLE_ROOT/${safe}_sample.$DEFAULT_EXT"
    [[ -e "$out" ]] && out="$SAMPLE_ROOT/${safe}_sample_$(date +%Y%m%d_%H%M%S).$DEFAULT_EXT"
    printf '%s' "$out"
}

move_source_to_done() {   # <srcpath> -> prints dest
    local src="$1" base ext dest
    base="$(basename -- "$src")"
    dest="$DONE_ROOT/$base"
    if [[ -e "$dest" ]]; then
        ext="${base##*.}"; local stem="${base%.*}"
        dest="$DONE_ROOT/${stem}_$(date +%Y%m%d_%H%M%S).$ext"
    fi
    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf '%s' "$dest"
    else
        mv -f -- "$src" "$dest"; printf '%s' "$dest"
    fi
}

get_safe_sample_start() {   # <duration_seconds> -> hh:mm:ss
    local dur="$1"
    local def_secs; def_secs=$(( $(echo "$DEFAULT_START" | awk -F: '{print ($1*3600)+($2*60)+$3}') ))
    # integer compare on floored duration
    local d; d="${dur%.*}"; [[ -z "$d" || ! "$d" =~ ^[0-9]+$ ]] && d=0
    if (( d <= DEFAULT_LENGTH + 5 )); then printf '00:00:00'; return; fi
    if (( d <= def_secs + DEFAULT_LENGTH )); then
        local fb=$(( d - DEFAULT_LENGTH - 5 )); (( fb < 0 )) && fb=0
        printf '%02d:%02d:%02d' $(( fb/3600 )) $(( (fb%3600)/60 )) $(( fb%60 )); return
    fi
    printf '%s' "$DEFAULT_START"
}

write_meta_file() {   # <movie> <src> <out> <durSecs> <trackMetaPath>
    local movie="$1" src="$2" out="$3" dur="$4" tmeta="$5"
    ensure_dirs "$TXT_ROOT"
    local f; f="$TXT_ROOT/$(safe_name "$movie").txt"
    cat > "$f" <<EOF
MovieName      : $movie
Source         : $src
Output         : $out
Encoded        : $(date '+%Y-%m-%d %H:%M:%S')
Codec          : libx265
SourceProfile  : ${VP_PROFILE:-unknown}
CRF            : ${VP_CRF:-?}
Preset         : $DEFAULT_PRESET
PixFmt         : ${VP_PIXFMT:-?}
PsyParams      : $X265_PSY_PARAMS
ColorPrimaries : ${VP_PRIM:-?}
ColorTrc       : ${VP_TRC:-?}
Colorspace     : ${VP_SPACE:-?}
MasterDisplay  : ${VP_MASTER:-n/a}
MaxCLL         : ${VP_MAXCLL:-n/a}
Audio          : $DEFAULT_AUDIO
Duration       : $dur
Sample         : $DEFAULT_LENGTH sec
TrackMeta      : $tmeta
EOF
}

# ── Track metadata discovery (ports Get-TrackMetaCandidates) ──
# Prints candidate sidecar paths, one per line.
trackmeta_candidates() {   # <srcpath> <movie>
    local src="$1" movie="$2" base movieSafe dir n folderSafe
    base="$(basename -- "${src%.*}")"
    movieSafe="$(safe_name "$movie")"
    if ! [[ "$base" =~ ^[0-9]{5}$ ]]; then
        printf '%s\n' "$META_ROOT/$base.json" "$META_ROOT/$base.tracks.txt" "$TXT_ROOT/$base.tracks.txt"
    fi
    printf '%s\n' "$META_ROOT/$movieSafe.json" "$META_ROOT/$movieSafe.tracks.txt" "$TXT_ROOT/$movieSafe.tracks.txt"
    dir="$(dirname -- "$src")"
    while [[ -n "$dir" && "$dir" != "$INPUT_ROOT" && "$dir" != "/" ]]; do
        n="$(basename -- "$dir")"
        if [[ -n "$n" && "$n" != "STREAM" && "$n" != "BDMV" ]]; then
            folderSafe="$(safe_name "$n")"
            printf '%s\n' "$META_ROOT/$folderSafe.json" "$META_ROOT/$folderSafe.tracks.txt" "$TXT_ROOT/$folderSafe.tracks.txt"
        fi
        dir="$(dirname -- "$dir")"
    done
}

# Auto-locate a metadata sidecar. Prints its path, or nothing.
load_trackmetadata() {   # <srcpath> <movie>
    local src="$1" movie="$2" p
    while IFS= read -r p; do
        [[ -f "$p" ]] && { printf '%s' "$p"; return 0; }
    done < <(trackmeta_candidates "$src" "$movie" | awk '!seen[$0]++')

    # Fallback scan: match by movie name when the stream is 00004.m2ts.
    local movieSafe base mv f
    movieSafe="$(safe_name "$movie")"
    local list=()
    [[ -d "$META_ROOT" ]] && while IFS= read -r f; do list+=("$f"); done \
        < <(find "$META_ROOT" -maxdepth 1 -type f \( -iname '*.json' -o -iname '*.tracks.txt' \) -printf '%T@\t%p\n' 2>/dev/null | sort -rn | cut -f2- | head -n "$METADATA_SCAN_LIMIT")
    [[ -d "$TXT_ROOT" ]]  && while IFS= read -r f; do list+=("$f"); done \
        < <(find "$TXT_ROOT" -maxdepth 1 -type f -iname '*.tracks.txt' -printf '%T@\t%p\n' 2>/dev/null | sort -rn | cut -f2-)
    for f in "${list[@]}"; do
        base="$(basename -- "$f")"; base="${base%.json}"; base="${base%.tracks.txt}"
        if [[ "$(safe_name "$base")" == "$movieSafe" ]]; then printf '%s' "$f"; return 0; fi
        mv="$(br_py meta_movie "$f" 2>/dev/null)"
        [[ -n "$mv" && "$(safe_name "$mv")" == "$movieSafe" ]] && { printf '%s' "$f"; return 0; }
    done
    return 1
}

# Interactive: confirm auto-match or pick from a list.
# Sets global SELECTED_META to the chosen path; returns 1 if none chosen.
SELECTED_META=""
select_trackmetadata() {   # <srcpath> <movie>
    SELECTED_META=""
    local src="$1" movie="$2" auto confirm
    auto="$(load_trackmetadata "$src" "$movie" || true)"
    if [[ -n "$auto" ]]; then
        ui_blank
        printf '  %sMetadata auto-matched:%s\n' "$UI_CYN" "$UI_R"
        printf '  %sFile%s  %s\n' "$UI_DIM" "$UI_R" "$(basename -- "$auto")"
        local langs
        langs="$(br_py normalize_tsv "$auto" 2>/dev/null | awk -F'\t' '$1=="audio"{a=a (a?", ":"") $2} $1=="subtitle"{s=s (s?", ":"") $2} END{if(a)print "audio\t"a; if(s)print "subtitle\t"s}')"
        [[ -n "$langs" ]] && printf '%s\n' "$langs" | while IFS=$'\t' read -r k v; do
            printf '  %s%-5s%s  %s\n' "$UI_DIM" "${k^}" "$UI_R" "$v"; done
        ui_blank
        read -rp "  Use this metadata file? [Y/n]: " confirm
        if [[ ! "${confirm^^}" =~ ^N ]]; then SELECTED_META="$auto"; return 0; fi
        printf '  %sAuto-match rejected. Showing full list...%s\n' "$UI_YLW" "$UI_R"
    else
        ui_blank
        printf "  %sNo auto-match found for '%s'.%s\n" "$UI_YLW" "$movie" "$UI_R"
    fi

    local files=() f
    [[ -d "$META_ROOT" ]] && while IFS= read -r f; do files+=("$f"); done \
        < <(find "$META_ROOT" -maxdepth 1 -type f \( -iname '*.json' -o -iname '*.tracks.txt' \) 2>/dev/null | sort)
    [[ -d "$TXT_ROOT" ]]  && while IFS= read -r f; do files+=("$f"); done \
        < <(find "$TXT_ROOT" -maxdepth 1 -type f -iname '*.tracks.txt' 2>/dev/null | sort)

    if [[ "${#files[@]}" -eq 0 ]]; then
        printf '  %sNo JSON or .tracks.txt files found.%s\n' "$UI_YLW" "$UI_R"
        return 1
    fi
    ui_blank
    printf '  %sAvailable metadata files:%s\n' "$UI_MAG" "$UI_R"
    local i
    for i in "${!files[@]}"; do printf '    [%2d]  %s\n' "$((i+1))" "$(basename -- "${files[$i]}")"; done
    printf '    [ 0]  Skip - use ffprobe language fallback instead\n'
    ui_blank
    local sel; read -rp "  Select metadata number [0]: " sel
    sel="$(trim "$sel")"; [[ -z "$sel" ]] && sel=0
    [[ "$sel" =~ ^[0-9]+$ ]] || { printf '  %sInvalid input - skipping metadata.%s\n' "$UI_YLW" "$UI_R"; return 1; }
    (( sel == 0 )) && { printf '  %sSkipping metadata - will fall back to ffprobe.%s\n' "$UI_YLW" "$UI_R"; return 1; }
    (( sel < 1 || sel > ${#files[@]} )) && { printf '  %sOut of range - skipping.%s\n' "$UI_YLW" "$UI_R"; return 1; }
    SELECTED_META="${files[$((sel-1))]}"
}

# ── mkvmerge / mkvpropedit ────────────────────────────────────
output_layout() {   # <mkv> -> "audioCount subCount"
    local jf; jf="$(mktemp)"
    "$MKVMERGE" -J "$1" > "$jf" 2>/dev/null || { rm -f "$jf"; echo "0 0"; return; }
    br_py mkv_layout "$jf"; rm -f "$jf"
}

show_final_verification() {   # <mkv>
    local jf; jf="$(mktemp)"
    if "$MKVMERGE" -J "$1" > "$jf" 2>/dev/null; then
        ui_blank
        printf '  %sFinal MKV metadata verification:%s\n' "$UI_CYN" "$UI_R"
        br_py mkv_verify "$jf" | sed 's/^/    /'
    fi
    rm -f "$jf"
}

run_or_echo() {   # run a command, or print it in dry-run
    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf '  %s[DRY RUN]%s' "$UI_YLW" "$UI_R"; printf ' %q' "$@"; printf '\n'
        return 0
    fi
    "$@"
}

# Apply language/name/default/forced from a normalized sidecar via mkvpropedit.
invoke_mkv_language_remux() {   # <mkv> <normTSVfile> <outAudio> <outSub>
    local mkv="$1" norm="$2" outA="$3" outS="$4"
    local -a audio_lang audio_name audio_def
    local -a sub_lang sub_name sub_def sub_forced
    local kind lang name def forced
    while IFS=$'\t' read -r kind lang name def forced; do
        case "$kind" in
            audio)    audio_lang+=("$lang"); audio_name+=("$name"); audio_def+=("$def") ;;
            subtitle) sub_lang+=("$lang"); sub_name+=("$name"); sub_def+=("$def"); sub_forced+=("$forced") ;;
        esac
    done < "$norm"

    local -a args=("$mkv")
    local applied=0 i n
    n=$(( outA < ${#audio_lang[@]} ? outA : ${#audio_lang[@]} ))
    for (( i=0; i<n; i++ )); do
        args+=(--edit "track:a$((i+1))" --set "language=${audio_lang[$i]}")
        [[ -n "${audio_name[$i]}" ]] && args+=(--set "name=${audio_name[$i]}")
        args+=(--set "flag-default=${audio_def[$i]}")
        printf '    audio %d: lang=%s name=%s default=%s\n' "$((i+1))" "${audio_lang[$i]}" "${audio_name[$i]:--}" "${audio_def[$i]}"
        applied=$((applied+1))
    done
    n=$(( outS < ${#sub_lang[@]} ? outS : ${#sub_lang[@]} ))
    for (( i=0; i<n; i++ )); do
        args+=(--edit "track:s$((i+1))" --set "language=${sub_lang[$i]}")
        [[ -n "${sub_name[$i]}" ]] && args+=(--set "name=${sub_name[$i]}")
        args+=(--set "flag-default=${sub_def[$i]}" --set "flag-forced=${sub_forced[$i]}")
        printf '    sub   %d: lang=%s name=%s default=%s forced=%s\n' "$((i+1))" "${sub_lang[$i]}" "${sub_name[$i]:--}" "${sub_def[$i]}" "${sub_forced[$i]}"
        applied=$((applied+1))
    done

    if (( applied == 0 )); then
        printf '  %sNo tracks to tag.%s\n' "$UI_YLW" "$UI_R"; return 0
    fi
    printf '  %sWriting track metadata via mkvpropedit...%s\n' "$UI_CYN" "$UI_R"
    run_or_echo "$MKVPROPEDIT" "${args[@]}"
}

# ffprobe fallback: copy source stream languages onto the output.
get_stream_languages_from_source() {   # <output_mkv> <source>
    local out="$1" src="$2" jf; jf="$(mktemp)"
    "$FFPROBE" -v error -show_streams -of json "$src" > "$jf" 2>/dev/null
    local -a args=("$out"); local ai=1 si=1 kind lang applied=0
    while IFS=$'\t' read -r kind lang; do
        if [[ "$kind" == audio ]]; then
            args+=(--edit "track:a$ai" --set "language=$lang"); ai=$((ai+1)); applied=$((applied+1))
        elif [[ "$kind" == sub ]]; then
            args+=(--edit "track:s$si" --set "language=$lang"); si=$((si+1)); applied=$((applied+1))
        fi
    done < <(br_py source_langs "$jf")
    rm -f "$jf"
    if (( applied == 0 )); then
        printf '  %sNo source language tags found.%s\n' "$UI_YLW" "$UI_R"; return 0
    fi
    printf '  %sApplying source ffprobe language tags...%s\n' "$UI_CYN" "$UI_R"
    run_or_echo "$MKVPROPEDIT" "${args[@]}"
}

# Master metadata application. Sets global APPLIED_META to the chosen sidecar
# path (empty when the ffprobe fallback was used). UI prints freely to stdout.
APPLIED_META=""
apply_trackmetadata() {   # <output_mkv> <source> <movie>
    APPLIED_META=""
    local out="$1" src="$2" movie="$3" meta=""
    select_trackmetadata "$src" "$movie" && meta="$SELECTED_META"

    if [[ -z "$meta" ]]; then
        ui_blank
        printf '  %sNo sidecar metadata - falling back to ffprobe source language tags.%s\n' "$UI_YLW" "$UI_R"
        get_stream_languages_from_source "$out" "$src"
        show_final_verification "$out"
        return 0
    fi

    local norm; norm="$(mktemp)"
    br_py normalize_tsv "$meta" > "$norm"
    local layout outA outS; layout="$(output_layout "$out")"; outA="${layout%% *}"; outS="${layout##* }"
    local metaA metaS
    metaA="$(grep -c '^audio' "$norm" || true)"; metaS="$(grep -c '^subtitle' "$norm" || true)"

    # validation warnings
    local warns=()
    (( metaA == 0 )) && warns+=("Metadata has no audio tracks.")
    (( outA != metaA )) && warns+=("Audio count mismatch: output=$outA metadata=$metaA. Applying safe minimum.")
    (( outS != metaS )) && warns+=("Subtitle count mismatch: output=$outS metadata=$metaS. Applying safe minimum.")
    if [[ "${#warns[@]}" -gt 0 ]]; then
        ui_blank; printf '  %sMetadata validation warnings:%s\n' "$UI_YLW" "$UI_R"
        local w; for w in "${warns[@]}"; do printf '  %s-%s %s\n' "$UI_YLW" "$UI_R" "$w"; done
    fi

    ui_blank
    printf '  %sApplying track metadata...%s\n' "$UI_CYN" "$UI_R"
    printf '  %sMeta %s  %s\n' "$UI_DIM" "$UI_R" "$meta"
    printf '  %sAudio%s  output=%s / meta=%s\n' "$UI_DIM" "$UI_R" "$outA" "$metaA"
    printf '  %sSubs %s  output=%s / meta=%s\n' "$UI_DIM" "$UI_R" "$outS" "$metaS"
    invoke_mkv_language_remux "$out" "$norm" "$outA" "$outS"
    rm -f "$norm"

    printf '  %sTrack metadata applied.%s\n' "$UI_GRN" "$UI_R"
    show_final_verification "$out"
    APPLIED_META="$meta"
}

# ── Sample ────────────────────────────────────────────────────
create_sample_from_finished_mkv() {   # <finished_mkv> <movie>
    local mkv="$1" movie="$2"
    local dur start out
    dur="$(get_video_duration "$mkv")"
    start="$(get_safe_sample_start "$dur")"
    out="$(get_sample_output_path "$movie")"
    ui_blank
    printf '  %sCreating sample from finished MKV...%s\n' "$UI_CYN" "$UI_R"
    printf '  %sStart %s  %s   Length %ss\n' "$UI_DIM" "$UI_R" "$start" "$DEFAULT_LENGTH"
    run_or_echo "$FFMPEG" -hide_banner -y \
        -probesize "$M2TS_PROBESIZE" -analyzeduration "$M2TS_ANALYZEDUR" \
        -ss "$start" -i "$mkv" -t "$DEFAULT_LENGTH" \
        -map '0:v?' -map '0:a?' -map '0:s?' -c copy "$out"
    [[ "$DRY_RUN" -eq 1 ]] && return 0
    if [[ -s "$out" ]]; then
        printf '  %sSample complete.%s  %s\n' "$UI_GRN" "$UI_R" "$out"
    fi
}

# ── Encode ────────────────────────────────────────────────────
build_x265_params() {   # echoes the x265-params string for current VP_*
    local p="$X265_PSY_PARAMS"
    if [[ "$VP_ISHDR" -eq 1 ]]; then
        p+=":colorprim=$VP_PRIM:transfer=$VP_TRC:colormatrix=$VP_SPACE:hdr10=1:hdr10-opt=1"
        [[ -n "$VP_MASTER" ]] && p+=":master-display=$VP_MASTER"
        [[ -n "$VP_MAXCLL" ]] && p+=":max-cll=$VP_MAXCLL"
    fi
    printf '%s' "$p"
}

encode_file() {   # <srcpath> <movie>
    local src="$1" movie="$2"
    local out dur trackmeta=""
    out="$(get_output_path "$movie")"
    dur="$(get_video_duration "$src")"

    ui_blank
    printf '  %sProbing source video profile...%s\n' "$UI_CYN" "$UI_R"
    get_source_video_profile "$src"
    printf '  %sProfile%s  %s\n' "$UI_DIM" "$UI_R" "$VP_PROFILE"
    printf '  %sColor  %s  primaries=%s trc=%s space=%s\n' "$UI_DIM" "$UI_R" "$VP_PRIM" "$VP_TRC" "$VP_SPACE"
    [[ -n "$VP_MASTER" ]] && printf '  %sMaster %s  %s\n' "$UI_DIM" "$UI_R" "$VP_MASTER"
    [[ -n "$VP_MAXCLL" ]] && printf '  %sMaxCLL %s  %s\n' "$UI_DIM" "$UI_R" "$VP_MAXCLL"

    local x265; x265="$(build_x265_params)"
    ui_blank
    printf '  %sEncoding file...%s\n' "$UI_GRN" "$UI_R"
    printf '  %sInput  %s  %s\n' "$UI_DIM" "$UI_R" "$src"
    printf '  %sOutput %s  %s\n' "$UI_DIM" "$UI_R" "$out"
    printf '  %sCRF    %s  %s (%s)\n' "$UI_DIM" "$UI_R" "$VP_CRF" "$VP_PROFILE"

    run_or_echo "$FFMPEG" -hide_banner -y \
        -probesize "$M2TS_PROBESIZE" -analyzeduration "$M2TS_ANALYZEDUR" \
        -i "$src" \
        -map '0:v:0' -map '0:a?' -map '0:s?' \
        -c:v libx265 -preset "$DEFAULT_PRESET" -crf "$VP_CRF" -pix_fmt "$VP_PIXFMT" \
        -x265-params "$x265" \
        -color_primaries "$VP_PRIM" -color_trc "$VP_TRC" -colorspace "$VP_SPACE" \
        -c:a "$DEFAULT_AUDIO" -c:s copy \
        "$out"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf '  %s[DRY RUN] Skipping metadata/sample/move steps.%s\n' "$UI_YLW" "$UI_R"
        return 0
    fi

    [[ -s "$out" ]] || { core_error "ffmpeg produced no output: $out"; return 1; }

    apply_trackmetadata "$out" "$src" "$movie"; trackmeta="$APPLIED_META"
    create_sample_from_finished_mkv "$out" "$movie"
    local donepath; donepath="$(move_source_to_done "$src")"
    write_meta_file "$movie" "$src" "$out" "$dur" "$trackmeta"

    ui_blank
    printf '  %sEncode complete.%s\n' "$UI_GRN" "$UI_R"
    printf '  %sSaved  %s  %s\n' "$UI_DIM" "$UI_R" "$out"
    printf '  %sMoved  %s  %s\n' "$UI_DIM" "$UI_R" "$donepath"
}

encode_single() {
    get_m2ts_files
    ui_blank
    if [[ "${#SRC_FILES[@]}" -eq 0 ]]; then core_error "No .m2ts files found in $INPUT_ROOT"; pause_return; return; fi
    printf '  %sSource files:%s\n' "$UI_MAG" "$UI_R"
    local i sz
    for i in "${!SRC_FILES[@]}"; do
        sz="$(stat -c '%s' "${SRC_FILES[$i]}" 2>/dev/null || echo 0)"
        printf '  %2d) %s  [%s GB]\n' "$((i+1))" "$(basename -- "${SRC_FILES[$i]}")" "$(human_gb "$sz")"
    done
    ui_blank
    local pick; read -rp "Choose file number [1]: " pick
    pick="$(trim "$pick")"; [[ -z "$pick" ]] && pick=1
    [[ "$pick" =~ ^[0-9]+$ ]] || { core_error "Invalid selection."; pause_return; return; }
    (( pick < 1 || pick > ${#SRC_FILES[@]} )) && { core_error "Selection out of range."; pause_return; return; }
    local file="${SRC_FILES[$((pick-1))]}"
    local movie; movie="$(read_movie_name_with_year "$(default_movie_name "$file")")"
    encode_file "$file" "$movie" || core_error "Encode failed."
    pause_return
}

encode_all() {
    get_m2ts_files
    ui_blank
    if [[ "${#SRC_FILES[@]}" -eq 0 ]]; then core_error "No .m2ts files found in $INPUT_ROOT"; pause_return; return; fi
    printf '  %sAbout to encode %d file(s).%s\n' "$UI_YLW" "${#SRC_FILES[@]}" "$UI_R"
    local confirm; read -rp "Continue? (Y/N): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { pause_return; return; }
    local file movie
    for file in "${SRC_FILES[@]}"; do
        movie="$(default_movie_name "$file")"
        ui_blank
        printf '  %sNow encoding:%s %s\n' "$UI_CYN" "$UI_R" "$(basename -- "$file")"
        encode_file "$file" "$movie" || core_error "Failed on $(basename -- "$file")"
    done
    pause_return
}

repair_mkv_languages() {
    show_header
    printf '  %sRepair Language Tags%s\n' "$UI_CYN" "$UI_R"; ui_blank
    printf '  Applies sidecar metadata (JSON / .tracks.txt) when available.\n'
    printf '  No re-encode. Falls back to source ffprobe language tags.\n'; ui_blank

    local mkvs=() f
    [[ -d "$OUTPUT_ROOT" ]] && while IFS= read -r f; do mkvs+=("$f"); done \
        < <(find "$OUTPUT_ROOT" -maxdepth 1 -type f -iname '*.mkv' 2>/dev/null | sort)
    if [[ "${#mkvs[@]}" -eq 0 ]]; then printf '  %sNo MKV files in %s%s\n' "$UI_YLW" "$OUTPUT_ROOT" "$UI_R"; pause_return; return; fi

    printf '  %sAvailable MKV files:%s\n' "$UI_MAG" "$UI_R"
    local i; for i in "${!mkvs[@]}"; do printf '    [%d] %s\n' "$((i+1))" "$(basename -- "${mkvs[$i]}")"; done
    ui_blank
    local sel; read -rp "  Select MKV number: " sel
    [[ "$sel" =~ ^[0-9]+$ ]] && (( sel>=1 && sel<=${#mkvs[@]} )) || { printf '  %sInvalid selection.%s\n' "$UI_YLW" "$UI_R"; pause_return; return; }
    local target="${mkvs[$((sel-1))]}"

    local m2ts=() 
    [[ -d "$DONE_ROOT" ]] && while IFS= read -r f; do m2ts+=("$f"); done < <(find "$DONE_ROOT" -type f -iname '*.m2ts' 2>/dev/null | sort)
    [[ "${#m2ts[@]}" -eq 0 && -d "$INPUT_ROOT" ]] && while IFS= read -r f; do m2ts+=("$f"); done < <(find "$INPUT_ROOT" -type f -iname '*.m2ts' 2>/dev/null | sort)

    local sourcepath=""
    if [[ "${#m2ts[@]}" -gt 0 ]]; then
        ui_blank; printf '  %sAvailable source files:%s\n' "$UI_MAG" "$UI_R"
        for i in "${!m2ts[@]}"; do printf '    [%d] %s\n' "$((i+1))" "$(basename -- "${m2ts[$i]}")"; done
        printf '    [0] Enter path manually\n'; ui_blank
        local s2; read -rp "  Select source number: " s2
        [[ "$s2" =~ ^[0-9]+$ ]] && (( s2>=1 && s2<=${#m2ts[@]} )) && sourcepath="${m2ts[$((s2-1))]}"
    fi
    [[ -z "$sourcepath" ]] && { read -rp "  Enter full path to source .m2ts: " sourcepath; sourcepath="$(trim "$sourcepath")"; sourcepath="${sourcepath%\"}"; sourcepath="${sourcepath#\"}"; }
    [[ -f "$sourcepath" ]] || { printf '  %sSource file not found: %s%s\n' "$UI_RED" "$sourcepath" "$UI_R"; pause_return; return; }

    ui_blank
    printf '  %sMKV   %s  %s\n' "$UI_DIM" "$UI_R" "$target"
    printf '  %sSource%s  %s\n' "$UI_DIM" "$UI_R" "$sourcepath"
    local movie; movie="$(basename -- "${target%.*}")"
    apply_trackmetadata "$target" "$sourcepath" "$movie" || core_error "Repair failed."
    pause_return
}

show_config() {
    ui_blank
    ui_row "RootPath"     "$ROOT_PATH"       "$UI_GRY"
    ui_row "InputRoot"    "$INPUT_ROOT"      "$UI_GRY"
    ui_row "OutputRoot"   "$OUTPUT_ROOT"     "$UI_GRY"
    ui_row "DoneRoot"     "$DONE_ROOT"       "$UI_GRY"
    ui_row "SampleRoot"   "$SAMPLE_ROOT"     "$UI_GRY"
    ui_row "MetaRoot"     "$META_ROOT"       "$UI_GRY"
    ui_row "TxtRoot"      "$TXT_ROOT"        "$UI_GRY"
    ui_row "CRF (HDR)"    "$CRF_HDR"         "$UI_GRY"
    ui_row "CRF (SDR)"    "$CRF_SDR"         "$UI_GRY"
    ui_row "Preset"       "$DEFAULT_PRESET"  "$UI_GRY"
    ui_row "PixFmt"       "yuv420p10le"      "$UI_GRY"
    ui_row "PsyParams"    "$X265_PSY_PARAMS" "$UI_GRY"
    ui_row "Audio"        "$DEFAULT_AUDIO"   "$UI_GRY"
    ui_row "FFmpeg"       "$FFMPEG"          "$UI_GRY"
    ui_row "FFprobe"      "$FFPROBE"         "$UI_GRY"
    ui_row "MKVPropEdit"  "$MKVPROPEDIT"     "$UI_GRY"
    ui_row "MKVMerge"     "$MKVMERGE"        "$UI_GRY"
    ui_row "DryRun"       "$([[ "$DRY_RUN" -eq 1 ]] && echo Yes || echo No)" "$UI_GRY"
    pause_return
}

# ── Startup ───────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--dry-run) DRY_RUN=1 ;;
        -h|--help) printf 'Usage: %s [--dry-run]\n' "$(basename -- "$0")"; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; exit 1 ;;
    esac
    shift
done

require_python || exit 1
ensure_dependencies || exit 1
ensure_dirs "$ROOT_PATH" "$INPUT_ROOT" "$OUTPUT_ROOT" "$DONE_ROOT" "$SAMPLE_ROOT" "$SUBTITLE_ROOT" "$META_ROOT" "$TXT_ROOT"

while true; do
    show_header
    show_menu
    read -rp "Choose: " choice
    case "$(trim "$choice" | tr '[:lower:]' '[:upper:]')" in
        1) encode_all ;;
        2) encode_single ;;
        3) show_source_files ;;
        4) show_config ;;
        5) repair_mkv_languages ;;
        Q) ui_blank; printf '  %sGoodbye.%s\n' "$UI_CYN" "$UI_R"; ui_blank; exit 0 ;;
        *) core_error "Invalid choice."; sleep 1 ;;
    esac
done
