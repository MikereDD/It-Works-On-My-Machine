#--------------------------------------------
# file:     i3blocks.conf
# author:   Mike Redd
# version:  1.9
# desc:     ThemeEngine-managed Arakiel telemetry bar
# theme:    {{THEME_NAME}}
#
# Layout:
#   Storage | Network | System | Session
#
# Design rules:
# - Metrics inside a group are separated by whitespace, not rules.
# - A separator appears only at a logical group boundary.
# - Pango en-spaces separate an icon/label from its value.
# - Inter-block spacing is controlled by i3blocks, not label padding.
# - Explicit spans keep Nerd Font glyphs and text on a consistent
#   baseline without relying on literal trailing whitespace.
#
# Spacing:
#   &#x2002; = en-space  (icon/label -> value)
#--------------------------------------------

separator=false
separator_block_width=16
markup=pango

# ── Storage ─────────────────────────────────

[disk-root]
label=<span rise="0">󰋊&#x2002;SD&#x2002;</span>
command=~/.config/i3/scripts/disk /
interval=30
color={{TEXT}}
background={{SURFACE}}

[disk-nvme]
label=<span rise="0">󰋊&#x2002;NV&#x2002;</span>
command=~/.config/i3/scripts/disk /mnt/nvme1
interval=30
color={{BRIGHT}}
background={{SURFACE}}
separator=true

# ── Network ─────────────────────────────────

[lan]
label=<span rise="0">󰈀&#x2002;</span>
command=~/.config/i3/scripts/iface end0
interval=10
color={{INFO}}
background={{SURFACE}}

[net]
label=<span rise="0">󰓅&#x2002;</span>
command=~/.config/i3/scripts/bandwidth end0
interval=2
color={{ACCENT}}
background={{SURFACE}}
separator=true

# ── System ──────────────────────────────────

[cpu]
label=<span rise="0">&#x2002;</span>
command=~/.config/i3/scripts/cpu_usage
interval=2
color={{ACCENT_BRIGHT}}
background={{SURFACE}}

[load]
label=<span rise="0">&#x2002;</span>
command=~/.config/i3/scripts/load_average
interval=5
color={{MUTED}}
background={{SURFACE}}

[temp]
label=<span rise="0">&#x2002;</span>
command=~/.config/i3/scripts/temp
interval=5
color={{WARNING}}
background={{SURFACE}}

[updates]
label=<span rise="0">󰏗&#x2002;</span>
command=~/.config/i3/scripts/updates.sh
interval=900
color={{SECONDARY}}
background={{SURFACE}}
separator=true

# ── Session ─────────────────────────────────

[uptime]
label=<span rise="0">󰔟&#x2002;</span>
command=~/.config/i3/scripts/uptime_short
interval=60
color={{MUTED}}
background={{SURFACE}}

[time]
label=<span rise="0">&#x2002;</span>
command=date '+%a %b %d  %H:%M:%S'
interval=1
color={{BRIGHT}}
background={{SURFACE_ALT}}
