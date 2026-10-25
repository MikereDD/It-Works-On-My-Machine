#!/usr/bin/env bash
#--------------------------------------------
# file:    net-monitor.sh
# author:  Mike Redd
# version: 1.0
# desc:    Connectivity report: default route, gateway + internet
#          latency/loss, DNS resolution, and an optional mtr trace.
#--------------------------------------------

LIB_DIR="${LIB_DIR:-$HOME/lib}"
if [[ -f "$LIB_DIR/core.sh" ]]; then
    # shellcheck source=/dev/null
    source <(sed 's/\r$//' "$LIB_DIR/core.sh")
else
    echo "Error: core.sh not found in $LIB_DIR" >&2; exit 1
fi
set +e +u 2>/dev/null || true

have() { command -v "$1" >/dev/null 2>&1; }
TARGET="${NET_TARGET:-1.1.1.1}"
DNS_HOST="${NET_DNS_HOST:-archlinux.org}"

gateway() {
    ip route 2>/dev/null | awk '/^default/{print $3; exit}'
}

ping_stats() {   # <host> <label>
    local host="$1" label="$2"
    [[ -z "$host" ]] && { ui_row "$label" "no host" "$UI_YLW"; return; }
    if ! have ping; then ui_row "$label" "ping not found" "$UI_RED"; return; fi
    local out loss rtt
    out="$(ping -c 4 -W 2 "$host" 2>/dev/null)"
    loss="$(printf '%s\n' "$out" | grep -oE '[0-9]+% packet loss' | head -1)"
    rtt="$(printf '%s\n' "$out" | awk -F'/' '/rtt|round-trip/{print $5" ms avg"}')"
    if [[ -n "$rtt" ]]; then
        ui_row "$label" "${rtt} (${loss:-0% loss})" "$UI_GRN"
    else
        ui_row "$label" "unreachable (${loss:-100% packet loss})" "$UI_RED"
    fi
}

ui_header "NET MONITOR"

gw="$(gateway)"
ui_row "Default route" "$(ip route 2>/dev/null | awk '/^default/{print $0; exit}')" "$UI_GRY"
ui_row "Gateway" "${gw:-unknown}" "$UI_CYN"

ui_section "Latency / loss"
ping_stats "$gw" "Gateway"
ping_stats "$TARGET" "Internet ($TARGET)"

ui_section "DNS resolution"
if have getent; then
    res="$(getent hosts "$DNS_HOST" 2>/dev/null | awk '{print $1}' | head -1)"
elif have host; then
    res="$(host "$DNS_HOST" 2>/dev/null | awk '/has address/{print $4; exit}')"
fi
if [[ -n "${res:-}" ]]; then
    ui_row "$DNS_HOST" "$res" "$UI_GRN"
else
    ui_row "$DNS_HOST" "resolution failed" "$UI_RED"
fi

ui_section "Interfaces"
ip -brief addr 2>/dev/null | sed 's/^/  /' || ip addr 2>/dev/null | grep -E 'inet ' | sed 's/^/  /'

echo
if have mtr; then
    read -rp "Run an mtr trace to $TARGET? (y/N): " ok
    [[ "${ok,,}" == "y" ]] && mtr -r -c 10 "$TARGET" 2>/dev/null | sed 's/^/  /'
fi

echo
pause
