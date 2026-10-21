#requires -Version 7.3
[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
param(
    [Parameter(Mandatory)][string]$TargetRoot,
    [string]$PackageRoot = $PSScriptRoot,
    [ValidateSet('Install','Rollback')][string]$Action = 'Install',
    [string]$BackupDirectory,
    [switch]$Execute,
    # Deterministic process-kill barrier; accepted only by marked disposable Git fixtures.
    [ValidateRange(-1,1000)][int]$FixturePauseAfterWrite = -1
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'This guarded installer requires Windows and PowerShell 7.3+.' }

if (-not ('TypezeroOverlay.Native' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
namespace TypezeroOverlay {
  public static class Native {
    [StructLayout(LayoutKind.Sequential)] public struct FileInfo {
      public uint Attributes; public System.Runtime.InteropServices.ComTypes.FILETIME Creation;
      public System.Runtime.InteropServices.ComTypes.FILETIME Access;
      public System.Runtime.InteropServices.ComTypes.FILETIME Write;
      public uint Volume; public uint SizeHigh; public uint SizeLow; public uint Links;
      public uint IndexHigh; public uint IndexLow;
    }
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool GetFileInformationByHandle(SafeFileHandle handle, out FileInfo info);
  }
}
'@
}
function Get-Hash([byte[]]$Bytes) { [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)) }
function Assert-OrdinaryPath([string]$Path) {
    $part = [IO.Path]::GetFullPath($Path)
    while ($part) {
        if ([IO.File]::Exists($part) -or [IO.Directory]::Exists($part)) {
            $attrs = [IO.File]::GetAttributes($part)
            if (($attrs -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Link/reparse path refused: $part" }
            if (($attrs -band [IO.FileAttributes]::Directory) -eq 0) {
                $handle = [IO.File]::Open($part, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
                try {
                    $info = [TypezeroOverlay.Native+FileInfo]::new()
                    if (-not [TypezeroOverlay.Native]::GetFileInformationByHandle($handle.SafeFileHandle, [ref]$info) -or $info.Links -ne 1) {
                        throw "Hard link or unreadable file identity refused: $part"
                    }
                } finally { $handle.Dispose() }
            }
        } else {
            # GetAttributes detects dangling links that Exists intentionally hides.
            try {
                $attrs = [IO.File]::GetAttributes($part)
                if (($attrs -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Dangling link refused: $part" }
            } catch [IO.FileNotFoundException] {} catch [IO.DirectoryNotFoundException] {}
        }
        $parent = [IO.Directory]::GetParent($part)
        $part = if ($null -eq $parent) { $null } else { $parent.FullName }
    }
}
function Get-SafeBytes([string]$Path, [int]$Maximum = 4194304) {
    Assert-OrdinaryPath $Path
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        if ($stream.Length -gt $Maximum) { throw "File too large: $Path" }
        $bytes = [byte[]]::new([int]$stream.Length)
        $stream.ReadExactly($bytes)
        return ,$bytes
    } finally { $stream.Dispose() }
}
function Write-NewDurable([string]$Path, [byte[]]$Bytes) {
    Assert-OrdinaryPath $Path
    $stream = [IO.FileStream]::new($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write,
        [IO.FileShare]::None, 4096, [IO.FileOptions]::WriteThrough)
    try { $stream.Write($Bytes); $stream.Flush($true) } finally { $stream.Dispose() }
}
function Assert-JsonNames($Node) {
    if ($Node.ValueKind -eq [Text.Json.JsonValueKind]::Object) {
        $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($property in $Node.EnumerateObject()) {
            if (-not $names.Add($property.Name)) { throw 'Duplicate/case-colliding JSON property.' }
            Assert-JsonNames $property.Value
        }
    } elseif ($Node.ValueKind -eq [Text.Json.JsonValueKind]::Array) {
        foreach ($item in $Node.EnumerateArray()) { Assert-JsonNames $item }
    }
}
function Read-StrictJson([byte[]]$Bytes) {
    $utf8 = [Text.UTF8Encoding]::new($false,$true)
    $json = $utf8.GetString($Bytes)
    $doc = [Text.Json.JsonDocument]::Parse($json)
    try { Assert-JsonNames $doc.RootElement } finally { $doc.Dispose() }
    return ConvertFrom-Json -InputObject $json -AsHashtable -Depth 24
}
function Assert-Keys($Object, [string[]]$Names) {
    if ($Object -isnot [Collections.IDictionary] -or $Object.Count -ne $Names.Count) { throw 'Unexpected JSON contract.' }
    foreach ($name in $Names) { if (-not $Object.Contains($name)) { throw "Missing JSON property: $name" } }
}
function Assert-Hash($Value) {
    if ($Value -isnot [string] -or $Value -cnotmatch '\A[A-F0-9]{64}\z') { throw 'Invalid SHA-256 value.' }
}
function Assert-Relative([string]$Path) {
    if ($Path -cnotmatch '\A(?:Netzach/PowerShell/ThemeEngine/|tools/overlay/)[A-Za-z0-9._/-]+\.(?:ps1|py|md)\z' -or
        $Path.Contains('//')) { throw "Forbidden overlay path: $Path" }
    foreach ($part in $Path.Split('/')) {
        if ($part -in @('.','..') -or $part.EndsWith('.') -or
            $part -match '\A(?:CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\..*)?\z') { throw "Unsafe path segment: $Path" }
    }
}
function Join-Safe([string]$Root, [string]$Relative) {
    $path = [IO.Path]::GetFullPath([IO.Path]::Combine($Root, $Relative.Replace('/',[IO.Path]::DirectorySeparatorChar)))
    if (-not $path.StartsWith($Root.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Path escaped root.' }
    Assert-OrdinaryPath $path
    return $path
}
function Get-LiveHash([string]$Path) {
    Assert-OrdinaryPath $Path
    if ([IO.Directory]::Exists($Path)) { throw "File/directory collision: $Path" }
    if ([IO.File]::Exists($Path)) { return Get-Hash (Get-SafeBytes $Path) }
    return $null
}
function Invoke-Git([string[]]$Arguments) {
    $result = & git -C $script:root @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Git verification failed: $result" }
    return ($result -join "`n").Trim()
}
function Write-Event([string]$Folder, [string]$Name, [int]$Index) {
    $event = [ordered]@{ SchemaVersion=1; Event=$Name; Index=$Index; Utc=[DateTime]::UtcNow.ToString('O') }
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($event | ConvertTo-Json -Compress))
    Write-NewDurable (Join-Path $Folder ('{0:D4}-{1}.json' -f $Index,$Name)) $bytes
}

$root = [IO.Path]::GetFullPath($TargetRoot).TrimEnd('\')
$package = [IO.Path]::GetFullPath($PackageRoot).TrimEnd('\')
if ($root.StartsWith('\\') -or $package.StartsWith('\\') -or -not [IO.Directory]::Exists($root)) {
    throw 'Use existing local absolute repository/package directories.'
}
Assert-OrdinaryPath $root
Assert-OrdinaryPath $package
$manifestBytes = Get-SafeBytes (Join-Path $package 'overlay.json') 1048576
$manifestHash = Get-Hash $manifestBytes
$manifest = Read-StrictJson $manifestBytes
Assert-Keys $manifest @('SchemaVersion','Kind','Version','BaselineCommit','FixtureOnlyRuntime','LiveFontActivation','InstallerSha256','ProtectedFiles','Files')
if ($manifest.SchemaVersion -ne 1 -or $manifest.Kind -cne 'TypezeroGuardedSourceOverlay' -or
    $manifest.Version -cnotmatch '\A[A-Za-z0-9][A-Za-z0-9._-]{0,79}\z' -or
    $manifest.BaselineCommit -cnotmatch '\A[a-f0-9]{40}\z' -or
    $manifest.FixtureOnlyRuntime -isnot [bool] -or $manifest.FixtureOnlyRuntime -ne $true -or
    $manifest.LiveFontActivation -isnot [bool] -or $manifest.LiveFontActivation -ne $false) { throw 'Invalid overlay manifest.' }
Assert-Hash $manifest.InstallerSha256
if ((Get-Hash (Get-SafeBytes $PSCommandPath)) -cne $manifest.InstallerSha256) { throw 'Installer hash differs from manifest.' }
$pinned = @('Netzach/PowerShell/ThemeEngine/TypezeroIntegrationPreflight.ps1',
    'Netzach/PowerShell/ThemeEngine/TerminalTransactionV2-WindowsTerminal.ps1',
    'Netzach/PowerShell/ThemeEngine/TerminalReplace-WindowsTerminal.ps1',
    'Netzach/PowerShell/ThemeEngine/TerminalEvidenceSealV2-WindowsTerminal.ps1')
$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$rows = @($manifest.Files)
if ($rows.Count -lt 1 -or $rows.Count -gt 1000) { throw 'Invalid overlay file count.' }
$payload = @{}
$total = 0L
foreach ($row in $rows) {
    Assert-Keys $row @('Path','BeforeSha256','AfterSha256','Length')
    Assert-Relative $row.Path
    if (-not $seen.Add($row.Path) -or $row.Path -iin $pinned) { throw 'Duplicate or pinned overlay path.' }
    if ($null -ne $row.BeforeSha256) { Assert-Hash $row.BeforeSha256 }
    Assert-Hash $row.AfterSha256
    if ($row.Length -isnot [long] -and $row.Length -isnot [int]) { throw 'Invalid payload length type.' }
    if ($row.Length -lt 0 -or $row.Length -gt 4194304) { throw 'Invalid payload length.' }
    $bytes = Get-SafeBytes (Join-Safe (Join-Path $package 'payload') $row.Path)
    if ($bytes.Length -ne $row.Length -or (Get-Hash $bytes) -cne $row.AfterSha256) { throw "Payload tampering: $($row.Path)" }
    $payload[$row.Path] = $bytes
    $total += $bytes.Length
    $null = Join-Safe $root $row.Path
}
if ($total -gt 67108864) { throw 'Overlay is too large.' }
foreach ($path in $seen) {
    foreach ($other in $seen) {
        if ($other.StartsWith($path + '/', [StringComparison]::OrdinalIgnoreCase)) { throw 'File/directory prefix collision.' }
    }
}
$protectedSeen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($item in $manifest.ProtectedFiles) {
    Assert-Keys $item @('Path','Sha256')
    if ($item.Path -cnotin $pinned -or -not $protectedSeen.Add($item.Path)) { throw 'Unexpected protected file.' }
    Assert-Hash $item.Sha256
    if ((Get-LiveHash (Join-Safe $root $item.Path)) -cne $item.Sha256) { throw "Pinned baseline file mismatch: $($item.Path)" }
}
if ((Invoke-Git @('rev-parse','--show-toplevel')).Replace('/','\').TrimEnd('\') -ine $root -or
    (Invoke-Git @('rev-parse','HEAD')) -cne $manifest.BaselineCommit) { throw 'Repository root/HEAD does not match exact baseline.' }
foreach ($path in $pinned) {
    $existsInBase = Invoke-Git @('ls-tree','--name-only',$manifest.BaselineCommit,'--',$path)
    if ($existsInBase -and -not $protectedSeen.Contains($path)) { throw 'Manifest omitted a pinned baseline file.' }
}

$backupRoot = Join-Path $root '.typezero-overlay-backups'
Assert-OrdinaryPath $backupRoot
$backup = $null
if ($Action -eq 'Install') {
    if ($BackupDirectory) { throw 'BackupDirectory is generated for Install; supply it only for Rollback.' }
    if (Invoke-Git @('status','--porcelain','--untracked-files=no')) { throw 'Install requires a clean tracked baseline worktree.' }
    foreach ($row in $rows) {
        if ((Get-LiveHash (Join-Safe $root $row.Path)) -cne $row.BeforeSha256) { throw "Baseline/new-file collision: $($row.Path)" }
    }
} else {
    if (-not $BackupDirectory) { throw 'Rollback requires the exact BackupDirectory reported by Install.' }
    $backup = [IO.Path]::GetFullPath($BackupDirectory).TrimEnd('\')
    if ([IO.Path]::GetDirectoryName($backup) -ine $backupRoot -or
        [IO.Path]::GetFileName($backup) -cnotmatch '\A[A-Za-z0-9][A-Za-z0-9._-]{0,79}-[a-f0-9]{32}\z') { throw 'Backup directory must be a direct guarded backup child.' }
    Assert-OrdinaryPath $backup
    $plan = Read-StrictJson (Get-SafeBytes (Join-Path $backup 'plan.json') 1048576)
    Assert-Keys $plan @('SchemaVersion','Kind','ManifestSha256','TargetRoot','BaselineCommit','Version')
    if ($plan.SchemaVersion -ne 1 -or $plan.Kind -cne 'TypezeroOverlayBackup' -or
        $plan.ManifestSha256 -cne $manifestHash -or $plan.TargetRoot -cne $root -or
        $plan.BaselineCommit -cne $manifest.BaselineCommit -or $plan.Version -cne $manifest.Version -or
        (Get-Hash (Get-SafeBytes (Join-Path $backup 'overlay.json') 1048576)) -cne $manifestHash) { throw 'Backup plan is not bound to this target/package.' }
    for ($i=0; $i -lt $rows.Count; $i++) {
        $row = $rows[$i]
        if ($null -ne $row.BeforeSha256 -and
            (Get-Hash (Get-SafeBytes (Join-Path $backup ('{0:D4}.bin' -f $i)))) -cne $row.BeforeSha256) { throw 'Backup bytes changed.' }
        $live = Get-LiveHash (Join-Safe $root $row.Path)
        if ($live -cne $row.BeforeSha256 -and $live -cne $row.AfterSha256) { throw "Rollback conflict; preserving all files: $($row.Path)" }
    }
}
if ($FixturePauseAfterWrite -ge 0) {
    if ($Action -ne 'Install' -or (Invoke-Git @('remote')) -or
        [Text.Encoding]::UTF8.GetString((Get-SafeBytes (Join-Path $root '.typezero-overlay-fixture'))) -cne 'TypezeroOverlayDisposableFixtureV1') {
        throw 'Interruption barrier requires a marked disposable Git fixture without remotes.'
    }
}
$summary = [ordered]@{ Action=$Action; Mode='DryRun'; Version=$manifest.Version; BaselineCommit=$manifest.BaselineCommit;
    ManifestSha256=$manifestHash; TargetRoot=$root; FileCount=$rows.Count; BackupDirectory=$backup }
if (-not $Execute) { [pscustomobject]$summary; return }
if (-not $PSCmdlet.ShouldProcess($root, "$Action verified source overlay $($manifest.Version)")) { [pscustomobject]$summary; return }

$lockPath = Join-Path $root '.typezero-overlay-install.lock'
Assert-OrdinaryPath $lockPath
$lock = [IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try {
    # Repeat all mutable-target checks after taking the cooperative writer lock.
    if ((Invoke-Git @('rev-parse','HEAD')) -cne $manifest.BaselineCommit) { throw 'HEAD changed before write.' }
    foreach ($item in $manifest.ProtectedFiles) {
        if ((Get-LiveHash (Join-Safe $root $item.Path)) -cne $item.Sha256) { throw 'Pinned file changed before write.' }
    }
    if ($Action -eq 'Install') {
        if (Invoke-Git @('status','--porcelain','--untracked-files=no')) { throw 'Tracked baseline changed before write.' }
        foreach ($row in $rows) {
            if ((Get-LiveHash (Join-Safe $root $row.Path)) -cne $row.BeforeSha256) { throw 'Baseline changed before write.' }
        }
        $null = [IO.Directory]::CreateDirectory($backupRoot)
        Assert-OrdinaryPath $backupRoot
        $backup = Join-Path $backupRoot ($manifest.Version + '-' + [guid]::NewGuid().ToString('N'))
        $null = [IO.Directory]::CreateDirectory($backup)
        Assert-OrdinaryPath $backup
        for ($i=0; $i -lt $rows.Count; $i++) {
            if ($null -ne $rows[$i].BeforeSha256) {
                $before = Get-SafeBytes (Join-Safe $root $rows[$i].Path)
                if ((Get-Hash $before) -cne $rows[$i].BeforeSha256) { throw 'Baseline changed during backup.' }
                Write-NewDurable (Join-Path $backup ('{0:D4}.bin' -f $i)) $before
            }
        }
        Write-NewDurable (Join-Path $backup 'overlay.json') $manifestBytes
        $plan = [ordered]@{SchemaVersion=1;Kind='TypezeroOverlayBackup';ManifestSha256=$manifestHash;
            TargetRoot=$root;BaselineCommit=$manifest.BaselineCommit;Version=$manifest.Version}
        Write-NewDurable (Join-Path $backup 'plan.json') ([Text.UTF8Encoding]::new($false).GetBytes(($plan | ConvertTo-Json -Compress)))
        Write-Event $backup 'Prepared' 0
        for ($i=0; $i -lt $rows.Count; $i++) {
            $row = $rows[$i]
            $target = Join-Safe $root $row.Path
            $parent = [IO.Path]::GetDirectoryName($target)
            $null = [IO.Directory]::CreateDirectory($parent)
            Assert-OrdinaryPath $parent
            $pending = $target + '.typezero-overlay-' + [guid]::NewGuid().ToString('N') + '.pending'
            Write-NewDurable $pending $payload[$row.Path]
            if ((Get-LiveHash $target) -cne $row.BeforeSha256) { throw 'Concurrent target edit refused; staging/backup retained.' }
            [IO.File]::Move($pending,$target,$true)
            if ((Get-LiveHash $target) -cne $row.AfterSha256) { throw 'Post-write verification failed; backup retained.' }
            Write-Event $backup 'Installed' ($i+1)
            if ($FixturePauseAfterWrite -eq ($i+1)) {
                Write-NewDurable (Join-Path $backup 'fixture-pause.ready') ([byte[]]@(1))
                while (-not [IO.File]::Exists((Join-Path $backup 'fixture-pause.release'))) { Start-Sleep -Milliseconds 50 }
            }
        }
        Write-Event $backup 'Completed' ($rows.Count+1)
    } else {
        # Preflight every row before reverting any row. Events are evidence, never authorization.
        for ($i=0; $i -lt $rows.Count; $i++) {
            $row = $rows[$i]
            if ($null -ne $row.BeforeSha256 -and
                (Get-Hash (Get-SafeBytes (Join-Path $backup ('{0:D4}.bin' -f $i)))) -cne $row.BeforeSha256) { throw 'Backup changed before rollback.' }
            $live = Get-LiveHash (Join-Safe $root $row.Path)
            if ($live -cne $row.BeforeSha256 -and $live -cne $row.AfterSha256) { throw 'Concurrent rollback conflict; no automatic overwrite.' }
        }
        for ($i=0; $i -lt $rows.Count; $i++) {
            $row = $rows[$i]
            $target = Join-Safe $root $row.Path
            $live = Get-LiveHash $target
            if ($live -ceq $row.BeforeSha256) { continue }
            if ($live -cne $row.AfterSha256) { throw 'Target changed during rollback; remaining evidence retained.' }
            if ($null -eq $row.BeforeSha256) { [IO.File]::Delete($target) }
            else {
                $bytes = Get-SafeBytes (Join-Path $backup ('{0:D4}.bin' -f $i))
                if ((Get-Hash $bytes) -cne $row.BeforeSha256) { throw 'Backup changed during rollback.' }
                $pending = $target + '.typezero-rollback-' + [guid]::NewGuid().ToString('N') + '.pending'
                Write-NewDurable $pending $bytes
                if ((Get-LiveHash $target) -cne $row.AfterSha256) { throw 'Rollback target changed before replacement.' }
                [IO.File]::Move($pending,$target,$true)
            }
            if ((Get-LiveHash $target) -cne $row.BeforeSha256) { throw 'Rollback post-write verification failed.' }
        }
        $event = Join-Path $backup ('rollback-' + [guid]::NewGuid().ToString('N') + '.json')
        Write-NewDurable $event ([Text.UTF8Encoding]::new($false).GetBytes('{"SchemaVersion":1,"Event":"RolledBack"}'))
    }
    $summary.Mode = 'Executed'
    $summary.BackupDirectory = $backup
    [pscustomobject]$summary
} finally {
    $lock.Dispose()
    # The stable lock file remains after success/crash; exclusive handle, not existence, owns it.
}
