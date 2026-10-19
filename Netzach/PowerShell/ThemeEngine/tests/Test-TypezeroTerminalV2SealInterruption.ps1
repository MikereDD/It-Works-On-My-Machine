
param(
    [ValidateSet('Parent', 'Child')]
    [string]$Mode = 'Parent',

    [string]$TestRoot = '',
    [string]$BackupDirectory = '',
    [string]$Point = '',
    [string]$Token = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$engine = Split-Path -Parent $PSScriptRoot
$repo = (Resolve-Path (Join-Path $engine '..\..\..')).Path
$utf8 = [Text.UTF8Encoding]::new($false)

function Assert-Condition {
    param([bool]$Condition, [string]$Description)
    if (-not $Condition) {
        throw "FAIL: $Description"
    }
}

function Assert-FixtureRoot {
    param([string]$Root)

    $full = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $temp = [IO.Path]::GetFullPath(
        [IO.Path]::GetTempPath()
    ).TrimEnd('\')

    Assert-Condition (
        [IO.Path]::GetDirectoryName($full) -ieq $temp -and
        [IO.Path]::GetFileName($full) -cmatch
            '\Atypezero-terminal-txn-[a-f0-9]{32}\z'
    ) 'Disposable fixture root required'

    return $full
}

foreach ($name in @(
    'FontPatch-WindowsTerminal.ps1'
    'TerminalColorPatch-WindowsTerminal.ps1'
    'TerminalCombinedPatch-WindowsTerminal.ps1'
    'TerminalTransaction-WindowsTerminal.ps1'
    'TerminalReplace-WindowsTerminal.ps1'
    'TerminalTransactionV2-WindowsTerminal.ps1'
    'TerminalTransactionV2Lock-WindowsTerminal.ps1'
    'TerminalEvidenceSealV2-WindowsTerminal.ps1'
)) {
    . (Join-Path $engine $name)
}

# --------------------------------------------------------------------
# CHILD PROCESS
# --------------------------------------------------------------------

if ($Mode -ceq 'Child') {
    Assert-Condition (
        $Point -cin @('BEFORE_SEAL', 'AFTER_SEAL') -and
        $Token -cmatch '\A[a-f0-9]{32}\z'
    ) 'Valid child arguments'

    $root = Assert-FixtureRoot $TestRoot
    $paths = Get-TypezeroOfflineTerminalV2Paths -TestRoot $root

    $null = Assert-TypezeroOfflineTerminalV2Folder `
        -Paths $paths -BackupDirectory $BackupDirectory

    $module = Join-Path $root (
        'instrumented\' +
        'TerminalEvidenceSealV2-WindowsTerminal.ps1'
    )

    Assert-TypezeroOfflineReplacePlainPath -Path $module
    Assert-TypezeroOfflineReplaceSingleLink -Path $module

    # Independent key arrives through standard input, not the
    # command line or fixture evidence directory.
    $keyLine = [Console]::In.ReadLine()

    Assert-Condition (
        $null -ne $keyLine -and
        $keyLine -cmatch '\A[A-Za-z0-9+/=]+\z'
    ) 'Independent key received'

    [byte[]]$key = [Convert]::FromBase64String($keyLine)

    Assert-Condition ($key.Length -eq 32) '256-bit key required'

    $script:CrashPoint = $Point
    $script:CrashRoot = $root
    $script:CrashToken = $Token
    $script:CrashFolder = $BackupDirectory

    function Invoke-SealCrashCheckpoint {
        param([string]$Name)

        if ($Name -cne $script:CrashPoint) {
            return
        }

        $signal = Join-Path $script:CrashRoot 'control\paused.json'

        $startTicks = (
            [Diagnostics.Process]::GetCurrentProcess()
        ).StartTime.ToUniversalTime().Ticks

        $data = [ordered]@{
            Point = $Name
            Token = $script:CrashToken
            ProcessId = $PID
            StartTicks = $startTicks
            TestRoot = $script:CrashRoot
            BackupDirectory = $script:CrashFolder
        }

        [IO.File]::WriteAllText(
            $signal,
            ($data | ConvertTo-Json -Compress),
            $utf8
        )

        # Only the parent-owned process can terminate this pause.
        while ($true) {
            Start-Sleep -Milliseconds 100
        }
    }

    . $module

    try {
        $null = New-TypezeroOfflineTerminalV2EvidenceSeal `
            -TestRoot $root `
            -BackupDirectory $BackupDirectory `
            -IndependentKey $key `
            -Execute -Confirm:$false

        throw 'Child returned without reaching crash checkpoint.'
    }
    finally {
        [array]::Clear($key, 0, $key.Length)
    }
}

# --------------------------------------------------------------------
# PARENT PREFLIGHT
# --------------------------------------------------------------------

Assert-Condition (
    (git -C $repo branch --show-current).Trim() -ceq
        'feature/themeengine-font-management'
) 'Expected development branch'


$expectedHashes = @{
    'TerminalTransactionV2-WindowsTerminal.ps1' =
        '20541E571439125AF568872A9AF764EAE40696BBFEFB7EA49D2B0CC9299D77C2'
    'TerminalReplace-WindowsTerminal.ps1' =
        '588B0403CEF83E50507A8742D1454B03272AD4E25C273CBA921E9AC989AFF235'
    'TerminalEvidenceSealV2-WindowsTerminal.ps1' =
        '93F05D1682166AC864B9C73FE80A8D77379259F0B2927DB43A96774635E45683'
}

foreach ($name in $expectedHashes.Keys) {
    $actual = (
        Get-FileHash (Join-Path $engine $name) -Algorithm SHA256
    ).Hash

    Assert-Condition (
        $actual -ceq $expectedHashes[$name]
    ) "Source hash: $name"
}

Write-Host 'PASS: Git and source integrity preflight.'

# --------------------------------------------------------------------
# BUILD A DISPOSABLE INSTRUMENTED SEAL MODULE
# --------------------------------------------------------------------

$sealModule = Join-Path $engine `
    'TerminalEvidenceSealV2-WindowsTerminal.ps1'

$original = [IO.File]::ReadAllText($sealModule)
$normalized = $original.Replace("`r`n", "`n")

$writeAnchor = @(
    '    Write-TypezeroOfflineTerminalV2NewFile `'
    '        -Path $context.Seal -Bytes $mac'
) -join "`n"

Assert-Condition (
    [regex]::Matches(
        $normalized,
        [regex]::Escape($writeAnchor)
    ).Count -eq 1
) 'Unique seal-write instrumentation anchor'

$instrumented = $normalized.Replace(
    $writeAnchor,
    (
        "    Invoke-SealCrashCheckpoint -Name 'BEFORE_SEAL'`n" +
        $writeAnchor +
        "`n    Invoke-SealCrashCheckpoint -Name 'AFTER_SEAL'"
    )
)

# Exact reversal must recover the original normalized source.
$reversed = $instrumented.Replace(
    (
        "    Invoke-SealCrashCheckpoint -Name 'BEFORE_SEAL'`n" +
        $writeAnchor +
        "`n    Invoke-SealCrashCheckpoint -Name 'AFTER_SEAL'"
    ),
    $writeAnchor
)

Assert-Condition (
    $reversed -ceq $normalized
) 'Instrumentation is exactly reversible'

$tokens = $null
$parseErrors = $null

[Management.Automation.Language.Parser]::ParseInput(
    $instrumented,
    [ref]$tokens,
    [ref]$parseErrors
) | Out-Null

Assert-Condition (
    $parseErrors.Count -eq 0
) 'Instrumented module parses'

Write-Host 'PASS: Instrumentation validated without source changes.'

# --------------------------------------------------------------------
# SYNTHETIC SETTINGS
# --------------------------------------------------------------------

$synthetic = [ordered]@{
    theme = 'Typezero ThemeEngine'
    schemes = @(
        @{
            name = 'Typezero Obsidian Silver'
            background = '#000000'
        }
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

$theme = @{
    THEME_NAME = 'Obsidian Silver'
    BG = '#123456'
    TEXT = '#eeeeee'
    CURSOR = '#ffffff'
    SELECTION = '#445566'
}

foreach ($name in @(
    'BLACK', 'RED', 'GREEN', 'YELLOW',
    'BLUE', 'PURPLE', 'CYAN', 'WHITE',
    'BRIGHT_BLACK', 'BRIGHT_RED', 'BRIGHT_GREEN',
    'BRIGHT_YELLOW', 'BRIGHT_BLUE', 'BRIGHT_PURPLE',
    'BRIGHT_CYAN', 'BRIGHT_WHITE'
)) {
    $theme["ANSI_$name"] = '#778899'
}

function Get-EvidenceSnapshot {
    param([string]$Root)

    $records = @(
        Get-ChildItem -LiteralPath $Root -Recurse -Force -File |
        Sort-Object FullName |
        ForEach-Object {
            $relative = $_.FullName.Substring($Root.Length)
            $hash = (
                Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256
            ).Hash

            "$relative|$hash|$($_.Length)"
        }
    )

    return ($records -join "`n")
}

# --------------------------------------------------------------------
# TWO CHILD-PROCESS INTERRUPTION CASES
# --------------------------------------------------------------------

$checks = 0

foreach ($point in @('BEFORE_SEAL', 'AFTER_SEAL')) {
    $root = Join-Path ([IO.Path]::GetTempPath()) (
        'typezero-terminal-txn-' +
        [guid]::NewGuid().ToString('N')
    )

    $root = Assert-FixtureRoot $root
    [IO.Directory]::CreateDirectory($root) | Out-Null

    $paths = Get-TypezeroOfflineTerminalV2Paths -TestRoot $root

    foreach ($directory in @(
        [IO.Path]::GetDirectoryName($paths.Settings)
        (Join-Path $root 'control')
        (Join-Path $root 'instrumented')
    )) {
        [IO.Directory]::CreateDirectory($directory) | Out-Null
    }

    [IO.File]::WriteAllText(
        $paths.Settings,
        ($synthetic | ConvertTo-Json -Depth 20),
        $utf8
    )

    $originalHash = (
        Get-FileHash $paths.Settings -Algorithm SHA256
    ).Hash

    $transaction = Invoke-TypezeroOfflineTerminalV2Locked `
        -TestRoot $root `
        -Theme $theme `
        -FontFace 'JetBrainsMono Nerd Font' `
        -FontSize 13 `
        -FontWeight normal `
        -Execute -Confirm:$false

    Assert-Condition (
        $transaction.Status -ceq 'VERIFIED'
    ) "$point initial transaction verified"

    $folder = $transaction.BackupDirectory

    $null = Assert-TypezeroOfflineTerminalV2Folder `
        -Paths $paths -BackupDirectory $folder

    $sealPath = Join-Path $folder 'evidence.seal'

    Assert-Condition (
        -not [IO.File]::Exists($sealPath)
    ) "$point starts without seal"

    $beforeCurrentHash = (
        Get-FileHash $paths.Settings -Algorithm SHA256
    ).Hash

    Assert-Condition (
        $beforeCurrentHash -cne $originalHash
    ) "$point transaction applied synthetic changes"

    $instrumentedPath = Join-Path $root (
        'instrumented\' +
        'TerminalEvidenceSealV2-WindowsTerminal.ps1'
    )

    [IO.File]::WriteAllText(
        $instrumentedPath,
        $instrumented,
        $utf8
    )

    [byte[]]$key = [byte[]]::new(32)
    [Security.Cryptography.RandomNumberGenerator]::Fill($key)

    $token = [guid]::NewGuid().ToString('N')
    $signal = Join-Path $root 'control\paused.json'

    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = (Get-Command pwsh -ErrorAction Stop).Source
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    foreach ($argument in @(
        '-NoProfile'
        '-NonInteractive'
        '-File'
        $PSCommandPath
        '-Mode'
        'Child'
        '-TestRoot'
        $root
        '-BackupDirectory'
        $folder
        '-Point'
        $point
        '-Token'
        $token
    )) {
        $psi.ArgumentList.Add($argument)
    }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $psi

    Write-Host "`n=== V2 SEAL INTERRUPTION: $point ==="

    try {
        Assert-Condition (
            $process.Start()
        ) 'Child process starts'

        $started = $process.StartTime.ToUniversalTime().Ticks

        $process.StandardInput.WriteLine(
            [Convert]::ToBase64String($key)
        )
        $process.StandardInput.Close()

        $deadline = [DateTime]::UtcNow.AddSeconds(15)
        $paused = $null

        while ([DateTime]::UtcNow -lt $deadline) {
            if ($process.HasExited) {
                break
            }

            if ([IO.File]::Exists($signal)) {
                try {
                    $paused = (
                        [IO.File]::ReadAllText($signal) |
                        ConvertFrom-Json -ErrorAction Stop
                    )
                }
                catch {
                    $paused = $null
                }

                if ($null -ne $paused) {
                    break
                }
            }

            Start-Sleep -Milliseconds 50
        }

        if ($null -eq $paused) {
            if ($process.HasExited) {
                $stderrText = $process.StandardError.ReadToEnd()
                throw "Child exited before checkpoint: $stderrText"
            }

            throw "Child did not reach $point within 15 seconds."
        }

        Assert-Condition (
            -not $process.HasExited -and
            $paused.Point -ceq $point -and
            $paused.Token -ceq $token -and
            $paused.ProcessId -eq $process.Id -and
            $paused.StartTicks -eq $started -and
            $paused.TestRoot -ceq $root -and
            $paused.BackupDirectory -ceq $folder
        ) 'Authenticated child checkpoint identity'

        $process.Kill()

        Assert-Condition (
            $process.WaitForExit(5000) -and
            $process.ExitCode -ne 0
        ) 'Hard termination of parent-owned child'

        $checks++
        Write-Host "PASS [$checks] Identified child terminated."

        $expectSeal = $point -ceq 'AFTER_SEAL'

        Assert-Condition (
            [IO.File]::Exists($sealPath) -eq $expectSeal
        ) 'Seal-file presence matches crash point'

        Assert-Condition (
            (Get-FileHash $paths.Settings -Algorithm SHA256).Hash `
                -ceq $beforeCurrentHash
        ) 'Synthetic settings remain unchanged'

        $checks++
        Write-Host "PASS [$checks] Surviving evidence matches checkpoint."

        $snapshotBefore = Get-EvidenceSnapshot $root

        $auth = Get-TypezeroOfflineTerminalV2SealResult `
            -TestRoot $root `
            -BackupDirectory $folder `
            -IndependentKey $key

        $diagnostic = `
            Get-TypezeroOfflineTerminalCombinedV2RecoveryDiagnostic `
            -TestRoot $root `
            -BackupDirectory $folder

        $snapshotAfter = Get-EvidenceSnapshot $root

        $expectedStatus = if ($expectSeal) {
            'AUTHENTICATED'
        }
        else {
            'INCOMPLETE'
        }

        Assert-Condition (
            $auth.Status -ceq $expectedStatus -and
            $auth.ReceiptAuthenticated -eq $expectSeal -and
            $auth.RecoveryAuthorized -eq $false -and
            $auth.LiveActivationAuthorized -eq $false -and
            $auth.OperationPhase -ceq 'UNKNOWN' -and
            $diagnostic.State -ceq 'APPLIED_BYTES_PRESENT' -and
            $diagnostic.ReadOnly -eq $true -and
            $diagnostic.RecoveryAllowed -eq $false -and
            $diagnostic.OperationPhase -ceq 'UNKNOWN' -and
            $snapshotBefore -ceq $snapshotAfter
        ) 'Read-only authentication and recovery boundary'

        $checks++
        Write-Host "PASS [$checks] Authentication and recovery remain guarded."

        Write-Host "Fixture retained: $root"
    }
    finally {
        if ($process.Id -ne 0 -and -not $process.HasExited) {
            $process.Kill()
            $null = $process.WaitForExit(5000)
        }

        $process.Dispose()
        [array]::Clear($key, 0, $key.Length)
    }
}

Assert-Condition (
    $checks -eq 6
) 'Expected six seal interruption checks'

Write-Host "`nPASS: 6/6 V2 evidence-seal interruption checks."
Write-Host 'RecoveryAuthorized=False'
Write-Host 'LiveActivationAuthorized=False'
