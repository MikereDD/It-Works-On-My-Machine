#--------------------------------------------
# file:     env.ps1
# author:   Mike Redd
# version:  2.5
# created:  2026-03-29
# updated:  2026-06-27
# desc:     PowerShell environment config
#           Loaded first by profile — sets global
#           flags, vars, and PATH used by other files.
#--------------------------------------------

# ── Toggles ───────────────────────────────────────────────────
# Silence all "loaded" messages on startup.
$global:ShowProfileLoad = $false
# Show git branch + dirty count in the prompt. Turn off if a large
# repo (e.g. the monorepo) makes `git status` lag the prompt.
$global:ShowGitStatus   = $true

# ── Shared path references ────────────────────────────────────
# Fallbacks if env.ps1 is ever loaded standalone.
if (-not $global:PSRootDir)     { $global:PSRootDir     = Join-Path $HOME "PS" }
if (-not $global:PSProfileDir)  { $global:PSProfileDir  = Join-Path $global:PSRootDir "profile.d" }
if (-not $global:PSScriptsDir)  { $global:PSScriptsDir  = Join-Path $global:PSRootDir "scripts" }
if (-not $global:PSMenuDir)     { $global:PSMenuDir     = Join-Path $global:PSScriptsDir "menu" }

# ── PATH helper ───────────────────────────────────────────────
# Append a folder to this session's PATH once, only if it exists.
function global:Add-PathSegment {
    param([Parameter(Mandatory = $true)][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $segments = $env:Path -split ';' | Where-Object { $_ -ne '' }
    if ($segments -notcontains $Path) { $env:Path += ";$Path" }
}

# ── Android SDK ───────────────────────────────────────────────
$global:AndroidSdk = Join-Path $env:LOCALAPPDATA "Android\Sdk"
if (Test-Path -LiteralPath $global:AndroidSdk) {
    $env:ANDROID_HOME     = $global:AndroidSdk
    $env:ANDROID_SDK_ROOT = $global:AndroidSdk
    Add-PathSegment (Join-Path $global:AndroidSdk "platform-tools")          # adb, fastboot
    Add-PathSegment (Join-Path $global:AndroidSdk "cmdline-tools\latest\bin") # sdkmanager, avdmanager
    Add-PathSegment (Join-Path $global:AndroidSdk "emulator")                # emulator
}

# ── Tool paths ────────────────────────────────────────────────
$global:ToolPaths = @{
    ffmpeg    = "ffmpeg"
    ffprobe   = "ffprobe"
    metaflac  = Join-Path $HOME "Apps\FLAC\metaflac.exe"
    flac      = Join-Path $HOME "Apps\FLAC\flac.exe"
    cdda2wav  = "C:\Program Files (x86)\cdrtfe\tools\cdrtools\cdda2wav.exe"
    mkvmerge  = "mkvmerge"
    mediainfo = "mediainfo"
    adb       = Join-Path $global:AndroidSdk "platform-tools\adb.exe"
    fastboot  = Join-Path $global:AndroidSdk "platform-tools\fastboot.exe"
}

# ── Cached capability checks (avoid per-prompt cost) ──────────
$global:HasGit = [bool](Get-Command git -ErrorAction SilentlyContinue)

# ── Optional: clear screen on new session ────────────────────
# Clear-Host

# ── Prompt ────────────────────────────────────────────────────
function global:prompt {
    # Resolve semantic ThemeEngine roles at prompt-render time.
    # env.ps1 loads before theme.ps1/ui.ps1, so retain ANSI fallbacks.
    $esc = [char]27

    if ($global:UI_Theme) {
        $accent  = $global:UI_Theme.Accent
        $success = $global:UI_Theme.Success
        $warning = $global:UI_Theme.Warning
        $error   = $global:UI_Theme.Error
        $text    = $global:UI_Theme.Text
        $dim     = $global:UI_Theme.Dim
        $bold    = $global:UI_Theme.Bold
        $reset   = $global:UI_Theme.Reset
    } else {
        $accent  = "$esc[96m"
        $success = "$esc[92m"
        $warning = "$esc[93m"
        $error   = "$esc[91m"
        $text    = "$esc[37m"
        $dim     = "$esc[2m"
        $bold    = "$esc[1m"
        $reset   = "$esc[0m"
    }

    $hostName = $env:COMPUTERNAME.ToLower()
    $userName = $env:USERNAME.ToLower()

    # Show just the current folder name (like \W in bash).
    $dir = Split-Path -Leaf (Get-Location)
    if (-not $dir) { $dir = (Get-Location).Path }

    # ── SSH detection ─────────────────────────────────────────
    $isSSH = $env:SSH_CLIENT -or $env:SSH_TTY

    # ── Git branch + dirty status ─────────────────────────────
    $git = ""
    if ($global:ShowGitStatus -and $global:HasGit) {
        try {
            $branch = git rev-parse --abbrev-ref HEAD 2>$null
            if ($branch) {
                $status = git status --porcelain 2>$null
                if ($status) {
                    $changed  = ($status | Measure-Object).Count
                    $dirtyStr = "${warning}*${changed}${reset}"
                    $git = " ${dim}${text}(${reset}${accent}$branch${reset}${dirtyStr}${dim}${text})${reset}"
                } else {
                    $git = " ${dim}${text}(${reset}${accent}$branch${reset}${dim}${text})${reset}"
                }
            }
        } catch {}
    }

    # ── Admin indicator ───────────────────────────────────────
    $adminStr = ""
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    if ($p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $adminStr = " ${error}${bold}[ADMIN]${reset}"
    }

    # ── Build prompt ──────────────────────────────────────────
    if ($isSSH) {
        Write-Host -NoNewline "${error}${bold}┌─[SSH]${reset}${error}─[${reset}${warning}$userName${error}@${warning}$hostName${reset}${error}]─[${reset}${error}$dir${reset}${error}]${reset}${git}${adminStr}"
    } else {
        Write-Host -NoNewline "${accent}┌─[${reset}${success}$userName${dim}${text}@${reset}${accent}$hostName${reset}${accent}]─[${reset}${text}$dir${reset}${accent}]${reset}${git}${adminStr}"
    }

    Write-Host ""
    Write-Host -NoNewline "${accent}└─╼${reset} "

    return " "
}

# ── Load message ──────────────────────────────────────────────
if ($global:ShowProfileLoad) {
    Write-Host "  env loaded" -ForegroundColor DarkGray
}
