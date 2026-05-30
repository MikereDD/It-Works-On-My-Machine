#!/usr/bin/env bash
# file: core.sh
# version: 1.2

# Exit on error
set -o errexit
set -o pipefail
set -o nounset

# Base paths. Prefer a LIB_DIR the caller already set (leaf scripts export it);
# otherwise try to self-locate, then fall back to ~/lib. This keeps working even
# when core.sh is sourced via process substitution (where BASH_SOURCE is a pipe).
if [[ -z "${LIB_DIR:-}" || ! -f "${LIB_DIR:-}/ui.sh" ]]; then
    _self="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
    for _d in "$_self" "$HOME/lib" "$HOME/scripts/lib"; do
        [[ -n "$_d" && -f "$_d/ui.sh" ]] && { LIB_DIR="$_d"; break; }
    done
fi
SCRIPTS_DIR="${SCRIPTS_DIR:-$HOME/scripts}"

# Load UI if present. Strip trailing CR so a Windows-saved ui.sh loads cleanly.
if [[ -f "${LIB_DIR:-}/ui.sh" ]]; then
    # shellcheck source=/dev/null
    source <(sed 's/\r$//' "$LIB_DIR/ui.sh")
fi

# Pause helper
pause() {
    read -rp "Press Enter to continue..."
}

# Return to menu (handled by caller loop)
back() {
    return 0
}
