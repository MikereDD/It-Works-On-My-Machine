#--------------------------------------------
# file:     i3blocks.conf
# author:   Mike Redd
# version:  1.6
# desc:     ThemeEngine-managed Arakiel status bar
# theme:    {{THEME_NAME}}
#--------------------------------------------

separator=true
separator_block_width=18

[disk-root]
label=󰋊 SD
command=~/.config/i3/scripts/disk /
interval=30
color={{TEXT}}
background={{SURFACE}}

[disk-nvme]
label=󰋊 NV
command=~/.config/i3/scripts/disk /mnt/nvme1
interval=30
color={{BRIGHT}}
background={{SURFACE}}

[lan]
label=󰈀
command=~/.config/i3/scripts/iface end0
interval=10
color={{INFO}}
background={{SURFACE}}

[net]
label=󰓅
command=~/.config/i3/scripts/bandwidth end0
interval=2
color={{ACCENT}}
background={{SURFACE}}

[cpu]
label=
command=~/.config/i3/scripts/cpu_usage
interval=2
color={{ACCENT_BRIGHT}}
background={{SURFACE}}

[load]
label=
command=~/.config/i3/scripts/load_average
interval=5
color={{MUTED}}
background={{SURFACE}}

[temp]
label=
command=~/.config/i3/scripts/temp
interval=5
color={{WARNING}}
background={{SURFACE}}

[updates]
label=󰚰
command=~/.config/i3/scripts/updates.sh
interval=900
color={{SECONDARY}}
background={{SURFACE}}

[uptime]
label=󰔟
command=~/.config/i3/scripts/uptime_short
interval=60
color={{MUTED}}
background={{SURFACE}}

[time]
label=
command=date '+%a %b %d  %H:%M:%S'
interval=1
color={{BRIGHT}}
background={{SURFACE_ALT}}
