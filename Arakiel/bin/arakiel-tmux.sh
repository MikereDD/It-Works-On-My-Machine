#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# file:     ~/bin/arakiel-tmux.sh
# author:   Mike Redd
# version:  2.0
# desc:     tmux launcher for the Arakiel workspace, Raguel, and Telegram bots
# -----------------------------------------------------------------------------

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

KOKABIEL_DIR="$BASE/Kokabiel"
KOKABIEL_PYTHON="$KOKABIEL_DIR/.venv/bin/python"
KOKABIEL="$KOKABIEL_DIR/kokabiel.py"

GABRIEL="$BASE/Gabriel/gabriel.py"
FORWARDBOT="$BASE/Selaphiel/forwardbot.py"

die() {
    printf 'arakiel-tmux: %s\n' "$*" >&2

    if command -v tmux >/dev/null 2>&1; then
        tmux kill-session -t "$SESSION" 2>/dev/null || true
    fi

    exit 1
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 ||
        die "required command is not installed or not in PATH: $1"
}

require_dir() {
    [[ -d "$1" ]] ||
        die "required directory does not exist: $1"
}

require_file() {
    [[ -f "$1" ]] ||
        die "required file does not exist: $1"
}

require_exec() {
    [[ -x "$1" ]] ||
        die "required executable does not exist or is not executable: $1"
}

# tmux must exist before anything attempts to inspect or kill a session.
require_cmd tmux

# If the workspace is already running, simply attach to it.
if tmux has-session -t "$SESSION" 2>/dev/null; then
    exec tmux attach -t "$SESSION"
fi

# Commands needed while constructing the workspace or inside its panes.
for cmd in \
    "$PYTHON" \
    hermes \
    awk \
    sort \
    wc \
    tr \
    tee \
    mkdir \
    touch \
    ls
do
    require_cmd "$cmd"
done

# Required workspace and bot paths.
require_dir "$BASE"
require_dir "$WORKSPACE"
require_dir "$KOKABIEL_DIR"

require_file "$WORKSPACE/AGENTS.md"

require_exec "$VENV"
require_exec "$KOKABIEL_PYTHON"

require_file "$YTBOT"
require_file "$MUSICBOT"
require_file "$KOKABIEL"
require_file "$GABRIEL"
require_file "$FORWARDBOT"

# Ensure the log directory and files exist before any panes are started.
mkdir -p "$LOGS" "$LOGS/kokabiel" ||
    die "could not create log directories"

touch \
    "$LOGS/ytbot.log" \
    "$LOGS/musicbot.log" \
    "$LOGS/kokabiel/kokabiel.log" \
    "$LOGS/gabriel.log" \
    "$LOGS/forwardbot.log" ||
    die "could not create bot log files"

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
    C-m ||
    die "could not initialize main window"

# ── Window 2: Raguel / Hermes ────────────────────────────────
tmux new-window \
    -t "$SESSION:2" \
    -n Raguel ||
    die "could not create Raguel window"

# Launch Hermes from the dedicated workspace so AGENTS.md loads.
tmux send-keys \
    -t "$SESSION:2" \
    "cd '$WORKSPACE' && hermes" \
    C-m ||
    die "could not launch Hermes"

# ── Window 3: bots ───────────────────────────────────────────
tmux new-window \
    -t "$SESSION:3" \
    -n bots ||
    die "could not create bots window"

# Build an explicit 2-column × 3-row layout.
# Automatic tiled layouts can reorder pane numbers, so each column is
# constructed directly and roles are assigned afterward by visible position.

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

tmux split-window \
    -v \
    -d \
    -p 50 \
    -t "$LEFT_MIDDLE" \
    >/dev/null ||
    die "could not finish the left bot column"

RIGHT_MIDDLE="$(
    tmux split-window \
        -v \
        -d \
        -p 67 \
        -P \
        -F '#{pane_id}' \
        -t "$RIGHT_TOP"
)" || die "could not split the right bot column"

tmux split-window \
    -v \
    -d \
    -p 50 \
    -t "$RIGHT_MIDDLE" \
    >/dev/null ||
    die "could not finish the right bot column"

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
KOKABIEL_PANE="${PANE_IDS[2]}"
GABRIEL_PANE="${PANE_IDS[3]}"
FORWARD_PANE="${PANE_IDS[4]}"
LOGS_PANE="${PANE_IDS[5]}"

# Intended visible layout:
#
#   1 ytbot / Raziel          | 2 musicbot / Sandalphon
#   3 Kokabiel                | 4 gabriel / Gabriel
#   5 forwardbot / Selaphiel  | 6 logs

# Pane 1 → ytbot / Raziel
tmux send-keys \
    -t "$YT_PANE" \
    "cd '$BASE' && '$VENV' '$YTBOT' 2>&1 | tee -a '$LOGS/ytbot.log'" \
    C-m ||
    die "could not launch Raziel"

# Pane 2 → musicbot / Sandalphon
tmux send-keys \
    -t "$MUSIC_PANE" \
    "cd '$BASE' && '$PYTHON' '$MUSICBOT' 2>&1 | tee -a '$LOGS/musicbot.log'" \
    C-m ||
    die "could not launch Sandalphon"

# Pane 3 → Kokabiel
tmux send-keys \
    -t "$KOKABIEL_PANE" \
    "cd '$KOKABIEL_DIR' && '$KOKABIEL_PYTHON' '$KOKABIEL'" \
    C-m ||
    die "could not launch Kokabiel"

# Pane 4 → gabriel / Gabriel
tmux send-keys \
    -t "$GABRIEL_PANE" \
    "cd '$BASE' && '$VENV' '$GABRIEL' 2>&1 | tee -a '$LOGS/gabriel.log'" \
    C-m ||
    die "could not launch Gabriel"

# Pane 5 → forwardbot / Selaphiel
tmux send-keys \
    -t "$FORWARD_PANE" \
    "cd '$BASE' && '$PYTHON' '$FORWARDBOT' 2>&1 | tee -a '$LOGS/forwardbot.log'" \
    C-m ||
    die "could not launch Selaphiel"

# Pane 6 → logs shell
tmux send-keys \
    -t "$LOGS_PANE" \
    "cd '$LOGS' && ls -lah" \
    C-m ||
    die "could not initialize logs pane"

# ── Bot pane labels ──────────────────────────────────────────
# Use a tmux user option instead of pane_title because shells can
# overwrite pane_title while @label remains unchanged.

tmux setw \
    -t "$SESSION:3" \
    pane-border-status top ||
    die "could not enable bot pane labels"

tmux setw \
    -t "$SESSION:3" \
    pane-border-format \
    " #[fg=#81a1c1]#P#[fg=#d8dee9] #{@label} " ||
    die "could not configure bot pane labels"

tmux set -p -t "$YT_PANE" \
    @label "ytbot (Raziel)"

tmux set -p -t "$MUSIC_PANE" \
    @label "musicbot (Sandalphon)"

tmux set -p -t "$KOKABIEL_PANE" \
    @label "media guide (Kokabiel)"

tmux set -p -t "$GABRIEL_PANE" \
    @label "gabriel (Gabriel)"

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
    C-m ||
    die "could not initialize scratch window"

# Begin in the Raguel window.
tmux select-window -t "$SESSION:2" ||
    die "could not select Raguel window"

# Attach to the completed session.
exec tmux attach -t "$SESSION"
