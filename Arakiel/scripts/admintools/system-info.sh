#!/usr/bin/env bash
# file:    system-info.sh
# version: 1.2

# shellcheck source=/dev/null
source "$HOME/lib/core.sh"
# core.sh enables errexit/nounset; relax for this simple report.
set +e +u 2>/dev/null || true

ui_header "SYSTEM INFO"

echo -e "${UI_CYN}Host:${UI_RST}    $(uname -n)"
echo -e "${UI_CYN}User:${UI_RST}    $USER"
echo -e "${UI_CYN}Kernel:${UI_RST}  $(uname -r)"
echo -e "${UI_CYN}Arch:${UI_RST}    $(uname -m)"
echo -e "${UI_CYN}Uptime:${UI_RST}  $(uptime -p)"
echo

ui_divider

echo -e "${UI_YLW}CPU:${UI_RST}"
if command -v lscpu >/dev/null 2>&1; then
    lscpu | grep -E 'Model name|CPU\(s\)|Architecture'
else
    echo "lscpu not available"
fi
echo

echo -e "${UI_YLW}Memory:${UI_RST}"
free -h || echo "free not available"
echo

echo -e "${UI_YLW}Disk:${UI_RST}"
df -h / || true
echo

echo -e "${UI_YLW}IP Addresses:${UI_RST}"
if command -v ip >/dev/null 2>&1; then
    ipv4="$(
        ip -4 route get 1.1.1.1 2>/dev/null |
            awk '{for (i=1; i<=NF; i++) if ($i=="src") {print $(i+1); exit}}'
    )"

    if [[ -n "$ipv4" ]]; then
        printf 'IPv4: %s\n' "$ipv4"
    else
        ip -brief addr show 2>/dev/null | grep -v '^lo' || true
    fi
else
    echo "ip command not available"
fi
echo

pause_return "Press Enter to return to Admin Tools..."
