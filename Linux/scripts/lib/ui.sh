#!/usr/bin/env bash
# file: ui.sh
# version: 1.1
# Shared UI helpers. v1.1 adds ui_row/ui_section/ui_blank/ui_clear, extra
# colors (UI_GRY/UI_DIM/UI_WHT/UI_MAG and UI_R as a reset alias), an optional
# subtitle arg on ui_header, real-escape colors (work with printf and echo -e),
# and a TTY guard so colors are dropped when output is redirected.

# ── Colors ────────────────────────────────────────────────────
# Consumed by scripts that source this library.
# shellcheck disable=SC2034
if [[ -t 1 ]]; then
    UI_CYN=$'\e[1;36m'
    UI_GRN=$'\e[1;32m'
    UI_YLW=$'\e[1;33m'
    UI_RED=$'\e[1;31m'
    UI_MAG=$'\e[1;35m'
    UI_WHT=$'\e[1;37m'
    UI_GRY=$'\e[90m'
    UI_DIM=$'\e[2m'
    UI_RST=$'\e[0m'
else
    UI_CYN=""; UI_GRN=""; UI_YLW=""; UI_RED=""; UI_MAG=""
    UI_WHT=""; UI_GRY=""; UI_DIM=""; UI_RST=""
fi
# Reset alias used by newer scripts.
UI_R="$UI_RST"

# ── Terminal helpers ──────────────────────────────────────────
term_width() {
    tput cols 2>/dev/null || echo 80
}

center_text() {
    local text="$1"
    local width
    width=$(term_width)
    local pad=$(( (width - ${#text}) / 2 ))
    (( pad < 0 )) && pad=0
    printf "%*s%s\n" "$pad" "" "$text"
}

# ── Structural output ─────────────────────────────────────────
ui_blank() { printf '\n'; }
ui_clear() { clear 2>/dev/null || printf '\033c'; }

# Header box. $1 = title, $2 = optional subtitle (printed under the box).
ui_header() {
    clear 2>/dev/null || printf '\033c'

    local title="$1"
    local subtitle="${2:-}"
    local margin=2
    local padding=2   # space inside box left/right

    local text_len=${#title}
    local inner_width=$((text_len + padding * 2))

    local line
    line=$(printf "%-${inner_width}s" "" | tr ' ' '-')

    printf '%s' "$UI_CYN"
    printf "%*s+%s+\n" "$margin" "" "$line"
    printf "%*s|%*s%s%*s|\n" \
        "$margin" "" \
        "$padding" "" \
        "$title" \
        "$padding" ""
    printf "%*s+%s+\n" "$margin" "" "$line"
    printf '%s\n' "$UI_RST"

    if [[ -n "$subtitle" ]]; then
        printf '  %s%s%s\n' "$UI_GRY" "$subtitle" "$UI_RST"
    fi
}

# Menu item: ui_option KEY "Description"
ui_option() {
    printf "  ${UI_GRN}[%s]${UI_RST} %s\n" "$1" "$2"
}

# Label/value row: ui_row "Label" "Value" [color]
ui_row() {
    printf '  %s%-13s%s %s\n' "${3:-}" "$1" "$UI_RST" "$2"
}

# Section heading: ui_section "Title" [color]
ui_section() {
    printf '\n  %s== %s ==%s\n' "${2:-$UI_CYN}" "$1" "$UI_RST"
}

# Error line.
ui_error() {
    printf '  %sError:%s %s\n' "$UI_RED" "$UI_RST" "$1" >&2
}

# Full-width divider.
ui_divider() {
    printf "%*s\n" "$(term_width)" "" | tr ' ' '-'
}
