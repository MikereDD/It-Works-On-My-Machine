function Get-TypezeroFontProfileTextSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text)

    $options = [System.Text.Json.JsonDocumentOptions]::new()
    $options.AllowTrailingCommas = $true
    $options.CommentHandling =
        [System.Text.Json.JsonCommentHandling]::Skip

    $doc = [System.Text.Json.JsonDocument]::Parse($Text, $options)

    try {
        $profiles = $doc.RootElement.GetProperty('profiles')
        $list = $profiles.GetProperty('list')
        $guid = '{574e775e-4f2a-5b96-ac1e-a2962a402336}'

        $hits = @()
        $others = [Collections.Generic.List[string]]::new()

        foreach ($entry in $list.EnumerateArray()) {
            $entryGuid = $null

            foreach ($property in $entry.EnumerateObject()) {
                if ($property.Name -ceq 'guid') {
                    $entryGuid = $property.Value.GetString()
                }
            }

            if ($entryGuid -ieq $guid) {
                $hasFont = $false
                $face = $null
                $size = $null
                $weight = $null

                foreach ($property in $entry.EnumerateObject()) {
                    if ($property.Name -ceq 'font') {
                        if ($hasFont) {
                            throw 'Duplicate profile font property.'
                        }

                        $hasFont = $true
                        $font = $property.Value
                        $face = $font.GetProperty('face').GetString()
                        $size = $font.GetProperty('size').GetDouble()
                        $weight = $font.GetProperty('weight').GetString()
                    }
                }

                $hits += [pscustomobject]@{
                    Raw     = $entry.GetRawText()
                    HasFont = $hasFont
                    Face    = $face
                    Size    = $size
                    Weight  = $weight
                }
            }
            else {
                $others.Add($entry.GetRawText())
            }
        }

        if ($hits.Count -ne 1) {
            throw 'Expected exactly one PowerShell 7 profile.'
        }

        $raw = $hits[0].Raw
        $position = $Text.IndexOf(
            $raw, [StringComparison]::Ordinal
        )

        if ($position -lt 0 -or
            $position -ne $Text.LastIndexOf(
                $raw, [StringComparison]::Ordinal
            )) {
            throw 'PowerShell profile text is ambiguous.'
        }

        [pscustomobject]@{
            Raw           = $raw
            Offset        = $position
            HasFont       = $hits[0].HasFont
            Face          = $hits[0].Face
            Size          = $hits[0].Size
            Weight        = $hits[0].Weight
            DefaultsRaw   = $profiles.GetProperty(
                'defaults'
            ).GetRawText()
            OtherProfiles = ($others -join [char]0)
        }
    }
    finally {
        $doc.Dispose()
    }
}

function New-TypezeroTerminalFontOverrideText {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text)

    $before = Get-TypezeroFontProfileTextSnapshot -Text $Text

    if ($before.HasFont) {
        throw 'Refusing to replace an existing profile font override.'
    }

    if ($Text.Contains('/* TYPEZERO_FONT_V2 */')) {
        throw 'Font ownership marker already exists.'
    }

    $property = (
        '/* TYPEZERO_FONT_V2 */ ' +
        '"font": {"face": "Cascadia Mono", ' +
        '"size": 12, "weight": "normal"},'
    )

    $opening = [regex]::Match(
        $before.Raw,
        '^\{(?<newline>\r\n|\n)(?<indent>[ \t]*)'
    )

    $prefix = if ($opening.Success) {
        $opening.Groups['newline'].Value +
            $opening.Groups['indent'].Value
    } else {
        ''
    }

    if (-not $before.Raw.Substring(1).TrimStart().StartsWith('"')) {
        throw 'Unsupported profile layout for minimal edit.'
    }

    $replacement = (
        '{' + $prefix + $property + $before.Raw.Substring(1)
    )

    $result = (
        $Text.Substring(0, $before.Offset) +
        $replacement +
        $Text.Substring($before.Offset + $before.Raw.Length)
    )

    $after = Get-TypezeroFontProfileTextSnapshot -Text $result

    if (-not $after.HasFont -or
        $after.Face -cne 'Cascadia Mono' -or
        $after.Size -ne 12 -or
        $after.Weight -cne 'normal' -or
        $after.DefaultsRaw -cne $before.DefaultsRaw -or
        $after.OtherProfiles -cne $before.OtherProfiles) {
        throw 'Font override failed validation.'
    }

    return $result
}

function Restore-TypezeroTerminalFontOverrideText {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text)

    $before = Get-TypezeroFontProfileTextSnapshot -Text $Text

    if (-not $before.HasFont -or
        $before.Face -cne 'Cascadia Mono' -or
        $before.Size -ne 12 -or
        $before.Weight -cne 'normal') {
        throw 'Expected Typezero font override is absent or altered.'
    }

    $marker = '/* TYPEZERO_FONT_V2 */'

    if ($Text.IndexOf($marker, [StringComparison]::Ordinal) -ne
        $Text.LastIndexOf($marker, [StringComparison]::Ordinal)) {
        throw 'Font ownership marker is ambiguous.'
    }

    $property = (
        $marker + ' ' +
        '"font": {"face": "Cascadia Mono", ' +
        '"size": 12, "weight": "normal"},'
    )

    $opening = [regex]::Match(
        $before.Raw,
        '^\{(?<newline>\r\n|\n)(?<indent>[ \t]*)'
    )

    $prefix = if ($opening.Success) {
        $opening.Groups['newline'].Value +
            $opening.Groups['indent'].Value
    } else {
        ''
    }

    $content = $before.Raw.Substring(1)
    $ownedPrefix = $prefix + $property

    if (-not $content.StartsWith(
        $ownedPrefix, [StringComparison]::Ordinal
    )) {
        throw 'Font ownership marker or edit layout has changed.'
    }

    $replacement = (
        '{' + $content.Substring($ownedPrefix.Length)
    )

    $result = (
        $Text.Substring(0, $before.Offset) +
        $replacement +
        $Text.Substring($before.Offset + $before.Raw.Length)
    )

    $after = Get-TypezeroFontProfileTextSnapshot -Text $result

    if ($after.HasFont -or
        $after.DefaultsRaw -cne $before.DefaultsRaw -or
        $after.OtherProfiles -cne $before.OtherProfiles -or
        $result.Contains($marker)) {
        throw 'Font restoration failed validation.'
    }

    return $result
}

function Invoke-TypezeroTerminalFontTempFileChange {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Apply', 'Restore')]
        [string]$Mode,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$TestRoot,

        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Fa-f0-9]{64}$')]
        [string]$ExpectedSha256,

        [string]$Family = 'Cascadia Mono',

        [ValidateRange(6, 36)]
        [double]$Size = 12,

        [ValidateSet('normal', 'semi-bold')]
        [string]$Weight = 'normal',

        [switch]$ForcePostWriteFailure
    )

    # Development safety boundary:
    # Only settings.json directly inside our unique TEMP test folder.
    $root = [IO.Path]::GetFullPath($TestRoot)
    $target = [IO.Path]::GetFullPath($Path)

    $tempParent = [IO.Path]::TrimEndingDirectorySeparator(
        [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    )

    if ([IO.Path]::GetDirectoryName($root) -ine $tempParent -or
        [IO.Path]::GetFileName($root) -cnotmatch
            '^typezero-font-persistence-test-[a-f0-9]{32}$') {
        throw 'Persistence test root is not an approved TEMP folder.'
    }

    $allowed = [IO.Path]::Combine($root, 'settings.json')

    if ($target -ine $allowed) {
        throw 'Refusing to write outside the test settings file.'
    }

    if (-not (Test-Path -LiteralPath $root -PathType Container) -or
        -not (Test-Path -LiteralPath $target -PathType Leaf)) {
        throw 'Persistence test file is missing.'
    }

    foreach ($itemPath in @($root, $target)) {
        $attributes = (Get-Item -LiteralPath $itemPath -Force).Attributes

        if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Reparse points are forbidden in the persistence test.'
        }
    }

    $actualHash = (
        Get-FileHash -LiteralPath $target -Algorithm SHA256
    ).Hash

    if ($actualHash -ine $ExpectedSha256) {
        throw 'Settings changed since the expected snapshot.'
    }

    $originalBytes = [IO.File]::ReadAllBytes($target)
    $byteHash = [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData($originalBytes)
    )

    if ($byteHash -ine $ExpectedSha256) {
        throw 'Settings changed during the initial read.'
    }

    $utf8 = [Text.UTF8Encoding]::new($false, $true)

    $bom = (
        $originalBytes.Length -ge 3 -and
        $originalBytes[0] -eq 239 -and
        $originalBytes[1] -eq 187 -and
        $originalBytes[2] -eq 191
    )

    $offset = if ($bom) { 3 } else { 0 }

    $text = $utf8.GetString(
        $originalBytes,
        $offset,
        $originalBytes.Length - $offset
    )

    $newText = switch ($Mode) {
        'Apply' {
            New-TypezeroMappedFontOverrideText `
                -Text $text `
                -Family $Family `
                -Size $Size `
                -Weight $Weight
        }
        'Restore' {
            Restore-TypezeroMappedFontOverrideText -Text $text
        }
    }

    if ($newText -ceq $text) {
        throw 'Font operation produced no change.'
    }

    $newBytes = $utf8.GetBytes($newText)

    if ($bom) {
        $newBytes = [byte[]](@(239, 187, 191) + $newBytes)
    }

    $newHash = [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData($newBytes)
    )

    $token = [guid]::NewGuid().ToString('N')
    $staging = "$target.typezero-$token.tmp"
    $backup = "$target.typezero-$token.bak"
    $failed = "$target.typezero-$token.failed"
    $recovery = "$target.typezero-$token.recovery"

    foreach ($candidate in @(
        $staging, $backup, $failed, $recovery
    )) {
        if (Test-Path -LiteralPath $candidate) {
            throw 'Generated transaction path already exists.'
        }
    }

    $replaced = $false

    try {
        [IO.File]::WriteAllBytes($staging, $newBytes)

        if ((Get-FileHash -LiteralPath $staging -Algorithm SHA256).Hash -ine
            $newHash) {
            throw 'Prepared settings file failed integrity verification.'
        }

        # Recheck immediately before atomic replacement.
        if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ine
            $ExpectedSha256) {
            throw 'Concurrent settings change detected before replacement.'
        }

        # Same-directory replacement. Windows retains the previous file
        # in a uniquely named transaction backup.
        [IO.File]::Replace($staging, $target, $backup)
        $replaced = $true

        if ($ForcePostWriteFailure) {
            throw 'Injected post-write verification failure.'
        }

        if ((Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash -ine
            $ExpectedSha256) {
            throw 'Transaction backup differs from expected original.'
        }

        if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ine
            $newHash) {
            throw 'Written settings failed verification.'
        }

        return [pscustomobject]@{
            Mode       = $Mode
            Path       = $target
            BackupPath = $backup
            BeforeHash = $ExpectedSha256.ToUpperInvariant()
            AfterHash  = $newHash
            Verified   = $true
        }
    }
    catch {
        $failureMessage = $_.Exception.Message

        if ($replaced -and
            (Test-Path -LiteralPath $backup -PathType Leaf) -and
            (Test-Path -LiteralPath $target -PathType Leaf)) {

            $backupValid = (
                (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash -ieq
                $ExpectedSha256
            )

            $targetIsOurs = (
                (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ieq
                $newHash
            )

            # Only roll back if our own candidate is still present.
            # Never overwrite a later third-party edit.
            if ($backupValid -and $targetIsOurs) {
                try {
                    [IO.File]::Copy($backup, $recovery, $false)
                    [IO.File]::Replace($recovery, $target, $failed)

                    if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ieq
                        $ExpectedSha256) {
                        throw "Original recovered after failure: $failureMessage"
                    }

                    throw "Rollback verification failed: $backup"
                }
                catch {
                    throw $_
                }
            }
        }

        throw
    }
    finally {
        if (Test-Path -LiteralPath $staging -PathType Leaf) {
            $stagingHash = (
                Get-FileHash -LiteralPath $staging -Algorithm SHA256
            ).Hash

            if ($stagingHash -ieq $newHash) {
                [IO.File]::Delete($staging)
            }
        }
    }
}

function Restore-TypezeroMappedFontOverrideText {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text)

    $marker = '/* TYPEZERO_FONT_V2 */'
    $first = $Text.IndexOf($marker, [StringComparison]::Ordinal)

    if ($first -lt 0 -or
        $first -ne $Text.LastIndexOf(
            $marker, [StringComparison]::Ordinal
        )) {
        throw 'Unique Typezero ownership marker required.'
    }

    $before = Get-TypezeroFontProfileTextSnapshot -Text $Text

    if (-not $before.HasFont) {
        throw 'Owned profile font override missing.'
    }

    $fontObject = [ordered]@{
        face   = [string]$before.Face
        size   = [double]$before.Size
        weight = [string]$before.Weight
    }

    $encoded = ConvertTo-Json `
        -InputObject $fontObject -Compress -Depth 10

    $property = $marker + ' "font": ' + $encoded + ','

    $opening = [regex]::Match(
        $before.Raw,
        '^\{(?<newline>\r\n|\n)(?<indent>[ \t]*)'
    )

    $prefix = if ($opening.Success) {
        $opening.Groups['newline'].Value +
            $opening.Groups['indent'].Value
    } else {
        ''
    }

    $content = $before.Raw.Substring(1)
    $owned = $prefix + $property

    if (-not $content.StartsWith(
        $owned, [StringComparison]::Ordinal
    )) {
        throw 'Owned font block has changed or is noncanonical.'
    }

    $replacement = '{' + $content.Substring($owned.Length)

    $result = (
        $Text.Substring(0, $before.Offset) +
        $replacement +
        $Text.Substring($before.Offset + $before.Raw.Length)
    )

    $after = Get-TypezeroFontProfileTextSnapshot -Text $result

    if ($after.HasFont -or
        $after.DefaultsRaw -cne $before.DefaultsRaw -or
        $after.OtherProfiles -cne $before.OtherProfiles -or
        $result.Contains($marker)) {
        throw 'Mapped font restoration failed.'
    }

    return $result
}

function New-TypezeroMappedFontOverrideText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Text,

        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9 ._+-]{0,99}$')]
        [string]$Family,

        [Parameter(Mandatory)]
        [ValidateRange(6, 36)]
        [double]$Size,

        [Parameter(Mandatory)]
        [ValidateSet('normal', 'semi-bold')]
        [string]$Weight
    )

    $before = Get-TypezeroFontProfileTextSnapshot -Text $Text
    $marker = '/* TYPEZERO_FONT_V2 */'

    if ($before.HasFont -or $Text.Contains($marker)) {
        throw 'An existing font override or marker is present.'
    }

    if (-not $before.Raw.Substring(1).TrimStart().StartsWith('"')) {
        throw 'Unsupported profile layout.'
    }

    $fontObject = [ordered]@{
        face   = $Family
        size   = $Size
        weight = $Weight
    }

    $encoded = ConvertTo-Json `
        -InputObject $fontObject -Compress -Depth 10

    $property = $marker + ' "font": ' + $encoded + ','

    $opening = [regex]::Match(
        $before.Raw,
        '^\{(?<newline>\r\n|\n)(?<indent>[ \t]*)'
    )

    $prefix = if ($opening.Success) {
        $opening.Groups['newline'].Value +
            $opening.Groups['indent'].Value
    } else {
        ''
    }

    $replacement = (
        '{' + $prefix + $property +
        $before.Raw.Substring(1)
    )

    $result = (
        $Text.Substring(0, $before.Offset) +
        $replacement +
        $Text.Substring($before.Offset + $before.Raw.Length)
    )

    $after = Get-TypezeroFontProfileTextSnapshot -Text $result

    if (-not $after.HasFont -or
        $after.Face -cne $Family -or
        $after.Size -ne $Size -or
        $after.Weight -cne $Weight -or
        $after.DefaultsRaw -cne $before.DefaultsRaw -or
        $after.OtherProfiles -cne $before.OtherProfiles) {
        throw 'Mapped font application failed validation.'
    }

    $restored = Restore-TypezeroMappedFontOverrideText `
        -Text $result

    if ($restored -cne $Text) {
        throw 'Mapped font did not round-trip exactly.'
    }

    return $result
}

# STEP 57F.17 -- DEVELOPMENT, TEMPORARY FIXTURES ONLY.
# No production destination, activation switch, CLI registration or automatic recovery.
# Trust boundary: current Windows user and SYSTEM; same-user/admin tampering is out of scope.
# Flush(true) + prepared immutable intent enables process-crash recovery. This does not
# claim power-loss durability or atomic compare-and-swap against other editors.

function Assert-TypezeroFontRecoveryPlainPath {
    param([Parameter(Mandatory)][string]$Path)
    if ($Path -cnotmatch '\A[A-Za-z]:\\' -or $Path.Substring(2).Contains(':')) {
        throw 'Recovery requires a local drive path without alternate streams.'
    }
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        try {
            $attr = [IO.File]::GetAttributes($cursor)
            if (($attr -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Recovery rejects redirected paths: $cursor"
            }
        }
        catch [IO.FileNotFoundException] { }
        catch [IO.DirectoryNotFoundException] { }
        $cursor = [IO.Path]::GetDirectoryName($cursor)
    }
}

function Initialize-TypezeroFontRecoveryNative {
    if ('TypezeroFontRecoveryNative57F17' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class TypezeroFontRecoveryNative57F17 {
    [StructLayout(LayoutKind.Sequential)] public struct Info {
        public uint Attributes;
        public System.Runtime.InteropServices.ComTypes.FILETIME Creation, Access, Write;
        public uint Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
    }
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool GetFileInformationByHandle(SafeFileHandle h, out Info i);
    public static void AssertSinglePlain(SafeFileHandle h) {
        Info i;
        if (!GetFileInformationByHandle(h, out i))
            throw new Win32Exception(Marshal.GetLastWin32Error());
        if (i.Links != 1 || (i.Attributes & 0x400) != 0)
            throw new IOException("Recovery rejects hard links and reparse points.");
    }
}
'@ -ErrorAction Stop
}

function Get-TypezeroFontRecoveryHash {
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes))
}

function Get-TypezeroFontRecoveryBytes {
    param([Parameter(Mandatory)][string]$Path, [long]$Maximum = 8388608)
    Assert-TypezeroFontRecoveryPlainPath $Path
    $Path = [IO.Path]::GetFullPath($Path)
    Initialize-TypezeroFontRecoveryNative
    $stream = [IO.FileStream]::new($Path, [IO.FileMode]::Open,
        [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        [TypezeroFontRecoveryNative57F17]::AssertSinglePlain($stream.SafeFileHandle)
        if ($stream.Length -gt $Maximum) { throw 'Recovery file exceeds size limit.' }
        $bytes = [byte[]]::new([int]$stream.Length)
        $stream.ReadExactly($bytes, 0, $bytes.Length)
        return ,$bytes
    }
    finally { $stream.Dispose() }
}

function Write-TypezeroFontRecoveryNewFile {
    param([Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)
    Assert-TypezeroFontRecoveryPlainPath $Path
    $full = [IO.Path]::GetFullPath($Path)
    $Path = $full
    $parent = [IO.Path]::GetDirectoryName($full)
    $leaf = [IO.Path]::GetFileName($full)
    if ($leaf -ceq 'settings.json') {
        $null = Assert-TypezeroFontRecoveryRoot $parent
    }
    else {
        if ([IO.Path]::GetFileName($parent) -cnotmatch '\Atxn-[a-f0-9]{32}\z' -or
            ($leaf -cnotin @('original.bin','candidate.bin','manifest.pending','manifest.dpapi') -and
             $leaf -cnotmatch '\Arestore-[a-f0-9]{32}\.tmp\z')) {
            throw 'Recovery write is outside an approved fixture artifact.'
        }
        $null = Assert-TypezeroFontRecoveryRoot ([IO.Path]::GetDirectoryName($parent))
    }
    $stream = [IO.FileStream]::new($Path, [IO.FileMode]::CreateNew,
        [IO.FileAccess]::Write, [IO.FileShare]::None, 4096, [IO.FileOptions]::WriteThrough)
    try {
        $stream.Write($Bytes, 0, $Bytes.Length)
        $stream.Flush($true)
    }
    finally { $stream.Dispose() }
}

function Assert-TypezeroFontRecoveryRoot {
    param([Parameter(Mandatory)][string]$TestRoot)
    if (-not $IsWindows -or $PSVersionTable.PSVersion -lt [version]'7.3') {
        throw 'Recovery fixtures require Windows PowerShell 7.3 or later.'
    }
    $root = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($TestRoot))
    $temp = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))
    if ([IO.Path]::GetDirectoryName($root) -ine $temp -or
        [IO.Path]::GetFileName($root) -cnotmatch '\Atypezero-font-recovery-test-[a-f0-9]{32}\z') {
        throw 'Recovery requires a direct, uniquely named TEMP fixture.'
    }
    Assert-TypezeroFontRecoveryPlainPath $root
    if (-not [IO.Directory]::Exists($root)) { throw 'Recovery fixture is missing.' }
    if ([IO.DriveInfo]::new([IO.Path]::GetPathRoot($root)).DriveFormat -cne 'NTFS') {
        throw 'Recovery fixtures require a local NTFS volume.'
    }
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl = Get-Acl -LiteralPath $root -ErrorAction Stop
    if (-not $acl.AreAccessRulesProtected -or
        $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -cne $sid.Value) {
        throw 'Recovery fixture must have a protected current-user ACL.'
    }
    $hasControl = $false
    foreach ($rule in $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
        if ($rule.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow -or
            $rule.IdentityReference.Value -cnotin @($sid.Value, 'S-1-5-18')) {
            throw 'Recovery fixture grants access to an unexpected principal.'
        }
        if ($rule.IdentityReference.Value -ceq $sid.Value -and
            ($rule.FileSystemRights -band [Security.AccessControl.FileSystemRights]::FullControl) -eq
            [Security.AccessControl.FileSystemRights]::FullControl) { $hasControl = $true }
    }
    if (-not $hasControl) { throw 'Recovery fixture lacks owner control.' }
    $root
}

function New-TypezeroFontRecoveryFixture {
    [CmdletBinding()]
    param([Parameter(Mandatory)][byte[]]$Bytes)
    if (-not $IsWindows -or $PSVersionTable.PSVersion -lt [version]'7.3') {
        throw 'Recovery fixtures require Windows PowerShell 7.3 or later.'
    }
    if ($Bytes.Length -eq 0 -or $Bytes.Length -gt 8388608) { throw 'Invalid fixture length.' }
    $root = Join-Path ([IO.Path]::GetTempPath()) ('typezero-font-recovery-test-' + [guid]::NewGuid().ToString('N'))
    Assert-TypezeroFontRecoveryPlainPath $root
    if ([IO.Directory]::Exists($root) -or [IO.File]::Exists($root)) { throw 'Fixture already exists.' }
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $acl.SetOwner($sid)
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($identity in @($sid, [Security.Principal.SecurityIdentifier]::new('S-1-5-18'))) {
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($identity,
            [Security.AccessControl.FileSystemRights]::FullControl,
            [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit',
            [Security.AccessControl.PropagationFlags]::None,
            [Security.AccessControl.AccessControlType]::Allow))
    }
    [IO.FileSystemAclExtensions]::Create([IO.DirectoryInfo]::new($root), $acl)
    $root = Assert-TypezeroFontRecoveryRoot $root
    Write-TypezeroFontRecoveryNewFile -Path (Join-Path $root 'settings.json') -Bytes $Bytes
    $root
}

function Open-TypezeroFontRecoveryLock {
    param([Parameter(Mandatory)][string]$TestRoot)
    $root = Assert-TypezeroFontRecoveryRoot $TestRoot
    $path = Join-Path $root '.transaction.lock'
    Assert-TypezeroFontRecoveryPlainPath $path
    Initialize-TypezeroFontRecoveryNative
    $stream = [IO.FileStream]::new($path, [IO.FileMode]::OpenOrCreate,
        [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try { [TypezeroFontRecoveryNative57F17]::AssertSinglePlain($stream.SafeFileHandle) }
    catch { $stream.Dispose(); throw }
    $stream
}

function Protect-TypezeroFontRecoveryManifest {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Data)
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    $plain = $utf8.GetBytes((ConvertTo-Json -InputObject $Data -Depth 4 -Compress))
    $entropy = $utf8.GetBytes('Typezero.FontRecovery.57F17')
    return ,([Security.Cryptography.ProtectedData]::Protect($plain, $entropy,
        [Security.Cryptography.DataProtectionScope]::CurrentUser))
}

function Read-TypezeroFontRecoveryManifest {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TestRoot,
        [Parameter(Mandatory)][ValidatePattern('\A[a-f0-9]{32}\z')][string]$TransactionId)
    $root = Assert-TypezeroFontRecoveryRoot $TestRoot
    $folder = Join-Path $root ('txn-' + $TransactionId)
    $sealed = Get-TypezeroFontRecoveryBytes -Path (Join-Path $folder 'manifest.dpapi') -Maximum 65536
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    $plain = [Security.Cryptography.ProtectedData]::Unprotect($sealed,
        $utf8.GetBytes('Typezero.FontRecovery.57F17'), [Security.Cryptography.DataProtectionScope]::CurrentUser)
    if ($plain.Length -gt 16384) { throw 'Recovery metadata exceeds size limit.' }
    $doc = [Text.Json.JsonDocument]::Parse($utf8.GetString($plain))
    try {
        $element = $doc.RootElement
        if ($element.ValueKind -ne [Text.Json.JsonValueKind]::Object) { throw 'Recovery metadata must be an object.' }
        $fields = @('Version','Kind','Root','TransactionId','Mode','BeforeSha256','AfterSha256',
            'BeforeLength','AfterLength','BackupName','TargetName')
        $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($p in $element.EnumerateObject()) {
            if (-not $names.Add($p.Name) -or $p.Name -cnotin $fields) { throw 'Recovery metadata fields are invalid or duplicated.' }
        }
        if ($names.Count -ne $fields.Count) { throw 'Recovery metadata fields are missing.' }
        $data = [ordered]@{}
        foreach ($name in $fields) {
            $p = $element.GetProperty($name)
            if ($name -in @('Version','BeforeLength','AfterLength')) {
                if ($p.ValueKind -ne [Text.Json.JsonValueKind]::Number -or
                    $p.GetRawText() -cnotmatch '\A[0-9]+\z') { throw 'Recovery metadata integer required.' }
                $data[$name] = $p.GetInt64()
            }
            else {
                if ($p.ValueKind -ne [Text.Json.JsonValueKind]::String) { throw 'Recovery metadata string required.' }
                $data[$name] = $p.GetString()
            }
        }
        if ($data.Version -ne 1 -or $data.Kind -cne 'TypezeroFontRecoveryFixture' -or
            $data.Root -ine $root -or $data.TransactionId -cne $TransactionId -or
            $data.Mode -cnotin @('Apply','Restore') -or $data.BackupName -cne 'original.bin' -or
            $data.TargetName -cne 'settings.json' -or
            $data.BeforeSha256 -cnotmatch '\A[A-F0-9]{64}\z' -or
            $data.AfterSha256 -cnotmatch '\A[A-F0-9]{64}\z' -or
            $data.BeforeSha256 -ceq $data.AfterSha256 -or
            $data.BeforeLength -lt 1 -or $data.BeforeLength -gt 8388608 -or
            $data.AfterLength -lt 1 -or $data.AfterLength -gt 8388608) {
            throw 'Recovery metadata does not match this fixture transaction.'
        }
        [pscustomobject]$data
    }
    finally { $doc.Dispose() }
}

function Assert-TypezeroFontRecoveryContent {
    param([Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Sha256, [Parameter(Mandatory)][long]$Length)
    $bytes = Get-TypezeroFontRecoveryBytes $Path
    if ($bytes.Length -ne $Length -or (Get-TypezeroFontRecoveryHash $bytes) -cne $Sha256) {
        throw "Recovery content integrity mismatch: $Path"
    }
    return ,$bytes
}

function Invoke-TypezeroFontDurableFixtureChange {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TestRoot,
        [Parameter(Mandatory)][ValidatePattern('\A[A-Fa-f0-9]{64}\z')][string]$ExpectedSha256,
        [Parameter(Mandatory)][ValidateSet('Apply','Restore')][string]$Mode,
        [ValidatePattern('\A[A-Za-z0-9][A-Za-z0-9 ._+-]{0,99}\z')][string]$Family = 'Cascadia Mono',
        [ValidateRange(6,36)][double]$Size = 12,
        [ValidateSet('normal','semi-bold')][string]$Weight = 'normal')
    $root = Assert-TypezeroFontRecoveryRoot $TestRoot
    $lock = Open-TypezeroFontRecoveryLock $root
    try {
        $Mode = if ($Mode -ieq 'Apply') { 'Apply' } else { 'Restore' }
        $Weight = $Weight.ToLowerInvariant()
        $target = Join-Path $root 'settings.json'
        $original = Get-TypezeroFontRecoveryBytes $target
        $before = Get-TypezeroFontRecoveryHash $original
        if ($before -ine $ExpectedSha256) { throw 'Settings changed since the expected snapshot.' }
        $utf8 = [Text.UTF8Encoding]::new($false, $true)
        $bom = $original.Length -ge 3 -and $original[0] -eq 239 -and $original[1] -eq 187 -and $original[2] -eq 191
        $offset = if ($bom) { 3 } else { 0 }
        $text = $utf8.GetString($original, $offset, $original.Length - $offset)
        $newText = if ($Mode -ceq 'Apply') {
            New-TypezeroMappedFontOverrideText -Text $text -Family $Family -Size $Size -Weight $Weight
        } else { Restore-TypezeroMappedFontOverrideText -Text $text }
        $candidate = $utf8.GetBytes($newText)
        if ($bom) { $candidate = [byte[]](@(239,187,191) + $candidate) }
        $after = Get-TypezeroFontRecoveryHash $candidate
        if ($before -ceq $after -or $candidate.Length -gt 8388608) { throw 'Invalid recovery candidate.' }
        $id = [guid]::NewGuid().ToString('N')
        $folder = Join-Path $root ('txn-' + $id)
        if (Test-Path -LiteralPath $folder) { throw 'Recovery transaction already exists.' }
        $null = [IO.Directory]::CreateDirectory($folder)
        $backup = Join-Path $folder 'original.bin'
        $stage = Join-Path $folder 'candidate.bin'
        Write-TypezeroFontRecoveryNewFile $backup $original
        $null = Assert-TypezeroFontRecoveryContent $backup $before $original.Length
        Write-Debug 'TZ57F17:BackupFlushed'
        Write-TypezeroFontRecoveryNewFile $stage $candidate
        $null = Assert-TypezeroFontRecoveryContent $stage $after $candidate.Length
        Write-Debug 'TZ57F17:CandidateFlushed'
        $data = [ordered]@{ Version=1; Kind='TypezeroFontRecoveryFixture'; Root=$root;
            TransactionId=$id; Mode=$Mode; BeforeSha256=$before; AfterSha256=$after;
            BeforeLength=$original.Length; AfterLength=$candidate.Length;
            BackupName='original.bin'; TargetName='settings.json' }
        $draft = Join-Path $folder 'manifest.pending'
        Write-TypezeroFontRecoveryNewFile $draft (Protect-TypezeroFontRecoveryManifest $data)
        [IO.File]::Move($draft, (Join-Path $folder 'manifest.dpapi'))
        $null = Read-TypezeroFontRecoveryManifest $root $id
        Write-Debug 'TZ57F17:Prepared'
        Write-Debug 'TZ57F17:BeforeApplyReplace'
        $null = Assert-TypezeroFontRecoveryRoot $root
        $null = Assert-TypezeroFontRecoveryContent $backup $before $original.Length
        $null = Assert-TypezeroFontRecoveryContent $stage $after $candidate.Length
        $null = Assert-TypezeroFontRecoveryContent $target $before $original.Length
        # This is NOT CAS. Preserve and verify the actual displaced bytes. Never
        # overwrite a conflict by automatic rollback; retain every artifact.
        $displaced = Join-Path $folder 'displaced-apply.bin'
        if (Test-Path -LiteralPath $displaced) { throw 'Recovery evidence already exists.' }
        [IO.File]::Replace($stage, $target, $displaced, $false)
        Write-Debug 'TZ57F17:Applied'
        $null = Assert-TypezeroFontRecoveryContent $displaced $before $original.Length
        $null = Assert-TypezeroFontRecoveryContent $target $after $candidate.Length
        Write-Debug 'TZ57F17:ApplyVerified'
        [pscustomobject]@{ TransactionId=$id; TransactionDirectory=$folder;
            BackupPath=$backup; MetadataPath=(Join-Path $folder 'manifest.dpapi');
            BeforeHash=$before; AfterHash=$after; Verified=$true; FixtureOnly=$true }
    }
    finally { $lock.Dispose() }
}

function Repair-TypezeroFontDurableFixtureChange {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TestRoot,
        [Parameter(Mandatory)][ValidatePattern('\A[a-f0-9]{32}\z')][string]$TransactionId)
    $root = Assert-TypezeroFontRecoveryRoot $TestRoot
    $lock = Open-TypezeroFontRecoveryLock $root
    try {
        $data = Read-TypezeroFontRecoveryManifest $root $TransactionId
        $folder = Join-Path $root ('txn-' + $TransactionId)
        $backup = Join-Path $folder 'original.bin'
        $target = Join-Path $root 'settings.json'
        $original = Assert-TypezeroFontRecoveryContent $backup $data.BeforeSha256 $data.BeforeLength
        # If replacement displaced unexpected bytes, recovery cannot safely infer
        # ownership even when the current target matches our candidate.
        $displacedApply = Join-Path $folder 'displaced-apply.bin'
        if ([IO.File]::Exists($displacedApply)) {
            $null = Assert-TypezeroFontRecoveryContent $displacedApply $data.BeforeSha256 $data.BeforeLength
        }
        foreach ($evidence in [IO.Directory]::EnumerateFileSystemEntries($folder, 'displaced-restore-*')) {
            if ([IO.Path]::GetFileName($evidence) -cnotmatch '\Adisplaced-restore-[a-f0-9]{32}\.bin\z') {
                throw 'Unexpected recovery displacement evidence.'
            }
            $null = Assert-TypezeroFontRecoveryContent $evidence $data.AfterSha256 $data.AfterLength
        }
        $current = Get-TypezeroFontRecoveryBytes $target
        $hash = Get-TypezeroFontRecoveryHash $current
        if ($hash -ceq $data.BeforeSha256 -and $current.Length -eq $data.BeforeLength) {
            return [pscustomobject]@{ State='OriginalPresent'; Verified=$true; FixtureOnly=$true }
        }
        if ($hash -cne $data.AfterSha256 -or $current.Length -ne $data.AfterLength) {
            throw 'Recovery conflict: settings contain a concurrent or unknown edit.'
        }
        # A candidate-state target requires evidence that File.Replace displaced
        # the expected original. Pre-replace journals can return above.
        if (-not [IO.File]::Exists($displacedApply)) {
            throw 'Recovery conflict: applied displacement evidence is missing.'
        }
        $null = Assert-TypezeroFontRecoveryContent $displacedApply $data.BeforeSha256 $data.BeforeLength
        $token = [guid]::NewGuid().ToString('N')
        $stage = Join-Path $folder ('restore-' + $token + '.tmp')
        Write-TypezeroFontRecoveryNewFile $stage $original
        $null = Assert-TypezeroFontRecoveryContent $stage $data.BeforeSha256 $data.BeforeLength
        Write-Debug 'TZ57F17:RestoreStaged'
        Write-Debug 'TZ57F17:BeforeRestoreReplace'
        $null = Assert-TypezeroFontRecoveryRoot $root
        $again = Read-TypezeroFontRecoveryManifest $root $TransactionId
        if (($again | ConvertTo-Json -Compress) -cne ($data | ConvertTo-Json -Compress)) {
            throw 'Recovery metadata changed during restoration.'
        }
        $null = Assert-TypezeroFontRecoveryContent $backup $data.BeforeSha256 $data.BeforeLength
        $null = Assert-TypezeroFontRecoveryContent $stage $data.BeforeSha256 $data.BeforeLength
        $null = Assert-TypezeroFontRecoveryContent $target $data.AfterSha256 $data.AfterLength
        # Recheck displacement evidence immediately before the restore replace.
        $null = Assert-TypezeroFontRecoveryContent $displacedApply $data.BeforeSha256 $data.BeforeLength
        $displaced = Join-Path $folder ('displaced-restore-' + $token + '.bin')
        if (Test-Path -LiteralPath $displaced) { throw 'Recovery evidence already exists.' }
        [IO.File]::Replace($stage, $target, $displaced, $false)
        Write-Debug 'TZ57F17:Restored'
        $null = Assert-TypezeroFontRecoveryContent $displaced $data.AfterSha256 $data.AfterLength
        $null = Assert-TypezeroFontRecoveryContent $target $data.BeforeSha256 $data.BeforeLength
        Write-Debug 'TZ57F17:RestoreVerified'
        [pscustomobject]@{ State='RecoveredOriginal'; Verified=$true; FixtureOnly=$true }
    }
    finally { $lock.Dispose() }
}
