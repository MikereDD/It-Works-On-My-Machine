param(
    [ValidateSet('Parent','Child')][string]$Mode = 'Parent',
    [string]$TestRoot = '',
    [string]$Point = '',
    [string]$Token = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$engine = Split-Path -Parent $PSScriptRoot
$utf8 = [Text.UTF8Encoding]::new($false)

$modules = @(
    'FontPatch-WindowsTerminal.ps1'
    'TerminalColorPatch-WindowsTerminal.ps1'
    'TerminalCombinedPatch-WindowsTerminal.ps1'
    'TerminalTransaction-WindowsTerminal.ps1'
    'TerminalReplace-WindowsTerminal.ps1'
)

foreach ($name in $modules) {
    . (Join-Path $engine $name)
}

if ($Mode -ceq 'Child') {
    . (Join-Path $TestRoot 'instrumented\TerminalReplace-WindowsTerminal.ps1')
}

if ($Mode -ceq 'Child') {
    $root = [IO.Path]::GetFullPath($TestRoot).TrimEnd('\')
    $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')

    if ([IO.Path]::GetDirectoryName($root) -ine $temp -or
        [IO.Path]::GetFileName($root) -cnotmatch
        '^typezero-terminal-txn-[a-f0-9]{32}$' -or
        $Token -cnotmatch '^[a-f0-9]{32}$' -or
        $Point -cnotin @('AFTER_STAGE','AFTER_RECEIPT','AFTER_FILE_REPLACE','AFTER_VERIFIED')) {
        throw 'REFUSED: Invalid child fixture, point, or token.'
    }

    $instrumented = Join-Path $root 'instrumented\TerminalTransactionV2-WindowsTerminal.ps1'

    if (-not [IO.File]::Exists($instrumented)) {
        throw 'REFUSED: Missing instrumented V2 module.'
    }

    Assert-TypezeroOfflineReplacePlainPath -Path $instrumented
    Assert-TypezeroOfflineReplaceSingleLink -Path $instrumented

    $script:SelectedPoint = $Point
    $script:ChildRoot = $root
    $script:ChildToken = $Token

    function Invoke-TypezeroV2CrashCheckpoint {
        param([string]$Name)

        if ($Name -cne $script:SelectedPoint) { return }

        $paths = Get-TypezeroOfflineTerminalV2Paths -TestRoot $script:ChildRoot

        $folders = @(
            Get-ChildItem -LiteralPath $paths.BackupRoot -Directory
        )

        if ($folders.Count -ne 1) {
            throw 'REFUSED: Unexpected transaction folder count.'
        }

        $signal = Join-Path $script:ChildRoot 'control\paused.json'
        $startTicks = (
            [Diagnostics.Process]::GetCurrentProcess()
        ).StartTime.ToUniversalTime().Ticks

        [IO.File]::WriteAllText(
            $signal,
            ([ordered]@{
                Point = $Name
                Token = $script:ChildToken
                ProcessId = $PID
                StartTicks = $startTicks
                TestRoot = $script:ChildRoot
                BackupDirectory = $folders[0].FullName
            } | ConvertTo-Json -Compress),
            $utf8
        )

        while ($true) {
            Start-Sleep -Milliseconds 100
        }
    }

    . $instrumented
    . (Join-Path $engine 'TerminalTransactionV2Lock-WindowsTerminal.ps1')

    $theme = @{
        THEME_NAME = 'Obsidian Silver'
        BG = '#123456'
        TEXT = '#eeeeee'
        CURSOR = '#ffffff'
        SELECTION = '#445566'
    }

    foreach ($name in @(
        'BLACK','RED','GREEN','YELLOW','BLUE','PURPLE','CYAN','WHITE',
        'BRIGHT_BLACK','BRIGHT_RED','BRIGHT_GREEN','BRIGHT_YELLOW',
        'BRIGHT_BLUE','BRIGHT_PURPLE','BRIGHT_CYAN','BRIGHT_WHITE'
    )) {
        $theme["ANSI_$name"] = '#778899'
    }

    $null = Invoke-TypezeroOfflineTerminalV2Locked `
        -TestRoot $root -Theme $theme `
        -FontFace 'JetBrainsMono Nerd Font' `
        -FontSize 13 -FontWeight normal `
        -Execute -Confirm:$false

    throw 'FAIL: Child returned without reaching crash checkpoint.'
}

# Parent: use authentic committed modules for independent inspection.
. (Join-Path $engine 'TerminalTransactionV2-WindowsTerminal.ps1')
. (Join-Path $engine 'TerminalEvidenceSealV2-WindowsTerminal.ps1')

$repo = (Resolve-Path (Join-Path $engine '..\..\..')).Path

if ((git -C $repo branch --show-current).Trim() -cne
    'feature/themeengine-font-management') {
    throw 'REFUSED: Unexpected development branch.'
}

$transactionPath = Join-Path $engine 'TerminalTransactionV2-WindowsTerminal.ps1'
$replacePath = Join-Path $engine 'TerminalReplace-WindowsTerminal.ps1'
$sealPath = Join-Path $engine 'TerminalEvidenceSealV2-WindowsTerminal.ps1'

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

    if ($actual -cne $expectedHashes[$name]) {
        throw "REFUSED: Source hash mismatch: $name"
    }
}

$originalSource = [IO.File]::ReadAllText($transactionPath)
$normalized = $originalSource.Replace("`r`n", "`n")

# Instrument only the APPLY function. Never alter the committed source.
$endMarker = 'function Restore-TypezeroOfflineTerminalCombinedTransactionV2'
$parts = $normalized.Split(
    @($endMarker),
    [StringSplitOptions]::None
)

if ($parts.Count -ne 2) {
    throw 'REFUSED: V2 function boundary is ambiguous.'
}

$applySource = $parts[0]

$hooks = @(
    @{
        Name = 'AFTER_STAGE'
        Old = 'Write-TypezeroOfflineTerminalV2NewFile -Path $stage -Bytes $stageBytes'
        New = 'Write-TypezeroOfflineTerminalV2NewFile -Path $stage -Bytes $stageBytes' +
              "`n    Invoke-TypezeroV2CrashCheckpoint -Name 'AFTER_STAGE'"
    }
    @{
        Name = 'AFTER_RECEIPT'
        Old = '-Bytes ($utf8.GetBytes(($receipt | ConvertTo-Json -Depth 8)))'
        New = '-Bytes ($utf8.GetBytes(($receipt | ConvertTo-Json -Depth 8)))' +
              "`n    Invoke-TypezeroV2CrashCheckpoint -Name 'AFTER_RECEIPT'"
    }
    @{
        Name = 'AFTER_VERIFIED'
        Old = "    [pscustomobject]@{`n        Status = 'VERIFIED'; Version = 2"
        New = "    Invoke-TypezeroV2CrashCheckpoint -Name 'AFTER_VERIFIED'`n" +
              "    [pscustomobject]@{`n        Status = 'VERIFIED'; Version = 2"
    }
)

foreach ($hook in $hooks) {
    $count = [regex]::Matches(
        $applySource,
        [regex]::Escape($hook.Old)
    ).Count

    if ($count -ne 1) {
        throw "REFUSED: Ambiguous checkpoint $($hook.Name): $count"
    }

    $applySource = $applySource.Replace($hook.Old, $hook.New)
}

$replaceSource = [IO.File]::ReadAllText($replacePath).Replace("`r`n", "`n")

$replacementOld = @"
    [IO.File]::Replace(
        `$stage,
        `$settings,
        `$backup,
        `$false
    )
"@

$replacementNew = $replacementOld +
    "`n    Invoke-TypezeroV2CrashCheckpoint -Name 'AFTER_FILE_REPLACE'"

if ([regex]::Matches(
    $replaceSource,
    [regex]::Escape($replacementOld)
).Count -ne 1) {
    throw 'REFUSED: File.Replace insertion point is ambiguous.'
}

$instrumentedReplacement = $replaceSource.Replace(
    $replacementOld, $replacementNew
)

$replacementTokens = $null
$replacementErrors = $null

[Management.Automation.Language.Parser]::ParseInput(
    $instrumentedReplacement,
    [ref]$replacementTokens,
    [ref]$replacementErrors
) | Out-Null

if ($replacementErrors.Count -ne 0) {
    throw 'REFUSED: Instrumented replacement parser errors.'
}
$instrumentedSource = $applySource + $endMarker + $parts[1]

$tokens = $null
$parseErrors = $null
[Management.Automation.Language.Parser]::ParseInput(
    $instrumentedSource, [ref]$tokens, [ref]$parseErrors
) | Out-Null

if ($parseErrors.Count -ne 0) {
    throw "REFUSED: Instrumented V2 parser errors: $($parseErrors.Count)"
}

function Get-FixtureInventory {
    param([string]$Root)

    $items = @(
        Get-ChildItem -LiteralPath $Root -Recurse -Force -File |
            Where-Object {
                $_.FullName -notlike (Join-Path $Root 'control\*')
            } |
            Sort-Object FullName
    )

    @(
        foreach ($item in $items) {
            "$($item.FullName.Substring($Root.Length))|" +
            "$((Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash)"
        }
    ) -join "`n"
}

$initial = [ordered]@{
    theme = 'Typezero ThemeEngine'
    schemes = @(
        @{ name='Typezero Obsidian Silver'; background='#000000' }
    )
    themes = @(
        @{
            name = 'Typezero ThemeEngine'
            window = @{ applicationTheme='dark' }
            tab = @{ background='terminalBackground' }
            tabRow = @{ background='#000000' }
        }
    )
    profiles = @{
        defaults = @{}
        list = @(
            @{
                guid='{574e775e-4f2a-5b96-ac1e-a2962a402336}'
                name='PowerShell'
                colorScheme='Typezero Obsidian Silver'
            }
        )
    }
}

$checks = 0

foreach ($case in @(
    @{ Point='AFTER_STAGE';   State='EVIDENCE_INCOMPLETE'; Backup=$false; Receipt=$false; Applied=$false; Stage=1 }
    @{ Point='AFTER_RECEIPT'; State='EVIDENCE_INCOMPLETE'; Backup=$false; Receipt=$true;  Applied=$false; Stage=1 }
    @{ Point='AFTER_FILE_REPLACE';State='APPLIED_BYTES_PRESENT'; Backup=$true; Receipt=$true; Applied=$true; Stage=0 }
    @{ Point='AFTER_VERIFIED';State='APPLIED_BYTES_PRESENT'; Backup=$true; Receipt=$true;  Applied=$true;  Stage=0 }
)) {
    $root = Join-Path ([IO.Path]::GetTempPath()) (
        'typezero-terminal-txn-' + [guid]::NewGuid().ToString('N')
    )

    [IO.Directory]::CreateDirectory($root) | Out-Null

    $paths = Get-TypezeroOfflineTerminalV2Paths -TestRoot $root

    [IO.Directory]::CreateDirectory(
        [IO.Path]::GetDirectoryName($paths.Settings)
    ) | Out-Null

    [IO.Directory]::CreateDirectory(
        (Join-Path $root 'instrumented')
    ) | Out-Null

    [IO.Directory]::CreateDirectory(
        (Join-Path $root 'control')
    ) | Out-Null

    [IO.File]::WriteAllText(
        $paths.Settings,
        ($initial | ConvertTo-Json -Depth 20),
        $utf8
    )

    $originalHash = (
        Get-FileHash -LiteralPath $paths.Settings -Algorithm SHA256
    ).Hash

    [IO.File]::WriteAllText(
        (Join-Path $root 'instrumented\TerminalTransactionV2-WindowsTerminal.ps1'),
        $instrumentedSource,
        $utf8
    )
    [IO.File]::WriteAllText(
        (Join-Path $root 'instrumented\TerminalReplace-WindowsTerminal.ps1'),
        $instrumentedReplacement,
        $utf8
    )

    $token = [guid]::NewGuid().ToString('N')
    $signal = Join-Path $root 'control\paused.json'

    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = (Get-Command pwsh -ErrorAction Stop).Source
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    foreach ($arg in @(
        '-NoProfile','-NonInteractive','-File',$PSCommandPath,
        '-Mode','Child','-TestRoot',$root,
        '-Point',$case.Point,'-Token',$token
    )) {
        $psi.ArgumentList.Add($arg)
    }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $psi

    Write-Host "`n=== V2 INTERRUPTION: $($case.Point) ==="

    try {
        if (-not $process.Start()) {
            throw 'FAIL: Child process could not start.'
        }

        $started = $process.StartTime.ToUniversalTime().Ticks
        $deadline = [DateTime]::UtcNow.AddSeconds(15)
        $paused = $null

        while ([DateTime]::UtcNow -lt $deadline) {
            if ($process.HasExited) {
                throw "FAIL: Child exited before checkpoint $($case.Point)."
            }

            if ([IO.File]::Exists($signal)) {
                try {
                    $paused = [IO.File]::ReadAllText($signal) |
                        ConvertFrom-Json -ErrorAction Stop
                }
                catch {
                    $paused = $null
                }

                if ($null -ne $paused) { break }
            }

            Start-Sleep -Milliseconds 50
        }

        if ($null -eq $paused -or
            $paused.Point -cne $case.Point -or
            $paused.Token -cne $token -or
            $paused.ProcessId -ne $process.Id -or
            $paused.StartTicks -ne $started -or
            $paused.TestRoot -cne $root) {
            throw 'FAIL: Child checkpoint acknowledgement invalid.'
        }

        $folder = $paused.BackupDirectory

        $null = Assert-TypezeroOfflineTerminalV2Folder `
            -Paths $paths -BackupDirectory $folder

        $process.Kill()
        if (-not $process.WaitForExit(5000)) {
            throw 'FAIL: Child failed to terminate.'
        }

        $checks++
        Write-Host "PASS [$checks] Identified child terminated at checkpoint."

        $receipt = Join-Path $folder 'receipt.json'
        $backup = Join-Path $folder 'settings-pre-replace.json'
        $seal = Join-Path $folder 'evidence.seal'

        $stages = @(
            Get-ChildItem `
                -LiteralPath (Split-Path -Parent $paths.Settings) `
                -Filter '.typezero-combined-*.tmp' -File
        )

        if ([IO.File]::Exists($receipt) -ne $case.Receipt -or
            [IO.File]::Exists($backup) -ne $case.Backup -or
            [IO.File]::Exists($seal) -or
            $stages.Count -ne $case.Stage) {
            throw "FAIL: Unexpected artifacts at $($case.Point)."
        }

        $currentHash = (
            Get-FileHash $paths.Settings -Algorithm SHA256
        ).Hash

        if (-not $case.Applied -and $currentHash -cne $originalHash) {
            throw 'FAIL: Original settings changed before replacement.'
        }

        if ($case.Applied -and $currentHash -ceq $originalHash) {
            throw 'FAIL: Expected replacement settings were not installed.'
        }

        if ($case.Backup -and
            (Get-FileHash $backup -Algorithm SHA256).Hash -cne $originalHash) {
            throw 'FAIL: Original backup bytes differ.'
        }

        $checks++
        Write-Host "PASS [$checks] Surviving fixture artifacts match checkpoint."

        [byte[]]$independentKey = [byte[]]::new(32)
        [Security.Cryptography.RandomNumberGenerator]::Fill($independentKey)

        $beforeInspection = Get-FixtureInventory $root

        $diagnostic = Get-TypezeroOfflineTerminalCombinedV2RecoveryDiagnostic `
            -TestRoot $root -BackupDirectory $folder

        $sealResult = Get-TypezeroOfflineTerminalV2SealResult `
            -TestRoot $root -BackupDirectory $folder `
            -IndependentKey $independentKey

        $afterInspection = Get-FixtureInventory $root

        if ($diagnostic.State -cne $case.State -or
            -not $diagnostic.ReadOnly -or
            $diagnostic.RecoveryAllowed -ne $false -or
            $diagnostic.OperationPhase -cne 'UNKNOWN' -or
            $sealResult.Status -cne 'INCOMPLETE' -or
            $sealResult.ReceiptAuthenticated -ne $false -or
            $sealResult.RecoveryAuthorized -ne $false -or
            $sealResult.LiveActivationAuthorized -ne $false -or
            $sealResult.OperationPhase -cne 'UNKNOWN' -or
            $beforeInspection -cne $afterInspection) {
            throw "FAIL: Read-only recovery boundary at $($case.Point)."
        }

        [array]::Clear($independentKey, 0, $independentKey.Length)

        $checks++
        Write-Host "PASS [$checks] Diagnostics read-only; phase unknown; recovery refused."

        $lockPath = Join-Path $root '.typezero-terminal-v2.lock'

        $lock = [IO.FileStream]::new(
            $lockPath,
            [IO.FileMode]::Open,
            [IO.FileAccess]::ReadWrite,
            [IO.FileShare]::None
        )

        try {
            $checks++
            Write-Host "PASS [$checks] Child termination released transaction lock."
        }
        finally {
            $lock.Dispose()
        }

        Write-Host "Fixture retained: $root"
    }
    finally {
        if (-not $process.HasExited) {
            $process.Kill()
            $process.WaitForExit()
        }

        $process.Dispose()
    }
}

if ($checks -ne 16) {
    throw "FAIL: Expected 16 checks; observed $checks."
}

Write-Host "`nPASS: 16/16 V2 interruption checks."
Write-Host 'RecoveryAuthorized=False'
Write-Host 'LiveActivationAuthorized=False'
