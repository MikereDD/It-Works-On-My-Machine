#!/usr/bin/env bash
# file: core.sh
# version: 1.1

# Exit on error
set -o errexit
set -o pipefail
set -o nounset

# Base paths
SCRIPTS_DIR="$HOME/scripts"
LIB_DIR="$SCRIPTS_DIR/lib"

# Load UI if present. Strip any trailing CR so a Windows-saved ui.sh still
# loads cleanly on Linux.
if [[ -f "$LIB_DIR/ui.sh" ]]; then
    # shellcheck source=/dev/null
    source <(sed 's/\r$//' "$LIB_DIR/ui.sh")
fi

# Pause helper
pause() {
    read -rp "Press Enter to continue..." _
}

# Alias used by newer scripts (accepts an optional prompt).
pause_return() {
    read -rp "${1:-Press Enter to return...}" _
}

# Return to menu (handled by caller loop)
back() {
    return 0
}
