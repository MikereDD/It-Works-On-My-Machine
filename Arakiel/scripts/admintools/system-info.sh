#!/usr/bin/env bash
# file:    system-info.sh
# version: 1.1

source "$HOME/lib/core.sh"
# core.sh enables errexit/nounset; relax for this simple report.
set +e +u 2>/dev/null || true

ui_header "SYSTEM INFO"

echo -e "${UI_CYN}Host:${UI_RST}    $(hostname)"
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
hostname -I 2>/dev/null || ip addr show | grep inet
echo

pause
