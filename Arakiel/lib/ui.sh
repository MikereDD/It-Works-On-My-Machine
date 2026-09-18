#!/usr/bin/env bash
# file: ui.sh
# version: 1.2
# Shared UI helpers. ThemeEngine may override the default ANSI palette through
# ~/.config/typezero/themeengine/current.sh.

# ── Colors ────────────────────────────────────────────────────
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

# ThemeEngine override. Existing scripts keep consuming their legacy UI_*
# variables, but those variables now inherit the selected semantic theme.
_themeengine_current="${XDG_CONFIG_HOME:-$HOME/.config}/typezero/themeengine/current.sh"
if [[ -r "$_themeengine_current" ]]; then
    # shellcheck source=/dev/null
    source "$_themeengine_current"
fi
unset _themeengine_current

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

# ── Structural output ──────────────────────────────────────────
ui_blank() { printf '\n'; }
ui_clear() { clear 2>/dev/null || printf '\033c'; }

ui_header() {
    clear 2>/dev/null || printf '\033c'

    local title="$1"
    local subtitle="${2:-}"
    local margin=2
    local padding=2

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

ui_option() {
    printf "  ${UI_GRN}[%s]${UI_RST} %s\n" "$1" "$2"
}

ui_row() {
    printf '  %s%-13s%s %s\n' "${3:-}" "$1" "$UI_RST" "$2"
}

ui_section() {
    printf '\n  %s== %s ==%s\n' "${2:-$UI_CYN}" "$1" "$UI_RST"
}

ui_error() {
    printf '  %sError:%s %s\n' "$UI_RED" "$UI_RST" "$1" >&2
}

ui_divider() {
    printf "%*s\n" "$(term_width)" "" | tr ' ' '-'
}
