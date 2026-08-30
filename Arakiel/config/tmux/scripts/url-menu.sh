#!/usr/bin/env bash
set -euo pipefail

pane_id="${1:-}"
[[ -n "$pane_id" ]] || {
    printf 'No pane ID supplied.\n' >&2
    exit 1
}

tmp_file="$(mktemp)"
trap 'rm -f "$tmp_file"' EXIT

tmux capture-pane -p -J -S -5000 -t "$pane_id" >"$tmp_file"

if command -v urlscan >/dev/null 2>&1; then
    exec urlscan <"$tmp_file"
fi

if command -v urlview >/dev/null 2>&1; then
    exec urlview "$tmp_file"
fi

mapfile -t urls < <(
    grep -Eo 'https?://[^][(){}<>[:space:]"'"'"']+' "$tmp_file" |
    sort -u
)

if ((${#urls[@]} == 0)); then
    printf 'No URLs found in the current pane history.\n'
    printf '\nPress Enter to close...'
    read -r _
    exit 0
fi

if command -v fzf >/dev/null 2>&1; then
    selected="$(printf '%s\n' "${urls[@]}" | fzf --prompt='url> ' --reverse)"
    [[ -n "${selected:-}" ]] || exit 0
    printf '%s' "$selected" | tmux load-buffer -
    tmux display-message "URL copied to tmux buffer"
    exit 0
fi

printf 'URLs found:\n\n'
printf '%s\n' "${urls[@]}"
printf '\nInstall urlscan for interactive opening or fzf for selection.\n'
printf 'Press Enter to close...'
read -r _
