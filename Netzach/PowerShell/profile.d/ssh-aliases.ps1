#--------------------------------------------
# file:     ssh-aliases.ps1
# author:   Mike Redd
# version:  1.1
# created:  2026-05-25
# updated:  2026-05-25
# desc:     SSH aliases and remote helpers
#--------------------------------------------

# ── Remote host config ────────────────────────────────────────
$global:ArakielUser = "typezero"
$global:ArakielHost = "arakiel.local"
$global:ArakielSSH  = "$global:ArakielUser@$global:ArakielHost"

# ── Local paths ───────────────────────────────────────────────
$global:LocalLogPullDir = Join-Path $HOME "Downloads\arakiel-logs"

# ── Remote paths ──────────────────────────────────────────────
$global:RemoteWorkDir = "/mnt/nvme1/work"
$global:RemoteLogsDir = "/mnt/nvme1/work/bots/logs"

# ── SSH helpers ───────────────────────────────────────────────
function arakiel {
    ssh $global:ArakielSSH
}

function py5 {
    arakiel
}

function arakiel-bots {
    ssh $global:ArakielSSH -t "tmux attach -t bots"
}

function arakiel-work {
    ssh $global:ArakielSSH -t "cd $global:RemoteWorkDir && bash"
}

function arakiel-logs {
    ssh $global:ArakielSSH -t "cd $global:RemoteLogsDir && ls -lah && bash"
}

# ── Remote status helpers ─────────────────────────────────────
function arakiel-ping {
    Test-Connection $global:ArakielHost -Count 2
}

function arakiel-df {
    ssh $global:ArakielSSH "df -h"
}

function arakiel-uptime {
    ssh $global:ArakielSSH "uptime"
}

function arakiel-fastfetch {
    ssh $global:ArakielSSH "fastfetch"
}

# ── File copy helpers ─────────────────────────────────────────

function pull-logs {
    New-Item -ItemType Directory -Force -Path $global:LocalLogPullDir | Out-Null

    scp -r `
        "$global:ArakielSSH`:$global:RemoteLogsDir/" `
        $global:LocalLogPullDir
}

# ── Load message ──────────────────────────────────────────────
if ($global:ShowProfileLoad) {
    Write-Host "  $($global:UI_Theme.Muted)ssh aliases loaded$($global:UI_Theme.Reset)"
}
