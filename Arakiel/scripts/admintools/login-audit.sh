#!/usr/bin/env bash
#--------------------------------------------
# file:    login-audit.sh
# author:  Mike Redd
# version: 1.0
# desc:    Login/security report: current sessions, recent logins,
#          failed attempts, and recent sshd auth activity.
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
SUDO=""; [[ "${EUID:-$(id -u)}" -ne 0 ]] && SUDO="sudo"

ui_header "LOGIN AUDIT"

ui_section "Currently logged in"
if have who; then who 2>/dev/null | sed 's/^/  /'; [[ -z "$(who 2>/dev/null)" ]] && printf '  %s(none)%s\n' "$UI_DIM" "$UI_R"
else printf '  %swho not available%s\n' "$UI_DIM" "$UI_R"; fi

ui_section "Recent logins"
if have last; then last -n 15 2>/dev/null | sed 's/^/  /'
else printf '  %slast not available%s\n' "$UI_DIM" "$UI_R"; fi

ui_section "Recent failed logins"
if have lastb; then
    out="$($SUDO lastb -n 15 2>/dev/null)"
    if [[ -n "$out" ]]; then printf '%s\n' "$out" | sed 's/^/  /'
    else printf '  %snone recorded (or needs root)%s\n' "$UI_DIM" "$UI_R"; fi
else printf '  %slastb not available%s\n' "$UI_DIM" "$UI_R"; fi

ui_section "Recent sshd auth activity"
if have journalctl; then
    $SUDO journalctl -u sshd -n 25 --no-pager 2>/dev/null \
        | grep -iE 'accepted|failed|invalid|disconnect' \
        | tail -n 15 | sed 's/^/  /' \
        || printf '  %sno recent sshd entries%s\n' "$UI_DIM" "$UI_R"
else
    printf '  %sjournalctl not available%s\n' "$UI_DIM" "$UI_R"
fi

echo
pause
