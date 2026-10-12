# Read-only recovery diagnostic regression tests. No Pester dependency.
# Creates synthetic fixtures only in NEW direct %TEMP% folders and retains them.
# Loads transaction function definitions only. Never invokes apply or restore.
[CmdletBinding()]
param([string]$SourceDirectory = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Passed = 0
$script:Failed = 0
$script:Skipped = 0
$script:Roots = [Collections.Generic.List[string]]::new()
$script:Failures = [Collections.Generic.List[string]]::new()
$script:Utf8 = [Text.UTF8Encoding]::new($false, $true)

function Assert-Test {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -cne $Expected) {
        throw ($Message + ': expected [' + $Expected + '], actual [' + $Actual + ']')
    }
}

function Invoke-Test {
    param([string]$Name, [scriptblock]$Body)
    try {
        & $Body
        $script:Passed++
        Write-Host ('PASS ' + $Name)
    }
    catch {
        $script:Failed++
        $detail = $Name + ': ' + $_.Exception.Message
        $script:Failures.Add($detail)
        Write-Host ('FAIL ' + $detail)
    }
}

function Get-TestByteHash {
    param([byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-', '') }
    finally { $sha.Dispose() }
}

function New-TestRoot {
    $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    $path = Join-Path $temp ('typezero-terminal-txn-' + [guid]::NewGuid().ToString('N'))
    Assert-Test (-not [IO.Directory]::Exists($path) -and -not [IO.File]::Exists($path)) 'Fixture root already exists'
    [IO.Directory]::CreateDirectory($path) | Out-Null
    $script:Roots.Add($path)
    return $path
}

function Write-TestBytes {
    param([string]$Root, [string]$Path, [byte[]]$Bytes)
    $canonicalRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $canonicalPath = [IO.Path]::GetFullPath($Path)
    Assert-Test ($script:Roots.Contains($canonicalRoot)) 'Writes require a newly-created fixture root'
    Assert-Test ($canonicalPath.StartsWith($canonicalRoot + '\', [StringComparison]::OrdinalIgnoreCase)) 'Write would escape fixture root'
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($canonicalPath)) | Out-Null
    [IO.File]::WriteAllBytes($canonicalPath, $Bytes)
}

function New-TestFixture {
    param([switch]$NoTransaction, [switch]$NoReceipt, [switch]$NoBackup, [switch]$NoSettings)
    $root = New-TestRoot
    $settings = Join-Path $root 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
    $backupRoot = Join-Path $root 'Typezero\ThemeEngine\backups\terminal-combined'
    $folder = Join-Path $backupRoot ('20000101-000000-0000000-' + [guid]::NewGuid().ToString('N'))
    $before = $script:Utf8.GetBytes('{"profiles":{"defaults":{"font":{"face":"Fixture Before","size":11}}},"fixture":"original"}' + "`r`n")
    $after = $script:Utf8.GetBytes('{"profiles":{"defaults":{"font":{"face":"Fixture After","size":13}}},"fixture":"applied"}' + "`n")
    $other = $script:Utf8.GetBytes('{"fixture":"unrelated edit"}')
    $fixture = [pscustomobject]@{
        Root = $root
        Settings = $settings
        SettingsDirectory = [IO.Path]::GetDirectoryName($settings)
        BackupRoot = $backupRoot
        BackupDirectory = $folder
        ReceiptPath = Join-Path $folder 'receipt.json'
        BackupPath = Join-Path $folder 'settings-original.json'
        BeforeBytes = $before
        AfterBytes = $after
        OtherBytes = $other
        BeforeHash = Get-TestByteHash $before
        AfterHash = Get-TestByteHash $after
    }
    if (-not $NoSettings) { Write-TestBytes $root $settings $before }
    if (-not $NoTransaction) {
        [IO.Directory]::CreateDirectory($folder) | Out-Null
        if (-not $NoBackup) { Write-TestBytes $root $fixture.BackupPath $before }
        if (-not $NoReceipt) { Write-TestReceipt $fixture (New-TestReceipt $fixture) }
    }
    return $fixture
}

function New-TestReceipt {
    param($Fixture)
    return [ordered]@{
        Version = 1
        Kind = 'TypezeroOfflineCombined'
        SettingsPath = $Fixture.Settings
        BeforeSha256 = $Fixture.BeforeHash
        AfterSha256 = $Fixture.AfterHash
        Font = 'Fixture After'
        Size = 13
        Weight = 'normal'
    }
}

function Write-TestReceipt {
    param($Fixture, [Collections.IDictionary]$Receipt)
    Write-TestBytes $Fixture.Root $Fixture.ReceiptPath $script:Utf8.GetBytes(($Receipt | ConvertTo-Json -Depth 20))
}

function Get-TestSnapshot {
    param([string[]]$FixtureRoots)
    $entries = [Collections.Generic.List[string]]::new()
    $pending = [Collections.Generic.Queue[string]]::new()
    foreach ($root in $FixtureRoots) { $pending.Enqueue($root) }
    while ($pending.Count -gt 0) {
        $path = $pending.Dequeue()
        if (-not [IO.File]::Exists($path) -and -not [IO.Directory]::Exists($path)) {
            $entries.Add($path + '|MISSING')
            continue
        }
        $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
        $attributes = $item.Attributes
        $prefix = $item.FullName + '|' + [int]$attributes + '|' + $item.CreationTimeUtc.Ticks + '|' + $item.LastWriteTimeUtc.Ticks
        if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            # Never traverse or open any redirected target.
            $entries.Add($prefix + '|REPARSE')
        }
        elseif (($attributes -band [IO.FileAttributes]::Directory) -ne 0) {
            $entries.Add($prefix + '|DIRECTORY')
            foreach ($child in [IO.Directory]::GetFileSystemEntries($path)) { $pending.Enqueue($child) }
        }
        else {
            $entries.Add($prefix + '|FILE|' + $item.Length + '|' + (Get-TestByteHash ([IO.File]::ReadAllBytes($path))))
        }
    }
    return [string]::Join("`n", @($entries | Sort-Object))
}

function Invoke-CheckedDiagnosis {
    param($Fixture, [string]$ExpectedState, [switch]$MustThrow, [string[]]$AdditionalRoots = @(), [hashtable]$Arguments = @{}, [string]$ThrowPattern)
    $roots = @($Fixture.Root) + $AdditionalRoots
    $beforeSnapshot = Get-TestSnapshot $roots
    $caught = $null
    $diagnostics = @()
    try {
        $parameters = @{ TestRoot = $Fixture.Root; BackupDirectory = $Fixture.BackupDirectory }
        foreach ($key in $Arguments.Keys) { $parameters[$key] = $Arguments[$key] }
        $diagnostics = @(Get-TypezeroOfflineTerminalCombinedRecoveryDiagnostic @parameters)
    }
    catch { $caught = $_ }
    $afterSnapshot = Get-TestSnapshot $roots
    Assert-Equal $afterSnapshot $beforeSnapshot 'Diagnostic changed fixture files/directories/bytes/metadata'
    if ($MustThrow) {
        Assert-Test ($null -ne $caught) 'Unsafe input unexpectedly returned a diagnostic'
        if ($ThrowPattern) { Assert-Test ($caught.Exception.Message -match $ThrowPattern) ('Unexpected exception: ' + $caught.Exception.Message) }
        return
    }
    if ($null -ne $caught) { throw $caught }
    Assert-Equal $diagnostics.Count 1 'Expected one result only'
    $result = $diagnostics[0]
    Assert-Equal $result.State $ExpectedState 'State'
    Assert-Test ($result.ReadOnly -is [bool] -and $result.ReadOnly) 'ReadOnly must be Boolean true'
    Assert-Test ($result.RecoveryAllowed -is [bool] -and -not $result.RecoveryAllowed) 'RecoveryAllowed must be Boolean false'
    Assert-Test ($result.SettingsState -cin @('MISSING','UNTRUSTED','BEFORE','AFTER','OTHER')) 'Invalid SettingsState'
    Assert-Test ($result.ReceiptState -cin @('MISSING','INVALID','VALID')) 'Invalid ReceiptState'
    Assert-Test ($result.BackupIntegrity -cin @('MISSING','UNVERIFIED','MISMATCH','MATCH')) 'Invalid BackupIntegrity'
    foreach ($name in @('CurrentSha256','BeforeSha256','AfterSha256','StageFiles')) {
        Assert-Test ($null -ne $result.PSObject.Properties[$name]) ('Missing field ' + $name)
    }
    return $result
}

function Assert-TestTrustedHashes {
    param($Result, $Fixture)
    Assert-Equal $Result.BeforeSha256 $Fixture.BeforeHash 'Before hash'
    Assert-Equal $Result.AfterSha256 $Fixture.AfterHash 'After hash'
    Assert-Equal $Result.ReceiptState 'VALID' 'Receipt state'
    Assert-Equal $Result.BackupIntegrity 'MATCH' 'Backup integrity'
}

function New-TestStage {
    param($Fixture, [ValidateSet('APPLY','RESTORE')][string]$Kind, [byte[]]$Bytes)
    $prefix = if ($Kind -eq 'RESTORE') { '.typezero-combined-restore-' } else { '.typezero-combined-' }
    $path = Join-Path $Fixture.SettingsDirectory ($prefix + [guid]::NewGuid().ToString('N') + '.tmp')
    Write-TestBytes $Fixture.Root $path $Bytes
    return $path
}

# Refuse a module with executable top-level statements before dot-sourcing it.
$source = Join-Path ([IO.Path]::GetFullPath($SourceDirectory)) 'TerminalTransaction-WindowsTerminal.ps1'
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$parseErrors)
Assert-Equal @($parseErrors).Count 0 'Module parse errors'
Assert-Test ($null -eq $ast.BeginBlock -and $null -eq $ast.ProcessBlock) 'Module must contain definitions only'
foreach ($statement in $ast.EndBlock.Statements) {
    Assert-Test ($statement -is [Management.Automation.Language.FunctionDefinitionAst]) 'Module must contain definitions only'
}
. $source

Invoke-Test 'Diagnostic has no Execute switch and rejects execution binding' {
    $command = Get-Command Get-TypezeroOfflineTerminalCombinedRecoveryDiagnostic
    Assert-Test (-not $command.Parameters.ContainsKey('Execute')) 'Unexpected Execute parameter'
    $fixture = New-TestFixture
    Invoke-CheckedDiagnosis $fixture -MustThrow -Arguments @{ Execute = $true }
}

Invoke-Test 'Recovery functions have no filesystem writing command calls' {
    $functions = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -match 'Recovery' }, $true))
    Assert-Test ($functions.Count -ge 2) 'Expected diagnostic and snapshot helper'
    foreach ($function in $functions) {
        foreach ($command in $function.Body.FindAll({ param($node) $node -is [Management.Automation.Language.CommandAst] }, $true)) {
            $name = $command.GetCommandName()
            Assert-Test ($null -ne $name) 'Dynamic command invocation in recovery code'
            Assert-Test ($name -notmatch '^(New|Set|Add|Clear|Copy|Move|Remove|Rename|Invoke|Restore|Start|Stop|Update|Out)-') ('Write-capable command in recovery code: ' + $name)
        }
        foreach ($member in $function.Body.FindAll({ param($node) $node -is [Management.Automation.Language.InvokeMemberExpressionAst] }, $true)) {
            if ($member.Expression -is [Management.Automation.Language.TypeExpressionAst] -and $member.Expression.TypeName.FullName -match '^(System\.)?IO\.(File|Directory)$') {
                Assert-Test ($member.Member.Value -notmatch '^(Write|Append|Create|Delete|Move|Copy|Replace|Set)') ('Write-capable file method in recovery code: ' + $member.Member.Value)
            }
        }
    }
}

Invoke-Test 'Absent transaction directory' {
    $fixture = New-TestFixture -NoTransaction
    $result = Invoke-CheckedDiagnosis $fixture 'TRANSACTION_MISSING'
    Assert-Equal $result.ReceiptState 'MISSING' 'Receipt state'
    Assert-Equal $result.BackupIntegrity 'MISSING' 'Backup integrity'
    Assert-Equal $result.SettingsState 'UNTRUSTED' 'Settings state'
    Assert-Equal $result.CurrentSha256 $fixture.BeforeHash 'Current hash'
}

foreach ($missing in @('BOTH','RECEIPT','BACKUP')) {
    Invoke-Test ('Incomplete evidence: ' + $missing) {
        $fixture = New-TestFixture -NoReceipt:($missing -in @('BOTH','RECEIPT')) -NoBackup:($missing -in @('BOTH','BACKUP'))
        $result = Invoke-CheckedDiagnosis $fixture 'EVIDENCE_INCOMPLETE'
        Assert-Equal $result.SettingsState 'UNTRUSTED' 'Settings state'
        if ($missing -eq 'BACKUP') { Assert-Equal $result.ReceiptState 'VALID' 'Receipt state' }
        else { Assert-Equal $result.ReceiptState 'MISSING' 'Receipt state' }
    }
}

foreach ($settingsCase in @('BEFORE','AFTER','OTHER','MISSING')) {
    Invoke-Test ('Valid evidence and settings ' + $settingsCase) {
        $fixture = New-TestFixture -NoSettings:($settingsCase -eq 'MISSING')
        $state = 'ORIGINAL_BYTES_PRESENT'
        if ($settingsCase -eq 'AFTER') { Write-TestBytes $fixture.Root $fixture.Settings $fixture.AfterBytes; $state = 'APPLIED_BYTES_PRESENT' }
        elseif ($settingsCase -eq 'OTHER') { Write-TestBytes $fixture.Root $fixture.Settings $fixture.OtherBytes; $state = 'SETTINGS_CONFLICT' }
        elseif ($settingsCase -eq 'MISSING') { $state = 'SETTINGS_MISSING' }
        $result = Invoke-CheckedDiagnosis $fixture $state
        Assert-TestTrustedHashes $result $fixture
        Assert-Equal $result.SettingsState $settingsCase 'Settings state'
        if ($settingsCase -eq 'MISSING') { Assert-Test ($null -eq $result.CurrentSha256) 'Missing settings have a current hash' }
    }
}

Invoke-Test 'Tampered backup blocks interpretation even with applied settings' {
    $fixture = New-TestFixture
    Write-TestBytes $fixture.Root $fixture.BackupPath $fixture.OtherBytes
    Write-TestBytes $fixture.Root $fixture.Settings $fixture.AfterBytes
    $result = Invoke-CheckedDiagnosis $fixture 'BACKUP_HASH_MISMATCH'
    Assert-Equal $result.BackupIntegrity 'MISMATCH' 'Backup integrity'
    Assert-Equal $result.SettingsState 'UNTRUSTED' 'Settings state'
}

$invalidJsonCases = [ordered]@{
    'empty receipt' = ''
    'null root' = 'null'
    'array root' = '[]'
    'array with object root' = '[{}]'
    'string root' = '"receipt"'
    'boolean root' = 'true'
    'number root' = '1'
    'empty object root' = '{}'
    'malformed JSON' = '{"Version":'
    'trailing data' = '{} {}'
    'comment syntax' = '{/*comment*/"Version":1}'
    'trailing comma' = '{"Version":1,}'
}
foreach ($invalidName in $invalidJsonCases.Keys) {
    Invoke-Test ('Invalid receipt: ' + $invalidName) {
        $fixture = New-TestFixture
        Write-TestBytes $fixture.Root $fixture.ReceiptPath $script:Utf8.GetBytes($invalidJsonCases[$invalidName])
        $result = Invoke-CheckedDiagnosis $fixture 'INVALID_RECEIPT'
        Assert-Equal $result.ReceiptState 'INVALID' 'Receipt state'
        Assert-Test ($null -eq $result.BeforeSha256 -and $null -eq $result.AfterSha256) 'Untrusted receipt hashes leaked as trusted fields'
    }
}

foreach ($field in @('Version','Kind','SettingsPath','BeforeSha256','AfterSha256')) {
    Invoke-Test ('Invalid receipt: missing ' + $field) {
        $fixture = New-TestFixture
        $receipt = New-TestReceipt $fixture
        $receipt.Remove($field)
        Write-TestReceipt $fixture $receipt
        Invoke-CheckedDiagnosis $fixture 'INVALID_RECEIPT' | Out-Null
    }
    Invoke-Test ('Invalid receipt: null ' + $field) {
        $fixture = New-TestFixture
        $receipt = New-TestReceipt $fixture
        $receipt[$field] = $null
        Write-TestReceipt $fixture $receipt
        Invoke-CheckedDiagnosis $fixture 'INVALID_RECEIPT' | Out-Null
    }
}

foreach ($value in @('1', $true, 0, 2, -1, 2147483648)) {
    Invoke-Test ('Invalid receipt: version ' + ($value | ConvertTo-Json -Compress)) {
        $fixture = New-TestFixture
        $receipt = New-TestReceipt $fixture
        $receipt.Version = $value
        Write-TestReceipt $fixture $receipt
        Invoke-CheckedDiagnosis $fixture 'INVALID_RECEIPT' | Out-Null
    }
}
foreach ($literal in @('1.0','1e0')) {
    Invoke-Test ('Invalid receipt: noninteger JSON version token ' + $literal) {
        $fixture = New-TestFixture
        $text = (New-TestReceipt $fixture | ConvertTo-Json -Depth 20) -replace '"Version":\s*1', ('"Version": ' + $literal)
        Write-TestBytes $fixture.Root $fixture.ReceiptPath $script:Utf8.GetBytes($text)
        Invoke-CheckedDiagnosis $fixture 'INVALID_RECEIPT' | Out-Null
    }
}

foreach ($field in @('Kind','SettingsPath','BeforeSha256','AfterSha256')) {
    Invoke-Test ('Invalid receipt: nonstring ' + $field) {
        $fixture = New-TestFixture
        $receipt = New-TestReceipt $fixture
        $receipt[$field] = 1
        Write-TestReceipt $fixture $receipt
        Invoke-CheckedDiagnosis $fixture 'INVALID_RECEIPT' | Out-Null
    }
    Invoke-Test ('Invalid receipt: array ' + $field) {
        $fixture = New-TestFixture
        $receipt = New-TestReceipt $fixture
        $receipt[$field] = @('value')
        Write-TestReceipt $fixture $receipt
        Invoke-CheckedDiagnosis $fixture 'INVALID_RECEIPT' | Out-Null
    }
}

foreach ($kind in @('typezeroofflinecombined', 'TypezeroCombined', '')) {
    Invoke-Test ('Invalid receipt kind [' + $kind + ']') {
        $fixture = New-TestFixture
        $receipt = New-TestReceipt $fixture
        $receipt.Kind = $kind
        Write-TestReceipt $fixture $receipt
        Invoke-CheckedDiagnosis $fixture 'INVALID_RECEIPT' | Out-Null
    }
}

foreach ($pathCase in @('MISMATCH','RELATIVE','NONCANONICAL','OUTSIDE')) {
    Invoke-Test ('Invalid receipt SettingsPath ' + $pathCase) {
        $fixture = New-TestFixture
        $receipt = New-TestReceipt $fixture
        $receipt.SettingsPath = switch ($pathCase) {
            'MISMATCH' { Join-Path $fixture.SettingsDirectory 'other.json' }
            'RELATIVE' { 'settings.json' }
            'NONCANONICAL' { Join-Path $fixture.SettingsDirectory '.\settings.json' }
            'OUTSIDE' { Join-Path ([IO.Path]::GetTempPath()) 'unowned-settings.json' }
        }
        Write-TestReceipt $fixture $receipt
        Invoke-CheckedDiagnosis $fixture 'INVALID_RECEIPT' | Out-Null
    }
}

foreach ($hashCase in @('SHORT','LONG','NONHEX','NEWLINE','WHITESPACE','SAME','SAME_CASE')) {
    Invoke-Test ('Invalid receipt checksum ' + $hashCase) {
        $fixture = New-TestFixture
        $receipt = New-TestReceipt $fixture
        $receipt.AfterSha256 = switch ($hashCase) {
            'SHORT' { 'A' * 63 }
            'LONG' { 'A' * 65 }
            'NONHEX' { 'G' * 64 }
            'NEWLINE' { $fixture.AfterHash + "`n" }
            'WHITESPACE' { ' ' + $fixture.AfterHash }
            'SAME' { $fixture.BeforeHash }
            'SAME_CASE' { $fixture.BeforeHash.ToLowerInvariant() }
        }
        Write-TestReceipt $fixture $receipt
        Invoke-CheckedDiagnosis $fixture 'INVALID_RECEIPT' | Out-Null
    }
}

foreach ($duplicate in @('Version','version','AfterSha256','aftersha256','Unused','unused')) {
    Invoke-Test ('Invalid receipt duplicate/case ambiguity: ' + $duplicate) {
        $fixture = New-TestFixture
        $receipt = New-TestReceipt $fixture
        if ($duplicate -in @('Unused','unused')) { $receipt.Unused = 'ignored' }
        $json = $receipt | ConvertTo-Json -Depth 20 -Compress
        $extraValue = if ($duplicate -imatch '^version$') { '1' } else { '"ignored"' }
        $json = $json.Substring(0, $json.Length - 1) + ',"' + $duplicate + '":' + $extraValue + '}'
        Write-TestBytes $fixture.Root $fixture.ReceiptPath $script:Utf8.GetBytes($json)
        Invoke-CheckedDiagnosis $fixture 'INVALID_RECEIPT' | Out-Null
    }
}

Invoke-Test 'Invalid receipt uses wrong case for a required key' {
    $fixture = New-TestFixture
    $json = (New-TestReceipt $fixture | ConvertTo-Json -Depth 20) -creplace '"Version"', '"version"'
    Write-TestBytes $fixture.Root $fixture.ReceiptPath $script:Utf8.GetBytes($json)
    Invoke-CheckedDiagnosis $fixture 'INVALID_RECEIPT' | Out-Null
}

Invoke-Test 'Lowercase hashes and case-insensitive Windows path are accepted' {
    $fixture = New-TestFixture
    $receipt = New-TestReceipt $fixture
    $receipt.BeforeSha256 = $fixture.BeforeHash.ToLowerInvariant()
    $receipt.AfterSha256 = $fixture.AfterHash.ToLowerInvariant()
    $receipt.SettingsPath = $fixture.Settings.ToUpperInvariant()
    Write-TestReceipt $fixture $receipt
    $result = Invoke-CheckedDiagnosis $fixture 'ORIGINAL_BYTES_PRESENT'
    Assert-TestTrustedHashes $result $fixture
}

Invoke-Test 'Ignored metadata cannot influence diagnostic and is never followed' {
    $fixture = New-TestFixture
    $receipt = New-TestReceipt $fixture
    $receipt.Font = @{ Execute = $true; Path = 'Z:\unowned\font' }
    $receipt.Size = 'malformed ignored metadata'
    $receipt.Weight = $null
    $receipt.RecoveryAllowed = $true
    $receipt.BackupPath = 'Z:\unowned\settings-original.json'
    $receipt.StagePath = 'Z:\unowned\stage.tmp'
    Write-TestReceipt $fixture $receipt
    $result = Invoke-CheckedDiagnosis $fixture 'ORIGINAL_BYTES_PRESENT'
    Assert-TestTrustedHashes $result $fixture
}

Invoke-Test 'Safety schema works without optional font metadata' {
    $fixture = New-TestFixture
    $receipt = New-TestReceipt $fixture
    foreach ($name in @('Font','Size','Weight')) { $receipt.Remove($name) }
    Write-TestReceipt $fixture $receipt
    Invoke-CheckedDiagnosis $fixture 'ORIGINAL_BYTES_PRESENT' | Out-Null
}

Invoke-Test 'Invalid UTF-8 receipt is not trusted' {
    $fixture = New-TestFixture
    Write-TestBytes $fixture.Root $fixture.ReceiptPath ([byte[]]@(255,254,0,1))
    Invoke-CheckedDiagnosis $fixture 'INVALID_RECEIPT' | Out-Null
}

Invoke-Test 'Oversized receipt is rejected without interpretation' {
    $fixture = New-TestFixture
    Write-TestBytes $fixture.Root $fixture.ReceiptPath $script:Utf8.GetBytes((' ' * 65537))
    Invoke-CheckedDiagnosis $fixture -MustThrow
}

foreach ($ancestor in @('SETTINGS','BACKUP')) {
    Invoke-Test ('Reject regular-file ancestor ' + $ancestor) {
        $fixture = New-TestFixture -NoSettings:($ancestor -eq 'SETTINGS') -NoTransaction:($ancestor -eq 'BACKUP')
        $path = if ($ancestor -eq 'SETTINGS') { Join-Path $fixture.Root 'Packages' } else { Join-Path $fixture.Root 'Typezero' }
        Write-TestBytes $fixture.Root $path $fixture.OtherBytes
        Invoke-CheckedDiagnosis $fixture -MustThrow
    }
}

Invoke-Test 'All apply/restore stages are inventoried without association or promotion' {
    $fixture = New-TestFixture
    $expected = @{}
    foreach ($kind in @('APPLY','RESTORE')) {
        foreach ($match in @('BEFORE','AFTER','OTHER')) {
            $bytes = switch ($match) { 'BEFORE' { $fixture.BeforeBytes }; 'AFTER' { $fixture.AfterBytes }; 'OTHER' { $fixture.OtherBytes } }
            $path = New-TestStage $fixture $kind $bytes
            $expected[$path] = @{ Kind = $kind; Match = $match; Hash = Get-TestByteHash $bytes }
        }
    }
    foreach ($ignored in @('.typezero-combined-not-a-guid.tmp', '.typezero-combined-' + [guid]::NewGuid().ToString('N') + '.tmp.bak', 'unrelated.tmp')) {
        Write-TestBytes $fixture.Root (Join-Path $fixture.SettingsDirectory $ignored) $fixture.OtherBytes
    }
    Write-TestBytes $fixture.Root (Join-Path $fixture.SettingsDirectory ('nested\.typezero-combined-' + [guid]::NewGuid().ToString('N') + '.tmp')) $fixture.AfterBytes
    $result = Invoke-CheckedDiagnosis $fixture 'ORIGINAL_BYTES_PRESENT'
    Assert-Equal @($result.StageFiles).Count 6 'Exact stage inventory count'
    foreach ($stage in $result.StageFiles) {
        Assert-Test ($expected.ContainsKey($stage.Path)) 'Unexpected stage path'
        Assert-Equal $stage.Kind $expected[$stage.Path].Kind 'Stage kind'
        Assert-Equal $stage.ContentMatch $expected[$stage.Path].Match 'Stage content match'
        Assert-Equal $stage.Sha256 $expected[$stage.Path].Hash 'Stage hash'
        Assert-Equal $stage.Association 'UNPROVEN' 'Stage association'
    }
}

foreach ($evidence in @('MISSING','INVALID')) {
    Invoke-Test ('Stages remain UNVERIFIED with ' + $evidence + ' receipt') {
        $fixture = New-TestFixture -NoReceipt:($evidence -eq 'MISSING')
        if ($evidence -eq 'INVALID') { Write-TestBytes $fixture.Root $fixture.ReceiptPath $script:Utf8.GetBytes('null') }
        New-TestStage $fixture 'APPLY' $fixture.AfterBytes | Out-Null
        $state = if ($evidence -eq 'MISSING') { 'EVIDENCE_INCOMPLETE' } else { 'INVALID_RECEIPT' }
        $result = Invoke-CheckedDiagnosis $fixture $state
        Assert-Equal @($result.StageFiles).Count 1 'Stage inventory count'
        Assert-Equal $result.StageFiles[0].ContentMatch 'UNVERIFIED' 'Stage content match'
        Assert-Equal $result.StageFiles[0].Association 'UNPROVEN' 'Stage association'
    }
}

foreach ($artifact in @('TRANSACTION','RECEIPT','BACKUP','SETTINGS','STAGE')) {
    Invoke-Test ('Reject nonfile/nondirectory artifact ' + $artifact) {
        $fixture = New-TestFixture -NoTransaction:($artifact -eq 'TRANSACTION') -NoReceipt:($artifact -eq 'RECEIPT') -NoBackup:($artifact -eq 'BACKUP') -NoSettings:($artifact -eq 'SETTINGS')
        $path = switch ($artifact) {
            'TRANSACTION' { $fixture.BackupDirectory }
            'RECEIPT' { $fixture.ReceiptPath }
            'BACKUP' { $fixture.BackupPath }
            'SETTINGS' { $fixture.Settings }
            'STAGE' { Join-Path $fixture.SettingsDirectory ('.typezero-combined-' + [guid]::NewGuid().ToString('N') + '.tmp') }
        }
        if ($artifact -eq 'TRANSACTION') { Write-TestBytes $fixture.Root $path $fixture.OtherBytes }
        else { [IO.Directory]::CreateDirectory($path) | Out-Null }
        Invoke-CheckedDiagnosis $fixture -MustThrow
    }
}

foreach ($pathCase in @('OTHER_FIXTURE','OUTSIDE_BACKUP_ROOT','TRAVERSAL_ESCAPE','NESTED_BACKUP','WRONG_ROOT_NAME','NESTED_TEST_ROOT')) {
    Invoke-Test ('Reject unsafe path ' + $pathCase) {
        $fixture = New-TestFixture
        $other = New-TestFixture
        $arguments = switch ($pathCase) {
            'OTHER_FIXTURE' { @{ BackupDirectory = $other.BackupDirectory } }
            'OUTSIDE_BACKUP_ROOT' { @{ BackupDirectory = $fixture.Root } }
            'TRAVERSAL_ESCAPE' { @{ BackupDirectory = Join-Path $fixture.BackupDirectory '..\..\..\..\escaped' } }
            'NESTED_BACKUP' { @{ BackupDirectory = Join-Path $fixture.BackupDirectory 'nested' } }
            'WRONG_ROOT_NAME' { @{ TestRoot = $fixture.SettingsDirectory } }
            'NESTED_TEST_ROOT' {
                $nested = Join-Path $fixture.Root ('typezero-terminal-txn-' + [guid]::NewGuid().ToString('N'))
                [IO.Directory]::CreateDirectory($nested) | Out-Null
                @{ TestRoot = $nested }
            }
        }
        Invoke-CheckedDiagnosis $fixture -MustThrow -AdditionalRoots @($other.Root) -Arguments $arguments
    }
}

# Junction targets are also NEW disposable fixture roots. No link points to user data.
foreach ($redirect in @('ROOT','BACKUP_ANCESTOR','SETTINGS_ANCESTOR','TRANSACTION','RECEIPT','BACKUP','SETTINGS','STAGE')) {
    Invoke-Test ('Reject junction/reparse path ' + $redirect) {
        $fixture = switch ($redirect) {
            'ROOT' { New-TestFixture -NoTransaction -NoSettings }
            'BACKUP_ANCESTOR' { New-TestFixture -NoTransaction }
            'SETTINGS_ANCESTOR' { New-TestFixture -NoSettings }
            'TRANSACTION' { New-TestFixture -NoTransaction }
            'RECEIPT' { New-TestFixture -NoReceipt }
            'BACKUP' { New-TestFixture -NoBackup }
            'SETTINGS' { New-TestFixture -NoSettings }
            default { New-TestFixture }
        }
        $target = New-TestFixture
        $path = switch ($redirect) {
            'ROOT' { $fixture.Root }
            'BACKUP_ANCESTOR' { Join-Path $fixture.Root 'Typezero' }
            'SETTINGS_ANCESTOR' { Join-Path $fixture.Root 'Packages' }
            'TRANSACTION' { $fixture.BackupDirectory }
            'RECEIPT' { $fixture.ReceiptPath }
            'BACKUP' { $fixture.BackupPath }
            'SETTINGS' { $fixture.Settings }
            'STAGE' { Join-Path $fixture.SettingsDirectory ('.typezero-combined-restore-' + [guid]::NewGuid().ToString('N') + '.tmp') }
        }
        if ($redirect -eq 'ROOT') {
            # Replace only our newly-created, confirmed empty root directory.
            Assert-Equal @([IO.Directory]::GetFileSystemEntries($path)).Count 0 'Root must be empty before junction setup'
            [IO.Directory]::Delete($path, $false)
        }
        else { [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path)) | Out-Null }
        New-Item -ItemType Junction -Path $path -Target $target.Root -ErrorAction Stop | Out-Null
        Invoke-CheckedDiagnosis $fixture -MustThrow -AdditionalRoots @($target.Root)
    }
}

foreach ($artifact in @('RECEIPT','BACKUP','SETTINGS','STAGE')) {
    Invoke-Test ('Reject exclusively locked evidence ' + $artifact) {
        $fixture = New-TestFixture
        $path = switch ($artifact) {
            'RECEIPT' { $fixture.ReceiptPath }
            'BACKUP' { $fixture.BackupPath }
            'SETTINGS' { $fixture.Settings }
            'STAGE' { New-TestStage $fixture 'APPLY' $fixture.AfterBytes }
        }
        $beforeSnapshot = Get-TestSnapshot @($fixture.Root)
        $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
        $caught = $null
        try {
            try { Get-TypezeroOfflineTerminalCombinedRecoveryDiagnostic -TestRoot $fixture.Root -BackupDirectory $fixture.BackupDirectory | Out-Null }
            catch { $caught = $_ }
        }
        finally { $stream.Dispose() }
        Assert-Test ($null -ne $caught) 'Locked evidence should throw'
        Assert-Equal (Get-TestSnapshot @($fixture.Root)) $beforeSnapshot 'Locked evidence diagnostic changed fixture'
    }
}

# Inject a changed *observation*, not a filesystem write. This deterministic
# sensitivity test exercises the race guard while all fixture bytes stay intact.
$script:RealRecoverySnapshot = (Get-Command Get-TypezeroOfflineRecoveryFileSnapshot).ScriptBlock
foreach ($change in @('SETTINGS_HASH','RECEIPT_HASH','BACKUP_HASH','STAGE_HASH','APPEARS','DISAPPEARS')) {
    Invoke-Test ('Reject changed evidence observation ' + $change) {
        $fixture = New-TestFixture -NoSettings:($change -eq 'APPEARS')
        $script:ChangedObservationPath = switch ($change) {
            'RECEIPT_HASH' { $fixture.ReceiptPath }
            'BACKUP_HASH' { $fixture.BackupPath }
            'STAGE_HASH' { New-TestStage $fixture 'APPLY' $fixture.AfterBytes }
            default { $fixture.Settings }
        }
        $script:ObservationChange = $change
        $script:ObservationCounts = @{}
        function Get-TypezeroOfflineRecoveryFileSnapshot {
            [CmdletBinding()]
            param([Parameter(Mandatory)][string]$Path, [switch]$IncludeBytes)
            $observation = & $script:RealRecoverySnapshot -Path $Path -IncludeBytes:$IncludeBytes
            if (-not $script:ObservationCounts.ContainsKey($Path)) { $script:ObservationCounts[$Path] = 0 }
            $script:ObservationCounts[$Path]++
            if ($Path -eq $script:ChangedObservationPath -and $script:ObservationCounts[$Path] -eq 2) {
                if ($script:ObservationChange -eq 'APPEARS') {
                    return [pscustomobject]@{ Exists = $true; Sha256 = ('F' * 64); Bytes = $null }
                }
                if ($script:ObservationChange -eq 'DISAPPEARS') {
                    return [pscustomobject]@{ Exists = $false; Sha256 = $null; Bytes = $null }
                }
                return [pscustomobject]@{ Exists = $observation.Exists; Sha256 = ('F' * 64); Bytes = $observation.Bytes }
            }
            return $observation
        }
        try {
            Invoke-CheckedDiagnosis $fixture -MustThrow -ThrowPattern 'Recovery evidence changed during diagnosis'
            Assert-Equal $script:ObservationCounts[$script:ChangedObservationPath] 2 'Changed evidence test must reach second observation'
        }
        finally {
            Set-Item -LiteralPath 'Function:Get-TypezeroOfflineRecoveryFileSnapshot' -Value $script:RealRecoverySnapshot
        }
    }
}

Write-Host ('RESULT passed=' + $script:Passed + ' failed=' + $script:Failed + ' skipped=' + $script:Skipped + ' retainedRoots=' + $script:Roots.Count)
[pscustomobject]@{
    Passed = $script:Passed
    Failed = $script:Failed
    Skipped = $script:Skipped
    RetainedFixtureRoots = @($script:Roots)
    Failures = @($script:Failures)
    Source = $source
    PowerShellVersion = $PSVersionTable.PSVersion.ToString()
}
if ($script:Failed -gt 0) { throw ($script:Failed.ToString() + ' recovery diagnostic regression test(s) failed.') }
