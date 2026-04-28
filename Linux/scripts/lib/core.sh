#!/usr/bin/env bash
# file: core.sh
# version: 1.0

# Exit on error
set -o errexit
set -o pipefail
set -o nounset

# Base paths
SCRIPTS_DIR="$HOME/scripts"
LIB_DIR="$SCRIPTS_DIR/lib"

# Load UI if present
if [[ -f "$LIB_DIR/ui.sh" ]]; then
    source "$LIB_DIR/ui.sh"
fi

# Pause helper
pause() {
    read -rp "Press Enter to continue..."
}

# Return to menu (handled by caller loop)
back() {
    return 0
}
