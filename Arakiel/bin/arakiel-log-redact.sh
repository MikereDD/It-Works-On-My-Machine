#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# file:     ~/bin/arakiel-log-redact.sh
# author:   Mike Redd
# version:  1.1
# desc:     Redact private/sensitive values from Arakiel tmux log displays
#
# This filters DISPLAY output only. Raw service/file logs remain unchanged.
# -----------------------------------------------------------------------------

set -o pipefail

sed -u -E \
    -e 's#(/bot)[0-9]+:[A-Za-z0-9_-]+#\1<redacted>#g' \
    -e 's#[0-9]{6,12}:[A-Za-z0-9_-]{20,}#<telegram-token>#g' \
    -e 's#^(Authorization[[:space:]]*:[[:space:]]*).*$#\1<redacted>#I' \
    -e 's#("authorization"[[:space:]]*:[[:space:]]*)"[^"]*"#\1"<redacted>"#gI' \
    -e 's#(authorization[[:space:]]*=[[:space:]]*)[^[:space:],;]+#\1<redacted>#gI' \
    -e 's#(Bearer[[:space:]]+)[A-Za-z0-9._~+/-]+=*#\1<redacted>#gI' \
    -e 's#("?(bot_token|token|api[_-]?key|secret|password)"?[[:space:]]*[:=][[:space:]]*)"?[^"[:space:],;]+"?#\1<redacted>#gI' \
    -e 's#("?(chat_id|user_id|sender_id|from_id|peer_id|message_thread_id|username|first_name|last_name|phone_number)"?[[:space:]]*[:=][[:space:]]*)("[^"]*"|-?[0-9]+|[^[:space:],;]+)#\1<redacted>#gI' \
    -e 's#("?(text|caption|message_text)"?[[:space:]]*[:=][[:space:]]*)"[^"]*"#\1"<redacted>"#gI' \
    -e 's#((text|caption|message_text)[[:space:]]*=[[:space:]]*).*$#\1<redacted>#gI'
