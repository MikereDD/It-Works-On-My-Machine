#--------------------------------------------
# file:     aliases.ps1
# author:   Mike Redd
# version:  2.6
# created:  2026-03-29
# updated:  2026-04-19
# desc:     Aliases and script wrappers
#--------------------------------------------

# ── Script path from env ──────────────────────────────────────
# $PSScriptsDir and $PSMenuDir are set in env.ps1.
# These are fallbacks if this file is loaded standalone.
if (-not $global:PSScriptsDir) { $global:PSScriptsDir = Join-Path $HOME "PS\scripts" }
if (-not $global:PSMenuDir)    { $global:PSMenuDir    = Join-Path $global:PSScriptsDir "menu" }

$PSScriptRoot_Custom = $global:PSScriptsDir
$PSMenuRoot_Custom   = $global:PSMenuDir

# ── Script wrappers ───────────────────────────────────────────
# Functions that call your PS scripts with the correct flags.
# These are what the aliases below actually point to.

function Invoke-ToolMenu {
    pwsh -ExecutionPolicy Bypass -File (Join-Path $PSMenuRoot_Custom "tool-menu.ps1") @args
}

# function Invoke-SysInfo {
#     pwsh -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot_Custom "systeminfo.ps1") @args
# }
#
# function Invoke-PowerMenu {
#     pwsh -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot_Custom "power-menu.ps1") @args
# }
#
# function Invoke-UpdatesMenu {
#     pwsh -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot_Custom "updates-menu.ps1") @args
# }
#
# function Invoke-Weather {
#     pwsh -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot_Custom "dtweatherfetch.ps1") @args
# }
#
# function Invoke-Network {
#     pwsh -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot_Custom "network-menu.ps1") @args
# }
#
# function Invoke-Speedtest {
#     pwsh -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot_Custom "speedtest-menu.ps1") @args
# }

# ── Aliases — your scripts ────────────────────────────────────
Set-Alias -Name toolmenu -Value Invoke-ToolMenu -Description "Tool Menu"

# Set-Alias -Name sysinfo   -Value Invoke-SysInfo     -Description "System info dump menu"
# Set-Alias -Name power     -Value Invoke-PowerMenu   -Description "Power menu (sleep/shutdown/restart)"
# Set-Alias -Name updates   -Value Invoke-UpdatesMenu -Description "Windows Update menu"
# Set-Alias -Name weather   -Value Invoke-Weather     -Description "DT Weather Fetch"
# Set-Alias -Name network   -Value Invoke-Network     -Description "Network Menu"
# Set-Alias -Name speedtest -Value Invoke-Speedtest   -Description "Speedtest"

# ── Aliases — navigation ──────────────────────────────────────
# Note: 'up' is a function in functions.ps1, so it is not aliased here.
# 'back' is simple enough for a direct alias.
Set-Alias -Name back  -Value Pop-Location  -Description "Pop last location (cd -)"
Set-Alias -Name ll    -Value Get-ChildItem -Description "List files"

# ── Aliases — system ──────────────────────────────────────────
Set-Alias -Name svc   -Value Get-Service -Description "List/query services"
Set-Alias -Name proc  -Value Get-Process -Description "List processes"
Set-Alias -Name which -Value Get-Command -Description "Find command location"

# ── Aliases — editor ──────────────────────────────────────────
# Uncomment and set your preferred editor.
# Set-Alias -Name edit -Value notepad -Description "Open file in editor"
# function Invoke-VSCode {
#     & "C:\Program Files\Microsoft VS Code\Code.exe" @args
# }
# Set-Alias -Name code -Value Invoke-VSCode -Description "Open VS Code"

# ── Load message ──────────────────────────────────────────────
if ($global:ShowProfileLoad) {
    Write-Host "  aliases loaded" -ForegroundColor DarkGray
}
