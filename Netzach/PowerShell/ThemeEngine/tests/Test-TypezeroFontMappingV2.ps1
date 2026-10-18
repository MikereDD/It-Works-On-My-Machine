$ErrorActionPreference = 'Stop'

$engine = Split-Path -Parent $PSScriptRoot

. (Join-Path $engine 'FontProvider-WindowsTerminal.ps1')
. (Join-Path $engine 'FontMapping-WindowsTerminal.ps1')
. (Join-Path $engine 'FontMappingV2-WindowsTerminal.ps1')

$root = Join-Path $env:TEMP (
    'typezero-font-v2-regression-' + [guid]::NewGuid().ToString('N')
)

$themes = Join-Path $root 'themes'
$configDir = Join-Path $root 'config'

New-Item -ItemType Directory -Path (
    Join-Path $themes 'gruvbox'
) -Force | Out-Null

New-Item -ItemType Directory -Path $configDir -Force | Out-Null

Set-Content -LiteralPath (
    Join-Path $themes 'gruvbox\theme.conf'
) -Value 'THEME_ID=gruvbox'

$config = Join-Path $configDir 'font-windows-terminal.json'

$v1 = @{
    Version = 1
    Enabled = $false
    Mappings = @{
        gruvbox = 'Cascadia Mono'
    }
} | ConvertTo-Json -Depth 10

[IO.File]::WriteAllText(
    $config, $v1 + "`n",
    [Text.UTF8Encoding]::new($false)
)

$before = (Get-FileHash $config -Algorithm SHA256).Hash

Write-Host '=== WHATIF ==='

Set-TypezeroWindowsFontMappingV2 `
    -ThemeId gruvbox `
    -FontFamily 'JetBrainsMono Nerd Font' `
    -Size 12 `
    -Weight normal `
    -ThemesRoot $themes `
    -ConfigPath $config `
    -WhatIf

if ((Get-FileHash $config -Algorithm SHA256).Hash -cne $before) {
    throw 'FAIL: WhatIf changed configuration.'
}

Write-Host 'PASS [1] WhatIf unchanged'

Write-Host '=== V1 MIGRATION ==='

$result = Set-TypezeroWindowsFontMappingV2 `
    -ThemeId gruvbox `
    -FontFamily 'JetBrainsMono Nerd Font' `
    -Size 12 `
    -Weight normal `
    -ThemesRoot $themes `
    -ConfigPath $config `
    -Confirm:$false

if ($result.Version -ne 2 -or
    $result.Enabled -ne $false -or
    $result.Mappings['gruvbox'].Family -cne 'JetBrainsMono Nerd Font') {
    throw 'FAIL: V1 migration.'
}

Write-Host 'PASS [2] V1 migration'

$backups = @(Get-ChildItem $configDir -Filter '*.bak' -File)

if ($backups.Count -ne 1 -or
    (Get-FileHash $backups[0].FullName -Algorithm SHA256).Hash -cne $before) {
    throw 'FAIL: Original backup.'
}

Write-Host 'PASS [3] Original backup exact'

$result = Set-TypezeroWindowsFontMappingV2 `
    -ThemeId gruvbox `
    -FontFamily 'Cascadia Mono' `
    -Size 14 `
    -Weight 'semi-bold' `
    -ThemesRoot $themes `
    -ConfigPath $config `
    -Confirm:$false

if ($result.Version -ne 2 -or
    $result.Mappings['gruvbox'].Family -cne 'Cascadia Mono' -or
    [double]$result.Mappings['gruvbox'].Size -ne 14 -or
    $result.Mappings['gruvbox'].Weight -cne 'semi-bold') {
    throw 'FAIL: V2 update.'
}

Write-Host 'PASS [4] V2 update'

$bad = @(
    @{ Name='Bad size'; Family='Cascadia Mono'; Size=99; Weight='normal' }
    @{ Name='Bad font'; Family='UnknownFontXYZ'; Size=12; Weight='normal' }
    @{ Name='Bad weight'; Family='Cascadia Mono'; Size=12; Weight='heavy' }
)

$i = 4

foreach ($case in $bad) {
    $hash = (Get-FileHash $config -Algorithm SHA256).Hash
    $rejected = $false

    try {
        Set-TypezeroWindowsFontMappingV2 `
            -ThemeId gruvbox `
            -FontFamily $case.Family `
            -Size $case.Size `
            -Weight $case.Weight `
            -ThemesRoot $themes `
            -ConfigPath $config `
            -Confirm:$false | Out-Null
    }
    catch {
        $rejected = $true
    }

    if (-not $rejected -or
        (Get-FileHash $config -Algorithm SHA256).Hash -cne $hash) {
        throw "FAIL: $($case.Name)"
    }

    $i++
    Write-Host "PASS [$i] $($case.Name)"
}

Write-Host 'PASS: 7/7 V2 regression checks.'
Write-Host "Fixture evidence retained: $root"
