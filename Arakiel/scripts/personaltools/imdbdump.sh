#!/usr/bin/env bash
#--------------------------------------------
# file:    imdbdump.sh
# author:  Mike Redd  (bash port)
# version: 1.5
# desc:    OMDb / IMDb metadata lookup tool. Search by title
#          or IMDb ID. Display only.
#--------------------------------------------

# ── Load shared UI/core ───────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${LIB_DIR:-$HOME/lib}"
_src() { [[ -f "$1" ]] && source <(sed 's/\r$//' "$1"); }
if ! _src "$LIB_DIR/core.sh"; then
    echo "Missing core.sh in $LIB_DIR" >&2; exit 1
fi
# core.sh enables errexit/nounset; relax for the interactive menu loop.
set +e +u 2>/dev/null || true
set -o pipefail 2>/dev/null || true

SCRIPT_NAME="IMDbDump"
SCRIPT_VERSION="1.5"
SCRIPT_AUTHOR="Mike Redd"

# ── Load config ───────────────────────────────────────────────
for cp in "$LIB_DIR/minforc.sh" "$SCRIPT_DIR/minforc.sh" "$HOME/.config/minforc.sh"; do
    _src "$cp" && break
done
API_KEY="${OMDB_API_KEY:-}"

# ── Dependencies ──────────────────────────────────────────────
require_python() { command -v python3 >/dev/null 2>&1; }
find_http() {
    if command -v curl >/dev/null 2>&1; then HTTP=curl; return 0; fi
    if command -v wget >/dev/null 2>&1; then HTTP=wget; return 0; fi
    return 1
}

http_get() {   # <url> -> body on stdout
    if [[ "$HTTP" == curl ]]; then
        curl --silent --location --max-time 20 "$1"
    else
        wget -q -O - --timeout=20 "$1"
    fi
}

urlencode() { python3 -c 'import sys,urllib.parse as u; print(u.quote(sys.argv[1], safe=""))' "$1"; }

# OMDb JSON field reader: omdb_field <jsonfile> <Key>
omdb_field() {
    python3 -c 'import sys,json
try:
    d=json.load(open(sys.argv[1],encoding="utf-8"))
except Exception:
    print(""); sys.exit(0)
v=d.get(sys.argv[2],"")
print("" if v is None else str(v))' "$1" "$2"
}

show_header() {
    ui_header "$SCRIPT_NAME" "v$SCRIPT_VERSION  by $SCRIPT_AUTHOR"
    ui_blank
}

# ── OMDb fetch ────────────────────────────────────────────────
# Fetches into global $RESP (temp file path). Returns 1 on transport error.
RESP=""
fetch_omdb() {   # <title> <year> <imdbid>
    local title="$1" year="$2" imdbid="$3" url
    local base="http://www.omdbapi.com/"
    if [[ -n "$imdbid" ]]; then
        url="${base}?apikey=${API_KEY}&i=${imdbid}&plot=full"
    elif [[ -n "$title" ]]; then
        url="${base}?apikey=${API_KEY}&t=$(urlencode "$title")&plot=full"
        [[ -n "$year" ]] && url+="&y=${year}"
    else
        return 1
    fi
    RESP="$(mktemp)"
    if ! http_get "$url" > "$RESP" 2>/dev/null || [[ ! -s "$RESP" ]]; then
        ui_blank
        printf '  %sFailed to contact OMDb API.%s\n' "$UI_RED" "$UI_R"
        rm -f "$RESP"; RESP=""
        return 1
    fi
    return 0
}

show_movie_result() {   # <jsonfile>
    local j="$1"
    ui_section "Result"
    ui_row "Title"    "$(omdb_field "$j" Title)" "$UI_GRN"
    ui_row "Year"     "$(omdb_field "$j" Year)"
    ui_row "Rated"    "$(omdb_field "$j" Rated)"
    ui_row "Released" "$(omdb_field "$j" Released)"
    ui_row "Runtime"  "$(omdb_field "$j" Runtime)"
    ui_row "Genre"    "$(omdb_field "$j" Genre)"
    ui_row "Director" "$(omdb_field "$j" Director)"
    ui_row "Writer"   "$(omdb_field "$j" Writer)"
    ui_row "Actors"   "$(omdb_field "$j" Actors)"
    ui_row "Language" "$(omdb_field "$j" Language)"
    ui_row "Country"  "$(omdb_field "$j" Country)"
    ui_row "Awards"   "$(omdb_field "$j" Awards)"
    ui_row "IMDb"     "$(omdb_field "$j" imdbRating)" "$UI_CYN"
    ui_row "Votes"    "$(omdb_field "$j" imdbVotes)"
    ui_row "IMDb ID"  "$(omdb_field "$j" imdbID)" "$UI_CYN"
    ui_blank
    ui_section "Plot"
    printf '  %s%s%s\n' "$UI_WHT" "$(omdb_field "$j" Plot)" "$UI_R"
    ui_blank
}

handle_response() {   # <jsonfile>  -> shows result or error
    local j="$1"
    if [[ "$(omdb_field "$j" Response)" == "False" ]]; then
        ui_blank
        printf '  %s%s%s\n' "$UI_RED" "$(omdb_field "$j" Error)" "$UI_R"
        ui_blank
        return 1
    fi
    ui_blank
    show_movie_result "$j"
    return 0
}

search_by_name() {
    show_header
    ui_section "Search by Movie Name"
    printf '  %sEnter movie name: %s' "$UI_YLW" "$UI_R"
    local title; read -r title; title="$(printf '%s' "$title" | sed -e 's/^ *//' -e 's/ *$//')"
    [[ -z "$title" ]] && return
    printf '  %sEnter year (optional): %s' "$UI_CYN" "$UI_R"
    local year; read -r year; year="$(printf '%s' "$year" | sed -e 's/^ *//' -e 's/ *$//')"

    if fetch_omdb "$title" "$year" ""; then
        handle_response "$RESP"
        rm -f "$RESP"
    fi
    pause
}

search_by_id() {
    show_header
    ui_section "Search by IMDb ID"
    printf '  %sEnter IMDb ID (example: tt0082761): %s' "$UI_YLW" "$UI_R"
    local id; read -r id; id="$(printf '%s' "$id" | sed -e 's/^ *//' -e 's/ *$//')"
    [[ -z "$id" ]] && return

    if fetch_omdb "" "" "$id"; then
        handle_response "$RESP"
        rm -f "$RESP"
    fi
    pause
}

show_menu() {
    show_header
    ui_section "Lookup Menu"
    printf '  %s1.%s Search by movie name\n' "$UI_WHT" "$UI_R"
    printf '  %s2.%s Search by IMDb ID\n'    "$UI_WHT" "$UI_R"
    printf '  %sQ.%s Quit\n'                 "$UI_WHT" "$UI_R"
    ui_blank
}

# ── Startup checks ────────────────────────────────────────────
require_python || { echo "python3 is required." >&2; exit 1; }
if ! find_http; then
    show_header; ui_row "Status" "curl or wget required" "$UI_RED"; ui_blank; pause; exit 1
fi
if [[ -z "$API_KEY" || "$API_KEY" == "your_api_key_here" ]]; then
    show_header
    ui_row "Status" "OMDB API key missing" "$UI_RED"
    ui_blank
    printf '  %sGet a free key at: https://www.omdbapi.com/apikey.aspx%s\n' "$UI_CYN" "$UI_R"
    printf '  %sSet OMDB_API_KEY in minforc.sh%s\n' "$UI_YLW" "$UI_R"
    ui_blank
    pause
    exit 0
fi

# ── Main ──────────────────────────────────────────────────────
while true; do
    show_menu
    printf '  Select option: '
    read -r choice
    case "$(printf '%s' "$choice" | tr '[:lower:]' '[:upper:]' | tr -d '[:space:]')" in
        1) search_by_name ;;
        2) search_by_id ;;
        Q) break ;;
        *) ui_blank; printf '  %sInvalid selection.%s\n' "$UI_RED" "$UI_R"; ui_blank; pause ;;
    esac
done
