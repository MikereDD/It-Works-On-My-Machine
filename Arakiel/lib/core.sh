#!/usr/bin/env bash
# ============================================================================
# Arakiel shared script core
# ============================================================================
# Script:       core.sh
# Component:    Typezer∅ shell utilities / shared script runtime
# Platform:     Linux / Bash (Arakiel)
# Purpose:      Provide common safety defaults, library discovery, UI loading,
#               and small control-flow helpers for maintained Bash tools.
# Consumers:    Arakiel scripts that source ~/lib/core.sh rather than repeating
#               the same startup and UI boilerplate.
# Dependencies: Bash, sed, and the companion ~/lib/ui.sh when available.
#
# Design notes:
#   - This file is sourced, not executed. Shell options enabled here therefore
#     affect the calling script and are intentionally part of the shared runtime
#     contract.
#   - Maintained scripts are expected to fail on unset variables, failed
#     commands, and failed pipeline stages instead of silently continuing with
#     partial state.
#   - LIB_DIR may be supplied by a caller. When it is absent or invalid, Core
#     first tries to locate itself and then falls back to ~/lib.
#   - ui.sh is optional so non-interactive or partially deployed scripts can
#     still use the basic Core helpers.
#   - ui.sh is filtered through sed when sourced to tolerate a copy that was
#     accidentally saved with Windows CRLF line endings. Repository copies
#     should still remain LF-normalized.
# ============================================================================

# ── Shared safety contract ──────────────────────────────────────────────────
# errexit: stop when an unhandled command fails.
# pipefail: make a pipeline fail when any stage fails, not only the last one.
# nounset: treat accidental reads of unset variables as errors.
#
# Because core.sh is sourced, these options deliberately apply to the caller.
set -o errexit
set -o pipefail
set -o nounset

# ── Library and script paths ────────────────────────────────────────────────
# Prefer a LIB_DIR the caller already supplied. This is useful for deployed
# tools that know exactly which library tree they should consume.
#
# Otherwise try to self-locate from BASH_SOURCE. A fallback to ~/lib is kept
# because BASH_SOURCE may not resolve to a normal path when Core itself was
# sourced through process substitution or another indirection.
if [[ -z "${LIB_DIR:-}" || ! -f "${LIB_DIR:-}/ui.sh" ]]; then
    _self="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
    for _d in "$_self" "$HOME/lib"; do
        [[ -n "$_d" && -f "$_d/ui.sh" ]] && {
            LIB_DIR="$_d"
            break
        }
    done
fi

# Callers may override SCRIPTS_DIR before sourcing Core. The normal deployed
# location on Arakiel is ~/scripts.
SCRIPTS_DIR="${SCRIPTS_DIR:-$HOME/scripts}"

# Internal discovery variables should not leak into the caller's namespace.
unset _self _d 2>/dev/null || true

# ── Shared terminal UI ──────────────────────────────────────────────────────
# ui.sh supplies semantic terminal colors and presentation helpers. ThemeEngine
# may further override its legacy UI_* values through the generated runtime
# palette, so scripts consuming Core automatically follow the active theme.
#
# Strip a trailing carriage return from each line while sourcing. This is a
# compatibility guard for a Windows-saved deployed copy, not permission for the
# tracked repository file to use mixed line endings.
if [[ -f "${LIB_DIR:-}/ui.sh" ]]; then
    # shellcheck source=/dev/null
    source <(sed 's/\r$//' "$LIB_DIR/ui.sh")
fi

# ── Shared control-flow helpers ─────────────────────────────────────────────
# Pause until the operator acknowledges the current screen.
pause() {
    read -rp "Press Enter to continue..." _
}

# Same behavior with an optional caller-supplied prompt. Newer menu tools use
# this form when the return destination is clearer than a generic "continue".
pause_return() {
    read -rp "${1:-Press Enter to return...}" _
}

# Menu handlers can call back instead of exiting the process. The surrounding
# caller loop decides what "return to menu" means.
back() {
    return 0
}
