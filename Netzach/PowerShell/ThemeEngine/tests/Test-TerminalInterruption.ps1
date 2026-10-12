param([string]$SourceDirectory = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Use PowerShell 7 or later.' }
$script:checks = 0
$script:retainedFixtures = [Collections.Generic.List[string]]::new()
$script:caseResults = [Collections.Generic.List[object]]::new()
$utf8 = [Text.UTF8Encoding]::new($false, $true)
$moduleNames = @('FontPatch-WindowsTerminal.ps1', 'TerminalColorPatch-WindowsTerminal.ps1',
    'TerminalCombinedPatch-WindowsTerminal.ps1', 'TerminalTransaction-WindowsTerminal.ps1')
$transactionName = $moduleNames[-1]
$childSource = Join-Path $PSScriptRoot 'Invoke-TerminalInterruptionChild.ps1'
$pwsh = (Get-Command pwsh -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source

function Assert-Interruption([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:checks++
    Write-Host "PASS: $Name"
}
function Get-BytesHash([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-', '') }
    finally { $sha.Dispose() }
}
function Get-Hash([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
}
function Get-PureSourceAst([string]$Text, [string]$Name) {
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$errors)
    if ($errors.Count -ne 0) { throw "Source has parse errors: $Name" }
    if ($null -ne $ast.BeginBlock -or $null -ne $ast.ProcessBlock -or
        $null -ne $ast.ParamBlock -or $null -ne $ast.DynamicParamBlock -or
        $ast.EndBlock.Statements.Count -eq 0) { throw "Module must contain only function definitions: $Name" }
    foreach ($statement in $ast.EndBlock.Statements) {
        if ($statement -isnot [Management.Automation.Language.FunctionDefinitionAst]) {
            throw "Unsafe top-level statement rejected in module: $Name"
        }
    }
    $ast
}

# Capture source bytes before dot-sourcing; reject every executable top-level
# statement. Production entry points and private configuration are never loaded.
$sourceBytes = [ordered]@{}
$sourceText = [ordered]@{}
$sourceAst = [ordered]@{}
foreach ($name in $moduleNames) {
    $path = Join-Path $SourceDirectory $name
    $sourceBytes[$name] = [IO.File]::ReadAllBytes($path)
    $sourceText[$name] = $utf8.GetString($sourceBytes[$name])
    $sourceAst[$name] = Get-PureSourceAst $sourceText[$name] $name
    . ([scriptblock]::Create($sourceText[$name]))
}

function New-InstrumentedTransaction {
    $text = $sourceText[$transactionName]
    $ast = $sourceAst[$transactionName]
    $points = @(
        @{ Operation = 'Apply'; Point = 'DIRECTORY_CREATED'; Pattern = 'New-Item -ItemType Directory -Path \$folder -Force `\r?\n        -ErrorAction Stop \| Out-Null' },
        @{ Operation = 'Apply'; Point = 'BACKUP_COPIED'; Pattern = 'Copy-Item -LiteralPath \$paths.Settings -Destination \$backup `\r?\n        -ErrorAction Stop' },
        @{ Operation = 'Apply'; Point = 'STAGE_WRITTEN'; Pattern = '\[IO.File\]::WriteAllText\(\$stage, \$candidate, \$utf8\)' },
        @{ Operation = 'Apply'; Point = 'RECEIPT_WRITTEN'; Pattern = '\[IO.File\]::WriteAllText\(\r?\n            \$receiptPath,\r?\n            \(\$receipt \| ConvertTo-Json -Depth 10\),\r?\n            \$utf8\r?\n        \)' },
        @{ Operation = 'Apply'; Point = 'SETTINGS_REPLACED'; Pattern = 'Move-Item -LiteralPath \$stage -Destination \$paths.Settings `\r?\n            -Force -ErrorAction Stop' },
        @{ Operation = 'Apply'; Point = 'VERIFIED'; Pattern = 'if \(\$verifiedHash -ne \$afterHash\) \{\r?\n            throw "Transaction verification failed\. Backup: \$folder"\r?\n        \}' },
        @{ Operation = 'Restore'; Point = 'STAGE_COPIED'; Pattern = 'Copy-Item -LiteralPath \$backup -Destination \$stage `\r?\n            -ErrorAction Stop' },
        @{ Operation = 'Restore'; Point = 'SETTINGS_REPLACED'; Pattern = 'Move-Item -LiteralPath \$stage -Destination \$paths.Settings `\r?\n            -Force -ErrorAction Stop' },
        @{ Operation = 'Restore'; Point = 'VERIFIED'; Pattern = 'if \(\$finalHash -ne \$receipt.BeforeSha256\) \{\r?\n            throw ''Transaction restoration verification failed\.''\r?\n        \}' }
    )
    $insertions = [Collections.Generic.List[object]]::new()
    foreach ($point in $points) {
        $functionName = if ($point.Operation -ceq 'Apply') {
            'Invoke-TypezeroOfflineTerminalCombinedTransaction'
        } else { 'Restore-TypezeroOfflineTerminalCombinedTransaction' }
        $functions = @($ast.EndBlock.Statements | Where-Object Name -CEQ $functionName)
        if ($functions.Count -ne 1) { throw "Expected exactly one definition: $functionName" }
        $matches = [regex]::Matches($functions[0].Extent.Text, $point.Pattern)
        if ($matches.Count -ne 1) { throw "Checkpoint anchor must match exactly once: $($point.Operation)/$($point.Point)" }
        $offset = $functions[0].Extent.StartOffset + $matches[0].Index + $matches[0].Length
        $newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
        $insertion = $newline + "        # TYPEZERO_INTERRUPTION_BEGIN $($point.Operation)/$($point.Point)" + $newline +
            "        Invoke-TypezeroInterruptionCheckpoint -Operation '$($point.Operation)' -Checkpoint '$($point.Point)' -BackupDirectory `$folder" +
            $newline + "        # TYPEZERO_INTERRUPTION_END $($point.Operation)/$($point.Point)"
        $insertions.Add([pscustomobject]@{ Offset = $offset; Text = $insertion })
    }
    $instrumented = $text
    foreach ($insertion in ($insertions | Sort-Object Offset -Descending)) {
        $instrumented = $instrumented.Insert($insertion.Offset, $insertion.Text)
    }
    # Remove only our nine precisely recorded insertions and prove byte identity.
    $reconstructed = $instrumented
    foreach ($insertion in $insertions) {
        $count = [regex]::Matches($reconstructed, [regex]::Escape($insertion.Text)).Count
        if ($count -ne 1) { throw 'Instrumented checkpoint text is missing or ambiguous.' }
        $reconstructed = $reconstructed.Replace($insertion.Text, '')
    }
    Assert-Interruption ((Get-BytesHash $utf8.GetBytes($reconstructed)) -ceq
        (Get-BytesHash $sourceBytes[$transactionName])) 'Removing nine checkpoint calls reproduces exact source bytes'
    $null = Get-PureSourceAst $instrumented 'instrumented transaction'
    $instrumented
}
$instrumentedTransaction = New-InstrumentedTransaction

$original = @'
{
    // Entirely synthetic JSONC; no actual settings or configuration is copied.
    "theme":"Typezero ThemeEngine",
    "schemes":[{"name":"Typezero Obsidian Silver","background":"#000000","custom":"retained"}],
    "themes":[{"name":"Typezero ThemeEngine","window":{"applicationTheme":"dark","custom":"retained"},"tab":{"background":"terminalBackground"},"tabRow":{"background":"#000000"}}],
    "profiles":{"defaults":{},"list":[
        {"guid":"{574e775e-4f2a-5b96-ac1e-a2962a402336}","name":"PowerShell","colorScheme":"Typezero Obsidian Silver"},
        {"guid":"{00000000-0000-0000-0000-000000000001}","name":"Untouched","custom":"retained"}
    ]},
    "customRoot":{"preserved":"yes"}
}
'@
$originalBytes = $utf8.GetBytes($original)
$originalHash = Get-BytesHash $originalBytes
$theme = @{ THEME_NAME = 'Obsidian Silver'; BG = '#123456'; TEXT = '#eeeeee';
    CURSOR = '#ffffff'; SELECTION = '#445566' }
foreach ($name in @('BLACK','RED','GREEN','YELLOW','BLUE','PURPLE','CYAN','WHITE',
    'BRIGHT_BLACK','BRIGHT_RED','BRIGHT_GREEN','BRIGHT_YELLOW','BRIGHT_BLUE',
    'BRIGHT_PURPLE','BRIGHT_CYAN','BRIGHT_WHITE')) { $theme["ANSI_$name"] = '#778899' }
$font = @{ FontFace = 'JetBrainsMono Nerd Font'; FontSize = 12; FontWeight = 'semi-bold' }
$candidate = New-TypezeroTerminalCombinedJsonCandidate -JsonText $original -Theme $theme @font
$candidateHash = Get-BytesHash $utf8.GetBytes($candidate)
Assert-Interruption ($candidateHash -cne $originalHash) 'Synthetic combined candidate changes settings bytes'

function Assert-OwnedFixture([string]$Root) {
    $full = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if (-not $script:retainedFixtures.Contains($full)) { throw 'Root was not created by this harness.' }
    $paths = Get-TypezeroOfflineTerminalTransactionPaths -TestRoot $full
    $paths
}
function New-InterruptionFixture {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('typezero-terminal-txn-' + [guid]::NewGuid().ToString('N'))
    if (Test-Path -LiteralPath $root) { throw 'Refusing to reuse an existing temporary fixture.' }
    $null = New-Item -ItemType Directory -Path $root -ErrorAction Stop
    $script:retainedFixtures.Add($root)
    $paths = Assert-OwnedFixture $root
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $paths.Settings) -Force -ErrorAction Stop
    [IO.File]::WriteAllBytes($paths.Settings, $originalBytes)
    foreach ($subdir in @('control','instrumented','uninstrumented')) {
        $null = New-Item -ItemType Directory -Path (Join-Path $root $subdir) -ErrorAction Stop
    }
    $protectedDirectory = Join-Path $root 'SyntheticProtected'
    $existingBackupDirectory = Join-Path $paths.BackupRoot 'synthetic-existing-backup'
    $null = New-Item -ItemType Directory -Path $protectedDirectory -ErrorAction Stop
    $null = New-Item -ItemType Directory -Path $existingBackupDirectory -Force -ErrorAction Stop
    [IO.File]::WriteAllText((Join-Path $protectedDirectory 'private-v1.json'), '{"fixtureOnly":"private-v1 sentinel"}', $utf8)
    [IO.File]::WriteAllText((Join-Path $protectedDirectory 'private-v2.json'), '{"fixtureOnly":"private-v2 sentinel"}', $utf8)
    [IO.File]::WriteAllText((Join-Path $existingBackupDirectory 'settings-original.json'), '{"fixtureOnly":"existing backup sentinel"}', $utf8)
    [IO.File]::WriteAllText((Join-Path $existingBackupDirectory 'receipt.json'), '{"fixtureOnly":"existing receipt sentinel"}', $utf8)
    foreach ($name in $moduleNames) {
        [IO.File]::WriteAllBytes((Join-Path (Join-Path $root 'uninstrumented') $name), $sourceBytes[$name])
        if ($name -ceq $transactionName) {
            [IO.File]::WriteAllText((Join-Path (Join-Path $root 'instrumented') $name), $instrumentedTransaction, $utf8)
        }
        else { [IO.File]::WriteAllBytes((Join-Path (Join-Path $root 'instrumented') $name), $sourceBytes[$name]) }
    }
    Copy-Item -LiteralPath $childSource -Destination (Join-Path $root 'control\child.ps1') -ErrorAction Stop
    $paths
}
function Get-FixtureSnapshot([string]$Root) {
    $null = Assert-OwnedFixture $Root
    $all = @((Get-Item -LiteralPath $Root -Force -ErrorAction Stop)) +
        @(Get-ChildItem -LiteralPath $Root -Recurse -Force -ErrorAction Stop)
    $entries = @(
        foreach ($item in ($all | Sort-Object FullName)) {
            Assert-TypezeroOfflinePlainPath -Path $item.FullName
            [pscustomobject]@{
                RelativePath = $item.FullName.Substring($Root.Length)
                IsDirectory = $item.PSIsContainer
                Attributes = [int]$item.Attributes
                CreatedUtcTicks = $item.CreationTimeUtc.Ticks
                LastWrittenUtcTicks = $item.LastWriteTimeUtc.Ticks
                # Access times can be updated by NTFS during ordinary reads;
                # creation/write timestamps and attributes detect mutations.
                Length = $(if ($item.PSIsContainer) { $null } else { $item.Length })
                Bytes = $(if ($item.PSIsContainer) { $null } else {
                    [Convert]::ToBase64String([IO.File]::ReadAllBytes($item.FullName))
                })
            }
        }
    )
    ConvertTo-Json -InputObject $entries -Depth 8 -Compress
}
function Get-StableFixtureSnapshot([string]$Root) {
    # NTFS can publish directory write times shortly after child/file handles
    # close. Establish a stable baseline BEFORE diagnosis; never normalize or
    # relax any byte, tree, creation/write-time or attribute comparison afterward.
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $previous = Get-FixtureSnapshot $Root
    $identical = 0
    while ($clock.ElapsedMilliseconds -lt 1000) {
        Start-Sleep -Milliseconds 20
        $current = Get-FixtureSnapshot $Root
        if ($current -ceq $previous) { $identical++ } else { $identical = 0 }
        if ($identical -ge 2) { $clock.Stop(); return $current }
        $previous = $current
    }
    throw 'Fixture bytes or metadata did not stabilize within one second before inspection.'
}
function Get-StagePaths([string]$Settings) {
    @(Get-ChildItem -LiteralPath (Split-Path -Parent $Settings) -Force -ErrorAction Stop |
        Where-Object Name -CMatch '\A\.typezero-combined-(?:restore-)?[a-f0-9]{32}\.tmp\z' |
        Sort-Object Name | ForEach-Object FullName)
}
function Get-ProtectedSentinelSnapshot([string]$Root) {
    $all = Get-StableFixtureSnapshot $Root | ConvertFrom-Json
    $protected = @($all | Where-Object {
        $_.RelativePath -clike '\SyntheticProtected*' -or
        $_.RelativePath -clike '\Typezero\ThemeEngine\backups\terminal-combined\synthetic-existing-backup*'
    })
    ConvertTo-Json -InputObject $protected -Depth 8 -Compress
}
function Start-FixtureChild([object]$Paths, [string]$Operation, [string]$Checkpoint,
    [string]$BackupDirectory, [switch]$Uninstrumented) {
    $null = Assert-OwnedFixture $Paths.Root
    $control = Join-Path $Paths.Root 'control'
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $pwsh
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.WorkingDirectory = $Paths.Root
    $token = [guid]::NewGuid().ToString('N')
    foreach ($arg in @('-NoProfile', '-NonInteractive', '-File', (Join-Path $control 'child.ps1'),
        '-TestRoot', $Paths.Root, '-Operation', $Operation, '-AcknowledgementToken', $token)) { $info.ArgumentList.Add($arg) }
    if ($Checkpoint) { $info.ArgumentList.Add('-Checkpoint'); $info.ArgumentList.Add($Checkpoint) }
    if ($BackupDirectory) { $info.ArgumentList.Add('-BackupDirectory'); $info.ArgumentList.Add($BackupDirectory) }
    if ($Uninstrumented) { $info.ArgumentList.Add('-Uninstrumented') }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    if (-not $process.Start()) { throw 'Child process could not start.' }
    [pscustomobject]@{
        Process = $process
        Output = $process.StandardOutput.ReadToEndAsync()
        Errors = $process.StandardError.ReadToEndAsync()
        Control = $control
        Operation = $Operation
        Checkpoint = $Checkpoint
        AcknowledgementToken = $token
        ProcessStartUtcTicks = $process.StartTime.ToUniversalTime().Ticks
        Start = [Diagnostics.Stopwatch]::StartNew()
    }
}
function Complete-FixtureChild([object]$Child, [switch]$Kill) {
    try {
        if ($Kill -and -not $Child.Process.HasExited) {
            # No process-name/PID search, shell terminate command or global kill.
            $Child.Process.Kill()
        }
        $remaining = [Math]::Max(0, 14000 - [int]$Child.Start.ElapsedMilliseconds)
        if (-not $Child.Process.WaitForExit($remaining)) {
            $Child.Process.Kill()
            if (-not $Child.Process.WaitForExit(1000)) {
                throw 'Started fixture child did not acknowledge hard termination within the 15 second deadline.'
            }
            throw 'Fixture child exceeded the 15 second per-case deadline.'
        }
        $output = $Child.Output.GetAwaiter().GetResult()
        $errors = $Child.Errors.GetAwaiter().GetResult()
        $prefix = if ($Child.Checkpoint) { $Child.Operation + '-' + $Child.Checkpoint } else { $Child.Operation + '-control' }
        [IO.File]::WriteAllText((Join-Path $Child.Control ($prefix + '-stdout.log')), $output, $utf8)
        [IO.File]::WriteAllText((Join-Path $Child.Control ($prefix + '-stderr.log')), $errors, $utf8)
        [pscustomobject]@{ ExitCode = $Child.Process.ExitCode; Output = $output; Errors = $errors }
    }
    finally { $Child.Start.Stop(); $Child.Process.Dispose() }
}
function Stop-AtCheckpoint([object]$Paths, [string]$Operation, [string]$Checkpoint, [string]$BackupDirectory = '') {
    $child = Start-FixtureChild $Paths $Operation $Checkpoint $BackupDirectory
    $paused = $null
    try {
        $signal = Join-Path $child.Control 'paused.json'
        while ($child.Start.ElapsedMilliseconds -lt 12000) {
            if ($child.Process.HasExited) { break }
            if (Test-Path -LiteralPath $signal -PathType Leaf) {
                try { $paused = [IO.File]::ReadAllText($signal) | ConvertFrom-Json -ErrorAction Stop }
                catch { $paused = $null }
                if ($null -ne $paused) { break }
            }
            Start-Sleep -Milliseconds 20
        }
        Assert-Interruption ($null -ne $paused -and -not $child.Process.HasExited) "$Operation/$Checkpoint child reached live pause"
        Assert-Interruption ($paused.ProcessId -eq $child.Process.Id -and
            $paused.Operation -ceq $Operation -and $paused.Checkpoint -ceq $Checkpoint -and
            $paused.TestRoot -ceq $Paths.Root -and
            $paused.AcknowledgementToken -ceq $child.AcknowledgementToken -and
            $paused.ProcessStartUtcTicks -eq $child.ProcessStartUtcTicks) "$Operation/$Checkpoint nonce, PID and start-time identify started fixture process"
        Assert-Interruption (-not (Test-Path -LiteralPath (Join-Path $child.Control 'completed.json'))) "$Operation/$Checkpoint has no completion before kill"
        $preKill = Get-StableFixtureSnapshot $Paths.Root
        $finishingChild = $child
        $child = $null
        $log = Complete-FixtureChild $finishingChild -Kill
        Assert-Interruption ($log.ExitCode -ne 0 -and -not $log.Output.Contains('Completed ') -and
            -not (Test-Path -LiteralPath (Join-Path $Paths.Root 'control\completed.json'))) "$Operation/$Checkpoint hard termination has no completion result"
        # Only the parent-owned stdout/stderr logs were added after termination.
        # Exclude them for the kill comparison, then include everything in the
        # subsequent complete before/after diagnostic byte/metadata snapshots.
        $killSnapshot = @(Get-FixtureSnapshot $Paths.Root | ConvertFrom-Json | Where-Object {
            $_.RelativePath -cnotmatch '\\control\\(?:Apply|Restore)-.+-(?:stdout|stderr)\.log\z'
        })
        $beforeKillSnapshot = @(ConvertFrom-Json $preKill)
        foreach ($entry in $killSnapshot) {
            if ($entry.RelativePath -eq '\control' -or $entry.RelativePath -eq '') {
                # Creating log files updates those directory write timestamps.
                $before = @($beforeKillSnapshot | Where-Object RelativePath -CEQ $entry.RelativePath)[0]
                $entry.LastWrittenUtcTicks = $before.LastWrittenUtcTicks
            }
        }
        Assert-Interruption ((ConvertTo-Json -InputObject $killSnapshot -Depth 8 -Compress) -ceq
            (ConvertTo-Json -InputObject $beforeKillSnapshot -Depth 8 -Compress)) "$Operation/$Checkpoint bypasses finally and preserves retained artifacts"
        $paused
    }
    finally {
        if ($null -ne $child) { $null = Complete-FixtureChild $child -Kill }
    }
}
function Assert-DiagnosticReadOnly([object]$Paths, [string]$Folder, [string]$State,
    [int]$StageCount, [string]$Name) {
    $before = Get-StableFixtureSnapshot $Paths.Root
    $diagnostic = Get-TypezeroOfflineTerminalCombinedRecoveryDiagnostic -TestRoot $Paths.Root -BackupDirectory $Folder
    $after = Get-FixtureSnapshot $Paths.Root
    if ($before -cne $after) {
        [IO.File]::WriteAllText((Join-Path $Paths.Root 'control\diagnostic-before.json'), $before, $utf8)
        [IO.File]::WriteAllText((Join-Path $Paths.Root 'control\diagnostic-after.json'), $after, $utf8)
    }
    Assert-Interruption ($before -ceq $after) "$Name diagnostic preserves entire fixture tree, bytes and metadata"
    $second = Get-TypezeroOfflineTerminalCombinedRecoveryDiagnostic -TestRoot $Paths.Root -BackupDirectory $Folder
    $afterSecond = Get-FixtureSnapshot $Paths.Root
    Assert-Interruption ($after -ceq $afterSecond -and
        ($diagnostic | ConvertTo-Json -Depth 12 -Compress) -ceq
        ($second | ConvertTo-Json -Depth 12 -Compress)) "$Name repeated diagnostic is identical and preserves full fixture"
    Assert-Interruption ($diagnostic.State -ceq $State -and $diagnostic.ReadOnly -and
        -not $diagnostic.RecoveryAllowed) "$Name reports $State without repair authorization"
    Assert-Interruption ($diagnostic.StageFiles.Count -eq $StageCount -and
        @(Get-StagePaths $Paths.Settings).Count -eq $StageCount) "$Name retained stage count $StageCount"
    foreach ($stage in $diagnostic.StageFiles) {
        Assert-Interruption ($stage.Association -ceq 'UNPROVEN') "$Name stage is never associated with receipt"
    }
    $diagnostic
}
function Assert-BackupEvidence([object]$Paths, [string]$Folder, [bool]$HasBackup,
    [bool]$HasReceipt, [string]$Name) {
    $backup = Join-Path $Folder 'settings-original.json'
    $receipt = Join-Path $Folder 'receipt.json'
    Assert-Interruption ((Test-Path -LiteralPath $backup -PathType Leaf) -eq $HasBackup -and
        (Test-Path -LiteralPath $receipt -PathType Leaf) -eq $HasReceipt) "$Name expected backup and receipt presence"
    if ($HasBackup) {
        Assert-Interruption ((Get-Hash $backup) -ceq $originalHash) "$Name original backup retains exact synthetic bytes"
    }
    if ($HasReceipt) {
        $doc = [IO.File]::ReadAllText($receipt) | ConvertFrom-Json -ErrorAction Stop
        Assert-Interruption ($doc.Version -eq 1 -and $doc.Kind -ceq 'TypezeroOfflineCombined' -and
            $doc.SettingsPath -ceq $Paths.Settings -and $doc.BeforeSha256 -ceq $originalHash -and
            $doc.AfterSha256 -ceq $candidateHash) "$Name receipt identifies exact before/after fixture bytes"
    }
}

try {
    # An actual uninstrumented child proves the exact copied transaction source
    # applies and restores correctly using the same synthetic fixture setup.
    $controlPaths = New-InterruptionFixture
    $controlProtected = Get-ProtectedSentinelSnapshot $controlPaths.Root
    foreach ($name in $moduleNames) {
        Assert-Interruption ((Get-Hash (Join-Path $controlPaths.Root "uninstrumented\$name")) -ceq
            (Get-BytesHash $sourceBytes[$name])) "Uninstrumented $name is byte-identical to source"
    }
    $controlChild = Start-FixtureChild $controlPaths 'Apply' '' '' -Uninstrumented
    $controlLog = Complete-FixtureChild $controlChild
    $completionPath = Join-Path $controlPaths.Root 'control\completed.json'
    $controlResult = [IO.File]::ReadAllText($completionPath) | ConvertFrom-Json -ErrorAction Stop
    Assert-Interruption ($controlLog.ExitCode -eq 0 -and $controlResult.Status -ceq 'VERIFIED' -and
        (Get-Hash $controlPaths.Settings) -ceq $candidateHash) 'Uninstrumented child successfully applies exact candidate bytes'
    $controlFolder = $controlResult.BackupDirectory
    Assert-BackupEvidence $controlPaths $controlFolder $true $true 'Uninstrumented apply control'
    $controlBackup = [IO.File]::ReadAllBytes((Join-Path $controlFolder 'settings-original.json'))
    $controlReceipt = [IO.File]::ReadAllBytes((Join-Path $controlFolder 'receipt.json'))
    $null = Assert-DiagnosticReadOnly $controlPaths $controlFolder 'APPLIED_BYTES_PRESENT' 0 'Uninstrumented apply control'
    # A previous completion cannot conceal a failure or new result.
    Remove-Item -LiteralPath $completionPath -Force -ErrorAction Stop
    $controlChild = Start-FixtureChild $controlPaths 'Restore' '' $controlFolder -Uninstrumented
    $controlLog = Complete-FixtureChild $controlChild
    $controlResult = [IO.File]::ReadAllText($completionPath) | ConvertFrom-Json -ErrorAction Stop
    Assert-Interruption ($controlLog.ExitCode -eq 0 -and $controlResult.Status -ceq 'RESTORED' -and
        (Get-Hash $controlPaths.Settings) -ceq $originalHash) 'Uninstrumented child successfully restores exact original bytes'
    Assert-Interruption ((Get-Hash (Join-Path $controlFolder 'settings-original.json')) -ceq (Get-BytesHash $controlBackup) -and
        (Get-Hash (Join-Path $controlFolder 'receipt.json')) -ceq (Get-BytesHash $controlReceipt)) 'Uninstrumented restore preserves original backup and receipt bytes'
    $null = Assert-DiagnosticReadOnly $controlPaths $controlFolder 'ORIGINAL_BYTES_PRESENT' 0 'Uninstrumented restore control'
    Assert-Interruption ((Get-ProtectedSentinelSnapshot $controlPaths.Root) -ceq $controlProtected) 'Uninstrumented child control preserves synthetic private configs and existing backup sentinels'
    $script:caseResults.Add([pscustomobject]@{ Operation = 'Apply/Restore'; Checkpoint = 'UNINSTRUMENTED_CONTROL';
        State = 'ORIGINAL_BYTES_PRESENT'; StageCount = 0; Root = $controlPaths.Root; BackupDirectory = $controlFolder })

    foreach ($case in @(
        @{ Point = 'DIRECTORY_CREATED'; State = 'EVIDENCE_INCOMPLETE'; Stages = 0; Backup = $false; Receipt = $false; Applied = $false },
        @{ Point = 'BACKUP_COPIED'; State = 'EVIDENCE_INCOMPLETE'; Stages = 0; Backup = $true; Receipt = $false; Applied = $false },
        @{ Point = 'STAGE_WRITTEN'; State = 'EVIDENCE_INCOMPLETE'; Stages = 1; Backup = $true; Receipt = $false; Applied = $false },
        @{ Point = 'RECEIPT_WRITTEN'; State = 'ORIGINAL_BYTES_PRESENT'; Stages = 1; Backup = $true; Receipt = $true; Applied = $false },
        @{ Point = 'SETTINGS_REPLACED'; State = 'APPLIED_BYTES_PRESENT'; Stages = 0; Backup = $true; Receipt = $true; Applied = $true },
        @{ Point = 'VERIFIED'; State = 'APPLIED_BYTES_PRESENT'; Stages = 0; Backup = $true; Receipt = $true; Applied = $true }
    )) {
        $paths = New-InterruptionFixture
        $protectedBefore = Get-ProtectedSentinelSnapshot $paths.Root
        $paused = Stop-AtCheckpoint $paths 'Apply' $case.Point
        $name = 'Apply/' + $case.Point
        Assert-Interruption ((Get-Hash $paths.Settings) -ceq $(if ($case.Applied) { $candidateHash } else { $originalHash })) "$name expected settings bytes"
        Assert-BackupEvidence $paths $paused.BackupDirectory $case.Backup $case.Receipt $name
        $diagnostic = Assert-DiagnosticReadOnly $paths $paused.BackupDirectory $case.State $case.Stages $name
        if ($case.Stages -eq 1) {
            $stage = @(Get-StagePaths $paths.Settings)[0]
            Assert-Interruption ((Get-Hash $stage) -ceq $candidateHash) "$name stage retains candidate after hard kill"
            $observedStage = $diagnostic.StageFiles[0]
            $expectedMatch = if ($case.Receipt) { 'AFTER' } else { 'UNVERIFIED' }
            Assert-Interruption ($observedStage.Kind -ceq 'APPLY' -and
                $observedStage.ContentMatch -ceq $expectedMatch -and $observedStage.Sha256 -ceq $candidateHash) "$name diagnostic reports exact retained APPLY stage observations"
        }
        Assert-Interruption ((Get-ProtectedSentinelSnapshot $paths.Root) -ceq $protectedBefore) "$name preserves synthetic private configs and existing backup sentinels"
        $script:caseResults.Add([pscustomobject]@{ Operation = 'Apply'; Checkpoint = $case.Point;
            State = $diagnostic.State; StageCount = $diagnostic.StageFiles.Count; Root = $paths.Root;
            BackupDirectory = $paused.BackupDirectory })
    }
    foreach ($case in @(
        @{ Point = 'STAGE_COPIED'; State = 'APPLIED_BYTES_PRESENT'; Stages = 1; Restored = $false },
        @{ Point = 'SETTINGS_REPLACED'; State = 'ORIGINAL_BYTES_PRESENT'; Stages = 0; Restored = $true },
        @{ Point = 'VERIFIED'; State = 'ORIGINAL_BYTES_PRESENT'; Stages = 0; Restored = $true }
    )) {
        $paths = New-InterruptionFixture
        $protectedBefore = Get-ProtectedSentinelSnapshot $paths.Root
        $applied = Invoke-TypezeroOfflineTerminalCombinedTransaction -TestRoot $paths.Root -Theme $theme @font -Execute -Confirm:$false
        $savedBackup = [IO.File]::ReadAllBytes((Join-Path $applied.BackupDirectory 'settings-original.json'))
        $savedReceipt = [IO.File]::ReadAllBytes((Join-Path $applied.BackupDirectory 'receipt.json'))
        $paused = Stop-AtCheckpoint $paths 'Restore' $case.Point $applied.BackupDirectory
        $name = 'Restore/' + $case.Point
        Assert-Interruption ((Get-Hash $paths.Settings) -ceq $(if ($case.Restored) { $originalHash } else { $candidateHash })) "$name expected settings bytes"
        Assert-BackupEvidence $paths $applied.BackupDirectory $true $true $name
        Assert-Interruption ((Get-Hash (Join-Path $applied.BackupDirectory 'settings-original.json')) -ceq (Get-BytesHash $savedBackup) -and
            (Get-Hash (Join-Path $applied.BackupDirectory 'receipt.json')) -ceq (Get-BytesHash $savedReceipt)) "$name interrupted restore preserves backup and receipt bytes"
        $diagnostic = Assert-DiagnosticReadOnly $paths $applied.BackupDirectory $case.State $case.Stages $name
        if ($case.Stages -eq 1) {
            $stage = @(Get-StagePaths $paths.Settings)[0]
            Assert-Interruption ((Get-Hash $stage) -ceq $originalHash) "$name stage retains original bytes after hard kill"
            $observedStage = $diagnostic.StageFiles[0]
            Assert-Interruption ($observedStage.Kind -ceq 'RESTORE' -and
                $observedStage.ContentMatch -ceq 'BEFORE' -and $observedStage.Sha256 -ceq $originalHash) "$name diagnostic reports exact retained RESTORE stage observations"
        }
        Assert-Interruption ((Get-ProtectedSentinelSnapshot $paths.Root) -ceq $protectedBefore) "$name preserves synthetic private configs and existing backup sentinels"
        $script:caseResults.Add([pscustomobject]@{ Operation = 'Restore'; Checkpoint = $case.Point;
            State = $diagnostic.State; StageCount = $diagnostic.StageFiles.Count; Root = $paths.Root;
            BackupDirectory = $applied.BackupDirectory })
    }
    foreach ($name in $moduleNames) {
        Assert-Interruption ((Get-Hash (Join-Path $SourceDirectory $name)) -ceq
            (Get-BytesHash $sourceBytes[$name])) "Source $name remains byte-identical after all tests"
    }
    [pscustomobject]@{
        Status = 'PASS'; Checks = $script:checks; InterruptedCases = 9; UninstrumentedControls = 2
        RetainedFixtures = @($script:retainedFixtures.ToArray()); Cases = @($script:caseResults.ToArray())
        ChildLogs = @(
            foreach ($root in $script:retainedFixtures) {
                Get-ChildItem -LiteralPath (Join-Path $root 'control') -File -ErrorAction Stop |
                    Where-Object Name -CMatch '\A(?:Apply|Restore)-.+-(?:stdout|stderr)\.log\z' |
                    Sort-Object Name | ForEach-Object FullName
            }
        )
        SourceDirectory = [IO.Path]::GetFullPath($SourceDirectory); FixtureOnly = $true; DiagnosticsReadOnly = $true
        Scope = 'Completed operation boundaries only; excludes partial writes, power-loss durability and filesystem atomicity claims.'
    }
}
catch {
    Write-Warning ('Retained disposable fixtures: ' + [string]::Join(', ', $script:retainedFixtures))
    throw
}
