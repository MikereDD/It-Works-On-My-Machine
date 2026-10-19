$ErrorActionPreference = 'Stop'

$engine = Split-Path -Parent $PSScriptRoot

foreach ($name in @(
    'FontPatch-WindowsTerminal.ps1'
    'TerminalColorPatch-WindowsTerminal.ps1'
    'TerminalCombinedPatch-WindowsTerminal.ps1'
    'TerminalTransaction-WindowsTerminal.ps1'
    'TerminalReplace-WindowsTerminal.ps1'
    'TerminalTransactionV2-WindowsTerminal.ps1'
    'TerminalTransactionV2Lock-WindowsTerminal.ps1'
    'FontMapping-WindowsTerminal.ps1'
    'FontMappingV2TransactionAdapter-WindowsTerminal.ps1'
)) {
    . (Join-Path $engine $name)
}

$root = Join-Path ([IO.Path]::GetTempPath()) (
    'typezero-terminal-txn-' + [guid]::NewGuid().ToString('N')
)

New-Item -ItemType Directory -Path $root -ErrorAction Stop | Out-Null

$paths = Get-TypezeroOfflineTerminalTransactionPaths -TestRoot $root
New-Item -ItemType Directory `
    -Path (Split-Path -Parent $paths.Settings) -Force | Out-Null

$theme = @{
    THEME_NAME = 'Obsidian Silver'
    BG = '#123456'
    TEXT = '#eeeeee'
    CURSOR = '#ffffff'
    SELECTION = '#445566'
}

foreach ($name in @(
    'BLACK','RED','GREEN','YELLOW','BLUE','PURPLE',
    'CYAN','WHITE','BRIGHT_BLACK','BRIGHT_RED',
    'BRIGHT_GREEN','BRIGHT_YELLOW','BRIGHT_BLUE',
    'BRIGHT_PURPLE','BRIGHT_CYAN','BRIGHT_WHITE'
)) {
    $theme["ANSI_$name"] = '#778899'
}

$synthetic = [ordered]@{
    theme = 'Typezero ThemeEngine'
    schemes = @(
        @{ name = 'Typezero Obsidian Silver'; background = '#000000' }
    )
    themes = @(
        @{
            name = 'Typezero ThemeEngine'
            window = @{ applicationTheme = 'dark' }
            tab = @{ background = 'terminalBackground' }
            tabRow = @{ background = '#000000' }
        }
    )
    profiles = @{
        defaults = @{}
        list = @(
            @{
                guid = '{574e775e-4f2a-5b96-ac1e-a2962a402336}'
                name = 'PowerShell'
                colorScheme = 'Typezero Obsidian Silver'
            }
        )
    }
}

$utf8 = [Text.UTF8Encoding]::new($false)

[IO.File]::WriteAllText(
    $paths.Settings,
    ($synthetic | ConvertTo-Json -Depth 20),
    $utf8
)

$config = Join-Path $root 'font-v2.json'

$mapping = @{
    Version = 2
    Enabled = $true
    ManualOverride = $null
    Mappings = @{
        gruvbox = @{
            family = 'JetBrainsMono Nerd Font'
            size = 12
            weight = 'normal'
        }
    }
}

[IO.File]::WriteAllText(
    $config,
    ($mapping | ConvertTo-Json -Depth 10),
    $utf8
)

$lockPath = Join-Path $root '.typezero-terminal-v2.lock'
$ready = Join-Path $root 'lock-ready.signal'
$release = Join-Path $root 'lock-release.signal'
$holderScript = Join-Path $root 'Hold-TransactionLock.ps1'

$holderSource = @"
param(
    [Parameter(Mandatory)][string]`$LockPath,
    [Parameter(Mandatory)][string]`$ReadyPath,
    [Parameter(Mandatory)][string]`$ReleasePath
)

`$ErrorActionPreference = 'Stop'

`$lock = [IO.FileStream]::new(
    `$LockPath,
    [IO.FileMode]::OpenOrCreate,
    [IO.FileAccess]::ReadWrite,
    [IO.FileShare]::None
)

try {
    [IO.File]::WriteAllText(`$ReadyPath, 'LOCKED')

    `$deadline = [DateTime]::UtcNow.AddSeconds(60)

    while (-not [IO.File]::Exists(`$ReleasePath)) {
        if ([DateTime]::UtcNow -gt `$deadline) {
            throw 'Timed out waiting for release signal.'
        }

        Start-Sleep -Milliseconds 100
    }
}
finally {
    `$lock.Dispose()
}
"@

[IO.File]::WriteAllText($holderScript, $holderSource, $utf8)

$pwsh = (Get-Command pwsh -ErrorAction Stop).Source

$process = Start-Process `
    -FilePath $pwsh `
    -ArgumentList @(
        '-NoProfile',
        '-NonInteractive',
        '-File',
        "`"$holderScript`"",
        '-LockPath',
        "`"$lockPath`"",
        '-ReadyPath',
        "`"$ready`"",
        '-ReleasePath',
        "`"$release`""
    ) `
    -PassThru -WindowStyle Hidden

try {
    $deadline = [DateTime]::UtcNow.AddSeconds(15)

    while (-not [IO.File]::Exists($ready)) {
        if ($process.HasExited) {
            throw 'FAIL: Independent lock holder exited prematurely.'
        }

        if ([DateTime]::UtcNow -gt $deadline) {
            throw 'FAIL: Lock holder readiness timeout.'
        }

        Start-Sleep -Milliseconds 100
    }

    $before = (Get-FileHash -LiteralPath $paths.Settings -Algorithm SHA256).Hash
    $configBefore = (Get-FileHash -LiteralPath $config -Algorithm SHA256).Hash

    Write-Host "`n=== CROSS-PROCESS ADAPTER LOCK ==="

    $rejected = $false

    try {
        Invoke-TypezeroOfflineFontMappingV2Transaction `
            -TestRoot $root `
            -ConfigPath $config `
            -ThemeId gruvbox `
            -Theme $theme `
            -Execute -Confirm:$false | Out-Null
    }
    catch {
        if ($_.Exception.Message -notlike '*lock is occupied*') {
            throw
        }

        $rejected = $true
    }

    if (-not $rejected) {
        throw 'FAIL: Independent lock did not block adapter.'
    }

    Write-Host 'PASS [1] Independent process lock refused adapter execution.'

    if ((Get-FileHash -LiteralPath $paths.Settings -Algorithm SHA256).Hash -cne $before -or
        (Get-FileHash -LiteralPath $config -Algorithm SHA256).Hash -cne $configBefore -or
        (Test-Path -LiteralPath $paths.BackupRoot)) {
        throw 'FAIL: Contention modified disposable fixture.'
    }

    Write-Host 'PASS [2] Refusal preserved settings, mapping, and backup inventory.'

    [IO.File]::WriteAllText($release, 'RELEASE', $utf8)

    if (-not $process.WaitForExit(10000)) {
        throw 'FAIL: Holder failed to exit after release.'
    }

    if ($process.ExitCode -ne 0) {
        throw "FAIL: Holder exited with code $($process.ExitCode)."
    }

    $probe = [IO.FileStream]::new(
        $lockPath,
        [IO.FileMode]::Open,
        [IO.FileAccess]::ReadWrite,
        [IO.FileShare]::None
    )

    try {
        Write-Host 'PASS [3] Independent lock released cleanly.'
    }
    finally {
        $probe.Dispose()
    }
}
finally {
    if (-not $process.HasExited) {
        $process.Kill()
        $process.WaitForExit()
    }

    $process.Dispose()
}

Write-Host "`nPASS: 3/3 cross-process locking checks."
Write-Host "Fixture evidence retained: $root"