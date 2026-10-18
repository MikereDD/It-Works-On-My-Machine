#requires -Version 7.3
<# Actual child-process termination tests; only newly created synthetic private TEMP fixtures.
   The child shadows Write-Debug to pause at a named checkpoint. Only that child is killed.
   No production module, theme entry point, or external provider is loaded. Evidence is retained. #>
[CmdletBinding()]
param(
    [string]$SourceDirectory = (Split-Path -Parent $PSScriptRoot),
    [string]$ReportPath,
    [string]$WorkerConfig
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows) { throw 'Process-crash regression requires Windows and local NTFS TEMP.' }
$source = [IO.Path]::GetFullPath($SourceDirectory)
$utf8 = [Text.UTF8Encoding]::new($false, $true)
$modules = @('FontWriter-WindowsTerminal.ps1',
    'TerminalCoordinatorRecovery-WindowsTerminal.ps1','TerminalCoordinatorReceipt-WindowsTerminal.ps1',
    'TypezeroIntegrationPreflight.ps1','TypezeroGuardedIntegrationEntry.ps1',
    'TypezeroFreshCoordinatorFixtureJournal-Locked.ps1','TerminalCoordinatorLifecycle-WindowsTerminal.ps1',
    'TerminalCoordinatorRehearsal-WindowsTerminal.ps1')
foreach ($name in $modules) {
    $path = Join-Path $source $name
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
    if (@($errors).Count -or @($ast.EndBlock.Statements | Where-Object {
        $_ -isnot [Management.Automation.Language.FunctionDefinitionAst]
    }).Count) { throw "Only function-only modules may be loaded: $path" }
    . $path
}

function Assert-Crash([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Get-CrashHash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
function New-CrashPrivateDirectory([string]$Prefix) {
    $path = Join-Path ([IO.Path]::GetTempPath()) ($Prefix + [guid]::NewGuid().ToString('N'))
    Assert-TypezeroFontRecoveryPlainPath $path
    Assert-Crash (-not (Test-Path -LiteralPath $path)) 'Private directory collision.'
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $acl.SetOwner($sid); $acl.SetAccessRuleProtection($true,$false)
    foreach ($identity in @($sid,[Security.Principal.SecurityIdentifier]::new('S-1-5-18'))) {
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($identity,
            [Security.AccessControl.FileSystemRights]::FullControl,
            [Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit',
            [Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow))
    }
    [IO.FileSystemAclExtensions]::Create([IO.DirectoryInfo]::new($path),$acl) | Out-Null
    $path
}
function Write-CrashNew([string]$Path, [byte[]]$Bytes) {
    Assert-TypezeroFontRecoveryPlainPath $Path
    $s = [IO.FileStream]::new($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,
        [IO.FileShare]::None,4096,[IO.FileOptions]::WriteThrough)
    try { $s.Write($Bytes,0,$Bytes.Length); $s.Flush($true) } finally { $s.Dispose() }
}
function Get-CrashTree([string]$Root) {
    $rows = @(Get-Item -LiteralPath $Root -Force) + @(Get-ChildItem -LiteralPath $Root -Force -Recurse)
    @($rows | ForEach-Object {
        Assert-Crash (($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) 'Unexpected redirect in crash fixture.'
        $hash = if ($_.PSIsContainer) { '-' } else { Get-CrashHash $_.FullName }
        $_.FullName + '|' + [long]$_.Attributes + '|' + $_.LastWriteTimeUtc.Ticks + '|' + $hash
    } | Sort-Object) -join "`n"
}

if ($WorkerConfig) {
    $configPath = [IO.Path]::GetFullPath($WorkerConfig)
    $control = [IO.Path]::GetDirectoryName($configPath)
    $temp = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))
    Assert-Crash ([IO.Path]::GetDirectoryName($control) -ieq $temp -and
        [IO.Path]::GetFileName($control) -cmatch '\Atypezero-coordinator-crash-[a-f0-9]{32}\z') 'Worker configuration is outside a crash-test directory.'
    Assert-Crash ([IO.Path]::GetFileName($configPath) -ceq 'worker.json') 'Unexpected worker config filename.'
    Assert-TypezeroFontRecoveryPlainPath $configPath
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl = Get-Acl -LiteralPath $control
    Assert-Crash ($acl.AreAccessRulesProtected -and
        $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -ceq $sid.Value) 'Worker config requires a private owned directory.'
    foreach ($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])) {
        Assert-Crash ($rule.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow -and
            $rule.IdentityReference.Value -cin @($sid.Value,'S-1-5-18')) 'Unexpected worker config ACL.'
    }
    $configuration = $utf8.GetString((Get-TypezeroFontRecoveryBytes -Path $configPath -Maximum 65536)) | ConvertFrom-Json
    Assert-Crash ($configuration.Operation -cin @('Apply','Restore')) 'Invalid crash worker operation.'
    Assert-Crash ($configuration.Checkpoint -cmatch '\ATZ57F2310090903:(Apply|Restore):[a-z.-]+:(StageFlushed|Replaced|Verified|PendingFlushed|BeforePublish)\z') 'Invalid crash checkpoint.'
    $script:crashSignal = Join-Path $control 'signal.ready'
    $script:crashCheckpoint = $configuration.Checkpoint
    function Write-Debug {
        param([string]$Message)
        if ($Message -ceq $script:crashCheckpoint) {
            Write-CrashNew $script:crashSignal ($utf8.GetBytes($Message))
            while ($true) { Start-Sleep -Milliseconds 100 }
        }
    }
    $arguments = @{ TestRoot=$configuration.TestRoot; TransactionId=$configuration.TransactionId;
        ExpectedJournalSha256=$configuration.ExpectedJournalSha256; Execute=$true; Confirm=$false }
    if ($configuration.Operation -ceq 'Apply') { Invoke-TypezeroCoordinatorFixtureApplyRehearsal @arguments | Out-Null }
    else { Restore-TypezeroCoordinatorFixtureRehearsal @arguments | Out-Null }
    throw 'Worker operation completed without reaching its required checkpoint.'
}

$targets = @('settings.json','vim-main.vim','vim-lightline.vim','shell-current.ps1',
    'appearance.mock','history-previous.txt','history-current.txt')
$cases = [Collections.Generic.List[object]]::new()
$fixtureRoots = [Collections.Generic.List[string]]::new()
$failure = $null
$sourceHashes = [ordered]@{}
foreach ($file in Get-ChildItem -LiteralPath $source -Recurse -File -Filter '*.ps1') {
    $sourceHashes[$file.FullName] = Get-CrashHash $file.FullName
}

$definitions = @(
    @{ Operation='Apply'; Target='settings.json'; Point='StageFlushed'; State='Prepared'; Resume=$false },
    @{ Operation='Apply'; Target='settings.json'; Point='Replaced'; State='PartiallyApplied'; Resume=$true },
    @{ Operation='Apply'; Target='settings.json'; Point='Verified'; State='PartiallyApplied'; Resume=$true },
    @{ Operation='Restore'; Target='history-current.txt'; Point='StageFlushed'; State='Applied'; Resume=$false },
    @{ Operation='Restore'; Target='history-current.txt'; Point='Replaced'; State='PartiallyApplied'; Resume=$true },
    @{ Operation='Restore'; Target='history-current.txt'; Point='Verified'; State='PartiallyApplied'; Resume=$true },
    @{ Operation='Restore'; Target='receipt'; Point='PendingFlushed'; State='OriginalUnresolved'; Resume=$false },
    @{ Operation='Restore'; Target='receipt'; Point='BeforePublish'; State='OriginalUnresolved'; Resume=$false }
)
try {
    foreach ($definition in $definitions) {
        $preflight = New-CrashPrivateDirectory 'typezero-integration-preflight-'
        $fixtureRoots.Add($preflight)
        $control = New-CrashPrivateDirectory 'typezero-coordinator-crash-'
        $fixtureRoots.Add($control)
        $originals = [ordered]@{}; $candidates = [ordered]@{}; $expected = [ordered]@{}
        foreach ($name in $targets) {
            $originals[$name] = [byte[]](@(239,187,191) + $utf8.GetBytes("SYNTHETIC crash original $name`r`nline two`n") + @(0,255,128))
            $candidates[$name] = $utf8.GetBytes("SYNTHETIC crash candidate $name`n")
            $expected[$name] = Get-TypezeroFontRecoveryHash $originals[$name]
        }
        $root = New-TypezeroFontRecoveryFixture -Bytes $originals['settings.json']
        $fixtureRoots.Add($root)
        Write-CrashNew (Join-Path $preflight '.fixture') ($utf8.GetBytes('TYPEZERO_INTEGRATION_PREFLIGHT_V2'))
        foreach ($name in $targets) {
            Write-CrashNew (Join-Path $preflight $name) $originals[$name]
            if ($name -cne 'settings.json') {
                Write-TypezeroCoordinatorFixtureFile -Path (Join-Path $root $name) -Bytes $originals[$name]
            }
        }
        $prepared = New-TypezeroFreshCoordinatorFixtureJournal -PreflightRoot $preflight -RecoveryRoot $root `
            -ExpectedHashes $expected -Candidates $candidates
        $arguments = @{ TestRoot=$root; TransactionId=$prepared.TransactionId; ExpectedJournalSha256=$prepared.JournalSHA256 }
        if ($definition.Operation -ceq 'Restore') {
            Invoke-TypezeroCoordinatorFixtureApplyRehearsal @arguments -Execute -Confirm:$false | Out-Null
        }
        $checkpoint = 'TZ57F2310090903:' + $definition.Operation + ':' + $definition.Target + ':' + $definition.Point
        $configuration = [ordered]@{ TestRoot=$root; TransactionId=$prepared.TransactionId;
            ExpectedJournalSha256=$prepared.JournalSHA256; Operation=$definition.Operation; Checkpoint=$checkpoint }
        $configurationPath = Join-Path $control 'worker.json'
        Write-CrashNew $configurationPath ($utf8.GetBytes(($configuration | ConvertTo-Json -Compress)))
        $start = [Diagnostics.ProcessStartInfo]::new()
        $start.FileName = (Get-Process -Id $PID).Path
        $start.UseShellExecute = $false; $start.CreateNoWindow = $true
        $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
        foreach ($argument in @('-NoLogo','-NoProfile','-File',$PSCommandPath,
            '-SourceDirectory',$source,'-WorkerConfig',$configurationPath)) { $start.ArgumentList.Add($argument) }
        $child = [Diagnostics.Process]::Start($start)
        $stdout = $child.StandardOutput.ReadToEndAsync(); $stderr = $child.StandardError.ReadToEndAsync()
        $signal = Join-Path $control 'signal.ready'
        $timer = [Diagnostics.Stopwatch]::StartNew()
        try {
            while (-not [IO.File]::Exists($signal) -and -not $child.HasExited -and $timer.Elapsed.TotalSeconds -lt 45) {
                Start-Sleep -Milliseconds 50
            }
            if (-not [IO.File]::Exists($signal)) {
                if (-not $child.HasExited) { $child.Kill(); $null = $child.WaitForExit(10000) }
                throw "Worker failed to reach ${checkpoint}: $($stderr.GetAwaiter().GetResult())"
            }
            Assert-Crash (-not $child.HasExited) 'Worker exited instead of pausing at checkpoint.'
            # Terminate exactly the child Process object created above, never a name-based process set.
            $child.Kill()
            Assert-Crash ($child.WaitForExit(10000)) 'Terminated worker did not exit.'
            Assert-Crash ($child.ExitCode -ne 0) 'Killed worker unexpectedly reported success.'
            Write-CrashNew (Join-Path $control 'worker.stdout.txt') ($utf8.GetBytes($stdout.GetAwaiter().GetResult()))
            Write-CrashNew (Join-Path $control 'worker.stderr.txt') ($utf8.GetBytes($stderr.GetAwaiter().GetResult()))
        } finally {
            if (-not $child.HasExited) { $child.Kill(); $null = $child.WaitForExit(10000) }
            $child.Dispose()
        }
        $assessment = Get-TypezeroCoordinatorFixtureLifecycleAssessment -TestRoot $root -TransactionId $prepared.TransactionId
        Assert-Crash ($assessment.ObservedState -ceq $definition.State) "Wrong observed state at $checkpoint"
        Assert-Crash ($assessment.RecordedState -ceq 'Prepared' -and -not $assessment.RecoveryAuthorized -and
            -not $assessment.LiveActivationAuthorized) 'Crash changed the journal/authorization contract.'
        Assert-Crash (-not $assessment.ReceiptValid) 'Interrupted operation claimed a valid published receipt.'
        $manifestHash = Get-CrashHash (Join-Path $prepared.JournalDirectory 'coordinator.dpapi')
        Assert-Crash ($manifestHash -ceq $prepared.JournalSHA256) 'Crash changed sealed manifest bytes.'
        # A dead process must release the existing OS lock.
        $probeLock = Open-TypezeroFontRecoveryLock -TestRoot $root
        $probeLock.Dispose()
        if ($definition.Resume) {
            if ($definition.Operation -ceq 'Apply') {
                Invoke-TypezeroCoordinatorFixtureApplyRehearsal @arguments -Execute -Confirm:$false | Out-Null
            }
            $restored = Restore-TypezeroCoordinatorFixtureRehearsal @arguments -Execute -Confirm:$false
            Assert-Crash ($restored.ExactOriginalBytesMatch -and $restored.ReceiptValid -and
                $restored.CompleteRoundRestored -and -not $restored.RecoveryAuthorized -and
                -not $restored.LiveActivationAuthorized) 'Resumed crash fixture failed complete exact restoration.'
            foreach ($name in $targets) {
                $bytes = Get-TypezeroFontRecoveryBytes -Path (Join-Path $root $name)
                Assert-Crash ([Convert]::ToBase64String($bytes) -ceq [Convert]::ToBase64String($originals[$name])) "Exact restored byte comparison failed: $name"
            }
        } else {
            $before = Get-CrashTree $root
            $refused = $false
            try {
                if ($definition.Operation -ceq 'Apply') {
                    Invoke-TypezeroCoordinatorFixtureApplyRehearsal @arguments -Execute -Confirm:$false | Out-Null
                } else { Restore-TypezeroCoordinatorFixtureRehearsal @arguments -Execute -Confirm:$false | Out-Null }
            } catch { $refused = $true }
            Assert-Crash $refused "Interrupted stage or pending receipt was reused at $checkpoint"
            Assert-Crash ((Get-CrashTree $root) -ceq $before) 'Refusal modified retained crash evidence.'
            if ($definition.Target -ceq 'receipt') {
                Assert-Crash $assessment.PendingReceiptPresent 'Pending receipt evidence was lost.'
            }
        }
        $cases.Add([pscustomobject]@{ Name=$checkpoint; Passed=$true; WorkerTerminated=$true;
            ObservedState=$assessment.ObservedState; AutomaticResumeAllowed=$definition.Resume;
            ExactRestorationAfterResume=[bool]$definition.Resume; PendingReceipt=$assessment.PendingReceiptPresent;
            Root=$root; ControlDirectory=$control; JournalSHA256=$manifestHash })
        Write-Host "PASS [$($cases.Count)] process termination at $checkpoint"
    }
} catch { $failure = $_.Exception.Message; throw }
finally {
    $unchanged = $true
    foreach ($path in $sourceHashes.Keys) {
        if (-not [IO.File]::Exists($path) -or (Get-CrashHash $path) -cne $sourceHashes[$path]) { $unchanged = $false }
    }
    $report = [pscustomobject]@{ Milestone='57F.23.10.09.09.03'; Suite='ActualProcessTermination';
        ComputerName=$env:COMPUTERNAME; PowerShellVersion=$PSVersionTable.PSVersion.ToString();
        Passed=($null -eq $failure -and $unchanged -and $cases.Count -eq 8); CaseCount=$cases.Count;
        Failure=$failure; SourceFilesUnchanged=$unchanged; RecoveryAuthorized=$false; LiveActivationAuthorized=$false;
        Cases=@($cases.ToArray()); SourceSHA256=$sourceHashes; FixtureRoots=@($fixtureRoots.ToArray()) }
    if ($ReportPath) {
        $reportFull = [IO.Path]::GetFullPath($ReportPath)
        Write-CrashNew $reportFull ($utf8.GetBytes(($report | ConvertTo-Json -Depth 12)))
        Write-Host "Report: $reportFull"
    }
    if (-not $unchanged) { throw 'Crash suite detected changed source bytes.' }
}
Write-Host "PASS: $($cases.Count) actual child termination cases; all source bytes unchanged."
