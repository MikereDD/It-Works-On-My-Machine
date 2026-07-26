#!/usr/bin/env bash
# file: arakiel-tmux.sh
# version: 1.9.3
# desc: tmux loader for Arakiel workspace, Raguel, and bots

set -u

SESSION="arakiel"

# User-facing symlinks resolve to the NVMe-backed directories.
BASE="$HOME/bots"
WORKSPACE="$HOME/dev/Hermes-Workspace"

VENV="$BASE/venv/bin/python"
PYTHON="python3"
LOGS="$BASE/logs"

YTBOT="$BASE/Raziel/ytbot.py"
MUSICBOT="$BASE/Sandalphon/musicbot.py"
AIBOT="$BASE/Zahkiel/aibot.py"
CARDBOT="$BASE/Gabriel/cardbot.py"
FORWARDBOT="$BASE/Selaphiel/forwardbot.py"

die() {
    printf 'arakiel-tmux: %s\n' "$*" >&2
    tmux kill-session -t "$SESSION" 2>/dev/null || true
    exit 1
}

# Attach if the session already exists.
if tmux has-session -t "$SESSION" 2>/dev/null; then
    exec tmux attach -t "$SESSION"
fi

# Verify required commands and directories.
command -v tmux >/dev/null 2>&1 ||
    die "tmux is not installed or not in PATH"

command -v "$PYTHON" >/dev/null 2>&1 ||
    die "$PYTHON is not installed or not in PATH"

[[ -d "$BASE" ]] ||
    die "bot directory does not exist: $BASE"

[[ -d "$WORKSPACE" ]] ||
    die "Hermes workspace does not exist: $WORKSPACE"

[[ -f "$WORKSPACE/AGENTS.md" ]] ||
    die "Hermes workspace context is missing: $WORKSPACE/AGENTS.md"

[[ -x "$VENV" ]] ||
    die "bot virtual-environment Python is missing: $VENV"

# Ensure the log directory and files exist.
mkdir -p "$LOGS"

touch \
    "$LOGS/ytbot.log" \
    "$LOGS/musicbot.log" \
    "$LOGS/aibot.log" \
    "$LOGS/cardbot.log" \
    "$LOGS/forwardbot.log"

# Create a generously sized detached session.
# Explicit dimensions prevent pane splits from failing while detached.
tmux new-session \
    -d \
    -x 200 \
    -y 60 \
    -s "$SESSION" \
    -n main ||
    die "could not create tmux session"

# ── Window 1: main workspace ─────────────────────────────────
tmux send-keys \
    -t "$SESSION:1" \
    "cd '$HOME'" \
    C-m

# ── Window 2: Raguel / Hermes ────────────────────────────────
tmux new-window \
    -t "$SESSION:2" \
    -n Raguel ||
    die "could not create Raguel window"

# Launch Hermes from the dedicated workspace so AGENTS.md loads.
tmux send-keys \
    -t "$SESSION:2" \
    "cd '$WORKSPACE' && hermes" \
    C-m

# ── Window 3: bots ───────────────────────────────────────────
tmux new-window \
    -t "$SESSION:3" \
    -n bots ||
    die "could not create bots window"

# Build an explicit 2-column × 3-row layout.
# Automatic tiled layouts can reorder pane numbers, so each column
# is constructed directly and roles are assigned by final position.

LEFT_TOP="$(
    tmux display-message \
        -p \
        -t "$SESSION:3" \
        '#{pane_id}'
)" || die "could not identify the initial bot pane"

RIGHT_TOP="$(
    tmux split-window \
        -h \
        -d \
        -p 50 \
        -P \
        -F '#{pane_id}' \
        -t "$LEFT_TOP"
)" || die "could not create the right bot column"

LEFT_MIDDLE="$(
    tmux split-window \
        -v \
        -d \
        -p 67 \
        -P \
        -F '#{pane_id}' \
        -t "$LEFT_TOP"
)" || die "could not split the left bot column"

LEFT_BOTTOM="$(
    tmux split-window \
        -v \
        -d \
        -p 50 \
        -P \
        -F '#{pane_id}' \
        -t "$LEFT_MIDDLE"
)" || die "could not finish the left bot column"

RIGHT_MIDDLE="$(
    tmux split-window \
        -v \
        -d \
        -p 67 \
        -P \
        -F '#{pane_id}' \
        -t "$RIGHT_TOP"
)" || die "could not split the right bot column"

RIGHT_BOTTOM="$(
    tmux split-window \
        -v \
        -d \
        -p 50 \
        -P \
        -F '#{pane_id}' \
        -t "$RIGHT_MIDDLE"
)" || die "could not finish the right bot column"

# Confirm that all six panes were created.
PANE_COUNT="$(
    tmux list-panes -t "$SESSION:3" |
        wc -l |
        tr -d ' '
)"

[[ "$PANE_COUNT" == "6" ]] ||
    die "expected 6 bot panes, but tmux created $PANE_COUNT"

# Sort panes by visible position:
# top-left, top-right, middle-left, middle-right,
# bottom-left, bottom-right.
mapfile -t PANE_IDS < <(
    tmux list-panes \
        -t "$SESSION:3" \
        -F '#{pane_top} #{pane_left} #{pane_id}' |
        sort -n -k1,1 -k2,2 |
        awk '{print $3}'
)

[[ "${#PANE_IDS[@]}" == "6" ]] ||
    die "could not determine the final six-pane display order"

YT_PANE="${PANE_IDS[0]}"
MUSIC_PANE="${PANE_IDS[1]}"
AI_PANE="${PANE_IDS[2]}"
CARD_PANE="${PANE_IDS[3]}"
FORWARD_PANE="${PANE_IDS[4]}"
LOGS_PANE="${PANE_IDS[5]}"

# Intended visible layout:
#
#   1 ytbot / Raziel          | 2 musicbot / Sandalphon
#   3 aibot / Zahkiel         | 4 cardbot / Gabriel
#   5 forwardbot / Selaphiel  | 6 logs

# Pane 1 → ytbot / Raziel
tmux send-keys \
    -t "$YT_PANE" \
    "cd '$BASE' && '$VENV' '$YTBOT' 2>&1 | tee -a '$LOGS/ytbot.log'" \
    C-m

# Pane 2 → musicbot / Sandalphon
tmux send-keys \
    -t "$MUSIC_PANE" \
    "cd '$BASE' && '$PYTHON' '$MUSICBOT' 2>&1 | tee -a '$LOGS/musicbot.log'" \
    C-m

# Pane 3 → aibot / Zahkiel
tmux send-keys \
    -t "$AI_PANE" \
    "cd '$BASE' && '$PYTHON' '$AIBOT' 2>&1 | tee -a '$LOGS/aibot.log'" \
    C-m

# Pane 4 → cardbot / Gabriel
tmux send-keys \
    -t "$CARD_PANE" \
    "cd '$BASE' && '$VENV' '$CARDBOT' 2>&1 | tee -a '$LOGS/cardbot.log'" \
    C-m

# Pane 5 → forwardbot / Selaphiel
tmux send-keys \
    -t "$FORWARD_PANE" \
    "cd '$BASE' && '$PYTHON' '$FORWARDBOT' 2>&1 | tee -a '$LOGS/forwardbot.log'" \
    C-m

# Pane 6 → logs shell
tmux send-keys \
    -t "$LOGS_PANE" \
    "cd '$LOGS' && ls -lah" \
    C-m

# ── Bot pane labels ──────────────────────────────────────────
# Use a tmux user option instead of pane_title because shells can
# overwrite pane_title while @label remains unchanged.

tmux setw \
    -t "$SESSION:3" \
    pane-border-status top

tmux setw \
    -t "$SESSION:3" \
    pane-border-format \
    " #[fg=#81a1c1]#P#[fg=#d8dee9] #{@label} "

tmux set -p -t "$YT_PANE" \
    @label "ytbot (Raziel)"

tmux set -p -t "$MUSIC_PANE" \
    @label "musicbot (Sandalphon)"

tmux set -p -t "$AI_PANE" \
    @label "aibot (Zahkiel)"

tmux set -p -t "$CARD_PANE" \
    @label "cardbot (Gabriel)"

tmux set -p -t "$FORWARD_PANE" \
    @label "forwardbot (Selaphiel)"

tmux set -p -t "$LOGS_PANE" \
    @label "logs"

# ── Window 4: scratch ────────────────────────────────────────
tmux new-window \
    -t "$SESSION:4" \
    -n scratch ||
    die "could not create scratch window"

tmux send-keys \
    -t "$SESSION:4" \
    "cd '$HOME'" \
    C-m

# Begin in the Raguel window.
tmux select-window -t "$SESSION:2"

# Attach to the completed session.
exec tmux attach -t "$SESSION"
