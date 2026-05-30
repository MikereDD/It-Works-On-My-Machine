#!/usr/bin/env bash
#--------------------------------------------
# file:    minfocreate.sh
# author:  Mike Redd  (bash port)
# version: 1.7
# desc:    Create NFO, HTML, and poster data for a video file
#          using OMDb and the MediaInfo CLI.
#--------------------------------------------

# ── Load shared UI/core ───────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${LIB_DIR:-$SCRIPT_DIR/../lib}"
_src() { [[ -f "$1" ]] && source <(sed 's/\r$//' "$1"); }
if ! _src "$LIB_DIR/core.sh"; then
    echo "Missing core.sh in $LIB_DIR" >&2; exit 1
fi
set +e +u 2>/dev/null || true
set -o pipefail 2>/dev/null || true

SCRIPT_NAME="MiNfoCreate"
SCRIPT_VERSION="1.7"
SCRIPT_AUTHOR="Mike Redd"

# ── Args ──────────────────────────────────────────────────────
ARG_VIDEODIR=""; ARG_VIDEOFILE=""; ARG_APIKEY=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--videodir)  ARG_VIDEODIR="$2";  shift 2 ;;
        -f|--videofile) ARG_VIDEOFILE="$2"; shift 2 ;;
        -k|--apikey)    ARG_APIKEY="$2";    shift 2 ;;
        -h|--help) printf 'Usage: %s [--videodir DIR] [--videofile FILE] [--apikey KEY]\n' "$(basename -- "$0")"; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; exit 1 ;;
    esac
    shift 2>/dev/null || true
done

# ── Load config ───────────────────────────────────────────────
for cp in "$LIB_DIR/minforc.sh" "$SCRIPT_DIR/minforc.sh" "$HOME/.config/minforc.sh"; do
    _src "$cp" && break
done
API_KEY="${ARG_APIKEY:-${OMDB_API_KEY:-}}"
VIDEO_DIR="${ARG_VIDEODIR:-${MINFO_VIDEODIR:-$HOME/Rip/done}}"
NFO_DIR="${MINFO_NFODIR:-$HOME/Rip/nfo}"
POSTER_DIR="${MINFO_POSTERDIR:-$HOME/Rip/meta/posters}"
mkdir -p -- "$NFO_DIR" "$POSTER_DIR"

# ── Dependencies ──────────────────────────────────────────────
require_python() { command -v python3 >/dev/null 2>&1; }
find_http() {
    if command -v curl >/dev/null 2>&1; then HTTP=curl; return 0; fi
    if command -v wget >/dev/null 2>&1; then HTTP=wget; return 0; fi
    return 1
}
api_get()  { if [[ "$HTTP" == curl ]]; then curl --silent --max-time 15 "$1"; else wget -q -O - --timeout=15 "$1"; fi; }
download() { if [[ "$HTTP" == curl ]]; then curl --silent --location --max-time 30 --output "$2" "$1"; else wget -q -O "$2" --timeout=30 "$1"; fi; }
urlencode(){ python3 -c 'import sys,urllib.parse as u; print(u.quote(sys.argv[1], safe=""))' "$1"; }
omdb_field(){ python3 -c 'import sys,json
try: d=json.load(open(sys.argv[1],encoding="utf-8"))
except Exception: print(""); sys.exit(0)
v=d.get(sys.argv[2],"")
print("" if v is None else str(v))' "$1" "$2"; }
omdb_rt(){ python3 -c 'import sys,json
try: d=json.load(open(sys.argv[1],encoding="utf-8"))
except Exception: print(""); sys.exit(0)
for r in (d.get("Ratings") or []):
    if r.get("Source")=="Rotten Tomatoes": print(r.get("Value","")); break' "$1"; }

# MediaInfo JSON -> formatted plain-text block (port of Format-MediaInfoFromJson)
format_mediainfo() {  # <mediainfo.json>
    python3 - "$1" <<'PYEOF'
import sys, json, re
try:
    obj = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    print("No MediaInfo available."); sys.exit(0)
tracks = (((obj or {}).get("media") or {}).get("track")) or []
if not tracks:
    print("No MediaInfo available."); sys.exit(0)
if isinstance(tracks, dict): tracks = [tracks]

def first(t):
    for x in tracks:
        if x.get("@type") == t: return x
    return None
def sval(track, names):
    if not track: return None
    for n in names:
        v = track.get(n)
        if v is not None and str(v).strip(): return str(v)
    return None
def resolution(v):
    if not v: return None
    w = sval(v, ["Width","Width_String"]); h = sval(v, ["Height","Height_String"])
    if w and h:
        w = re.sub(r"\s*pixels?","",w).strip(); h = re.sub(r"\s*pixels?","",h).strip()
        return f"{w} x {h}"
    return None

L = []
def sec(t): L.append(f"[ {t} ]"); L.append("-"*80)
def row(label, val):
    if val is None or not str(val).strip() or str(val) == "N/A": return
    L.append("{0:<24} : {1}".format(label, val))

g = first("General"); v = first("Video"); a = first("Audio"); x = first("Text")

if g:
    sec("GENERAL")
    row("Complete Name",       sval(g, ["CompleteName","CompleteName_String"]))
    row("Format",              sval(g, ["Format"]))
    row("Format Version",      sval(g, ["Format_Version"]))
    row("File Size",           sval(g, ["FileSize_String4","FileSize_String3","FileSize_String2","FileSize_String"]))
    row("Duration",            sval(g, ["Duration_String3","Duration_String2","Duration_String"]))
    row("Overall Bit Rate",    sval(g, ["OverallBitRate_String"]))
    row("Frame Rate",          sval(g, ["FrameRate_String"]))
    row("Writing Application", sval(g, ["WritingApplication"]))
    row("Writing Library",     sval(g, ["WritingLibrary"]))
    L.append("")
if v:
    sec("VIDEO")
    row("Format",             sval(v, ["Format"]))
    row("Profile",            sval(v, ["Format_Profile"]))
    row("Codec ID",           sval(v, ["CodecID"]))
    row("Duration",           sval(v, ["Duration_String3","Duration_String2","Duration_String"]))
    row("Resolution",         resolution(v))
    row("Aspect Ratio",       sval(v, ["DisplayAspectRatio_String","DisplayAspectRatio"]))
    row("Frame Rate",         sval(v, ["FrameRate_String","FrameRate"]))
    row("Color Space",        sval(v, ["ColorSpace"]))
    row("Chroma Subsampling", sval(v, ["ChromaSubsampling_String","ChromaSubsampling"]))
    row("Bit Depth",          sval(v, ["BitDepth_String","BitDepth"]))
    row("Scan Type",          sval(v, ["ScanType"]))
    row("Scan Order",         sval(v, ["ScanOrder"]))
    row("Writing Library",    sval(v, ["WritingLibrary"]))
    L.append("")
if a:
    sec("AUDIO")
    row("Format",           sval(a, ["Format"]))
    row("Commercial Name",  sval(a, ["Format_Commercial_IfAny"]))
    row("Duration",         sval(a, ["Duration_String3","Duration_String2","Duration_String"]))
    row("Channels",         sval(a, ["Channel_s_","Channel_s__String","Channels"]))
    row("Channel Layout",   sval(a, ["ChannelLayout"]))
    row("Sampling Rate",    sval(a, ["SamplingRate_String","SamplingRate"]))
    row("Bit Depth",        sval(a, ["BitDepth_String","BitDepth"]))
    row("Compression Mode", sval(a, ["Compression_Mode"]))
    row("Language",         sval(a, ["Language"]))
    L.append("")
if x:
    sec("TEXT")
    row("Format",   sval(x, ["Format"]))
    row("Codec ID", sval(x, ["CodecID"]))
    row("Duration", sval(x, ["Duration_String3","Duration_String2","Duration_String"]))
    row("Language", sval(x, ["Language"]))
    row("Default",  sval(x, ["Default"]))
    row("Forced",   sval(x, ["Forced"]))
    L.append("")

enc = (sval(v, ["Encoded_Library_Settings"]) if v else None) or (sval(g, ["Encoded_Library_Settings"]) if g else None)
if enc:
    sec("ENCODING SETTINGS")
    for part in re.split(r"\s*/\s*", enc):
        item = part.strip()
        if not item: continue
        if "=" in item:
            k, val = item.split("=", 1)
            L.append("{0:<24} : {1}".format(k.strip(), val.strip()))
        else:
            L.append("{0:<24} : enabled".format(item))
    L.append("")

print("\n".join(L).strip())
PYEOF
}

# ── UI ────────────────────────────────────────────────────────
show_header() {
    ui_header "$SCRIPT_NAME" "v$SCRIPT_VERSION  by $SCRIPT_AUTHOR"
    ui_row "User"      "$(id -un)@$(hostname)"
    ui_row "VideoDir"  "$VIDEO_DIR"  "$UI_GRY"
    ui_row "NfoDir"    "$NFO_DIR"    "$UI_GRY"
    ui_row "PosterDir" "$POSTER_DIR" "$UI_GRY"
    ui_blank
}

show_result_table() {  # <dir>
    local d="$1"
    [[ -d "$d" ]] || return
    ui_blank; ui_divider
    local f sz
    for f in "$d"/*; do
        [[ -e "$f" ]] || continue
        if [[ -d "$f" ]]; then sz="<DIR>"
        else
            local b; b="$(stat -c '%s' "$f" 2>/dev/null || echo 0)"
            if   (( b >= 1048576 )); then sz="$(awk "BEGIN{printf \"%.1f MB\", $b/1048576}")"
            elif (( b >= 1024 ));    then sz="$(awk "BEGIN{printf \"%.1f KB\", $b/1024}")"
            else sz="$b B"; fi
        fi
        printf '  %-40s %12s  %s\n' "$(basename -- "$f")" "$sz" "$(date -r "$f" '+%Y-%m-%d %H:%M' 2>/dev/null)"
    done
    ui_blank
}

# ── Startup ───────────────────────────────────────────────────
require_python || { echo "python3 is required." >&2; exit 1; }
if [[ -z "$API_KEY" || "$API_KEY" == "your_api_key_here" ]]; then
    show_header
    ui_row "Status" "OMDB_API_KEY not set" "$UI_RED"
    ui_blank
    printf '  %sGet a free key at: https://www.omdbapi.com/apikey.aspx%s\n' "$UI_CYN" "$UI_R"
    printf '  %sThen set it in minforc.sh%s\n' "$UI_YLW" "$UI_R"
    ui_blank
    pause_return
    exit 0
fi

HAVE_HTTP=1; find_http || HAVE_HTTP=0
MEDIAINFO="$(command -v mediainfo 2>/dev/null)"

show_header
ui_row "curl/wget" "$([[ "$HAVE_HTTP" -eq 1 ]] && echo found || echo 'not found')" "$([[ "$HAVE_HTTP" -eq 1 ]] && echo "$UI_GRN" || echo "$UI_RED")"
ui_row "MediaInfo" "$([[ -n "$MEDIAINFO" ]] && echo found || echo 'not found')" "$([[ -n "$MEDIAINFO" ]] && echo "$UI_GRN" || echo "$UI_YLW")"
ui_blank

# ── Validate video dir ────────────────────────────────────────
if [[ ! -d "$VIDEO_DIR" ]]; then
    printf '  %sVideo directory not found: %s%s\n' "$UI_RED" "$VIDEO_DIR" "$UI_R"
    printf '  %sPass --videodir to specify a different path.%s\n' "$UI_YLW" "$UI_R"
    ui_blank; pause_return; exit 1
fi

# ── Find source video ─────────────────────────────────────────
FOUND_FILE=""; VIDEO_FILE="$ARG_VIDEOFILE"
if [[ -n "$VIDEO_FILE" ]]; then
    FOUND_FILE="$VIDEO_DIR/$VIDEO_FILE"
    if [[ ! -f "$FOUND_FILE" ]]; then
        printf '  %sFile not found: %s%s\n' "$UI_RED" "$FOUND_FILE" "$UI_R"; ui_blank; pause_return; exit 1
    fi
else
    for ext in mkv mp4 avi m2ts mov wmv; do
        for f in "$VIDEO_DIR"/*."$ext"; do
            [[ -f "$f" ]] || continue
            FOUND_FILE="$f"; VIDEO_FILE="$(basename -- "$f")"; break 2
        done
    done
    if [[ -z "$FOUND_FILE" ]]; then
        printf '  %sNo video file found in %s%s\n' "$UI_RED" "$VIDEO_DIR" "$UI_R"
        printf '  %sPass --videofile filename.mkv to specify one.%s\n' "$UI_YLW" "$UI_R"
        ui_blank; pause_return; exit 1
    fi
fi
ui_row "Found File" "$VIDEO_FILE" "$UI_GRN"
ui_blank

# ── Output title ──────────────────────────────────────────────
default_title="$(basename -- "${VIDEO_FILE%.*}" | sed -e 's/[._]/ /g')"
printf '  %sName your NFO/HTML files:%s\n' "$UI_YLW" "$UI_R"
printf '  %sDefault: %s%s\n' "$UI_GRN" "$default_title" "$UI_R"
ui_blank
printf '  %sKeep default? (y/n): %s' "$UI_YLW" "$UI_R"
read -r keep
if [[ "$keep" =~ ^[Yy]$ ]]; then
    title="$default_title"
else
    printf '  %sEnter title: %s' "$UI_CYN" "$UI_R"
    read -r title
    [[ -z "$(printf '%s' "$title" | tr -d '[:space:]')" ]] && title="$default_title"
fi
base_name="$(printf '%s' "$title" | sed -e 's/^ *//' -e 's/ *$//' -e 's/[<>:"/\\|?*]//g')"
[[ -z "$base_name" ]] && base_name="$(printf '%s' "$default_title" | sed -e 's/^ *//' -e 's/ *$//')"
ui_row "Base Name" "$base_name" "$UI_CYN"
ui_blank

# ── OMDb lookup ───────────────────────────────────────────────
ui_section "OMDb Lookup"
printf '  %sEnter search title or IMDb ID (example: tt0083907)%s\n' "$UI_CYN" "$UI_R"
printf '  Search: '; read -r search_input
printf '  Year (optional): '; read -r search_year

base_url="http://www.omdbapi.com/"
if [[ "$search_input" =~ ^tt[0-9]+ ]]; then
    api_url="${base_url}?apikey=${API_KEY}&i=${search_input}&plot=full"
else
    api_url="${base_url}?apikey=${API_KEY}&t=$(urlencode "$search_input")&plot=full"
    [[ -n "$search_year" ]] && api_url+="&y=${search_year}"
fi

ui_blank
printf '  %sFetching movie data...%s\n' "$UI_CYN" "$UI_R"

OMDB_OK=0
RESP="$(mktemp)"
if [[ "$HAVE_HTTP" -eq 1 ]] && api_get "$api_url" > "$RESP" 2>/dev/null && [[ -s "$RESP" ]]; then
    if [[ "$(omdb_field "$RESP" Response)" == "True" ]]; then
        OMDB_OK=1
        mTitle="$(omdb_field "$RESP" Title)";    : "${mTitle:=N/A}"
        mYear="$(omdb_field "$RESP" Year)";      : "${mYear:=N/A}"
        mRated="$(omdb_field "$RESP" Rated)";    : "${mRated:=N/A}"
        mRel="$(omdb_field "$RESP" Released)";   : "${mRel:=N/A}"
        mRuntime="$(omdb_field "$RESP" Runtime)";: "${mRuntime:=N/A}"
        mGenre="$(omdb_field "$RESP" Genre)";    : "${mGenre:=N/A}"
        mDir="$(omdb_field "$RESP" Director)";   : "${mDir:=N/A}"
        mWriter="$(omdb_field "$RESP" Writer)";  : "${mWriter:=N/A}"
        mCast="$(omdb_field "$RESP" Actors)";    : "${mCast:=N/A}"
        mPlot="$(omdb_field "$RESP" Plot)";      : "${mPlot:=N/A}"
        mLang="$(omdb_field "$RESP" Language)";  : "${mLang:=N/A}"
        mCountry="$(omdb_field "$RESP" Country)";: "${mCountry:=N/A}"
        mAwards="$(omdb_field "$RESP" Awards)";  : "${mAwards:=N/A}"
        mImdbId="$(omdb_field "$RESP" imdbID)";  : "${mImdbId:=N/A}"
        mRating="$(omdb_field "$RESP" imdbRating)"; : "${mRating:=N/A}"
        mVotes="$(omdb_field "$RESP" imdbVotes)";: "${mVotes:=N/A}"
        mMeta="$(omdb_field "$RESP" Metascore)"; : "${mMeta:=N/A}"
        mPoster="$(omdb_field "$RESP" Poster)";  : "${mPoster:=N/A}"
        mRT="$(omdb_rt "$RESP")";                : "${mRT:=N/A}"
        printf '  %sFound: %s (%s)%s\n' "$UI_GRN" "$mTitle" "$mYear" "$UI_R"
    else
        printf '  %sOMDb Error: %s%s\n' "$UI_RED" "$(omdb_field "$RESP" Error)" "$UI_R"
        printf '  %sContinuing with MediaInfo only...%s\n' "$UI_YLW" "$UI_R"
    fi
else
    printf '  %sAPI call failed.%s\n' "$UI_RED" "$UI_R"
    printf '  %sContinuing with MediaInfo only...%s\n' "$UI_YLW" "$UI_R"
fi
rm -f "$RESP"

# ── MediaInfo ─────────────────────────────────────────────────
mediainfo_text=""
if [[ -n "$MEDIAINFO" ]]; then
    ui_blank
    printf '  %sRunning MediaInfo on %s...%s\n' "$UI_CYN" "$VIDEO_FILE" "$UI_R"
    mi_json="$(mktemp)"
    if "$MEDIAINFO" --Output=JSON "$FOUND_FILE" > "$mi_json" 2>/dev/null && [[ -s "$mi_json" ]]; then
        mediainfo_text="$(format_mediainfo "$mi_json")"
    else
        mediainfo_text="MediaInfo parsing failed."
    fi
    rm -f "$mi_json"
else
    mediainfo_text="MediaInfo CLI not installed. Install with your package manager (e.g. apt install mediainfo)."
fi

# ── Output folder ─────────────────────────────────────────────
out_dir="$NFO_DIR/$base_name"
mkdir -p -- "$out_dir"
timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

# ── Write NFO ─────────────────────────────────────────────────
nfo_file="$out_dir/$base_name.nfo"
{
    printf '================================================================================\n'
    printf '  %s\n' "$title"
    printf '================================================================================\n'
    printf '  Generated by %s v%s\n' "$SCRIPT_NAME" "$SCRIPT_VERSION"
    printf '  by %s\n' "$SCRIPT_AUTHOR"
    printf '  Date: %s\n' "$timestamp"
    printf '================================================================================\n\n'
    if [[ "$OMDB_OK" -eq 1 ]]; then
        printf '[ MOVIE INFO ]\n'
        printf -- '--------------------------------------------------------------------------------\n'
        printf '  Title     : %s\n'  "$mTitle"
        printf '  Year      : %s\n'  "$mYear"
        printf '  Rated     : %s\n'  "$mRated"
        printf '  Released  : %s\n'  "$mRel"
        printf '  Runtime   : %s\n'  "$mRuntime"
        printf '  Genre     : %s\n'  "$mGenre"
        printf '  Director  : %s\n'  "$mDir"
        printf '  Writer    : %s\n'  "$mWriter"
        printf '  Cast      : %s\n'  "$mCast"
        printf '  Language  : %s\n'  "$mLang"
        printf '  Country   : %s\n'  "$mCountry"
        printf '  Awards    : %s\n\n' "$mAwards"
        printf '[ RATINGS ]\n'
        printf -- '--------------------------------------------------------------------------------\n'
        printf '  IMDB      : %s/10  (%s votes)\n' "$mRating" "$mVotes"
        printf '  Rotten T  : %s\n' "$mRT"
        printf '  Metascore : %s\n' "$mMeta"
        printf '  IMDB URL  : https://www.imdb.com/title/%s/\n\n' "$mImdbId"
        printf '[ PLOT ]\n'
        printf -- '--------------------------------------------------------------------------------\n'
        printf '%s\n\n' "$mPlot"
    fi
    printf '[ TECHNICAL INFO ]\n'
    printf -- '--------------------------------------------------------------------------------\n'
    printf '%s\n\n' "$mediainfo_text"
    printf '================================================================================\n'
} > "$nfo_file"
ui_blank
printf '  %sNFO saved: %s%s\n' "$UI_GRN" "$nfo_file" "$UI_R"

# ── Write HTML ────────────────────────────────────────────────
htm_file="$out_dir/$base_name.htm"
# Export the fields the python HTML builder needs, then render.
export H_OMDB_OK="$OMDB_OK" H_TITLE="$title" H_SCRIPT="$SCRIPT_NAME" H_VER="$SCRIPT_VERSION" \
       H_AUTHOR="$SCRIPT_AUTHOR" H_TS="$timestamp" H_MEDIAINFO="$mediainfo_text"
if [[ "$OMDB_OK" -eq 1 ]]; then
    export H_MTITLE="$mTitle" H_MYEAR="$mYear" H_MRATED="$mRated" H_MREL="$mRel" H_MRUNTIME="$mRuntime" \
           H_MGENRE="$mGenre" H_MDIR="$mDir" H_MWRITER="$mWriter" H_MCAST="$mCast" H_MPLOT="$mPlot" \
           H_MLANG="$mLang" H_MCOUNTRY="$mCountry" H_MAWARDS="$mAwards" H_MIMDBID="$mImdbId" \
           H_MRATING="$mRating" H_MVOTES="$mVotes" H_MMETA="$mMeta" H_MPOSTER="$mPoster" H_MRT="$mRT"
fi
python3 - > "$htm_file" <<'PYEOF'
import os, html
def g(k, d=""): return os.environ.get(k, d)
ok = g("H_OMDB_OK") == "1"
e = html.escape
title = g("H_TITLE")
mi = g("H_MEDIAINFO")
if ok:
    mTitle=g("H_MTITLE"); mYear=g("H_MYEAR"); mRated=g("H_MRATED"); mRel=g("H_MREL")
    mRuntime=g("H_MRUNTIME"); mGenre=g("H_MGENRE"); mDir=g("H_MDIR"); mWriter=g("H_MWRITER")
    mCast=g("H_MCAST"); mPlot=g("H_MPLOT"); mLang=g("H_MLANG"); mCountry=g("H_MCOUNTRY")
    mAwards=g("H_MAWARDS"); mImdbId=g("H_MIMDBID"); mRating=g("H_MRATING"); mVotes=g("H_MVOTES")
    mMeta=g("H_MMETA"); mPoster=g("H_MPOSTER"); mRT=g("H_MRT")
    head_title = f"{mTitle} ({mYear})"
    poster = (f'<img src="{e(mPoster)}" alt="{e(mTitle)} poster">'
              if mPoster and mPoster != "N/A"
              else '<div class="noposter">No Poster Available</div>')
    rt_block = (f'''<div class="rating-box"><div class="score" style="color:#fa320a">{e(mRT)}</div>
                <div class="source">Rotten Tomatoes</div></div>''' if mRT and mRT != "N/A" else "")
    meta_block = (f'''<div class="rating-box"><div class="score" style="color:#6c3">{e(mMeta)}</div>
                <div class="source">Metascore</div></div>''' if mMeta and mMeta != "N/A" else "")
    h1 = e(mTitle)
    year_line = f"{e(mYear)} &nbsp;|&nbsp; {e(mRated)} &nbsp;|&nbsp; {e(mRuntime)} &nbsp;|&nbsp; {e(mGenre)}"
    info = f'''        <div class="field"><span class="label">Director</span> {e(mDir)}</div>
        <div class="field"><span class="label">Writer</span> {e(mWriter)}</div>
        <div class="field"><span class="label">Cast</span> {e(mCast)}</div>
        <div class="field"><span class="label">Language</span> {e(mLang)}</div>
        <div class="field"><span class="label">Country</span> {e(mCountry)}</div>
        <div class="field"><span class="label">Released</span> {e(mRel)}</div>
        <div class="field"><span class="label">Awards</span> {e(mAwards)}</div>
        <div class="ratings">
            <div class="rating-box"><div class="score">{e(mRating)}<span style="font-size:0.9rem;color:#888">/10</span></div>
                <div class="source">IMDB ({e(mVotes)})</div></div>
            {rt_block}
            {meta_block}
        </div>
        <div class="imdb-link"><span class="label">IMDB</span>
            <a href="https://www.imdb.com/title/{e(mImdbId)}/" target="_blank">https://www.imdb.com/title/{e(mImdbId)}/</a>
        </div>'''
    plot_div = f'<div class="plot">{e(mPlot)}</div>'
else:
    head_title = title; h1 = e(title); year_line = "No OMDb data"
    poster = '<div class="noposter">No Poster Available</div>'
    info = "        <div class='field'>No OMDb data available.</div>"
    plot_div = ""

print(f'''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{e(head_title)}</title>
    <style>
        * {{ box-sizing: border-box; margin: 0; padding: 0; }}
        body {{ font-family: 'Courier New', monospace; background: #0d0d0d; color: #c8c8c8;
            padding: 2rem; max-width: 960px; margin: 0 auto; }}
        h1 {{ color: #00d4ff; font-size: 1.8rem; margin-bottom: 0.25rem; }}
        .year {{ color: #888; font-size: 1rem; margin-bottom: 1.5rem; }}
        .container {{ display: flex; gap: 2rem; margin-bottom: 2rem; }}
        .poster img {{ width: 220px; border: 2px solid #333; border-radius: 4px; }}
        .poster .noposter {{ width: 220px; height: 330px; background: #1a1a1a;
            border: 2px solid #333; display: flex; align-items: center;
            justify-content: center; color: #555; font-size: 0.8rem; }}
        .info {{ flex: 1; }}
        .field {{ margin-bottom: 0.6rem; line-height: 1.5; }}
        .label {{ color: #00d4ff; font-weight: bold; min-width: 100px; display: inline-block; }}
        .ratings {{ display: flex; gap: 1.5rem; margin: 1rem 0; flex-wrap: wrap; }}
        .rating-box {{ background: #1a1a1a; border: 1px solid #333; padding: 0.5rem 1rem;
            border-radius: 4px; text-align: center; }}
        .rating-box .score {{ font-size: 1.4rem; color: #f5c518; font-weight: bold; }}
        .rating-box .source {{ font-size: 0.7rem; color: #888; margin-top: 0.2rem; }}
        .plot {{ background: #111; border-left: 3px solid #00d4ff; padding: 1rem 1.2rem;
            margin: 1.5rem 0; line-height: 1.7; color: #bbb; }}
        h2 {{ color: #00d4ff; font-size: 1rem; text-transform: uppercase; letter-spacing: 2px;
            margin: 2rem 0 1rem; border-bottom: 1px solid #333; padding-bottom: 0.4rem; }}
        .mediainfo {{ background: #0a0a0a; border: 1px solid #222; padding: 1rem; font-size: 0.85rem;
            white-space: pre-wrap; overflow-x: auto; color: #bbb; border-radius: 4px; line-height: 1.55; }}
        .imdb-link a {{ color: #f5c518; text-decoration: none; }}
        .imdb-link a:hover {{ text-decoration: underline; }}
        footer {{ margin-top: 3rem; font-size: 0.75rem; color: #444; border-top: 1px solid #222; padding-top: 1rem; }}
    </style>
</head>
<body>

<h1>{h1}</h1>
<div class="year">{year_line}</div>

<div class="container">
    <div class="poster">{poster}</div>
    <div class="info">
{info}
    </div>
</div>

{plot_div}

<h2>Technical Info</h2>
<div class="mediainfo">{e(mi)}</div>

<footer>
    Generated by {e(g("H_SCRIPT"))} v{e(g("H_VER"))} &nbsp;|&nbsp; {e(g("H_TS"))} &nbsp;|&nbsp; by {e(g("H_AUTHOR"))}
</footer>

</body>
</html>''')
PYEOF
printf '  %sHTML saved: %s%s\n' "$UI_GRN" "$htm_file" "$UI_R"

# ── Download poster ───────────────────────────────────────────
if [[ "$OMDB_OK" -eq 1 && "$mPoster" != "N/A" && "$HAVE_HTTP" -eq 1 ]]; then
    ui_blank
    printf '  %sDownloading poster...%s\n' "$UI_CYN" "$UI_R"
    poster_out="$out_dir/$base_name.jpg"
    if download "$mPoster" "$poster_out" && [[ -s "$poster_out" ]]; then
        printf '  %sPoster saved: %s%s\n' "$UI_GRN" "$poster_out" "$UI_R"
    else
        printf '  %sPoster download failed (non-fatal).%s\n' "$UI_YLW" "$UI_R"
        rm -f "$poster_out"
    fi
fi

# ── Done ──────────────────────────────────────────────────────
ui_blank
ui_divider
printf '  %sDone!%s  %s\n' "$UI_GRN" "$UI_R" "$out_dir"
show_result_table "$out_dir"
pause_return
