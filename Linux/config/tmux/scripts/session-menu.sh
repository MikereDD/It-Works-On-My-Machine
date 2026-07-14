#!/usr/bin/env bash
set -euo pipefail

if ! command -v fzf >/dev/null 2>&1; then
    # Replace this popup with tmux's native chooser.
    tmux display-message "fzf not installed — opening native chooser"
    tmux choose-tree -Zw
    exit 0
fi

selection="$(
    tmux list-sessions \
        -F '#{session_name} | #{session_windows} windows | attached=#{session_attached}' |
    fzf --prompt='session> ' --height=100% --reverse --border=none
)"

[[ -n "$selection" ]] || exit 0
session="${selection%% |*}"
tmux switch-client -t "$session"
