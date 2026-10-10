# Typezero ThemeEngine - Windows appearance provider
# Version: 0.2-dev
#
# Windows mode/transparency controls and native .theme accent integration.

function Get-TypezeroWindowsAppearance {
    $personalize = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    $dwm = 'HKCU:\Software\Microsoft\Windows\DWM'

    $p = Get-ItemProperty -Path $personalize
    $d = Get-ItemProperty -Path $dwm

    [pscustomobject]@{
        AppsUseLightTheme    = [int]$p.AppsUseLightTheme
        SystemUsesLightTheme = [int]$p.SystemUsesLightTheme
        EnableTransparency   = [int]$p.EnableTransparency
        TitlebarAccent       = [int]$d.ColorPrevalence
        TaskbarAccent        = [int]$p.ColorPrevalence
    }
}

function Set-TypezeroWindowsAppearance {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('dark', 'light')]
        [string]$Mode = 'dark',
        [bool]$Transparency = $true,
        [bool]$TitlebarAccent = $true,
        [bool]$TaskbarAccent = $false
    )

    $personalize = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    $dwm = 'HKCU:\Software\Microsoft\Windows\DWM'
    $light = if ($Mode -eq 'light') { 1 } else { 0 }

    $values = @(
        @{ Path=$personalize; Name='AppsUseLightTheme'; Value=$light }
        @{ Path=$personalize; Name='SystemUsesLightTheme'; Value=$light }
        @{ Path=$personalize; Name='EnableTransparency'; Value=[int]$Transparency }
        @{ Path=$personalize; Name='ColorPrevalence'; Value=[int]$TaskbarAccent }
        @{ Path=$dwm; Name='ColorPrevalence'; Value=[int]$TitlebarAccent }
    )

    foreach ($entry in $values) {
        if ($PSCmdlet.ShouldProcess(
            "$($entry.Path)\$($entry.Name)",
            "Set DWORD to $($entry.Value)"
        )) {
            New-ItemProperty `
                -Path $entry.Path `
                -Name $entry.Name `
                -Value $entry.Value `
                -PropertyType DWord `
                -Force | Out-Null
        }
    }
}

function Set-TypezeroWindowsNativeTheme {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Accent,
        [switch]$GenerateOnly
    )

    if ($Accent -notmatch '^#[0-9A-Fa-f]{6}$') {
        throw "Invalid Windows accent: $Accent"
    }

    if ($Id -notmatch '^[a-z0-9][a-z0-9-]*$') {
        throw "Invalid theme ID: $Id"
    }

    $themesKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes'
    $source = (Get-ItemProperty $themesKey).CurrentTheme

    if (-not $source -or -not (Test-Path -LiteralPath $source)) {
        throw "Windows source theme not found: $source"
    }

    $root = Join-Path $env:LOCALAPPDATA 'Typezero\ThemeEngine\windows'
    New-Item -ItemType Directory -Force -Path $root | Out-Null

    $destination = Join-Path $root "Typezero-$Id.theme"

    # Preserve the existing working Windows theme structure.
    $content = Get-Content -LiteralPath $source -Raw

    foreach ($section in @(
        '[Theme]',
        '[VisualStyles]',
        '[Control Panel\Desktop]',
        '[MasterThemeSelector]'
    )) {
        if (-not $content.Contains($section)) {
            throw "Source theme missing required section: $section"
        }
    }

    if ($content -notmatch '(?m)^Wallpaper=') {
        throw 'Source theme lacks wallpaper configuration.'
    }

    if ($content -notmatch '(?m)^ColorizationColor=') {
        throw 'Source theme lacks ColorizationColor.'
    }

    # Windows owns its wallpaper-derived accent in Automatic mode.
    # ThemeEngine's ACCENT remains authoritative for application integrations.
    if ($content -notmatch '(?m)^AutoColorization=[01]\s*$') {
        throw 'Source theme lacks a supported AutoColorization value.'
    }

    # Typezero Windows accent policy v1
    # Default: theme (manual Windows accent from theme.conf ACCENT).
    # Optional: automatic (wallpaper-derived Windows accent).
    $policyPath = Join-Path $env:LOCALAPPDATA 'Typezero\ThemeEngine\windows-accent-policy'
    $policy = 'theme'
    if (Test-Path -LiteralPath $policyPath) {
        $policy = (Get-Content -LiteralPath $policyPath -Raw).Trim().ToLowerInvariant()
    }
    if ($policy -notin @('theme', 'automatic')) {
        throw "Invalid Windows accent policy '$policy'. Expected theme or automatic in $policyPath"
    }
    $autoValue = if ($policy -eq 'automatic') { '1' } else { '0' }
    $content = [regex]::Replace(
        $content,
        '(?m)^AutoColorization=[01]\s*$',
        "AutoColorization=$autoValue"
    )
    # Preserve the source theme's colorization alpha byte.
    $currentColor = [regex]::Match(
        $content,
        '(?m)^ColorizationColor=0[xX]([0-9A-Fa-f]{8})\s*$'
    )

    if (-not $currentColor.Success) {
        throw 'Unsupported ColorizationColor format.'
    }

    $alpha = $currentColor.Groups[1].Value.Substring(0, 2)
    $rgb = $Accent.TrimStart('#').ToUpperInvariant()
    $newColor = "ColorizationColor=0x$alpha$rgb"

    $content = [regex]::Replace(
        $content,
        '(?m)^ColorizationColor=.*$',
        $newColor
    )

    $content = [regex]::Replace(
        $content,
        '(?m)^DisplayName=.*$',
        "DisplayName=Typezero $Name"
    )

    [System.IO.File]::WriteAllText(
        $destination,
        $content,
        [System.Text.UTF8Encoding]::new($false)
    )

    Write-Host "Windows theme generated: $destination"

    if ($GenerateOnly) {
        return
    }

    # The Windows shell handles .theme activation asynchronously.
    # Verify its active saved theme (name/policy/RGB), not pixel-level refresh.
    # A pre-existing match cannot prove that reapplication completed.
    $alreadyActive = $false
    try {
        $priorPath = (Get-ItemProperty -Path $themesKey -ErrorAction Stop).CurrentTheme
        if ($priorPath -and (Test-Path -LiteralPath $priorPath)) {
            $priorText = Get-Content -LiteralPath $priorPath -Raw -ErrorAction Stop
            $priorName = [regex]::Match($priorText, '(?m)^DisplayName=(.+)\r?$')
            $priorAuto = [regex]::Match($priorText, '(?m)^AutoColorization=([01])\r?$')
            $priorColor = [regex]::Match($priorText, '(?m)^ColorizationColor=0[xX][0-9A-Fa-f]{2}([0-9A-Fa-f]{6})\r?$')
            $alreadyActive = $priorName.Success -and
                $priorName.Groups[1].Value.Trim() -eq "Typezero $Name" -and
                $priorAuto.Success -and $priorAuto.Groups[1].Value -eq $autoValue -and
                ($policy -eq 'automatic' -or ($priorColor.Success -and
                    $priorColor.Groups[1].Value -ieq $rgb))
        }
    } catch { $alreadyActive = $false }

    Start-Process -FilePath $destination -ErrorAction Stop

    $verified = $false
    $lastPath = $null
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    do {
        Start-Sleep -Milliseconds 350
        try {
            $lastPath = (Get-ItemProperty -Path $themesKey -ErrorAction Stop).CurrentTheme
            if (-not $lastPath -or -not (Test-Path -LiteralPath $lastPath)) { continue }
            $activeText = Get-Content -LiteralPath $lastPath -Raw -ErrorAction Stop
            $activeName = [regex]::Match($activeText, '(?m)^DisplayName=(.+)\r?$')
            $activeAuto = [regex]::Match($activeText, '(?m)^AutoColorization=([01])\r?$')
            $activeColor = [regex]::Match($activeText, '(?m)^ColorizationColor=0[xX][0-9A-Fa-f]{2}([0-9A-Fa-f]{6})\r?$')
            $verified = $activeName.Success -and
                $activeName.Groups[1].Value.Trim() -eq "Typezero $Name" -and
                $activeAuto.Success -and $activeAuto.Groups[1].Value -eq $autoValue -and
                ($policy -eq 'automatic' -or ($activeColor.Success -and
                    $activeColor.Groups[1].Value -ieq $rgb))
        } catch { $verified = $false }
    } while (-not $verified -and [DateTime]::UtcNow -lt $deadline)

    if (-not $verified) {
        throw "Windows did not confirm theme '$Name' ($policy) within 15 seconds. Last theme path: $lastPath"
    }
    if ($alreadyActive) {
        Write-Host "Windows native theme confirmed: $Name (already selected; reapplication not independently verified)"
    } else {
        Write-Host "Windows native theme confirmed: $Name ($policy)"
    }
}
