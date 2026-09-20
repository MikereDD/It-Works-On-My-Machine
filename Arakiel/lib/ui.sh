#!/usr/bin/env bash
# ============================================================================
# Arakiel shared terminal UI
# ============================================================================
# Script:       ui.sh
# Component:    Typezer∅ shell utilities / terminal presentation layer
# Platform:     Linux / Bash-compatible shell (Arakiel)
# Purpose:      Provide the shared terminal color API and presentation helpers
#               used by maintained Arakiel shell tools.
# Consumers:    Loaded by ~/lib/core.sh and may also be sourced directly by
#               scripts that only need the UI layer.
# Theme source: ~/.config/typezero/themeengine/current.sh
#
# Design notes:
#   - This file is the compatibility bridge between ThemeEngine and Arakiel's
#     existing UI_* shell API. Older scripts continue consuming UI_* variables
#     while the selected ThemeEngine palette supplies their semantic colors.
#   - Scripts should consume these shared helpers or UI_* values instead of
#     reading ThemeEngine runtime state themselves. Centralizing the mapping
#     keeps presentation consistent and prevents each script from inventing its
#     own theme integration.
#   - A built-in ANSI fallback remains necessary so tools still render
#     sensibly before ThemeEngine is bootstrapped, when the generated palette is
#     missing, or when ui.sh is used in isolation.
#   - ANSI styling is disabled when stdout is not a terminal. This keeps piped
#     or redirected output free of escape sequences.
#   - ThemeEngine owns appearance; scripts own behavior and content.
# ============================================================================

# ── Fallback terminal palette ───────────────────────────────────────────────
# These legacy UI_* variables are part of the shared Arakiel shell interface.
# ThemeEngine may replace their values later in this file, but callers should
# not need to know whether a color came from the fallback palette or a theme.
#
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
    # Non-interactive output should remain plain text so logs, pipes, command
    # substitution, and redirected output do not contain raw ANSI sequences.
    UI_CYN=""
    UI_GRN=""
    UI_YLW=""
    UI_RED=""
    UI_MAG=""
    UI_WHT=""
    UI_GRY=""
    UI_DIM=""
    UI_RST=""
fi

# ── ThemeEngine compatibility bridge ───────────────────────────────────────
# ThemeEngine renders the active semantic palette into current.sh. Sourcing it
# here lets maintained scripts inherit the selected theme without coupling
# themselves directly to ThemeEngine internals or runtime paths.
#
# The generated file intentionally reassigns the legacy UI_* variables above.
# If no generated palette exists, the fallback values remain in effect.
_themeengine_current="${XDG_CONFIG_HOME:-$HOME/.config}/typezero/themeengine/current.sh"
if [[ -r "$_themeengine_current" ]]; then
    # shellcheck source=/dev/null
    source "$_themeengine_current"
fi
unset _themeengine_current

# Historical shorthand retained for scripts that use UI_R as the reset token.
UI_R="$UI_RST"

# ── Terminal measurement helpers ────────────────────────────────────────────
# Return the current terminal width. Fall back to 80 columns when tput cannot
# determine it, such as in a minimal or partially initialized environment.
term_width() {
    tput cols 2>/dev/null || echo 80
}

# Center one line using visible string length. This helper assumes the supplied
# text does not contain ANSI escape sequences; colored callers should apply
# styling outside the text argument when accurate centering matters.
center_text() {
    local text="$1"
    local width
    local pad

    width=$(term_width)
    pad=$(( (width - ${#text}) / 2 ))
    (( pad < 0 )) && pad=0

    printf "%*s%s\n" "$pad" "" "$text"
}

# ── Structural output helpers ───────────────────────────────────────────────
# Emit one blank line. Keeping even small layout actions centralized makes
# menu-style tools read consistently and provides one place to change behavior
# later if needed.
ui_blank() {
    printf '\n'
}

# Clear the active terminal. The ANSI reset fallback is used when clear is not
# available, preserving expected menu behavior in smaller environments.
ui_clear() {
    clear 2>/dev/null || printf '\033c'
}

# Render the standard boxed title used by Arakiel menus and status tools.
# Subtitle is optional and intentionally uses the muted semantic color.
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

# Render a numbered or keyed menu option.
ui_option() {
    printf "  ${UI_GRN}[%s]${UI_RST} %s\n" "$1" "$2"
}

# Render a simple label/value row. The third argument may optionally supply the
# color for the label, allowing status tools to emphasize a particular row.
ui_row() {
    printf '  %s%-13s%s %s\n' "${3:-}" "$1" "$UI_RST" "$2"
}

# Render a lightweight section heading. Callers may override the section color;
# otherwise the shared cyan accent is used.
ui_section() {
    printf '\n  %s== %s ==%s\n' "${2:-$UI_CYN}" "$1" "$UI_RST"
}

# Emit a standardized error line to stderr so human-facing failures are both
# visually consistent and pipeline-friendly.
ui_error() {
    printf '  %sError:%s %s\n' "$UI_RED" "$UI_RST" "$1" >&2
}

# Draw a full-width divider using the current terminal width.
ui_divider() {
    printf "%*s\n" "$(term_width)" "" | tr ' ' '-'
}
