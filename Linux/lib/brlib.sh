#!/usr/bin/env bash
#--------------------------------------------
# file:    brlib.sh
# desc:    Shared library for the Blu-ray toolchain (bash port).
#          Sourced by bluray-backup.sh, bluray-trackdump.sh, brencoder.sh.
#          Provides UI helpers, safe-name, tool discovery, the MakeMKV
#          robot-mode parser, the BRTrackMeta JSON schema writer/reader,
#          ISO-639 language resolution, and the language quick-pick menu.
#          JSON and MakeMKV-robot parsing are delegated to python3.
#--------------------------------------------

# ── Shared UI: defer to core.sh / ui.sh in the lib dir ────────
# brlib.sh lives in ~/scripts/lib alongside core.sh and ui.sh. We source them
# so ui.sh stays the single source of truth for colors, then fill the few
# helpers/colors ui.sh does not provide. If neither is found (e.g. brlib was
# copied next to the scripts), we fall back to built-in defaults below.
BRLIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Source a shell file with any trailing CR stripped, so libraries saved with
# Windows (CRLF) line endings still load cleanly on Linux. core.sh enables
# strict mode and (re)sources ui.sh; load it quietly, then load a clean ui.sh
# ourselves so its colors/helpers win regardless of how core.sh fared.
# shellcheck disable=SC1090
_brlib_source() { [[ -f "$1" ]] || return 1; source <(sed 's/\r$//' "$1"); }
[[ -f "$BRLIB_DIR/core.sh" ]] && { _brlib_source "$BRLIB_DIR/core.sh" 2>/dev/null || true; }
_brlib_source "$BRLIB_DIR/ui.sh" 2>/dev/null || true

# Interactive menu loops don't mix with the errexit/nounset that core.sh turns
# on (a no-match grep, an Enter at a prompt, or an empty array would abort the
# script mid-menu), so relax them here. pipefail is harmless and kept.
set +e +u 2>/dev/null || true
set -o pipefail 2>/dev/null || true

# ui.sh stores colors as literal "\033[..m" (for `echo -e`). Normalize to real
# escape bytes so they work with printf, map its UI_RST -> UI_R, and add the
# extra colors brlib needs. Blank everything when stdout is not a terminal.
# shellcheck disable=SC2034
if [[ -t 1 ]]; then
    UI_CYN="$(printf '%b' "${UI_CYN:-$'\e[36m'}")"
    UI_GRN="$(printf '%b' "${UI_GRN:-$'\e[32m'}")"
    UI_YLW="$(printf '%b' "${UI_YLW:-$'\e[33m'}")"
    UI_RED="$(printf '%b' "${UI_RED:-$'\e[31m'}")"
    UI_R="$(printf  '%b' "${UI_RST:-$'\e[0m'}")"
    UI_MAG="${UI_MAG:-$'\e[35m'}"
    UI_GRY="${UI_GRY:-$'\e[90m'}"
    UI_DIM="${UI_DIM:-$'\e[2m'}"
else
    UI_CYN=""; UI_GRN=""; UI_YLW=""; UI_RED=""; UI_R=""; UI_MAG=""; UI_GRY=""; UI_DIM=""
fi

# Helpers ui.sh / core.sh don't define (added only if missing so theirs win).
declare -F core_error   >/dev/null || core_error()   { if declare -F ui_error >/dev/null; then ui_error "$1"; else printf '  %sError:%s %s\n' "$UI_RED" "$UI_R" "$1" >&2; fi; }
declare -F pause_return >/dev/null || pause_return() { if declare -F pause >/dev/null; then pause; else read -rp "  Press Enter to return... " _; fi; }
declare -F ui_divider   >/dev/null || ui_divider()   { printf '  %s------------------------------------------------------------%s\n' "$UI_GRY" "$UI_R"; }
ui_blank()   { printf '\n'; }
ui_clear()   { clear 2>/dev/null || printf '\033c'; }
ui_row()     { printf '  %s%-13s%s %s\n' "${3:-}" "$1" "$UI_R" "$2"; }
ui_section() { printf '\n  %s== %s ==%s\n' "${2:-$UI_CYN}" "$1" "$UI_R"; }

# Title banner: use ui.sh's box header when available, then a subtitle line.
show_title() {
    local title="$1" subtitle="${2:-}"
    if declare -F ui_header >/dev/null; then
        ui_header "$title"
    else
        ui_blank; printf '  %s== %s ==%s\n' "$UI_CYN" "$title" "$UI_R"
    fi
    [[ -n "$subtitle" ]] && printf '  %s%s%s\n' "$UI_GRY" "$subtitle" "$UI_R"
    ui_blank
}

# ── Utilities ─────────────────────────────────────────────────
trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

# Strip filesystem-hostile characters but keep [ ] (naming convention).
safe_name() {
    local name="$1" safe
    safe="$(printf '%s' "$name" | sed -e 's#[\\/:*?"<>|]#_#g')"
    safe="$(trim "$safe")"
    [[ -z "$safe" ]] && safe="bluray_$(date +%Y%m%d_%H%M%S)"
    printf '%s' "$safe"
}

ensure_dirs() {
    local p
    for p in "$@"; do [[ -d "$p" ]] || mkdir -p -- "$p"; done
}

require_python() {
    if ! command -v python3 >/dev/null 2>&1; then
        core_error "python3 is required (used for JSON and MakeMKV parsing)."
        return 1
    fi
}

# ── Tool discovery ────────────────────────────────────────────
find_makemkv() {
    local c
    for c in makemkvcon makemkvcon64; do
        if command -v "$c" >/dev/null 2>&1; then command -v "$c"; return 0; fi
    done
    for c in /usr/bin/makemkvcon /usr/local/bin/makemkvcon /opt/makemkv/bin/makemkvcon; do
        [[ -x "$c" ]] && { printf '%s' "$c"; return 0; }
    done
    return 1
}

find_tool() { command -v "$1" 2>/dev/null; }

# ── Language quick-pick (replaces Show-LanguagePicker) ────────
# Sets LANG_PICK to a 3-letter code or 'und'.
br_quicklang_codes=(eng spa fre ger ita por jpn chi kor ara rus dut hin)
br_quicklang_names=(English Spanish French German Italian Portuguese Japanese Chinese Korean Arabic Russian Dutch Hindi)

LANG_PICK="und"
show_language_picker() {
    local label="$1" i input
    ui_blank
    printf '  Track: %s\n' "$label"
    printf '  Language is missing or unknown. Pick a number or type a 3-letter code:\n'
    ui_blank
    for i in "${!br_quicklang_codes[@]}"; do
        printf '    %2d)  %-12s  %s\n' "$((i + 1))" "${br_quicklang_codes[$i]}" "${br_quicklang_names[$i]}"
    done
    printf '     S)  Skip (leave as '\''und'\'')\n'
    ui_blank
    read -rp "  Language [S]: " input
    input="$(trim "$input")"

    if [[ -z "$input" || "$input" =~ ^[Ss]$ ]]; then LANG_PICK="und"; return; fi
    if [[ "$input" =~ ^[0-9]+$ ]] && (( input >= 1 && input <= ${#br_quicklang_codes[@]} )); then
        LANG_PICK="${br_quicklang_codes[$((input - 1))]}"; return
    fi
    if [[ "$input" =~ ^[A-Za-z]{3}$ ]]; then LANG_PICK="${input,,}"; return; fi

    declare -A two=( [en]=eng [es]=spa [fr]=fre [de]=ger [it]=ita [pt]=por [ja]=jpn
                     [zh]=chi [ko]=kor [ar]=ara [ru]=rus [nl]=dut [hi]=hin [sv]=swe
                     [no]=nor [da]=dan [fi]=fin [pl]=pol [cs]=cze [hu]=hun )
    local low="${input,,}"
    if [[ -n "${two[$low]:-}" ]]; then LANG_PICK="${two[$low]}"; return; fi

    printf "  Unrecognised input '%s' — leaving as 'und'.\n" "$input"
    LANG_PICK="und"
}

# ── python backend ────────────────────────────────────────────
# All JSON + MakeMKV-robot + ffprobe-JSON parsing goes through here.
br_py() { python3 -c "$BR_PY" "$@"; }

read -r -d '' BR_PY <<'PYEOF'
import sys, json, re, datetime, os

def resolve_lang(code):
    if not code or not str(code).strip():
        return 'und'
    c = str(code).strip().lower()
    if re.fullmatch(r'[a-z]{3}', c):
        return c
    names = {
        'english':'eng','spanish':'spa','french':'fre','japanese':'jpn','german':'ger',
        'italian':'ita','portuguese':'por','chinese':'chi','korean':'kor','arabic':'ara',
        'russian':'rus','dutch':'dut','hindi':'hin','swedish':'swe','norwegian':'nor',
        'danish':'dan','finnish':'fin','polish':'pol','czech':'cze','hungarian':'hun',
        'turkish':'tur','greek':'gre','hebrew':'heb','thai':'tha','vietnamese':'vie',
        'indonesian':'ind','malay':'may','romanian':'rum','ukrainian':'ukr','croatian':'hrv',
        'slovak':'slo','bulgarian':'bul','catalan':'cat',
        'en':'eng','es':'spa','fr':'fre','ja':'jpn','de':'ger','it':'ita','pt':'por',
        'zh':'chi','ko':'kor','ar':'ara','ru':'rus','nl':'dut','hi':'hin','sv':'swe',
        'no':'nor','da':'dan','fi':'fin','pl':'pol','cs':'cze','hu':'hun','tr':'tur',
        'el':'gre','he':'heb','th':'tha','vi':'vie','id':'ind','ms':'may','ro':'rum',
        'uk':'ukr','hr':'hrv','sk':'slo','bg':'bul','ca':'cat',
        'unknown':'und','undetermined':'und',
    }
    return names.get(c, c)

LANG_NAMES = {
    'eng':'English','spa':'Spanish','fre':'French','fra':'French','ger':'German',
    'ita':'Italian','por':'Portuguese','jpn':'Japanese','chi':'Chinese','kor':'Korean',
    'ara':'Arabic','rus':'Russian','dut':'Dutch','hin':'Hindi',
}

# ---- MakeMKV robot-mode info parser -------------------------------------
def parse_makemkv(text):
    titles = {}
    def ensure_title(tid):
        if tid not in titles:
            titles[tid] = dict(TitleId=tid, Name=None, Chapters=None, Duration=None,
                               SizeText=None, SizeBytes=0, SourceFile=None, SegmentMap=None,
                               OutputName=None, LanguageCode=None, LanguageName=None,
                               Summary=None, Tracks={})
        return titles[tid]
    tinfo = re.compile(r'^TINFO:(\d+),(\d+),\d+,"(.*)"$')
    sinfo = re.compile(r'^SINFO:(\d+),(\d+),(\d+),\d+,"(.*)"$')
    for line in text.splitlines():
        if not line.strip():
            continue
        m = tinfo.match(line)
        if m:
            tid, fid, val = int(m.group(1)), int(m.group(2)), m.group(3)
            t = ensure_title(tid)
            if   fid == 2:  t['Name'] = val
            elif fid == 8:  t['Chapters'] = val
            elif fid == 9:  t['Duration'] = val
            elif fid == 10: t['SizeText'] = val
            elif fid == 11:
                if re.fullmatch(r'\d+', val): t['SizeBytes'] = int(val)
            elif fid == 16: t['SourceFile'] = val
            elif fid == 26: t['SegmentMap'] = val
            elif fid == 27: t['OutputName'] = val
            elif fid == 28: t['LanguageCode'] = val
            elif fid == 29: t['LanguageName'] = val
            elif fid == 30: t['Summary'] = val
            continue
        m = sinfo.match(line)
        if m:
            tid, trk, fid, val = int(m.group(1)), int(m.group(2)), int(m.group(3)), m.group(4)
            t = ensure_title(tid)
            tr = t['Tracks'].setdefault(trk, dict(TrackId=trk, Type=None, LanguageCode=None,
                    LanguageName=None, CodecId=None, CodecShort=None, CodecLong=None,
                    ChannelsText=None, Description=None, Default=False, Forced=False))
            if   fid == 1: tr['Type'] = val
            elif fid == 2: tr['ChannelsText'] = val
            elif fid == 3: tr['LanguageCode'] = val
            elif fid == 4: tr['LanguageName'] = val
            elif fid == 5: tr['CodecId'] = val
            elif fid == 6: tr['CodecShort'] = val
            elif fid == 7: tr['CodecLong'] = val
            elif fid == 30:
                tr['Description'] = val
                if re.search(r'forced only', val, re.I): tr['Forced'] = True
            elif fid == 38:
                if 'd' in val: tr['Default'] = True
            elif fid == 39:
                if 'Default' in val: tr['Default'] = True
            continue
    out = []
    for tid in sorted(titles):
        t = titles[tid]
        tracks = [t['Tracks'][k] for k in sorted(t['Tracks'])]
        t2 = {k: v for k, v in t.items() if k != 'Tracks'}
        t2['Tracks'] = tracks
        t2['AudioTracks']    = [x for x in tracks if x['Type'] == 'Audio']
        t2['SubtitleTracks'] = [x for x in tracks if x['Type'] == 'Subtitles']
        t2['VideoTracks']    = [x for x in tracks if x['Type'] == 'Video']
        out.append(t2)
    return out

def dur_secs(d):
    if d and re.fullmatch(r'\d{1,2}:\d{2}:\d{2}', str(d)):
        h, m, s = map(int, d.split(':'))
        return h*3600 + m*60 + s
    return 0

def main_title(titles):
    if not titles:
        return None
    return sorted(titles, key=lambda t: (t.get('SizeBytes', 0), dur_secs(t.get('Duration'))),
                  reverse=True)[0]

# ---- tracks.txt cleaning (port of New-BRTextTrackObject) ----------------
def clean_desc(desc, langcode, forced):
    name = LANG_NAMES.get(langcode)
    d = desc.strip()
    d = re.sub(r'\s*\([^)]*forced only[^)]*\)', '', d)
    d = re.sub(r'\s*\[[^\]]+\]', '', d)
    d = re.sub(r'\s+', ' ', d).strip()
    if name:
        if re.fullmatch(r'PGS\s+' + re.escape(name), d):
            d = name + ' PGS'
        else:
            m = re.fullmatch(r'(.+?)\s+' + re.escape(name), d)
            if m:
                d = name + ' ' + m.group(1).strip()
    if forced and not re.search(r'forced', d, re.I):
        d = d + ' Forced'
    return d

def parse_tracks_txt(path):
    audio, subs, section, order = [], [], '', 0
    movie = re.sub(r'\.tracks$', '', os.path.splitext(os.path.basename(path))[0])
    with open(path, encoding='utf-8', errors='replace') as fh:
        for line in fh:
            t = line.strip()
            if not t:
                continue
            m = re.match(r'^Movie\s*:\s*(.+)$', t)
            if m:
                movie = m.group(1).strip(); continue
            if t.startswith('[Audio]'):     section = 'audio'; continue
            if t.startswith('[Subtitles]'): section = 'subtitle'; continue
            if t.startswith('['):           section = ''; continue
            if section not in ('audio', 'subtitle'):
                continue
            m = re.match(r'^(?P<id>[as]\d+)\s*:\s*(?P<lang>[A-Za-z]{2,3}|und)\b.*?\|\s*(?P<desc>.+)$', t)
            if not m:
                continue
            order += 1
            tid, lang, desc = m.group('id'), m.group('lang'), m.group('desc').strip()
            forced = bool(re.search(r'\[([^\]]*,\s*)?forced(\s*,[^\]]*)?\]', t) or re.search(r'\(forced only\)', t))
            default = bool(re.search(r'\[([^\]]*,\s*)?default(\s*,[^\]]*)?\]', t))
            code = resolve_lang(lang)
            cd = clean_desc(desc, code, forced)
            rec = dict(TrackId=tid, LanguageCode=code, Name=cd, Default=default, Forced=forced,
                       Order=order)
            (audio if section == 'audio' else subs).append(rec)
    audio.sort(key=lambda x: int(re.sub(r'^a', '', str(x['TrackId'])) or 0))
    subs.sort(key=lambda x: x['Order'])
    return {'MovieName': movie, 'MainTitle': {'OutputName': movie,
            'AudioTracks': audio, 'SubtitleTracks': subs}}

# ---- normalize any sidecar to {audio:[...], subtitle:[...]} --------------
def track_field(tr, *keys):
    for k in keys:
        v = tr.get(k)
        if v not in (None, ''):
            return v
    return None

def normalize(path):
    if path.endswith('.tracks.txt'):
        data = parse_tracks_txt(path)
    else:
        with open(path, encoding='utf-8', errors='replace') as fh:
            data = json.load(fh)
    title = data.get('MainTitle') or data.get('Title') or {}
    def norm_list(lst):
        out = []
        for tr in (lst or []):
            code = resolve_lang(track_field(tr, 'LanguageCode', 'Language', 'languageCode', 'language') or '')
            name = track_field(tr, 'Name', 'TrackName', 'Description', 'CodecLong', 'CodecShort') or ''
            out.append({'lang': code, 'name': name,
                        'default': bool(tr.get('Default')), 'forced': bool(tr.get('Forced'))})
        return out
    audio = title.get('AudioTracks')
    sub   = title.get('SubtitleTracks')
    if audio is None and title.get('Tracks'):
        audio = [t for t in title['Tracks'] if t.get('Type') == 'Audio']
        sub   = [t for t in title['Tracks'] if t.get('Type') == 'Subtitles']
    return {'audio': norm_list(audio), 'subtitle': norm_list(sub)}

# ---- write BRTrackMeta JSON (+aliases) and tracks.txt -------------------
def write_meta(meta_base, movie, largest_name, largest_path, title_file, overrides_file, created_by):
    with open(title_file, encoding='utf-8') as fh:
        title = json.load(fh)
    overrides = {}
    if overrides_file and os.path.exists(overrides_file):
        with open(overrides_file, encoding='utf-8') as fh:
            overrides = json.load(fh)  # { "trackId": "code" }
    # apply language overrides onto matching tracks
    for tr in title.get('Tracks', []):
        ov = overrides.get(str(tr['TrackId']))
        if ov:
            tr['LanguageCode'] = ov
            tr['LanguageName'] = LANG_NAMES.get(ov, 'Undetermined' if ov == 'und' else ov)
    # rebuild Audio/SubtitleTracks views after overrides
    tracks = title.get('Tracks', [])
    title['AudioTracks']    = [t for t in tracks if t.get('Type') == 'Audio']
    title['SubtitleTracks'] = [t for t in tracks if t.get('Type') == 'Subtitles']

    schema = {
        'SchemaVersion': 'BRTrackMeta/1.0',
        'CreatedAt': datetime.datetime.now().replace(microsecond=0).isoformat(),
        'CreatedBy': created_by,
        'MovieName': movie,
        'LargestM2TS': largest_name,
        'LargestPath': largest_path,
        'SourceFingerprint': {
            'FileName': largest_name, 'FullPath': largest_path,
            'TitleId': title.get('TitleId'), 'TitleName': title.get('Name'),
            'Duration': title.get('Duration'), 'SizeText': title.get('SizeText'),
            'SizeBytes': title.get('SizeBytes'), 'Playlist': title.get('SourceFile'),
            'SegmentMap': title.get('SegmentMap'), 'OutputName': title.get('OutputName'),
        },
        'MainTitle': title,
        'Title': title,
    }
    json_path = meta_base + '.json'
    txt_path  = meta_base + '.tracks.txt'
    text = json.dumps(schema, indent=2, ensure_ascii=False)
    with open(json_path, 'w', encoding='utf-8') as fh:
        fh.write(text + '\n')

    # alias JSONs (skip 5-digit stream names that collide between discs)
    bases = []
    for v in (largest_name, title.get('SourceFile'), title.get('OutputName')):
        if v:
            bases.append(os.path.splitext(os.path.basename(str(v)))[0])
    seen = set()
    for b in bases:
        if not b or b in seen:
            continue
        seen.add(b)
        if re.fullmatch(r'\d{5}', b):
            continue
        safe = re.sub(r'[\\/:*?"<>|]', '_', b).strip()
        ap = os.path.join(os.path.dirname(meta_base), safe + '.json')
        if os.path.abspath(ap) != os.path.abspath(json_path):
            with open(ap, 'w', encoding='utf-8') as fh:
                fh.write(text + '\n')

    # tracks.txt
    L = []
    L.append('Schema     : ' + schema['SchemaVersion'])
    L.append('Movie      : ' + str(movie))
    L.append('LargestM2TS: ' + str(largest_name or ''))
    L.append('TitleId    : ' + str(title.get('TitleId', '')))
    L.append('TitleName  : ' + str(title.get('Name') or ''))
    L.append('SourceFile : ' + str(title.get('SourceFile') or ''))
    L.append('Duration   : ' + str(title.get('Duration') or ''))
    L.append('Size       : ' + str(title.get('SizeText') or ''))
    fp = schema['SourceFingerprint']
    L.append('Fingerprint: title=%s playlist=%s bytes=%s' % (fp['TitleId'], fp['Playlist'], fp['SizeBytes']))
    L.append('')
    def lang_disp(tr):
        c = tr.get('LanguageCode') or 'und'
        n = tr.get('LanguageName')
        return ('%s / %s' % (c, n)) if n else c
    if title['AudioTracks']:
        L.append('[Audio]')
        for a in title['AudioTracks']:
            flags = ' [default]' if a.get('Default') else ''
            L.append('a%s: %s | %s%s' % (a['TrackId'], lang_disp(a), a.get('Description') or '', flags))
        L.append('')
    if title['SubtitleTracks']:
        L.append('[Subtitles]')
        for s in title['SubtitleTracks']:
            fl = []
            if s.get('Forced'):  fl.append('forced')
            if s.get('Default'): fl.append('default')
            flags = (' [' + ', '.join(fl) + ']') if fl else ''
            L.append('s%s: %s | %s%s' % (s['TrackId'], lang_disp(s), s.get('Description') or '', flags))
        L.append('')
    with open(txt_path, 'w', encoding='utf-8') as fh:
        fh.write('\n'.join(L) + '\n')

# ---- ffprobe-driven HDR/SDR profile -------------------------------------
def video_profile(stream_file, frame_file, crf_hdr, crf_sdr):
    try:
        with open(stream_file, encoding='utf-8') as fh:
            sj = json.load(fh)
    except Exception:
        sj = {}
    st = (sj.get('streams') or [{}])[0] if sj.get('streams') else {}
    trc = (st.get('color_transfer') or '')
    prim = (st.get('color_primaries') or '')
    space = (st.get('color_space') or '')
    is_hdr = bool(re.search(r'smpte2084|arib-std-b67|smpte428|bt2020-10|bt2020-12', trc))
    master = None; maxcll = None
    if is_hdr and frame_file and os.path.exists(frame_file):
        try:
            with open(frame_file, encoding='utf-8') as fh:
                fj = json.load(fh)
        except Exception:
            fj = {}
        frames = fj.get('frames') or []
        if frames:
            sd = frames[0].get('side_data_list') or []
            md = next((x for x in sd if re.search(r'Mastering display', x.get('side_data_type',''))), None)
            cll = next((x for x in sd if re.search(r'Content light level', x.get('side_data_type',''))), None)
            def frac(v):
                # ffprobe gives "x/y" rationals or floats
                try:
                    if isinstance(v, str) and '/' in v:
                        a, b = v.split('/'); return float(a)/float(b)
                    return float(v)
                except Exception:
                    return 0.0
            if md:
                gx=int(frac(md.get('green_x'))*50000); gy=int(frac(md.get('green_y'))*50000)
                bx=int(frac(md.get('blue_x'))*50000);  by=int(frac(md.get('blue_y'))*50000)
                rx=int(frac(md.get('red_x'))*50000);    ry=int(frac(md.get('red_y'))*50000)
                wx=int(frac(md.get('white_point_x'))*50000); wy=int(frac(md.get('white_point_y'))*50000)
                lmax=int(frac(md.get('max_luminance'))*10000); lmin=int(frac(md.get('min_luminance'))*10000)
                master='G(%d,%d)B(%d,%d)R(%d,%d)WP(%d,%d)L(%d,%d)'%(gx,gy,bx,by,rx,ry,wx,wy,lmax,lmin)
            if cll:
                maxcll='%d,%d'%(int(frac(cll.get('max_content'))),int(frac(cll.get('max_average'))))
    out_prim  = prim  or ('bt2020' if is_hdr else 'bt709')
    out_trc   = trc   or ('smpte2084' if is_hdr else 'bt709')
    out_space = space or ('bt2020nc' if is_hdr else 'bt709')
    profile = ('HLG' if re.search(r'arib-std-b67', trc) else 'HDR10') if is_hdr else 'SDR'
    print(json.dumps({
        'IsHDR': is_hdr, 'CRF': int(crf_hdr if is_hdr else crf_sdr), 'PixFmt': 'yuv420p10le',
        'ColorPrimaries': out_prim, 'ColorTrc': out_trc, 'Colorspace': out_space,
        'MasterDisplay': master, 'MaxCLL': maxcll, 'Profile': profile,
    }))

# ---- mkvmerge -J helpers ------------------------------------------------
def mkv_layout(jfile):
    with open(jfile, encoding='utf-8') as fh:
        j = json.load(fh)
    tracks = j.get('tracks') or []
    a = sum(1 for t in tracks if t.get('type') == 'audio')
    s = sum(1 for t in tracks if t.get('type') == 'subtitles')
    print('%d %d' % (a, s))

def mkv_verify(jfile):
    with open(jfile, encoding='utf-8') as fh:
        j = json.load(fh)
    tracks = j.get('tracks') or []
    a = [t for t in tracks if t.get('type') == 'audio']
    s = [t for t in tracks if t.get('type') == 'subtitles']
    n = 1
    for t in a:
        p = t.get('properties', {})
        flags = ''
        if p.get('default_track'): flags += ' default'
        print('a%d: %s %s%s' % (n, p.get('language') or 'und', p.get('track_name') or '', flags))
        n += 1
    n = 1
    for t in s:
        p = t.get('properties', {})
        flags = ''
        if p.get('default_track'): flags += ' default'
        if p.get('forced_track'):  flags += ' forced'
        print('s%d: %s %s%s' % (n, p.get('language') or 'und', p.get('track_name') or '', flags))
        n += 1

# ---- ffprobe source stream languages (fallback path) -------------------
def source_langs(jfile):
    with open(jfile, encoding='utf-8') as fh:
        j = json.load(fh)
    streams = j.get('streams') or []
    a = [s for s in streams if s.get('codec_type') == 'audio']
    s = [s for s in streams if s.get('codec_type') == 'subtitle']
    for t in a:
        print('audio\t%s' % resolve_lang((t.get('tags') or {}).get('language') or 'und'))
    for t in s:
        print('sub\t%s' % resolve_lang((t.get('tags') or {}).get('language') or 'und'))

# ---- dispatch -----------------------------------------------------------
cmd = sys.argv[1] if len(sys.argv) > 1 else ''
if cmd == 'parse_main_title':
    with open(sys.argv[2], encoding='utf-8', errors='replace') as fh:
        titles = parse_makemkv(fh.read())
    mt = main_title(titles)
    print(json.dumps(mt) if mt else 'null')
elif cmd == 'write_meta':
    write_meta(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6], sys.argv[7], sys.argv[8])
elif cmd == 'normalize':
    print(json.dumps(normalize(sys.argv[2])))
elif cmd == 'video_profile':
    video_profile(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5])
elif cmd == 'mkv_layout':
    mkv_layout(sys.argv[2])
elif cmd == 'mkv_verify':
    mkv_verify(sys.argv[2])
elif cmd == 'source_langs':
    source_langs(sys.argv[2])
elif cmd == 'normalize_tsv':
    nz = normalize(sys.argv[2])
    for a in nz['audio']:
        print('audio\t%s\t%s\t%d' % (a['lang'], a['name'], 1 if a['default'] else 0))
    for s in nz['subtitle']:
        print('subtitle\t%s\t%s\t%d\t%d' % (s['lang'], s['name'], 1 if s['default'] else 0, 1 if s['forced'] else 0))
elif cmd == 'meta_movie':
    p = sys.argv[2]
    if p.endswith('.tracks.txt'):
        print(parse_tracks_txt(p).get('MovieName') or '')
    else:
        with open(p, encoding='utf-8', errors='replace') as fh:
            d = json.load(fh)
        t = d.get('MainTitle') or d.get('Title') or {}
        print(d.get('MovieName') or t.get('OutputName') or '')
elif cmd == 'needs_lang':
    with open(sys.argv[2], encoding='utf-8') as fh:
        t = json.load(fh)
    def missing(c):
        return (not c) or str(c).strip() == '' or str(c).strip().lower() == 'und'
    for a in (t.get('AudioTracks') or []):
        if missing(a.get('LanguageCode')):
            codec = a.get('CodecShort') or a.get('CodecLong') or 'audio'
            ch = (' ' + a['ChannelsText']) if a.get('ChannelsText') else ''
            print('%s\taudio\tAudio track %s - %s%s' % (a['TrackId'], a['TrackId'], codec, ch))
    for s in (t.get('SubtitleTracks') or []):
        if missing(s.get('LanguageCode')):
            forced = ' [forced]' if s.get('Forced') else ''
            print('%s\tsubtitle\tSubtitle track %s%s' % (s['TrackId'], s['TrackId'], forced))
elif cmd == 'resolve_lang':
    print(resolve_lang(sys.argv[2]))
elif cmd == 'json_get':
    with open(sys.argv[2], encoding='utf-8', errors='replace') as fh:
        d = json.load(fh)
    cur = d
    for key in sys.argv[3].split('.'):
        if isinstance(cur, dict):
            cur = cur.get(key)
        else:
            cur = None
        if cur is None:
            break
    print('' if cur is None else (cur if isinstance(cur, str) else json.dumps(cur)))
else:
    sys.stderr.write('unknown brlib python command: %s\n' % cmd)
    sys.exit(2)
PYEOF

# ── MakeMKV runners (shared by backup + trackdump) ────────────
makemkv_run_info() {   # <exe> <drive> <outfile> ; returns exit code
    "$1" -r info "$2" > "$3" 2>/dev/null
}

# Backup with a live progress bar parsed from robot-mode PRGV lines.
makemkv_backup_progress() {   # <exe> <drive> <dest> ; returns makemkv exit code
    local exe="$1" drive="$2" dest="$3"
    local percent=0 line cur tot filled bar rcfile rc
    rcfile="$(mktemp)"
    while IFS= read -r line; do
        if [[ "$line" =~ PRGV:([0-9]+),([0-9]+),([0-9]+) ]]; then
            cur="${BASH_REMATCH[2]}"; tot="${BASH_REMATCH[3]}"
            (( tot > 0 )) && percent=$(( cur * 100 / tot ))
            filled=$(( percent / 4 )); (( filled < 0 )) && filled=0; (( filled > 25 )) && filled=25
            bar="$(printf '%*s' "$filled" '' | tr ' ' '#')"
            printf '\r  [%-25s] %d%%' "$bar" "$percent"
        fi
    done < <( "$exe" backup --decrypt --cache=512 -r --progress=-same "$drive" "$dest" 2>&1; echo $? > "$rcfile" )
    printf '\n'
    rc="$(cat "$rcfile" 2>/dev/null || echo 1)"; rm -f "$rcfile"
    return "${rc:-1}"
}

# ── BD structure helpers ──────────────────────────────────────
# Find a STREAM dir (case-insensitive) that contains .m2ts files.
find_stream_dir() {   # <root> ; prints path or nothing
    local root="$1" d
    while IFS= read -r d; do
        if compgen -G "$d/"*.m2ts > /dev/null 2>&1 || compgen -G "$d/"*.M2TS > /dev/null 2>&1; then
            printf '%s' "$d"; return 0
        fi
    done < <(find "$root" -type d \( -iname STREAM \) 2>/dev/null)
    return 1
}

# Largest .m2ts under a directory: prints "path<TAB>bytes".
largest_m2ts() {   # <dir>
    find "$1" -maxdepth 1 -type f \( -iname '*.m2ts' \) -printf '%s\t%p\n' 2>/dev/null \
        | sort -rn | head -1 | sed 's/\t/\t/'
}

# ── Interactive missing-language resolver (backup + trackdump) ─
# Reads a parsed main-title JSON, prompts for any track with no language,
# and writes an overrides JSON ({"trackId":"code"}) to $2.
resolve_track_languages() {   # <main.json> <overrides_out_file>
    local main="$1" ovfile="$2" need
    need="$(br_py needs_lang "$main")"
    if [[ -z "$need" ]]; then
        ui_blank
        printf '  All tracks have language codes from MakeMKV.\n'
        printf '{}' > "$ovfile"
        return 0
    fi
    ui_blank
    ui_section "Language Assignment"
    local count; count="$(printf '%s\n' "$need" | grep -c .)"
    printf '  %s track(s) have no language. Assign them now so BREncoder\n' "$count"
    printf '  can write correct language tags to the encoded MKV.\n'

    local -A ov=()
    local tid label
    while IFS=$'\t' read -r tid _ label; do
        [[ -z "$tid" ]] && continue
        show_language_picker "$label"
        ov[$tid]="$LANG_PICK"
        printf '  -> Set to: %s\n' "$LANG_PICK"
    done <<< "$need"

    { printf '{'; local first=1 k
      for k in "${!ov[@]}"; do
          [[ $first -eq 1 ]] || printf ','
          first=0
          printf '"%s":"%s"' "$k" "${ov[$k]}"
      done
      printf '}'
    } > "$ovfile"
    ui_blank
    printf '  Language assignment complete.\n'
}
