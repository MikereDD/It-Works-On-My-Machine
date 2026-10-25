#!/usr/bin/env bash
#--------------------------------------------
# file:    logview.sh
# author:  Mike Redd
# version: 1.0
# desc:    Quick log viewer: journal errors, this boot, a chosen
#          service, kernel ring buffer, and hardware/throttle warnings.
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
PAGER_CMD="cat"; have less && PAGER_CMD="less -R"

errors_this_boot() {
    have journalctl || { core_error "journalctl not found"; pause; return; }
    journalctl -b -p err --no-pager 2>/dev/null | $PAGER_CMD
    pause
}
full_boot() {
    have journalctl || { core_error "journalctl not found"; pause; return; }
    journalctl -b -n 200 --no-pager 2>/dev/null | $PAGER_CMD
    pause
}
service_log() {
    have journalctl || { core_error "journalctl not found"; pause; return; }
    read -rp "  Service/unit name (e.g. sshd, NetworkManager): " unit
    [[ -z "$unit" ]] && return
    journalctl -u "$unit" -n 100 --no-pager 2>/dev/null | $PAGER_CMD
    pause
}
kernel_ring() {
    if have dmesg; then
        ( dmesg --color=never 2>/dev/null || sudo dmesg 2>/dev/null ) | tail -n 200 | $PAGER_CMD
    else
        core_error "dmesg not found"
    fi
    pause
}
hw_warnings() {
    ui_header "HARDWARE / THROTTLE WARNINGS"
    if have dmesg; then
        ( dmesg 2>/dev/null || sudo dmesg 2>/dev/null ) \
            | grep -iE 'throttl|voltage|temperature|hwmon|nvme|pcie|firmware' \
            | tail -n 40 | sed 's/^/  /' \
            || printf '  %sNothing notable.%s\n' "$UI_DIM" "$UI_R"
    else
        printf '  %sdmesg not available.%s\n' "$UI_DIM" "$UI_R"
    fi
    echo; pause
}

while true; do
    ui_header "LOG VIEWER"
    ui_option "1" "Errors this boot"
    ui_option "2" "Recent log (this boot)"
    ui_option "3" "A specific service"
    ui_option "4" "Kernel ring buffer (dmesg)"
    ui_option "5" "Hardware / throttle warnings"
    ui_option "q" "Back"
    echo
    read -rp "Select option: " choice
    case "$choice" in
        1) errors_this_boot ;;
        2) full_boot ;;
        3) service_log ;;
        4) kernel_ring ;;
        5) hw_warnings ;;
        q|Q) break ;;
        *) core_error "Invalid option"; sleep 1 ;;
    esac
done
