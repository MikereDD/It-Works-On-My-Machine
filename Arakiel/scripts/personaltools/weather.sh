#!/usr/bin/env bash
# file:    weather.sh
# version: 1.1

source "$HOME/lib/core.sh"

DEFAULT_LOCATION="Houston"

ui_header "WEATHER"

read -rp "Location [$DEFAULT_LOCATION]: " location
location="${location:-$DEFAULT_LOCATION}"

# URL encode spaces
location_encoded=$(echo "$location" | sed 's/ /+/g')

echo
echo -e "${UI_CYN}Fetching weather for:${UI_RST} $location"
echo

if ! curl -s "wttr.in/${location_encoded}?format=3"; then
    ui_error "Failed to fetch weather"
    pause
    exit 1
fi

echo
echo

read -rp "Show full forecast? [y/N]: " full

case "$full" in
    y|Y)
        echo
        curl -s "wttr.in/${location_encoded}"
        echo
        ;;
esac

pause
