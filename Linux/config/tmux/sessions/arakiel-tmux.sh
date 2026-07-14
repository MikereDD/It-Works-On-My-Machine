#!/usr/bin/env bash
# file: arakiel-tmux.sh
# version: 1.9.1
# desc: tmux loader for Arakiel workspace, Raguel, and bots

set -u

SESSION="arakiel"
BASE="/mnt/nvme1/work/bots"
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

# Ensure log directory and files exist.
mkdir -p "$LOGS"
touch \
    "$LOGS/ytbot.log" \
    "$LOGS/musicbot.log" \
    "$LOGS/aibot.log" \
    "$LOGS/cardbot.log" \
    "$LOGS/forwardbot.log"

# Create a generously sized detached session.
# The explicit dimensions prevent tmux from refusing later pane splits
# because a detached session initially appears too small.
tmux new-session -d -x 200 -y 60 -s "$SESSION" -n main ||
    die "could not create tmux session"

# ── Window 1: workspace ──────────────────────────────────────
tmux send-keys -t "$SESSION:1" "cd ~" C-m

# ── Window 2: Raguel / Hermes ────────────────────────────────
tmux new-window -t "$SESSION:2" -n Raguel ||
    die "could not create Raguel window"

tmux send-keys -t "$SESSION:2" "cd ~ && hermes" C-m

# ── Window 3: bots ───────────────────────────────────────────
tmux new-window -t "$SESSION:3" -n bots ||
    die "could not create bots window"

# Capture the original pane by its stable pane ID.
PANE_1="$(tmux display-message -p -t "$SESSION:3" '#{pane_id}')"
PANE_IDS=("$PANE_1")

# Create five more panes for six total.
# Reapply the tiled layout after every split so the active pane never
# becomes too small before all six panes have been created.
for pane_number in 2 3 4 5 6; do
    new_pane="$(
        tmux split-window \
            -d \
            -P \
            -F '#{pane_id}' \
            -t "$SESSION:3"
    )" || die "failed while creating bot pane $pane_number"

    PANE_IDS+=("$new_pane")

    tmux select-layout -t "$SESSION:3" tiled >/dev/null ||
        die "could not tile bot panes"
done

# Confirm all six panes actually exist before launching anything.
PANE_COUNT="$(tmux list-panes -t "$SESSION:3" | wc -l | tr -d ' ')"
[[ "$PANE_COUNT" == "6" ]] ||
    die "expected 6 bot panes, but tmux created $PANE_COUNT"

# Stable pane IDs avoid depending on pane-index numbering or reordering.
YT_PANE="${PANE_IDS[0]}"
MUSIC_PANE="${PANE_IDS[1]}"
AI_PANE="${PANE_IDS[2]}"
CARD_PANE="${PANE_IDS[3]}"
FORWARD_PANE="${PANE_IDS[4]}"
LOGS_PANE="${PANE_IDS[5]}"

# Pane 1 → ytbot / Raziel (venv)
tmux send-keys -t "$YT_PANE" \
    "cd '$BASE' && '$VENV' '$YTBOT' 2>&1 | tee -a '$LOGS/ytbot.log'" C-m

# Pane 2 → musicbot / Sandalphon (system Python)
tmux send-keys -t "$MUSIC_PANE" \
    "cd '$BASE' && $PYTHON '$MUSICBOT' 2>&1 | tee -a '$LOGS/musicbot.log'" C-m

# Pane 3 → aibot / Zahkiel (system Python)
tmux send-keys -t "$AI_PANE" \
    "cd '$BASE' && $PYTHON '$AIBOT' 2>&1 | tee -a '$LOGS/aibot.log'" C-m

# Pane 4 → cardbot / Gabriel (venv)
tmux send-keys -t "$CARD_PANE" \
    "cd '$BASE' && '$VENV' '$CARDBOT' 2>&1 | tee -a '$LOGS/cardbot.log'" C-m

# Pane 5 → forwardbot / Selaphiel (system Python)
tmux send-keys -t "$FORWARD_PANE" \
    "cd '$BASE' && $PYTHON '$FORWARDBOT' 2>&1 | tee -a '$LOGS/forwardbot.log'" C-m

# Pane 6 → logs shell
tmux send-keys -t "$LOGS_PANE" \
    "cd '$LOGS' && ls -lah" C-m

# ── Label panes on their borders ─────────────────────────────
# Use a tmux user option (@label) instead of pane_title: the shell
# prompt overwrites pane_title, but it does not touch @label.
tmux setw -t "$SESSION:3" pane-border-status top
tmux setw -t "$SESSION:3" \
    pane-border-format " #[fg=#81a1c1]#P#[fg=#d8dee9] #{@label} "

tmux set -p -t "$YT_PANE"      @label "ytbot (Raziel)"
tmux set -p -t "$MUSIC_PANE"   @label "musicbot (Sandalphon)"
tmux set -p -t "$AI_PANE"      @label "aibot (Zahkiel)"
tmux set -p -t "$CARD_PANE"    @label "cardbot (Gabriel)"
tmux set -p -t "$FORWARD_PANE" @label "forwardbot (Selaphiel)"
tmux set -p -t "$LOGS_PANE"    @label "logs"

# Reapply the final six-pane layout after labels and commands are set.
tmux select-layout -t "$SESSION:3" tiled >/dev/null

# ── Window 4: scratch ────────────────────────────────────────
tmux new-window -t "$SESSION:4" -n scratch ||
    die "could not create scratch window"

tmux send-keys -t "$SESSION:4" "cd ~" C-m

# Start in the Raguel window.
tmux select-window -t "$SESSION:2"

# Attach.
exec tmux attach -t "$SESSION"

