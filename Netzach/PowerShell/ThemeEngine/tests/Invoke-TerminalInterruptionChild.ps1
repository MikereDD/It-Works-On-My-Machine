param(
    [Parameter(Mandatory)][string]$TestRoot,
    [Parameter(Mandatory)][ValidateSet('Apply','Restore')][string]$Operation,
    [Parameter(Mandatory)][ValidatePattern('\A[a-f0-9]{32}\z')][string]$AcknowledgementToken,
    [string]$Checkpoint = '',
    [string]$BackupDirectory = '',
    [switch]$Uninstrumented
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Use PowerShell 7 or later.' }

# Everything this child loads and writes is in its newly created disposable root.
$root = [IO.Path]::GetFullPath($TestRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
$temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)
if ([IO.Path]::GetDirectoryName($root) -ine $temp -or
    [IO.Path]::GetFileName($root) -cnotmatch '\Atypezero-terminal-txn-[a-f0-9]{32}\z') {
    throw 'Child accepts only direct, specially named temporary test roots.'
}
$moduleFolder = if ($Uninstrumented) { 'uninstrumented' } else { 'instrumented' }
$moduleDirectory = Join-Path $root $moduleFolder
foreach ($name in @('FontPatch-WindowsTerminal.ps1', 'TerminalColorPatch-WindowsTerminal.ps1',
    'TerminalCombinedPatch-WindowsTerminal.ps1', 'TerminalTransaction-WindowsTerminal.ps1')) {
    $path = Join-Path $moduleDirectory $name
    $cursor = $path
    while ($cursor) {
        if (([IO.File]::GetAttributes($cursor) -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Child module paths cannot be redirected.'
        }
        $cursor = [IO.Path]::GetDirectoryName($cursor)
    }
    . $path
}
$paths = Get-TypezeroOfflineTerminalTransactionPaths -TestRoot $root
$control = Join-Path $root 'control'
Assert-TypezeroOfflinePlainPath -Path $control
if (-not (Test-Path -LiteralPath $control -PathType Container)) { throw 'Missing fixture control directory.' }
$signalPath = Join-Path $control 'paused.json'
$resultPath = Join-Path $control 'completed.json'
$script:RequestedOperation = $Operation
$script:RequestedCheckpoint = $Checkpoint
$utf8 = [Text.UTF8Encoding]::new($false)

function Invoke-TypezeroInterruptionCheckpoint {
    param([string]$Operation, [string]$Checkpoint, [string]$BackupDirectory)
    if ($Operation -cne $script:RequestedOperation -or
        $Checkpoint -cne $script:RequestedCheckpoint) { return }
    $folder = [IO.Path]::GetFullPath($BackupDirectory).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if ([IO.Path]::GetDirectoryName($folder) -ine $paths.BackupRoot) {
        throw 'Checkpoint reported a backup outside the disposable fixture.'
    }
    Assert-TypezeroOfflinePlainPath -Path $folder
    [IO.File]::WriteAllText($signalPath, ([ordered]@{
        Operation = $Operation; Checkpoint = $Checkpoint; BackupDirectory = $folder
        ProcessId = $PID; TestRoot = $root; AcknowledgementToken = $AcknowledgementToken
        ProcessStartUtcTicks = [Diagnostics.Process]::GetCurrentProcess().StartTime.ToUniversalTime().Ticks
    } | ConvertTo-Json -Compress), $utf8)
    # The parent kills precisely the Process object it started. No release path,
    # timeout, throw, or exit can execute the transaction's finally cleanup here.
    while ($true) { Start-Sleep -Milliseconds 50 }
}

try {
    $theme = @{ THEME_NAME = 'Obsidian Silver'; BG = '#123456'; TEXT = '#eeeeee';
        CURSOR = '#ffffff'; SELECTION = '#445566' }
    foreach ($name in @('BLACK','RED','GREEN','YELLOW','BLUE','PURPLE','CYAN','WHITE',
        'BRIGHT_BLACK','BRIGHT_RED','BRIGHT_GREEN','BRIGHT_YELLOW','BRIGHT_BLUE',
        'BRIGHT_PURPLE','BRIGHT_CYAN','BRIGHT_WHITE')) { $theme["ANSI_$name"] = '#778899' }
    if ($Operation -ceq 'Apply') {
        $result = Invoke-TypezeroOfflineTerminalCombinedTransaction -TestRoot $root `
            -Theme $theme -FontFace 'JetBrainsMono Nerd Font' -FontSize 12 `
            -FontWeight 'semi-bold' -Execute -Confirm:$false
    }
    else {
        $result = Restore-TypezeroOfflineTerminalCombinedTransaction -TestRoot $root `
            -BackupDirectory $BackupDirectory -Execute -Confirm:$false
    }
    [IO.File]::WriteAllText($resultPath, ($result | ConvertTo-Json -Depth 10), $utf8)
    Write-Output "Completed $Operation with $($result.Status)."
}
catch {
    Write-Error $_
    exit 1
}
