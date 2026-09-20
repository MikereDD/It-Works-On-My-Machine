# ============================================================================
# Arakiel shared interactive environment
# ============================================================================
# Script:       env.sh
# Component:    Typezer∅ shell environment / shared interactive defaults
# Platform:     Linux / Bash + Zsh (Arakiel)
# Purpose:      Define environment variables and PATH behavior shared by both
#               supported interactive shells.
# Consumers:    Loaded by ~/.bash.d/env and ~/.zsh.d/env.
# Dependencies: Standard POSIX-style shell behavior plus Bash/Zsh-compatible
#               parameter expansion.
#
# Design notes:
#   - Shell-specific behavior belongs in the small Bash/Zsh loader files rather
#     than here. This keeps the two interactive environments aligned without
#     duplicating the same defaults.
#   - PATH normalization preserves the first occurrence of unmanaged entries
#     while guaranteeing Arakiel's user command directories stay first.
#   - ~/bin and ~/.local/bin are intentionally reinserted at the front instead
#     of merely deduplicated in place. User-managed tools must win before
#     system-wide commands when names overlap.
#   - The PATH helper is removed after use so an implementation detail does not
#     become part of the interactive shell API.
#   - less/man styling remains here because it is shell-agnostic terminal
#     environment behavior, not prompt or theme-rendering logic.
# ============================================================================

# ── Default editor and pager ────────────────────────────────────────────────
# Keep both EDITOR and VISUAL aligned so terminal tools that honor either
# convention open the same editor.
export EDITOR=vim
export VISUAL=vim

# less is the expected pager for command help, man-page integrations, and tools
# that honor the conventional PAGER environment variable.
export PAGER=less

# ── PATH normalization ──────────────────────────────────────────────────────
# Rebuild PATH while preserving the first occurrence of every unmanaged entry.
# This removes duplicates without reordering system/toolchain paths relative to
# one another.
#
# Arakiel's user command directories are handled specially:
#   1. existing occurrences are removed while scanning
#   2. ~/bin and ~/.local/bin are inserted once at the front
#
# That guarantees personal and locally installed commands retain highest
# priority regardless of how a parent process constructed PATH.
_arakiel_path_normalize() {
    local remaining="$PATH"
    local entry
    local deduped=""

    while [[ -n "$remaining" ]]; do
        if [[ "$remaining" == *:* ]]; then
            entry=${remaining%%:*}
            remaining=${remaining#*:}
        else
            entry=$remaining
            remaining=""
        fi

        # Ignore empty PATH fields rather than interpreting them as the current
        # working directory. Explicit paths are safer and easier to reason about.
        [[ -n "$entry" ]] || continue

        # These paths are reinserted explicitly at the front below.
        [[ "$entry" == "$HOME/bin" ]] && continue
        [[ "$entry" == "$HOME/.local/bin" ]] && continue

        # Keep only the first appearance of each remaining path.
        case ":$deduped:" in
            *":$entry:"*) ;;
            *) deduped="${deduped:+$deduped:}$entry" ;;
        esac
    done

    PATH="$HOME/bin:$HOME/.local/bin${deduped:+:$deduped}"
}

_arakiel_path_normalize
export PATH

# Do not leave the internal normalization helper in the interactive shell.
unset -f _arakiel_path_normalize 2>/dev/null || true

# ── less / man-page terminal styling ────────────────────────────────────────
# These variables style terminal capabilities used by less and, through less,
# many man-page viewers. They are presentation defaults rather than ThemeEngine
# roles because they describe pager capabilities directly.
#
# The reset values intentionally restore terminal state after each styled span.
export LESS_TERMCAP_mb=$'\E[01;31m'    # Begin blinking text: bold red
export LESS_TERMCAP_md=$'\E[01;31m'    # Begin bold text: bold red
export LESS_TERMCAP_me=$'\E[0m'        # End mode: reset attributes
export LESS_TERMCAP_se=$'\E[0m'        # End standout mode: reset attributes
export LESS_TERMCAP_so=$'\E[01;44;33m' # Begin standout: yellow on blue
export LESS_TERMCAP_ue=$'\E[0m'        # End underline: reset attributes
export LESS_TERMCAP_us=$'\E[01;32m'    # Begin underline: bold green
