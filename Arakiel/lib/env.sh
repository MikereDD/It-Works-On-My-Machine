# -----------------------------------------------------------------------------
# Arakiel shared interactive environment
# -----------------------------------------------------------------------------
# Component:   Typezer∅ shell environment
# Platform:    Linux / Bash + Zsh (Arakiel)
# Purpose:     Common interactive environment variables shared by both shells.
#
# Keep shell-specific behavior in ~/.bash.d/env or ~/.zsh.d/env.
# -----------------------------------------------------------------------------

# Default terminal editor.
export EDITOR=vim
export VISUAL=vim

# Default pager.
export PAGER=less

# Normalize PATH while preserving the first occurrence of all unmanaged entries.
# Arakiel's user command directories always retain highest priority.
_arakiel_path_normalize() {
    local remaining="$PATH" entry deduped=""

    while [[ -n "$remaining" ]]; do
        if [[ "$remaining" == *:* ]]; then
            entry=${remaining%%:*}
            remaining=${remaining#*:}
        else
            entry=$remaining
            remaining=""
        fi

        [[ -n "$entry" ]] || continue

        # These are inserted explicitly at the front below.
        [[ "$entry" == "$HOME/bin" ]] && continue
        [[ "$entry" == "$HOME/.local/bin" ]] && continue

        case ":$deduped:" in
            *":$entry:"*) ;;
            *) deduped="${deduped:+$deduped:}$entry" ;;
        esac
    done

    PATH="$HOME/bin:$HOME/.local/bin${deduped:+:$deduped}"
}

_arakiel_path_normalize
export PATH

# Do not leave the internal helper in the interactive shell.
unset -f _arakiel_path_normalize 2>/dev/null || true

# less/man-page terminal styling.
export LESS_TERMCAP_mb=$'\E[01;31m'    # Begin blinking text: bold red
export LESS_TERMCAP_md=$'\E[01;31m'    # Begin bold text: bold red
export LESS_TERMCAP_me=$'\E[0m'        # End mode: reset attributes
export LESS_TERMCAP_se=$'\E[0m'        # End standout mode: reset attributes
export LESS_TERMCAP_so=$'\E[01;44;33m' # Begin standout: yellow on blue
export LESS_TERMCAP_ue=$'\E[0m'        # End underline: reset attributes
export LESS_TERMCAP_us=$'\E[01;32m'    # Begin underline: bold green
