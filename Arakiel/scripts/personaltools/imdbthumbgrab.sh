#!/usr/bin/env bash
#--------------------------------------------
# file:    imdbthumbgrab.sh
# author:  Mike Redd  (bash port)
# version: 1.2
# desc:    Search OMDb by title/year or IMDb ID, download the
#          poster/thumbnail, and optionally open it in an image viewer.
#--------------------------------------------

# ── Load shared UI/core ───────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${LIB_DIR:-$HOME/lib}"
_src() { [[ -f "$1" ]] && source <(sed 's/\r$//' "$1"); }
if ! _src "$LIB_DIR/core.sh"; then
    echo "Missing core.sh in $LIB_DIR" >&2; exit 1
fi
set +e +u 2>/dev/null || true
set -o pipefail 2>/dev/null || true

SCRIPT_NAME="ImdbThumbGrab"
SCRIPT_VERSION="1.2"
SCRIPT_AUTHOR="Mike Redd"

# ── Args ──────────────────────────────────────────────────────
ARG_TITLE=""; ARG_YEAR=""; ARG_IMDBID=""; ARG_APIKEY=""; ARG_SHOW=0; ARG_HELP=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        -t|--title)  ARG_TITLE="$2";  shift 2 ;;
        -y|--year)   ARG_YEAR="$2";   shift 2 ;;
        -i|--imdbid) ARG_IMDBID="$2"; shift 2 ;;
        -k|--apikey) ARG_APIKEY="$2"; shift 2 ;;
        -s|--show)   ARG_SHOW=1;      shift ;;
        -h|--help)   ARG_HELP=1;      shift ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; exit 1 ;;
    esac
done

# ── Load config ───────────────────────────────────────────────
for cp in "$LIB_DIR/minforc.sh" "$SCRIPT_DIR/minforc.sh" "$HOME/.config/minforc.sh"; do
    _src "$cp" && break
done
API_KEY="${ARG_APIKEY:-${OMDB_API_KEY:-}}"
POSTER_DIR="${MINFO_POSTERDIR:-$HOME/Rip/meta/posters}"
mkdir -p -- "$POSTER_DIR"

# ── Dependencies ──────────────────────────────────────────────
require_python() { command -v python3 >/dev/null 2>&1; }
find_http() {
    if command -v curl >/dev/null 2>&1; then HTTP=curl; return 0; fi
    if command -v wget >/dev/null 2>&1; then HTTP=wget; return 0; fi
    return 1
}
api_get() { # <url> -> body
    if [[ "$HTTP" == curl ]]; then curl --silent --max-time 15 "$1"
    else wget -q -O - --timeout=15 "$1"; fi
}
download() { # <url> <outfile> -> rc
    if [[ "$HTTP" == curl ]]; then curl --silent --location --max-time 30 --output "$2" "$1"
    else wget -q -O "$2" --timeout=30 "$1"; fi
}
urlencode() { python3 -c 'import sys,urllib.parse as u; print(u.quote(sys.argv[1], safe=""))' "$1"; }
omdb_field() {
    python3 -c 'import sys,json
try: d=json.load(open(sys.argv[1],encoding="utf-8"))
except Exception: print(""); sys.exit(0)
v=d.get(sys.argv[2],"")
print("" if v is None else str(v))' "$1" "$2"
}

# ── UI ────────────────────────────────────────────────────────
show_header() {
    ui_header "$SCRIPT_NAME" "v$SCRIPT_VERSION  by $SCRIPT_AUTHOR"
    ui_row "User"      "$(id -un)@$(hostname)"
    ui_row "PosterDir" "$POSTER_DIR" "$UI_GRY"
    ui_blank
}

show_usage() {
    show_header
    ui_section "Usage"
    printf '  %simdbthumbgrab.sh --title "movie title"%s\n' "$UI_WHT" "$UI_R"
    printf '  %simdbthumbgrab.sh --title "Blade Runner" --year 1982%s\n' "$UI_WHT" "$UI_R"
    printf '  %simdbthumbgrab.sh --imdbid tt0083658%s\n' "$UI_WHT" "$UI_R"
    ui_blank
    ui_section "Parameters"
    printf '  %s--title    Movie or show title%s\n'        "$UI_GRY" "$UI_R"
    printf '  %s--year     Optional year filter%s\n'       "$UI_GRY" "$UI_R"
    printf '  %s--imdbid   Lookup directly by IMDb ID%s\n' "$UI_GRY" "$UI_R"
    printf '  %s--apikey   OMDb API key%s\n'               "$UI_GRY" "$UI_R"
    printf '  %s--show     Open the poster after download%s\n' "$UI_GRY" "$UI_R"
    ui_blank
    pause_return
}

read_input() {  # <prompt> -> trimmed value on stdout
    printf '  %s%s%s%s: %s' "$UI_CYN" "$1" "$UI_R" "$UI_DIM" "$UI_R" >&2
    local v; read -r v
    printf '%s' "$(printf '%s' "$v" | sed -e 's/^ *//' -e 's/ *$//')"
}

safe_poster_name() {  # <title> <year> <imdbid>
    local title="$1" year="$2" id="$3" base
    base="$(printf '%s' "$title" | sed -e 's/^ *//' -e 's/ *$//')"
    [[ -n "$year" && "$year" != "N/A" ]] && base="$base [$year]"
    base="$(printf '%s' "$base" | sed -e 's/[<>:"/\\|?*]//g' -e 's/ *$//')"
    if [[ -z "$base" ]]; then
        if [[ -n "$id" && "$id" != "N/A" ]]; then base="$id"; else base="poster"; fi
    fi
    printf '%s' "$base"
}

# Open an image with whatever viewer exists (best-effort, non-fatal).
show_poster() {  # <imagepath>
    local img="$1" v
    [[ -f "$img" ]] || { printf '  Image not found: %s\n' "$img"; return; }
    for v in xdg-open eog feh display gpicview gwenview open; do
        if command -v "$v" >/dev/null 2>&1; then
            printf '  %sOpening preview with %s...%s\n' "$UI_DIM" "$v" "$UI_R"
            nohup "$v" "$img" >/dev/null 2>&1 &
            return
        fi
    done
    printf '  %sNo image viewer found; saved to: %s%s\n' "$UI_YLW" "$img" "$UI_R"
}

# ── Lookup ────────────────────────────────────────────────────
invoke_lookup() {  # <title> <year> <imdbid> <show:0|1>
    local title="$1" year="$2" id="$3" doshow="$4" url base resp

    show_header
    ui_row "Mode" "$([[ -n "$id" ]] && echo 'IMDb ID lookup' || echo 'Title lookup')" "$UI_CYN"
    [[ -n "$title" ]] && ui_row "Title"   "$title" "$UI_GRY"
    [[ -n "$year"  ]] && ui_row "Year"    "$year"  "$UI_GRY"
    [[ -n "$id"    ]] && ui_row "IMDb ID" "$id"    "$UI_GRY"
    ui_blank

    local b="http://www.omdbapi.com/"
    if [[ -n "$id" ]]; then
        url="${b}?apikey=${API_KEY}&i=${id}&plot=short"
    else
        url="${b}?apikey=${API_KEY}&t=$(urlencode "$title")&plot=short"
        [[ -n "$year" ]] && url+="&y=${year}"
    fi

    resp="$(mktemp)"
    if ! api_get "$url" > "$resp" 2>/dev/null || [[ ! -s "$resp" ]]; then
        printf '  %scurl request failed.%s\n' "$UI_RED" "$UI_R"; ui_blank; rm -f "$resp"; pause_return; return
    fi
    if [[ "$(omdb_field "$resp" Response)" != "True" ]]; then
        printf '  %sOMDb Error: %s%s\n' "$UI_RED" "$(omdb_field "$resp" Error)" "$UI_R"; ui_blank; rm -f "$resp"; pause_return; return
    fi

    local mTitle mYear mType mId mPoster mRated
    mTitle="$(omdb_field "$resp" Title)";  [[ -z "$mTitle" ]] && mTitle="N/A"
    mYear="$(omdb_field "$resp" Year)";    [[ -z "$mYear" ]] && mYear="N/A"
    mType="$(omdb_field "$resp" Type)";    [[ -z "$mType" ]] && mType="N/A"
    mId="$(omdb_field "$resp" imdbID)";    [[ -z "$mId" ]] && mId="N/A"
    mPoster="$(omdb_field "$resp" Poster)";[[ -z "$mPoster" ]] && mPoster="N/A"
    mRated="$(omdb_field "$resp" imdbRating)"; [[ -z "$mRated" ]] && mRated="N/A"
    rm -f "$resp"

    ui_section "$mTitle ($mYear)"
    ui_row "Type"        "$mType"
    ui_row "IMDb ID"     "$mId"
    ui_row "IMDb Rating" "$mRated"
    ui_row "Poster URL"  "$mPoster" "$UI_GRY"
    ui_blank

    if [[ -z "$mPoster" || "$mPoster" == "N/A" ]]; then
        printf '  %sNo poster was returned by OMDb.%s\n' "$UI_RED" "$UI_R"; ui_blank; pause_return; return
    fi

    local base_name out
    base_name="$(safe_poster_name "$mTitle" "$mYear" "$mId")"
    out="$POSTER_DIR/$base_name.jpg"

    printf '  %sDownloading poster...%s\n' "$UI_CYN" "$UI_R"
    if ! download "$mPoster" "$out" || [[ ! -s "$out" ]]; then
        rm -f "$out"
        ui_blank; printf '  %sPoster download failed.%s\n' "$UI_RED" "$UI_R"; ui_blank; pause_return; return
    fi

    local kb; kb="$(awk "BEGIN{printf \"%.1f\", $(stat -c '%s' "$out")/1024}")"
    ui_blank
    printf '  %sPoster saved: %s  (%s KB)%s\n' "$UI_GRN" "$out" "$kb" "$UI_R"
    ui_blank

    [[ "$doshow" -eq 1 ]] && show_poster "$out"
    pause_return
}

interactive_mode() {
    while true; do
        show_header
        ui_section "Search Input"
        printf '  %sLeave year blank if unknown.%s\n' "$UI_GRY" "$UI_R"
        printf '  %sEnter Q at any prompt to return.%s\n' "$UI_GRY" "$UI_R"
        ui_blank

        local first; first="$(read_input "Movie title or IMDb ID")"
        [[ "$first" =~ ^[Qq]$ ]] && return
        if [[ -z "$first" ]]; then
            printf '  %sA title or IMDb ID is required.%s\n' "$UI_RED" "$UI_R"; ui_blank; pause_return; continue
        fi

        local title="" year="" id=""
        if [[ "$first" =~ ^tt[0-9]{6,10}$ ]]; then
            id="$first"
        else
            title="$first"
            year="$(read_input "Year (optional)")"
            [[ "$year" =~ ^[Qq]$ ]] && return
        fi

        local preview doshow=0
        preview="$(read_input "Show preview? (Y/N)")"
        [[ "$preview" =~ ^[Qq]$ ]] && return
        [[ "$preview" =~ ^[Yy]([Ee][Ss])?$ ]] && doshow=1

        invoke_lookup "$title" "$year" "$id" "$doshow"
        return
    done
}

# ── Startup ───────────────────────────────────────────────────
require_python || { echo "python3 is required." >&2; exit 1; }
find_http || { show_header; ui_row "http" "curl or wget required" "$UI_RED"; ui_blank; pause_return; exit 1; }

[[ "$ARG_HELP" -eq 1 ]] && { show_usage; exit 0; }

if [[ -z "$API_KEY" || "$API_KEY" == "your_api_key_here" ]]; then
    show_header
    ui_row "Status" "OMDB_API_KEY not set" "$UI_RED"
    ui_blank
    printf '  %sGet a free key at: https://www.omdbapi.com/apikey.aspx%s\n' "$UI_CYN" "$UI_R"
    printf '  %sSet it in minforc.sh or pass --apikey yourkey%s\n' "$UI_YLW" "$UI_R"
    ui_blank
    pause_return
    exit 0
fi

# ── Main ──────────────────────────────────────────────────────
if [[ -z "$ARG_TITLE" && -z "$ARG_IMDBID" ]]; then
    interactive_mode
else
    invoke_lookup "$ARG_TITLE" "$ARG_YEAR" "$ARG_IMDBID" "$ARG_SHOW"
fi
