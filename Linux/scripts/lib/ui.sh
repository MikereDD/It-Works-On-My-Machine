#!/usr/bin/env bash
# file: ui.sh
# version: 1.0

# Colors
UI_CYN="\033[1;36m"
UI_GRN="\033[1;32m"
UI_YLW="\033[1;33m"
UI_RED="\033[1;31m"
UI_RST="\033[0m"

# Get terminal width
term_width() {
    tput cols 2>/dev/null || echo 80
}

# Center text
center_text() {
    local text="$1"
    local width
    width=$(term_width)
    local pad=$(( (width - ${#text}) / 2 ))
    printf "%*s%s\n" "$pad" "" "$text"
}

ui_header() {
    clear

    local title="$1"
    local margin=2
    local padding=2   # space inside box left/right

    local text_len=${#title}
    local inner_width=$((text_len + padding * 2))

    local line
    line=$(printf "%-${inner_width}s" "" | tr ' ' '-')

    echo -e "${UI_CYN}"
    printf "%*s+%s+\n" "$margin" "" "$line"
    printf "%*s|%*s%s%*s|\n" \
        "$margin" "" \
        "$padding" "" \
        "$title" \
        "$padding" ""
    printf "%*s+%s+\n" "$margin" "" "$line"
    echo -e "${UI_RST}"
}

# Menu item
ui_option() {
    printf "  ${UI_GRN}[%s]${UI_RST} %s\n" "$1" "$2"
}

# Error
ui_error() {
    echo -e "${UI_RED}Error:${UI_RST} $1"
}

# Section divider
ui_divider() {
    printf "%*s\n" "$(term_width)" "" | tr ' ' '-'
}
