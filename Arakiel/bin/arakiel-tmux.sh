#!/usr/bin/env bash
# file: arakiel-tmux.sh
# version: 1.9.5
# desc: tmux loader for Arakiel workspace, Raguel, bots, and Raziel service log

set -u

SESSION="arakiel"

BASE="$HOME/bots"
WORKSPACE="$HOME/dev/Hermes-Workspace"

VENV="$BASE/venv/bin/python"
PYTHON="python3"
LOGS="$BASE/logs"

MUSICBOT="$BASE/Sandalphon/musicbot.py"
KOKABIEL_DIR="$BASE/Kokabiel"
KOKABIEL_PYTHON="$KOKABIEL_DIR/.venv/bin/python"
KOKABIEL="$KOKABIEL_DIR/kokabiel.py"
GABRIEL="$BASE/Gabriel/gabriel.py"
FORWARDBOT="$BASE/Selaphiel/forwardbot.py"

die() {
    printf 'arakiel-tmux: %s\n' "$*" >&2
    tmux kill-session -t "$SESSION" 2>/dev/null || true
    exit 1
}

if tmux has-session -t "$SESSION" 2>/dev/null; then
    exec tmux attach -t "$SESSION"
fi

command -v tmux >/dev/null 2>&1 || die "tmux is not installed or not in PATH"
command -v "$PYTHON" >/dev/null 2>&1 || die "$PYTHON is not installed or not in PATH"
command -v journalctl >/dev/null 2>&1 || die "journalctl is not installed or not in PATH"

[[ -d "$BASE" ]] || die "bot directory does not exist: $BASE"
[[ -d "$WORKSPACE" ]] || die "Hermes workspace does not exist: $WORKSPACE"
[[ -f "$WORKSPACE/AGENTS.md" ]] || die "Hermes workspace context is missing: $WORKSPACE/AGENTS.md"
[[ -x "$VENV" ]] || die "bot virtual-environment Python is missing: $VENV"
[[ -x "$KOKABIEL_PYTHON" ]] || die "Kokabiel virtual-environment Python is missing: $KOKABIEL_PYTHON"
[[ -f "$KOKABIEL" ]] || die "Kokabiel launcher is missing: $KOKABIEL"

systemctl list-unit-files raziel.service >/dev/null 2>&1 ||
    die "Raziel systemd service is not installed"

mkdir -p "$LOGS" "$LOGS/kokabiel"

touch \
    "$LOGS/musicbot.log" \
    "$LOGS/kokabiel/kokabiel.log" \
    "$LOGS/gabriel.log" \
    "$LOGS/forwardbot.log"

tmux new-session -d -x 200 -y 60 -s "$SESSION" -n main ||
    die "could not create tmux session"

tmux send-keys -t "$SESSION:1" "cd '$HOME'" C-m

tmux new-window -t "$SESSION:2" -n Raguel ||
    die "could not create Raguel window"

tmux send-keys -t "$SESSION:2" "cd '$WORKSPACE' && hermes" C-m

tmux new-window -t "$SESSION:3" -n bots ||
    die "could not create bots window"

LEFT_TOP="$(
    tmux display-message -p -t "$SESSION:3" '#{pane_id}'
)" || die "could not identify the initial bot pane"

RIGHT_TOP="$(
    tmux split-window -h -d -p 50 -P -F '#{pane_id}' -t "$LEFT_TOP"
)" || die "could not create the right bot column"

LEFT_MIDDLE="$(
    tmux split-window -v -d -p 67 -P -F '#{pane_id}' -t "$LEFT_TOP"
)" || die "could not split the left bot column"

LEFT_BOTTOM="$(
    tmux split-window -v -d -p 50 -P -F '#{pane_id}' -t "$LEFT_MIDDLE"
)" || die "could not finish the left bot column"

RIGHT_MIDDLE="$(
    tmux split-window -v -d -p 67 -P -F '#{pane_id}' -t "$RIGHT_TOP"
)" || die "could not split the right bot column"

RIGHT_BOTTOM="$(
    tmux split-window -v -d -p 50 -P -F '#{pane_id}' -t "$RIGHT_MIDDLE"
)" || die "could not finish the right bot column"

PANE_COUNT="$(
    tmux list-panes -t "$SESSION:3" | wc -l | tr -d ' '
)"

[[ "$PANE_COUNT" == "6" ]] ||
    die "expected 6 bot panes, but tmux created $PANE_COUNT"

mapfile -t PANE_IDS < <(
    tmux list-panes -t "$SESSION:3" -F '#{pane_top} #{pane_left} #{pane_id}' |
        sort -n -k1,1 -k2,2 |
        awk '{print $3}'
)

[[ "${#PANE_IDS[@]}" == "6" ]] ||
    die "could not determine the final six-pane display order"

RAZIEL_PANE="${PANE_IDS[0]}"
MUSIC_PANE="${PANE_IDS[1]}"
KOKABIEL_PANE="${PANE_IDS[2]}"
GABRIEL_PANE="${PANE_IDS[3]}"
FORWARD_PANE="${PANE_IDS[4]}"
LOGS_PANE="${PANE_IDS[5]}"

# Raziel is supervised by systemd now; tmux only displays its journal.
tmux send-keys -t "$RAZIEL_PANE" \
    "journalctl -u raziel.service -n 100 -f" C-m

tmux send-keys -t "$MUSIC_PANE" \
    "cd '$BASE' && '$PYTHON' '$MUSICBOT' 2>&1 | tee -a '$LOGS/musicbot.log'" C-m

tmux send-keys -t "$KOKABIEL_PANE" \
    "cd '$KOKABIEL_DIR' && '$KOKABIEL_PYTHON' '$KOKABIEL'" C-m

tmux send-keys -t "$GABRIEL_PANE" \
    "cd '$BASE' && '$VENV' '$GABRIEL' 2>&1 | tee -a '$LOGS/gabriel.log'" C-m

tmux send-keys -t "$FORWARD_PANE" \
    "cd '$BASE' && '$PYTHON' '$FORWARDBOT' 2>&1 | tee -a '$LOGS/forwardbot.log'" C-m

tmux send-keys -t "$LOGS_PANE" \
    "cd '$LOGS' && ls -lah" C-m

tmux setw -t "$SESSION:3" pane-border-status top
tmux setw -t "$SESSION:3" pane-border-format " #[fg=#81a1c1]#P#[fg=#d8dee9] #{@label} "

tmux set -p -t "$RAZIEL_PANE" @label "Raziel (systemd log)"
tmux set -p -t "$MUSIC_PANE" @label "Sandalphon"
tmux set -p -t "$KOKABIEL_PANE" @label "Kokabiel"
tmux set -p -t "$GABRIEL_PANE" @label "Gabriel"
tmux set -p -t "$FORWARD_PANE" @label "Selaphiel"
tmux set -p -t "$LOGS_PANE" @label "logs"

tmux new-window -t "$SESSION:4" -n scratch ||
    die "could not create scratch window"

tmux send-keys -t "$SESSION:4" "cd '$HOME'" C-m

tmux select-window -t "$SESSION:2"

exec tmux attach -t "$SESSION"

