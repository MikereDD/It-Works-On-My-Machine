#!/usr/bin/env bash
# file: arakiel-tmux.sh
# version: 1.8
# desc: tmux loader for Arakiel workspace, Raguel, and bots

SESSION="arakiel"
BASE="/mnt/nvme1/work/bots"
VENV="$BASE/venv/bin/python"
PYTHON="python3"
LOGS="$BASE/logs"

YTBOT="$BASE/Raziel/ytbot.py"
MUSICBOT="$BASE/Sandalphon/musicbot.py"
AIBOT="$BASE/Zahkiel/aibot.py"
CARDBOT="$BASE/Gabriel/cardbot.py"

# Attach if session exists
if tmux has-session -t "$SESSION" 2>/dev/null; then
  exec tmux attach -t "$SESSION"
fi

# Ensure logs exist
mkdir -p "$LOGS"
touch "$LOGS/ytbot.log"
touch "$LOGS/musicbot.log"
touch "$LOGS/aibot.log"
touch "$LOGS/cardbot.log"

# Create session
tmux new-session -d -s "$SESSION" -n main

# ── Window 1: workspace ─────────────────────
tmux send-keys -t "$SESSION:1" "cd ~" C-m

# ── Window 2: Raguel / Hermes ────────────────
tmux new-window -t "$SESSION:2" -n raguel
tmux send-keys -t "$SESSION:2"   "cd ~ && hermes" C-m

# ── Window 3: bots ──────────────────────────
tmux new-window -t "$SESSION:3" -n bots

# Create 5 panes
tmux split-window -h -t "$SESSION:3"
tmux split-window -v -t "$SESSION:3.1"
tmux split-window -v -t "$SESSION:3.2"
tmux split-window -v -t "$SESSION:3.3"
tmux select-layout -t "$SESSION:3" tiled

# Pane 1 → ytbot (venv)
tmux send-keys -t "$SESSION:3.1"   "cd '$BASE' && '$VENV' '$YTBOT' 2>&1 | tee -a '$LOGS/ytbot.log'" C-m

# Pane 2 → musicbot (system python)
tmux send-keys -t "$SESSION:3.2"   "cd '$BASE' && $PYTHON '$MUSICBOT' 2>&1 | tee -a '$LOGS/musicbot.log'" C-m

# Pane 3 → aibot (system python)
tmux send-keys -t "$SESSION:3.3"   "cd '$BASE' && $PYTHON '$AIBOT' 2>&1 | tee -a '$LOGS/aibot.log'" C-m

# Pane 4 → Gabriel / cardbot (venv)
tmux send-keys -t "$SESSION:3.4"   "cd '$BASE' && '$VENV' '$CARDBOT' 2>&1 | tee -a '$LOGS/cardbot.log'" C-m

# Pane 5 → logs shell
tmux send-keys -t "$SESSION:3.5"   "cd '$LOGS' && ls -lah" C-m

# ── Label panes on their borders ────────────
# Use a tmux user option (@label) instead of pane_title: the shell prompt
# overwrites pane_title on every prompt, but it never touches @label.
tmux setw -t "$SESSION:3" pane-border-status top
tmux setw -t "$SESSION:3" pane-border-format " #[fg=#81a1c1]#P#[fg=#d8dee9] #{@label} "
tmux set -p -t "$SESSION:3.1" @label "ytbot (Raziel)"
tmux set -p -t "$SESSION:3.2" @label "musicbot (Sandalphon)"
tmux set -p -t "$SESSION:3.3" @label "aibot (Zahkiel)"
tmux set -p -t "$SESSION:3.4" @label "cardbot (Gabriel)"
tmux set -p -t "$SESSION:3.5" @label "logs"

# ── Window 4: scratch ───────────────────────
tmux new-window -t "$SESSION:4" -n scratch
tmux send-keys -t "$SESSION:4" "cd ~" C-m

# Start in Raguel window
tmux select-window -t "$SESSION:2"

# Attach
exec tmux attach -t "$SESSION"
