#!/usr/bin/env bash
set -euo pipefail

pane_id="${1:-}"
[[ -n "$pane_id" ]] || {
    tmux display-message "No pane ID supplied"
    exit 1
}

if ! tmux display-message -p -t "$pane_id" '#{pane_id}' >/dev/null 2>&1; then
    tmux display-message "Pane no longer exists: $pane_id"
    exit 1
fi

title="$(tmux display-message -p -t "$pane_id" '#{pane_title}')"
path="$(tmux display-message -p -t "$pane_id" '#{pane_current_path}')"
start_command="$(tmux display-message -p -t "$pane_id" '#{pane_start_command}')"

if [[ -n "$start_command" ]]; then
    tmux respawn-pane -k -t "$pane_id" -c "$path" "$start_command"
else
    tmux respawn-pane -k -t "$pane_id" -c "$path"
fi

tmux select-pane -t "$pane_id" -T "$title"
tmux display-message "Restarted pane: ${title:-$pane_id}"
