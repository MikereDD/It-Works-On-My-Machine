#!/usr/bin/env bash
# file:    arakiel-tmux.sh
# version: 1.3
# desc:    tmux loader for arakiel bots workspace

SESSION="arakiel"

BASE="/mnt/nvme1/work/bots"
VENV="$BASE/venv/bin/python"
PYTHON="python3"
LOGS="$BASE/logs"

YTBOT="$BASE/Raziel/ytbot.py"
MUSICBOT="$BASE/Sandalphon/musicbot.py"
AIBOT="$BASE/Zahkiel/aibot.py"

# Attach if session exists
if tmux has-session -t "$SESSION" 2>/dev/null; then
    exec tmux attach -t "$SESSION"
fi

# Ensure logs exist
mkdir -p "$LOGS"
touch "$LOGS/ytbot.log"
touch "$LOGS/musicbot.log"
touch "$LOGS/aibot.log"

# Create session
tmux new-session -d -s "$SESSION" -n main

# ── Window 1: workspace ─────────────────────
tmux send-keys -t "$SESSION:1" "cd ~" C-m

# ── Window 2: bots ──────────────────────────
tmux new-window -t "$SESSION:2" -n bots

# Create 4 panes
tmux split-window -h -t "$SESSION:2"
tmux split-window -v -t "$SESSION:2.1"
tmux split-window -v -t "$SESSION:2.2"

tmux select-layout -t "$SESSION:2" tiled

# Pane 1 → ytbot (venv)
tmux send-keys -t "$SESSION:2.1" \
"cd '$BASE' && '$VENV' '$YTBOT' 2>&1 | tee -a '$LOGS/ytbot.log'" C-m

# Pane 2 → musicbot (system python)
tmux send-keys -t "$SESSION:2.2" \
"cd '$BASE' && $PYTHON '$MUSICBOT' 2>&1 | tee -a '$LOGS/musicbot.log'" C-m

# Pane 3 → aibot (system python)
tmux send-keys -t "$SESSION:2.3" \
"cd '$BASE' && $PYTHON '$AIBOT' 2>&1 | tee -a '$LOGS/aibot.log'" C-m

# Pane 4 → logs shell
tmux send-keys -t "$SESSION:2.4" \
"cd '$LOGS' && ls -lah" C-m

# ── Window 3: scratch ───────────────────────
tmux new-window -t "$SESSION:3" -n scratch
tmux send-keys -t "$SESSION:3" "cd ~" C-m

# ── Window 4: Hermes ───────────────────────
tmux new-window -t "$SESSION:4" -n Hermes

tmux send-keys -t "$SESSION:4" \
"~/dev/github/llama.cpp/build/bin/llama-cli \
-m ~/dev/github/models/Qwen2.5-Coder-3B-Q6_K.gguf \
--jinja \
-c 2048 \
-t 4 \
-n 512 \
-sys 'You are Hermes, an expert coding assistant. Write clean, well-documented, efficient code.' \
--color auto \
-cnv" C-m

# Start in bots window
tmux select-window -t "$SESSION:2"

# Attach
exec tmux attach -t "$SESSION"
