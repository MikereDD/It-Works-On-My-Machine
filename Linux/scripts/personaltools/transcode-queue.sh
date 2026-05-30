#!/usr/bin/env bash
#--------------------------------------------
# file:    transcode-queue.sh
# author:  Mike Redd
# version: 1.0
# desc:    Batch-encode videos in a watch folder to x265 with ffmpeg.
#          Run once over the folder, or --watch to process new files
#          as they land. Config via env or ~/.config/transcoderc:
#            TQ_IN    input/watch dir
#            TQ_OUT   output dir
#            TQ_DONE  where to move sources after success
#            TQ_CRF   x265 CRF (default 20)
#            TQ_PRESET ffmpeg x265 preset (default slow)
#--------------------------------------------

LIB_DIR="${LIB_DIR:-$HOME/lib}"
if [[ -f "$LIB_DIR/core.sh" ]]; then
    # shellcheck source=/dev/null
    source <(sed 's/\r$//' "$LIB_DIR/core.sh")
else
    echo "Error: core.sh not found in $LIB_DIR" >&2; exit 1
fi
set +e +u 2>/dev/null || true

RC="${TRANSCODERC:-$HOME/.config/transcoderc}"
[[ -f "$RC" ]] && { # shellcheck source=/dev/null
    source <(sed 's/\r$//' "$RC"); }

TQ_IN="${TQ_IN:-$HOME/Rip/incoming}"
TQ_OUT="${TQ_OUT:-$HOME/Rip/raw265}"
TQ_DONE="${TQ_DONE:-$HOME/Rip/done}"
TQ_CRF="${TQ_CRF:-20}"
TQ_PRESET="${TQ_PRESET:-slow}"
TQ_EXTS="${TQ_EXTS:-mkv mp4 m2ts avi mov}"

have() { command -v "$1" >/dev/null 2>&1; }

encode_one() {   # <infile>
    local in="$1" base out
    base="$(basename -- "${in%.*}")"
    out="$TQ_OUT/${base}.mkv"
    [[ -e "$out" ]] && { printf '  %sskip (exists): %s%s\n' "$UI_DIM" "$base" "$UI_R"; return 0; }

    printf '  %sEncoding%s %s\n' "$UI_CYN" "$UI_R" "$(basename -- "$in")"
    if ffmpeg -hide_banner -loglevel warning -y -i "$in" \
        -map 0 -c:v libx265 -crf "$TQ_CRF" -preset "$TQ_PRESET" \
        -c:a copy -c:s copy "$out"; then
        printf '  %sDone -> %s%s\n' "$UI_GRN" "$out" "$UI_R"
        mkdir -p -- "$TQ_DONE" && mv -- "$in" "$TQ_DONE/" 2>/dev/null
        return 0
    else
        core_error "Encode failed: $(basename -- "$in")"
        rm -f -- "$out"
        return 1
    fi
}

scan_once() {
    local found=0 f ext
    for ext in $TQ_EXTS; do
        for f in "$TQ_IN"/*."$ext"; do
            [[ -f "$f" ]] || continue
            found=1
            encode_one "$f"
        done
    done
    (( found == 0 )) && printf '  %sNothing to encode in %s%s\n' "$UI_DIM" "$TQ_IN" "$UI_R"
}

ui_header "TRANSCODE QUEUE"
ui_row "Input"  "$TQ_IN"  "$UI_GRY"
ui_row "Output" "$TQ_OUT" "$UI_GRY"
ui_row "x265"   "CRF $TQ_CRF / preset $TQ_PRESET" "$UI_GRY"
echo

if ! have ffmpeg; then
    ui_row "ffmpeg" "not installed" "$UI_RED"
    printf '  %sInstall: sudo pacman -S ffmpeg%s\n' "$UI_DIM" "$UI_R"
    echo; pause; exit 0
fi
mkdir -p -- "$TQ_IN" "$TQ_OUT"

if [[ "${1:-}" == "--watch" || "${1:-}" == "-w" ]]; then
    if ! have inotifywait; then
        core_error "inotifywait not found (install inotify-tools) — doing a one-time scan instead."
        scan_once; echo; pause; exit 0
    fi
    printf '  %sWatching %s (Ctrl-C to stop)...%s\n' "$UI_CYN" "$TQ_IN" "$UI_R"
    scan_once
    trap 'echo; exit 0' INT
    inotifywait -m -e close_write -e moved_to --format '%f' "$TQ_IN" 2>/dev/null | while read -r name; do
        for ext in $TQ_EXTS; do
            [[ "$name" == *."$ext" ]] && encode_one "$TQ_IN/$name"
        done
    done
else
    scan_once
    echo
    pause
fi
