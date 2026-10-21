# Synthetic fixtures only. Keys travel to child workers through redirected stdin.
param(
    [ValidateSet('Parent','Child')][string]$Mode = 'Parent',
    [string]$TestRoot = '',
    [string]$BackupDirectory = '',
    [ValidateSet('APPLY','RESTORE')][string]$Operation = 'APPLY',
    [string]$Point = '',
    [string]$Token = '',
    [switch]$DenyConsent,
    [string]$ReportPath = ''
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows -or $PSVersionTable.PSVersion.Major -lt 7) {
    throw 'Windows / PowerShell 7 / local NTFS required.'
}
$engine = Split-Path -Parent $PSScriptRoot
$utf8 = [Text.UTF8Encoding]::new($false, $true)
foreach ($name in @(
    'FontPatch-WindowsTerminal.ps1','TerminalColorPatch-WindowsTerminal.ps1',
    'TerminalCombinedPatch-WindowsTerminal.ps1','TerminalTransaction-WindowsTerminal.ps1',
    'TerminalReplace-WindowsTerminal.ps1','TerminalTransactionV2-WindowsTerminal.ps1',
    'TerminalTransactionV2Lock-WindowsTerminal.ps1','TerminalEvidenceSealV2-WindowsTerminal.ps1',
    'TerminalRecoveryAuthorizationV2-WindowsTerminal.ps1','TerminalRecoveryGrantV2-WindowsTerminal.ps1',
    'TerminalRecoveryReplayV2-WindowsTerminal.ps1'
)) { . (Join-Path $engine $name) }
$modulePath = Join-Path $engine 'TerminalTransactionV2Durable-WindowsTerminal.ps1'
$theme = @{ THEME_NAME='Obsidian Silver'; BG='#123456'; TEXT='#eeeeee';
    CURSOR='#ffffff'; SELECTION='#445566' }
foreach ($name in @('BLACK','RED','GREEN','YELLOW','BLUE','PURPLE','CYAN','WHITE',
    'BRIGHT_BLACK','BRIGHT_RED','BRIGHT_GREEN','BRIGHT_YELLOW','BRIGHT_BLUE',
    'BRIGHT_PURPLE','BRIGHT_CYAN','BRIGHT_WHITE')) { $theme["ANSI_$name"]='#778899' }
$font = @{ FontFace='JetBrainsMono Nerd Font'; FontSize=12; FontWeight='semi-bold' }
function Assert-Test([bool]$Condition, [string]$Description) {
    if (-not $Condition) { throw "FAIL: $Description" }
}
function Hash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
function Snapshot([string]$Root) {
    (@(Get-ChildItem -LiteralPath $Root -Recurse -Force -File | Sort-Object FullName |
        ForEach-Object { $_.FullName.Substring($Root.Length) + '|' + (Hash $_.FullName) })) -join "`n"
}

if ($Mode -ceq 'Child') {
    $paths = Get-TypezeroOfflineTerminalV2Paths -TestRoot $TestRoot
    Assert-Test ($Token -cmatch '\A[a-f0-9]{32}\z') 'Child token'
    $inputData = [Console]::In.ReadLine() | ConvertFrom-Json
    [byte[]]$evidenceKey = [Convert]::FromBase64String($inputData.EvidenceKey)
    [byte[]]$approvalKey = [Convert]::FromBase64String($inputData.ApprovalKey)
    if ($Point) {
        $source = [IO.File]::ReadAllText($modulePath).Replace("`r`n", "`n")
        $anchor = '# DURABLE-CHECKPOINT: ' + $Point
        $pause = @'
[IO.File]::WriteAllText((Join-Path '__ROOT__' 'paused-__TOKEN__.json'), (@{ ProcessId=$PID; StartTicks=[Diagnostics.Process]::GetCurrentProcess().StartTime.ToUniversalTime().Ticks; Token='__TOKEN__'; Point='__POINT__' } | ConvertTo-Json -Compress))
while (-not [IO.File]::Exists((Join-Path '__ROOT__' 'release-__TOKEN__'))) { Start-Sleep -Milliseconds 20 }
'@
        $pause = $pause.Replace('__ROOT__', $paths.Root.Replace("'", "''")).Replace('__TOKEN__',$Token).Replace('__POINT__',$Point)
        if ($Point -match '_(BEFORE_NATIVE_CALL|AFTER_NATIVE_UNVERIFIED)$') {
            # Instrument a copy of the pinned primitive only in this worker.
            $body=(Get-Command Invoke-TypezeroOfflineTerminalVerifiedReplace).ScriptBlock.ToString().Replace("`r`n","`n")
            $native=@'
    [IO.File]::Replace(
        $stage,
        $settings,
        $backup,
        $false
    )
'@
            Assert-Test ($body.Split($native).Count -eq 2) 'Unique exact native replace anchor'
            $replacement=if ($Point.EndsWith('_BEFORE_NATIVE_CALL')) { $pause+"`n"+$native } else { $native+"`n"+$pause }
            $instrumented=$body.Replace($native,$replacement)
            Assert-Test ($instrumented.Replace($replacement,$native) -ceq $body) 'Reversible native instrumentation'
            Set-Item Function:\Invoke-TypezeroOfflineTerminalVerifiedReplace -Value ([scriptblock]::Create($instrumented))
            . $modulePath
        }
        else {
            Assert-Test ($source.Split($anchor).Count -eq 2) "Unique exact checkpoint $Point"
            $instrumented = $source.Replace($anchor, ($anchor + "`n" + $pause))
            Assert-Test ($instrumented.Replace(($anchor + "`n" + $pause),$anchor) -ceq $source) 'Reversible instrumentation'
            . ([scriptblock]::Create($instrumented))
        }
    }
    else { . $modulePath }
    try {
        if ($Operation -ceq 'APPLY') {
            $result = Invoke-TypezeroOfflineTerminalV2Durable -TestRoot $paths.Root `
                -Theme $theme @font -IndependentKey $evidenceKey -Execute -Confirm:$DenyConsent.IsPresent
        }
        else {
            $result = Restore-TypezeroOfflineTerminalV2Durable -TestRoot $paths.Root `
                -BackupDirectory $BackupDirectory -GrantJson $inputData.GrantJson `
                -AuthorizationMac ([Convert]::FromBase64String($inputData.Mac)) `
                -ApprovalKey $approvalKey -EvidenceKey $evidenceKey -Execute -Confirm:$false
        }
        $result | ConvertTo-Json -Depth 10 -Compress
    }
    finally {
        [array]::Clear($evidenceKey,0,$evidenceKey.Length)
        [array]::Clear($approvalKey,0,$approvalKey.Length)
    }
    return
}
. $modulePath
$checks = [Collections.Generic.List[string]]::new()
$fixtures = [Collections.Generic.List[string]]::new()
$crashes = [Collections.Generic.List[object]]::new()
$completed = $false
function Pass([string]$Label) { $checks.Add($Label); Write-Host "PASS [$($checks.Count)] $Label" }
function Refused([scriptblock]$Action,[string]$Label) {
    $caught = $false
    try { $r = & $Action; if ($null -ne $r -and ($r.PSObject.Properties.Name -contains 'Status')) { $caught = $r.Status -notin @('VERIFIED','RESTORED') } }
    catch { $caught=$true }
    Assert-Test $caught $Label
    Pass $Label
}
[byte[]]$evidenceKey = 1..32
[byte[]]$approvalKey = 33..64
[byte[]]$wrongKey = 65..96
$original = @'
{
  "theme":"Typezero ThemeEngine",
  "schemes":[{"name":"Typezero Obsidian Silver","background":"#000000","custom":"retained"}],
  "themes":[{"name":"Typezero ThemeEngine","window":{"applicationTheme":"dark","custom":"retained"},"tab":{"background":"terminalBackground"},"tabRow":{"background":"#000000"}}],
  "profiles":{"defaults":{},"list":[{"guid":"{574e775e-4f2a-5b96-ac1e-a2962a402336}","name":"PowerShell","colorScheme":"Typezero Obsidian Silver"},{"guid":"{00000000-0000-0000-0000-000000000001}","name":"Untouched","custom":"retained"}]},
  "customRoot":{"preserved":"yes"}
}
'@
function New-Fixture {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('typezero-terminal-txn-' + [guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($root) | Out-Null
    $fixtures.Add($root)
    $paths = Get-TypezeroOfflineTerminalV2Paths -TestRoot $root
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($paths.Settings)) | Out-Null
    [IO.File]::WriteAllText($paths.Settings,$original,$utf8)
    [pscustomobject]@{ Root=$root; Settings=$paths.Settings; OriginalHash=(Hash $paths.Settings) }
}
function Apply($Fixture) {
    Invoke-TypezeroOfflineTerminalV2Durable -TestRoot $Fixture.Root -Theme $theme @font `
        -IndependentKey $evidenceKey -Execute -Confirm:$false
}
function Assess($Fixture,[string]$Folder,[byte[]]$Key=$evidenceKey) {
    Get-TypezeroOfflineTerminalV2DurableAssessment -TestRoot $Fixture.Root `
        -BackupDirectory $Folder -IndependentKey $Key
}
function New-Grant($Fixture,[string]$Folder,[hashtable]$Overrides=@{}) {
    $ctx = Get-TypezeroOfflineTerminalV2SealContext -TestRoot $Fixture.Root -BackupDirectory $Folder
    $fields = [ordered]@{
        Version=2; GrantId=[guid]::NewGuid().ToString('N'); Operation='RESTORE';
        FixtureRoot=$Fixture.Root; BackupDirectory=$Folder; ReceiptSha256=(Hash $ctx.Receipt);
        BackupSha256=(Hash $ctx.Backup); SealSha256=(Hash $ctx.Seal);
        ExpectedSettingsSha256=(Hash $Fixture.Settings);
        IssuedUtc=[datetime]::UtcNow.AddSeconds(-1).ToString("yyyy-MM-ddTHH:mm:ss.fffffff'Z'");
        ExpiresUtc=[datetime]::UtcNow.AddMinutes(10).ToString("yyyy-MM-ddTHH:mm:ss.fffffff'Z'")
    }
    foreach ($key in $Overrides.Keys) { $fields[$key]=$Overrides[$key] }
    [byte[]]$payload = Get-TypezeroOfflineTerminalV2GrantPayload -Fields $fields
    @{ Id=$fields.GrantId; Json=($fields | ConvertTo-Json -Compress);
       Mac=[Security.Cryptography.HMACSHA256]::HashData($approvalKey,$payload) }
}
function Recover($Fixture,[string]$Folder,$Grant,[byte[]]$Approval=$approvalKey,[byte[]]$Evidence=$evidenceKey) {
    Restore-TypezeroOfflineTerminalV2Durable -TestRoot $Fixture.Root -BackupDirectory $Folder `
        -GrantJson $Grant.Json -AuthorizationMac $Grant.Mac -ApprovalKey $Approval `
        -EvidenceKey $Evidence -Execute -Confirm:$false
}
function Init-Replay($Fixture) {
    $null=Initialize-TypezeroOfflineTerminalV2ReplayStore -TestRoot $Fixture.Root -Execute -Confirm:$false
}
function Start-Worker($Fixture,[string]$Op,[string]$Folder='',$Grant=$null,[string]$Checkpoint='', [switch]$Deny) {
    $token=[guid]::NewGuid().ToString('N')
    $psi=[Diagnostics.ProcessStartInfo]::new()
    $psi.FileName=(Get-Process -Id $PID).Path
    $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true
    $psi.RedirectStandardInput=$true; $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true
    foreach ($arg in @('-NoLogo','-NoProfile','-File',$PSCommandPath,'-Mode','Child','-TestRoot',$Fixture.Root,'-Operation',$Op,'-Token',$token)) { $psi.ArgumentList.Add($arg) }
    if ($Deny) { $psi.ArgumentList.Insert(2,'-NonInteractive');$psi.ArgumentList.Add('-DenyConsent') }
    if ($Folder) { $psi.ArgumentList.Add('-BackupDirectory');$psi.ArgumentList.Add($Folder) }
    if ($Checkpoint) { $psi.ArgumentList.Add('-Point');$psi.ArgumentList.Add($Checkpoint) }
    $process=[Diagnostics.Process]::Start($psi)
    $data=@{ EvidenceKey=[Convert]::ToBase64String($evidenceKey);ApprovalKey=[Convert]::ToBase64String($approvalKey);GrantJson='';Mac='' }
    if ($null -ne $Grant) { $data.GrantJson=$Grant.Json;$data.Mac=[Convert]::ToBase64String($Grant.Mac) }
    $process.StandardInput.WriteLine(($data | ConvertTo-Json -Compress));$process.StandardInput.Close()
    [pscustomobject]@{ Process=$process;Token=$token;Fixture=$Fixture;Out=$process.StandardOutput.ReadToEndAsync();Err=$process.StandardError.ReadToEndAsync() }
}
function Finish-Worker($Worker) {
    if (-not $Worker.Process.WaitForExit(30000)) { $Worker.Process.Kill();throw 'Child timeout' }
    [pscustomobject]@{ ExitCode=$Worker.Process.ExitCode;Output=$Worker.Out.GetAwaiter().GetResult();Error=$Worker.Err.GetAwaiter().GetResult() }
}
function Wait-Checkpoint($Worker) {
    $signal=Join-Path $Worker.Fixture.Root ('paused-' + $Worker.Token + '.json')
    $deadline=[datetime]::UtcNow.AddSeconds(30)
    while (-not [IO.File]::Exists($signal) -and -not $Worker.Process.HasExited -and [datetime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 20 }
    if (-not [IO.File]::Exists($signal)) {
        if (-not $Worker.Process.HasExited) { $Worker.Process.Kill() }
        $r=Finish-Worker $Worker
        throw "Checkpoint absent: $($r.Output) $($r.Error)"
    }
    $s=[IO.File]::ReadAllText($signal) | ConvertFrom-Json
    Assert-Test ($s.ProcessId -eq $Worker.Process.Id -and $s.Token -ceq $Worker.Token -and $s.StartTicks -eq $Worker.Process.StartTime.ToUniversalTime().Ticks) 'Parent owns signaled worker'
}
function Assert-Flags($Result) {
    Assert-Test ($Result.FixtureOnly -eq $true -and $Result.LiveActivationAuthorized -eq $false -and $Result.RecoveryAllowed -eq $false) 'Read-only assessment cannot authorize execution'
}

try {
    $f=New-Fixture
    $before=Snapshot $f.Root
    $null=Invoke-TypezeroOfflineTerminalV2Durable -TestRoot $f.Root -Theme $theme @font -IndependentKey $evidenceKey
    Assert-Test ((Snapshot $f.Root) -ceq $before) 'Apply preview is byte read-only';Pass 'Apply preview is byte read-only'
    $null=Invoke-TypezeroOfflineTerminalV2Durable -TestRoot $f.Root -Theme $theme @font -IndependentKey $evidenceKey -Execute -WhatIf
    Assert-Test ((Snapshot $f.Root) -ceq $before) 'Apply WhatIf is byte read-only';Pass 'Apply WhatIf is byte read-only'
    $worker=Start-Worker $f 'APPLY' -Deny
    $outcome=Finish-Worker $worker
    Assert-Test ($outcome.ExitCode -ne 0 -and (Snapshot $f.Root) -ceq $before) 'Unavailable explicit consent fails before writes';Pass 'Unavailable explicit consent fails before writes'
    Refused { Invoke-TypezeroOfflineTerminalV2Durable -TestRoot $f.Root -Theme $theme @font -IndependentKey ([byte[]]::new(31)) -Execute -Confirm:$false } 'Reject short evidence key'
    $a=Apply $f
    Assert-Test ($a.Status -ceq 'VERIFIED' -and (Hash $f.Settings) -cne $f.OriginalHash) 'Durable apply completes';Pass 'Durable apply completes'
    $d=Assess $f $a.BackupDirectory
    Assert-Flags $d
    Assert-Test ($d.OperationPhase -ceq 'COMPLETE' -and $d.ChainAuthenticated) 'Complete authenticated phase chain';Pass 'Complete authenticated phase chain'
    $backup=Join-Path $a.BackupDirectory 'settings-pre-replace.json'
    Assert-Test ((Hash $backup) -ceq $f.OriginalHash) 'Exact original backup';Pass 'Exact original backup'
    $json=[IO.File]::ReadAllText($f.Settings)|ConvertFrom-Json
    Assert-Test ($json.customRoot.preserved -ceq 'yes' -and $json.profiles.list[1].custom -ceq 'retained') 'Unrelated settings preserved';Pass 'Unrelated settings preserved'
    $bad=Assess $f $a.BackupDirectory $wrongKey
    Assert-Test (-not $bad.ChainAuthenticated) 'Wrong journal key refused';Pass 'Wrong journal key refused'
    Init-Replay $f
    $grant=New-Grant $f $a.BackupDirectory
    $before=Snapshot $f.Root
    $null=Restore-TypezeroOfflineTerminalV2Durable -TestRoot $f.Root -BackupDirectory $a.BackupDirectory -GrantJson $grant.Json -AuthorizationMac $grant.Mac -ApprovalKey $approvalKey -EvidenceKey $evidenceKey
    $null=Restore-TypezeroOfflineTerminalV2Durable -TestRoot $f.Root -BackupDirectory $a.BackupDirectory -GrantJson $grant.Json -AuthorizationMac $grant.Mac -ApprovalKey $approvalKey -EvidenceKey $evidenceKey -Execute -WhatIf
    Assert-Test ((Snapshot $f.Root) -ceq $before) 'Recovery preview and WhatIf spend no grant';Pass 'Recovery preview and WhatIf spend no grant'
    Refused { Recover $f $a.BackupDirectory $grant $wrongKey } 'Wrong approval key refused'
    Refused { Recover $f $a.BackupDirectory $grant $approvalKey $wrongKey } 'Wrong evidence key refused'
    Refused { Recover $f $a.BackupDirectory $grant $evidenceKey $evidenceKey } 'Equal independent keys refused'
    Assert-Test ((Snapshot $f.Root) -ceq $before) 'Unauthorized recovery leaves evidence unchanged';Pass 'Unauthorized recovery leaves evidence unchanged'
    $expired=New-Grant $f $a.BackupDirectory @{IssuedUtc=[datetime]::UtcNow.AddMinutes(-2).ToString("yyyy-MM-ddTHH:mm:ss.fffffff'Z'");ExpiresUtc=[datetime]::UtcNow.AddMinutes(-1).ToString("yyyy-MM-ddTHH:mm:ss.fffffff'Z'")}
    Refused { Recover $f $a.BackupDirectory $expired } 'Expired grant refused'
    $malformed=@{Json=$grant.Json.Replace('"Version":2','"Version":2,"version":2');Mac=$grant.Mac}
    Refused { Recover $f $a.BackupDirectory $malformed } 'Duplicate grant fields refused'
    $r=Recover $f $a.BackupDirectory $grant
    Assert-Test ($r.Status -ceq 'RESTORED' -and (Hash $f.Settings) -ceq $f.OriginalHash) 'Authorized fixture recovery restores exact original';Pass 'Authorized fixture recovery restores exact original'
    $before=Snapshot $f.Root
    Refused { Recover $f $a.BackupDirectory $grant } 'Spent recovery grant refused'
    Assert-Test ((Snapshot $f.Root) -ceq $before) 'Replay changes no evidence';Pass 'Replay changes no evidence'

    foreach ($tamper in @('record-bytes','last-record-whitespace','duplicate-field','unknown-field','case-field','wrong-type','wrong-phase','wrong-sequence','missing-record','partial-record','extra-entry','receipt','backup','settings')) {
        $t=New-Fixture;$ta=Apply $t
        $records=@(Get-ChildItem -LiteralPath $t.Root -Recurse -File -Filter '00000*.json' | Sort-Object Name)
        Assert-Test ($records.Count -eq 4) 'Exactly four durable journal phases'
        switch ($tamper) {
            'record-bytes' { [IO.File]::AppendAllText($records[0].FullName,'x',$utf8) }
            'last-record-whitespace' { [IO.File]::AppendAllText($records[3].FullName,' ',$utf8) }
            'duplicate-field' { [IO.File]::WriteAllText($records[0].FullName,[IO.File]::ReadAllText($records[0].FullName).Replace('"Version":2','"Version":2,"Version":2'),$utf8) }
            'unknown-field' { [IO.File]::WriteAllText($records[0].FullName,[IO.File]::ReadAllText($records[0].FullName).Replace('"Version":2','"Version":2,"Unexpected":"yes"'),$utf8) }
            'case-field' { [IO.File]::WriteAllText($records[0].FullName,[IO.File]::ReadAllText($records[0].FullName).Replace('"Version":2','"Version":2,"version":2'),$utf8) }
            'wrong-type' { [IO.File]::WriteAllText($records[0].FullName,[IO.File]::ReadAllText($records[0].FullName).Replace('"Version":2','"Version":"2"'),$utf8) }
            'wrong-phase' { [IO.File]::WriteAllText($records[0].FullName,[IO.File]::ReadAllText($records[0].FullName).Replace('"Phase":"INTENT"','"Phase":"COMPLETE"'),$utf8) }
            'wrong-sequence' { [IO.File]::WriteAllText($records[0].FullName,[IO.File]::ReadAllText($records[0].FullName).Replace('"Sequence":1','"Sequence":4'),$utf8) }
            'missing-record' { [IO.File]::Move($records[1].FullName,($records[1].FullName+'.removed')) }
            'partial-record' { [IO.File]::WriteAllText($records[3].FullName,'{',$utf8) }
            'extra-entry' { [IO.File]::WriteAllText((Join-Path $records[0].DirectoryName 'unexpected.json'),'{}',$utf8) }
            'receipt' { [IO.File]::AppendAllText((Join-Path $ta.BackupDirectory 'receipt.json'),' ',$utf8) }
            'backup' { [IO.File]::AppendAllText((Join-Path $ta.BackupDirectory 'settings-pre-replace.json'),' ',$utf8) }
            'settings' { [IO.File]::AppendAllText($t.Settings,' ',$utf8) }
        }
        $before=Snapshot $t.Root
        $td=Assess $t $ta.BackupDirectory
        Assert-Flags $td
        Assert-Test ($td.Decision -cne 'COMPLETE') "Tampering is never certified complete: $tamper"
        Assert-Test ((Snapshot $t.Root) -ceq $before) "Tamper assessment read-only: $tamper"
        Pass "Tamper refusal and read-only assessment: $tamper"
    }
    $t=New-Fixture;$ta=Apply $t
    $other=New-Fixture
    $sourceStore=Join-Path $t.Root '.typezero-terminal-v2-durable'
    Copy-Item -LiteralPath $sourceStore -Destination $other.Root -Recurse
    $otherPaths=Get-TypezeroOfflineTerminalV2Paths -TestRoot $other.Root
    [IO.Directory]::CreateDirectory($otherPaths.BackupRoot)|Out-Null
    Copy-Item -LiteralPath $ta.BackupDirectory -Destination $otherPaths.BackupRoot -Recurse
    [IO.File]::Copy($t.Settings,$other.Settings,$true)
    $otherFolder=Join-Path $otherPaths.BackupRoot ([IO.Path]::GetFileName($ta.BackupDirectory))
    $td=Assess $other $otherFolder
    Assert-Test (-not $td.ChainAuthenticated) 'Cross-root evidence cannot authenticate';Pass 'Cross-root evidence cannot authenticate'

    $t=New-Fixture;$before=Snapshot $t.Root
    $lock=Open-TypezeroOfflineTerminalV2ReplayLock -TestRoot $t.Root
    try {
        $worker=Start-Worker $t 'APPLY'
        $outcome=Finish-Worker $worker
        Assert-Test ($outcome.ExitCode -ne 0 -and (Hash $t.Settings) -ceq $t.OriginalHash) 'Occupied lock blocks child before settings mutation'
    }
    finally { $lock.Dispose() }
    Pass 'Occupied shared lock blocks a separate process'

    $t=New-Fixture;$ta=Apply $t;Init-Replay $t;$g=New-Grant $t $ta.BackupDirectory
    $w1=Start-Worker $t 'RESTORE' $ta.BackupDirectory $g
    $w2=Start-Worker $t 'RESTORE' $ta.BackupDirectory $g
    $o1=Finish-Worker $w1;$o2=Finish-Worker $w2
    $successes=@(@($o1,$o2)|Where-Object {$_.ExitCode -eq 0 -and $_.Output -match 'RESTORED'}).Count
    Assert-Test ($successes -eq 1 -and (Hash $t.Settings) -ceq $t.OriginalHash) 'Exactly one concurrent same-grant restore succeeds'
    Pass 'Concurrent same-grant processes have one winner'
    $worker=Start-Worker $t 'RESTORE' $ta.BackupDirectory $g
    $outcome=Finish-Worker $worker
    Assert-Test ($outcome.ExitCode -ne 0) 'Cross-process replay refused';Pass 'Cross-process replay refused'

    Refused { Invoke-TypezeroOfflineTerminalV2Durable -TestRoot $engine -Theme $theme @font -IndependentKey $evidenceKey -Execute -Confirm:$false } 'Non-fixture destination refused'
    $t=New-Fixture
    $legacy=Invoke-TypezeroOfflineTerminalV2Locked -TestRoot $t.Root -Theme $theme @font -Execute -Confirm:$false
    $null=New-TypezeroOfflineTerminalV2EvidenceSeal -TestRoot $t.Root -BackupDirectory $legacy.BackupDirectory -IndependentKey $evidenceKey -Execute -Confirm:$false
    Init-Replay $t;$g=New-Grant $t $legacy.BackupDirectory;$before=Snapshot $t.Root
    Refused { Recover $t $legacy.BackupDirectory $g } 'Legacy seal cannot promote UNKNOWN into durable phase authority'
    Assert-Test ((Snapshot $t.Root) -ceq $before) 'Legacy refusal preserves all bytes';Pass 'Legacy refusal preserves all bytes'

    foreach ($barrier in @('RESTORE_BEFORE_RESERVATION','RESTORE_AFTER_PREPARED')) {
        $t=New-Fixture;$ta=Apply $t;Init-Replay $t
        $expiry=[datetime]::UtcNow.AddSeconds(8)
        $g=New-Grant $t $ta.BackupDirectory @{ExpiresUtc=$expiry.ToString("yyyy-MM-ddTHH:mm:ss.fffffff'Z'")}
        $worker=Start-Worker $t 'RESTORE' $ta.BackupDirectory $g $barrier
        try {
            Wait-Checkpoint $worker
            while ([datetime]::UtcNow -lt $expiry) { Start-Sleep -Milliseconds 20 }
            [IO.File]::WriteAllText((Join-Path $t.Root ('release-'+$worker.Token)),'release',$utf8)
            $outcome=Finish-Worker $worker
            Assert-Test ($outcome.ExitCode -ne 0 -and (Hash $t.Settings) -ceq $ta.AfterSha256) "Expired paused recovery never replaces: $barrier"
            $reservation=Join-Path (Join-Path $t.Root '.typezero-terminal-v2-recovery-replay') ($g.Id+'.reserved')
            Assert-Test ([IO.File]::Exists($reservation) -eq ($barrier -ceq 'RESTORE_AFTER_PREPARED')) "Final expiry/reservation boundary: $barrier"
            $fresh=New-Grant $t $ta.BackupDirectory
            $before=Snapshot $t.Root
            Refused { Recover $t $ta.BackupDirectory $fresh } "Fresh grant cannot bypass expired interrupted intent: $barrier"
            Assert-Test ((Snapshot $t.Root) -ceq $before) 'Expired intent refusal is read-only'
            Pass "Expiry checked after locked preparation: $barrier"
        }
        finally { if (-not $worker.Process.HasExited) {$worker.Process.Kill();$null=$worker.Process.WaitForExit(5000)} }
    }

    $t=New-Fixture
    $worker=Start-Worker $t 'APPLY' '' $null 'APPLY_AFTER_STAGE'
    try {
        Wait-Checkpoint $worker
        [IO.File]::AppendAllText($t.Settings,' ',$utf8);$conflict=Hash $t.Settings
        [IO.File]::WriteAllText((Join-Path $t.Root ('release-'+$worker.Token)),'release',$utf8)
        $outcome=Finish-Worker $worker
        Assert-Test ($outcome.ExitCode -ne 0 -and (Hash $t.Settings) -ceq $conflict) 'External settings edit preserved and replacement refused'
        Pass 'Concurrent external settings edit is preserved'
    }
    finally {if (-not $worker.Process.HasExited) {$worker.Process.Kill();$null=$worker.Process.WaitForExit(5000)}}

    $t=New-Fixture;$ta=Apply $t
    $record=Get-ChildItem -LiteralPath $t.Root -Recurse -File -Filter '000001.intent.json' | Select-Object -First 1
    $alias=Join-Path $t.Root 'hardlink-evidence.json'
    $null=New-Item -ItemType HardLink -Path $alias -Target $record.FullName -ErrorAction Stop
    $td=Assess $t $ta.BackupDirectory
    Assert-Test (-not $td.ChainAuthenticated) 'Hard-linked journal refused';Pass 'Hard-linked journal refused'

    $source=[IO.File]::ReadAllText($modulePath)
    $points=@([regex]::Matches($source,'# DURABLE-CHECKPOINT: ([A-Z_]+)') | ForEach-Object {$_.Groups[1].Value})
    Assert-Test ($points.Count -ge 12 -and @($points|Select-Object -Unique).Count -eq $points.Count) 'Complete unique interruption boundaries required'
    $points+=@('APPLY_BEFORE_NATIVE_CALL','APPLY_AFTER_NATIVE_UNVERIFIED','RESTORE_BEFORE_NATIVE_CALL','RESTORE_AFTER_NATIVE_UNVERIFIED')
    foreach ($point in $points) {
        $t=New-Fixture
        $op=if ($point.StartsWith('RESTORE_')) {'RESTORE'} else {'APPLY'}
        $folder='';$g=$null
        if ($op -ceq 'RESTORE') { $ta=Apply $t; $folder=$ta.BackupDirectory;Init-Replay $t;$g=New-Grant $t $folder }
        $worker=Start-Worker $t $op $folder $g $point
        try {
            Wait-Checkpoint $worker
            $worker.Process.Kill()
            $outcome=Finish-Worker $worker
            Assert-Test ($outcome.ExitCode -ne 0) "Worker actually terminated at $point"
        }
        finally { if (-not $worker.Process.HasExited) { $worker.Process.Kill();$null=$worker.Process.WaitForExit(5000) } }
        $store=Join-Path $t.Root '.typezero-terminal-v2-durable'
        $dirs=@(if ([IO.Directory]::Exists($store)) { Get-ChildItem -LiteralPath $store -Directory -Force | Where-Object { -not $folder -or $_.Name -cne [IO.Path]::GetFileName($folder) } })
        if ($point.EndsWith('_BEFORE_INTENT')) {
            Assert-Test (@($dirs).Count -eq 0) "Crash before intent starts no transaction: $point"
            $expected=if ($op -ceq 'APPLY') {$t.OriginalHash} else {$ta.AfterSha256}
            Assert-Test ((Hash $t.Settings) -ceq $expected) "Crash before intent leaves settings unchanged: $point"
            $crashes.Add([ordered]@{Point=$point;Operation=$op;Root=$t.Root;Assessment='NOT_STARTED';Phase='UNKNOWN';ExitCode=$outcome.ExitCode})
            Pass "Actual process termination before transaction start: $point"
            continue
        }
        Assert-Test ($dirs.Count -eq 1) "One retained attempted operation: $point"
        $paths=Get-TypezeroOfflineTerminalV2Paths -TestRoot $t.Root
        $attemptFolder=Join-Path $paths.BackupRoot $dirs[0].Name
        $before=Snapshot $t.Root
        $td=Assess $t $attemptFolder
        Assert-Flags $td
        $finished=$point.EndsWith('_AFTER_COMPLETE')
        if ($finished) { Assert-Test ($td.OperationPhase -ceq 'COMPLETE' -and $td.ChainAuthenticated) "Only durable completion certified: $point" }
        else {
            Assert-Test ($td.Decision -cne 'COMPLETE') "No phase promotion after crash: $point"
            Refused { Apply $t } "Uncertain operation blocks new apply: $point"
            if ($op -ceq 'RESTORE') {
                Refused { Recover $t $folder $g } "Interrupted grant cannot replay: $point"
                if ((Hash $t.Settings) -ceq $ta.AfterSha256) {
                    $fresh=New-Grant $t $folder
                    Refused { Recover $t $folder $fresh } "Different grant cannot bypass uncertain source claim: $point"
                }
            }
        }
        Assert-Test ((Snapshot $t.Root) -ceq $before) "Crash assessment/refusal preserves every byte: $point"
        $crashes.Add([ordered]@{Point=$point;Operation=$op;Root=$t.Root;Assessment=$td.Decision;Phase=$td.OperationPhase;ExitCode=$outcome.ExitCode})
        Pass "Actual process termination and conservative assessment: $point"
    }
    $completed=$true
}
finally {
    $report=[ordered]@{SchemaVersion=1;Suite='TypezeroTerminalV2Durable';Completed=$completed;Passed=$checks.Count;Checks=@($checks);Fixtures=@($fixtures);Crashes=@($crashes);FixtureOnly=$true;LiveActivationAuthorized=$false}
    if ($ReportPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ReportPath),($report|ConvertTo-Json -Depth 12),$utf8) }
    [array]::Clear($evidenceKey,0,$evidenceKey.Length);[array]::Clear($approvalKey,0,$approvalKey.Length)
    Write-Host "Retained $($fixtures.Count) synthetic fixtures. Passed $($checks.Count) checks."
}
