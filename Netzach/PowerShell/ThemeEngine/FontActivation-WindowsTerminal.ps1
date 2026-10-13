# Typezero ThemeEngine - Windows Terminal Font Activation
# Explicit manual activation and selective restoration.
# Does not enable automatic font switching.

function Get-TypezeroFontDocument {
    $status = Get-TypezeroTerminalFontStatus
    $path = $status.SettingsPath

    $settings = Get-Content -LiteralPath $path -Raw -ErrorAction Stop |
        ConvertFrom-Json -ErrorAction Stop

    $guid = '{574e775e-4f2a-5b96-ac1e-a2962a402336}'

    $matches = @($settings.profiles.list |
        Where-Object { $_.guid -eq $guid })

    if ($matches.Count -ne 1) {
        throw 'Expected exactly one PowerShell 7 profile.'
    }

    [pscustomobject]@{
        Path     = $path
        Hash     = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        Settings = $settings
        Profile  = $matches[0]
        Guid     = $guid
    }
}

function New-TypezeroFontSettingsTemp {
    # Surgical UTF-8 font insertion: preserve all unrelated source text.
    param(
        [Parameter(Mandatory)]$Settings,
        [Parameter(Mandatory)][string]$SettingsPath
    )

    $guid = '{574e775e-4f2a-5b96-ac1e-a2962a402336}'
    $intended = @($Settings.profiles.list |
        Where-Object { $_.guid -eq $guid })

    if ($intended.Count -ne 1) {
        throw 'Expected one intended PowerShell profile.'
    }

    $face = [string]$intended[0].font.face

    if ([string]::IsNullOrWhiteSpace($face)) {
        throw 'Missing intended font face.'
    }

    $bytes = [IO.File]::ReadAllBytes($SettingsPath)

    # Initially support strict UTF-8 without BOM only.
    # Refuse other encodings rather than silently altering them.
    if ($bytes.Length -ge 3 -and
        $bytes[0] -eq 239 -and
        $bytes[1] -eq 187 -and
        $bytes[2] -eq 191) {
        throw 'UTF-8 BOM detected. Surgical writer requires review.'
    }

    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    $source = $utf8.GetString($bytes)

    $options = [Text.Json.JsonDocumentOptions]::new()
    $options.CommentHandling = [Text.Json.JsonCommentHandling]::Skip
    $options.AllowTrailingCommas = $true

    $document = [Text.Json.JsonDocument]::Parse($source, $options)
    $candidateDocument = $null

    try {
        $list = $document.RootElement.
            GetProperty('profiles').GetProperty('list')

        $matches = @(
            foreach ($item in $list.EnumerateArray()) {
                if ($item.GetProperty('guid').GetString() -ieq $guid) {
                    $item
                }
            }
        )

        if ($matches.Count -ne 1) {
            throw 'Could not uniquely identify PowerShell 7.'
        }

        $fontProperty = [Text.Json.JsonElement]::new()

        if ($matches[0].TryGetProperty('font', [ref]$fontProperty)) {
            throw 'Existing font override detected. Refusing initial surgical insertion.'
        }

        $rawProfile = $matches[0].GetRawText()
        $first = $source.IndexOf($rawProfile, [StringComparison]::Ordinal)
        $last = $source.LastIndexOf($rawProfile, [StringComparison]::Ordinal)

        if ($first -lt 0 -or $first -ne $last -or
            -not $rawProfile.StartsWith('{')) {
            throw 'PowerShell profile source is not uniquely identifiable.'
        }

        $insertion = '"font":{"face":' +
            (ConvertTo-Json -InputObject $face -Compress) + '},'

        $insertAt = $first + 1
        $candidate = $source.Insert($insertAt, $insertion)

        $candidateDocument = [Text.Json.JsonDocument]::Parse(
            $candidate, $options
        )

        $candidateProfiles = $candidateDocument.RootElement.
            GetProperty('profiles').GetProperty('list')

        $updated = @(
            foreach ($item in $candidateProfiles.EnumerateArray()) {
                if ($item.GetProperty('guid').GetString() -ieq $guid) {
                    $item
                }
            }
        )

        if ($updated.Count -ne 1 -or
            $updated[0].GetProperty('font').GetProperty('face').GetString() -cne
            $face) {
            throw 'Surgical candidate validation failed.'
        }

        if ($candidate.Remove($insertAt, $insertion.Length) -cne $source) {
            throw 'Surgical candidate modified unrelated text.'
        }

        $temp = Join-Path (Split-Path -Parent $SettingsPath) (
            '.typezero-font-' + [guid]::NewGuid().ToString('N') + '.tmp'
        )

        [IO.File]::WriteAllBytes($temp, $utf8.GetBytes($candidate))

        [pscustomobject]@{
            Path = $temp
            Hash = (Get-FileHash -LiteralPath $temp -Algorithm SHA256).Hash
        }
    }
    finally {
        if ($null -ne $candidateDocument) {
            $candidateDocument.Dispose()
        }
        $document.Dispose()
    }
}

function Invoke-TypezeroTerminalFontSwitch {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[a-z0-9][a-z0-9-]*$')]
        [string]$ThemeId,

        [switch]$Execute
    )

    $plan = Get-TypezeroTerminalFontSwitchPlan -ThemeId $ThemeId

    # The surgical writer currently supports v1 family-only mappings.
    # Never report a successful v2 activation without applying size/weight.
    if ($Execute -and $plan.MappingVersion -ne 1) {
        throw 'v2 activation is not implemented. No Terminal change attempted.'
    }

    if (-not $Execute) {
        return $plan
    }

    if (-not $plan.IntegrationEnabled) {
        throw 'Windows Terminal font integration is disabled. No activation attempted.'
    }

    if (-not $plan.WouldChange) {
        return [pscustomobject]@{
            Status = 'NO CHANGE'
            Font   = $plan.CurrentFont
        }
    }

    if (-not $PSCmdlet.ShouldProcess(
        'Windows Terminal PowerShell 7 profile',
        "Change font to '$($plan.RequestedFont)' with backup"
    )) {
        return
    }

    $doc = Get-TypezeroFontDocument
    $hadFont = $null -ne $doc.Profile.PSObject.Properties['font']

    $originalFont = if ($hadFont) {
        $doc.Profile.font |
            ConvertTo-Json -Depth 100 |
            ConvertFrom-Json -Depth 100
    } else {
        $null
    }

    $backupRoot = Join-Path $env:LOCALAPPDATA `
        'Typezero\ThemeEngine\backups\font-switch'

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fffffff'
    $backupDir = Join-Path $backupRoot $stamp

    New-Item -ItemType Directory -Path $backupDir -ErrorAction Stop |
        Out-Null

    $backupFile = Join-Path $backupDir 'settings-original.json'

    Copy-Item -LiteralPath $doc.Path `
        -Destination $backupFile -ErrorAction Stop

    if ((Get-FileHash -LiteralPath $backupFile -Algorithm SHA256).Hash -ne
        $doc.Hash) {
        throw 'Original settings backup failed verification.'
    }

    # Change only the PowerShell 7 profile font object.
    if (-not $hadFont) {
        $doc.Profile | Add-Member -NotePropertyName font `
            -NotePropertyValue ([pscustomobject]@{
                face = $plan.RequestedFont
            })
    }
    elseif ($null -eq $doc.Profile.font) {
        $doc.Profile.font = [pscustomobject]@{
            face = $plan.RequestedFont
        }
    }
    elseif ($doc.Profile.font.PSObject.Properties['face']) {
        $doc.Profile.font.face = $plan.RequestedFont
    }
    else {
        $doc.Profile.font | Add-Member -NotePropertyName face `
            -NotePropertyValue $plan.RequestedFont
    }

    $temp = New-TypezeroFontSettingsTemp `
        -Settings $doc.Settings -SettingsPath $doc.Path

    try {
        $receipt = [ordered]@{
            Version         = 1
            ProfileGuid     = $doc.Guid
            Theme           = $ThemeId
            RequestedFont   = $plan.RequestedFont
            PreviousFont    = $plan.CurrentFont
            HadFontProperty = $hadFont
            OriginalFont    = $originalFont
            BeforeSha256    = $doc.Hash
            AfterSha256     = $temp.Hash
        }

        $receiptFile = Join-Path $backupDir 'receipt.json'

        [IO.File]::WriteAllText(
            $receiptFile,
            ($receipt | ConvertTo-Json -Depth 100),
            [Text.UTF8Encoding]::new($false)
        )

        if ((Get-FileHash -LiteralPath $doc.Path -Algorithm SHA256).Hash -ne
            $doc.Hash) {
            throw 'Terminal settings changed concurrently. No write attempted.'
        }

        Move-Item -LiteralPath $temp.Path `
            -Destination $doc.Path -Force -ErrorAction Stop

        $verified = Get-TypezeroTerminalFontStatus

        if ($verified.Face -cne $plan.RequestedFont) {
            throw "Font activation not verified. Inspect backup: $backupDir"
        }

        [pscustomobject]@{
            Status          = 'VERIFIED'
            Font            = $verified.Face
            BackupDirectory = $backupDir
            Note            = 'Original PowerShell profile font state saved.'
        }
    }
    finally {
        if (Test-Path -LiteralPath $temp.Path) {
            Remove-Item -LiteralPath $temp.Path -Force
        }
    }
}

function Restore-TypezeroTerminalFontSwitch {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][string]$BackupDirectory,
        [switch]$Execute
    )

    $root = [IO.Path]::GetFullPath(
        (Join-Path $env:LOCALAPPDATA 'Typezero\ThemeEngine\backups\font-switch')
    )

    $folder = [IO.Path]::GetFullPath($BackupDirectory)

    if (-not $folder.StartsWith(
        $root + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw 'Backup directory is outside the font-switch backup root.'
    }

    # Reject junctions and symbolic links in any backup path component.
    # Deliberately fail closed, including reparse points above backup root.
    $backupComponent = [IO.DirectoryInfo]::new($folder)

    while ($null -ne $backupComponent) {
        if (-not $backupComponent.Exists) {
            throw 'Backup directory component does not exist.'
        }

        if (($backupComponent.Attributes -band
            [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Backup path contains a reparse point. Restore blocked.'
        }

        $backupComponent = $backupComponent.Parent
    }

    $receiptPath = Join-Path $folder 'receipt.json'
    $originalPath = Join-Path $folder 'settings-original.json'

    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $originalPath -PathType Leaf)) {
        throw 'Complete font-switch backup not found.'
    }

    # Backup inputs must be ordinary files, not file-system links.
    foreach ($backupInput in @($receiptPath, $originalPath)) {
        $backupItem = Get-Item -LiteralPath $backupInput `
            -Force -ErrorAction Stop

        if (($backupItem.Attributes -band
            [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Backup input is a reparse point. Restore blocked.'
        }
    }

    if (-not ('TypezeroFontRestoreSnapshot55H26' -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.ComponentModel;
using System.Security.Cryptography;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public static class TypezeroFontRestoreSnapshot55H26
{
    [StructLayout(LayoutKind.Sequential)]
    private struct NativeTime
    {
        public uint Low;
        public uint High;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeInfo
    {
        public uint Attributes;
        public NativeTime Created;
        public NativeTime Accessed;
        public NativeTime Modified;
        public uint VolumeSerial;
        public uint SizeHigh;
        public uint SizeLow;
        public uint LinkCount;
        public uint IndexHigh;
        public uint IndexLow;
    }

    [DllImport("kernel32.dll", EntryPoint = "CreateFileW",
        CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFile(
        string path, uint access, uint shareMode,
        IntPtr security, uint disposition,
        uint flags, IntPtr template
    );

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetFileInformationByHandle(
        SafeFileHandle handle, out NativeInfo info
    );

    public sealed class Snapshot
    {
        public byte[] Bytes { get; set; }
        public string Sha256 { get; set; }
    }

    public static Snapshot Capture(string path, long maximumBytes)
    {
        const uint GENERIC_READ = 0x80000000;
        const uint FILE_SHARE_READ = 0x00000001;
        const uint OPEN_EXISTING = 3;
        const uint OPEN_REPARSE_POINT = 0x00200000;
        const uint REPARSE_POINT = 0x00000400;
        const uint DIRECTORY = 0x00000010;

        using (var handle = CreateFile(
            path, GENERIC_READ, FILE_SHARE_READ,
            IntPtr.Zero, OPEN_EXISTING,
            OPEN_REPARSE_POINT, IntPtr.Zero))
        {
            if (handle.IsInvalid)
                throw new Win32Exception(Marshal.GetLastWin32Error());

            NativeInfo info;

            if (!GetFileInformationByHandle(handle, out info))
                throw new Win32Exception(Marshal.GetLastWin32Error());

            if ((info.Attributes & REPARSE_POINT) != 0)
                throw new InvalidOperationException(
                    "Backup input is a reparse point. Restore blocked.");

            if ((info.Attributes & DIRECTORY) != 0)
                throw new InvalidOperationException(
                    "Backup input must be a regular file.");

            if (info.LinkCount != 1)
                throw new InvalidOperationException(
                    "Backup has multiple hardlinks. Restore blocked.");

            using (var stream = new FileStream(
                handle, FileAccess.Read))
            {
                if (stream.Length > maximumBytes)
                    throw new InvalidOperationException(
                        "Backup input exceeds permitted size.");

                using (var memory = new MemoryStream())
                {
                    stream.CopyTo(memory);
                    byte[] bytes = memory.ToArray();

                    NativeInfo verified;

                    if (!GetFileInformationByHandle(
                        stream.SafeFileHandle, out verified))
                        throw new Win32Exception(
                            Marshal.GetLastWin32Error());

                    if (verified.LinkCount != 1 ||
                        verified.VolumeSerial != info.VolumeSerial ||
                        verified.IndexHigh != info.IndexHigh ||
                        verified.IndexLow != info.IndexLow)
                        throw new InvalidOperationException(
                            "Backup file identity changed. Restore blocked.");

                    return new Snapshot
                    {
                        Bytes = bytes,
                        Sha256 = Convert.ToHexString(
                            SHA256.HashData(bytes))
                    };
                }
            }
        }
    }
}
"@ -ErrorAction Stop
    }

    # Both inputs are captured through native no-follow handles.
    # Do not reopen either pathname for RESTORE content.
    $receiptSnapshot = [TypezeroFontRestoreSnapshot55H26]::Capture(
        $receiptPath, 1048576
    )

    $backupSnapshot = [TypezeroFontRestoreSnapshot55H26]::Capture(
        $originalPath, 33554432
    )

    # Decode only the receipt snapshot; BOM detection maintains
    # compatibility with older UTF-8/UTF-16 receipt encodings.
    $receiptStream = [IO.MemoryStream]::new(
        $receiptSnapshot.Bytes, $false
    )

    $receiptReader = [IO.StreamReader]::new(
        $receiptStream,
        [Text.UTF8Encoding]::new($false, $true),
        $true
    )

    try {
        $receiptText = $receiptReader.ReadToEnd()
    }
    finally {
        $receiptReader.Dispose()
    }

    $receipt = $receiptText | ConvertFrom-Json -ErrorAction Stop

    if ($receipt.Version -ne 1 -or
        $receipt.ProfileGuid -ne '{574e775e-4f2a-5b96-ac1e-a2962a402336}') {
        throw 'Invalid font-switch receipt.'
    }

    if ($backupSnapshot.Sha256 -ne $receipt.BeforeSha256) {
        throw 'Original backup checksum mismatch.'
    }

    $doc = Get-TypezeroFontDocument

    if ($doc.Hash -ne $receipt.AfterSha256) {
        throw 'Terminal settings changed since activation. Review before restoring.'
    }

    if (-not $Execute) {
        return [pscustomobject]@{
            Action          = 'PREVIEW ONLY - no changes'
            ReceiptAuthenticated = $false
            CurrentFont     = (Get-TypezeroTerminalFontStatus).Face
            PreviousFont    = $receipt.PreviousFont
            BackupDirectory = $folder
        }
    }

    Write-Warning 'Receipt authenticity is not independently verified. RESTORE replaces the entire Windows Terminal settings document.'

    if (-not $PSCmdlet.ShouldProcess(
        'Windows Terminal settings.json (entire document)',
        'Restore byte-exact pre-activation configuration'
    )) {
        return
    }

    # Exact-byte restore is permitted only when the current hash
    # matches the post-activation receipt (checked above).
    $tempPath = Join-Path (Split-Path -Parent $doc.Path) (
        '.typezero-font-restore-' + [guid]::NewGuid().ToString('N') + '.tmp'
    )

    [IO.File]::WriteAllBytes($tempPath, $backupSnapshot.Bytes)

    $temp = [pscustomobject]@{
        Path = $tempPath
        Hash = (Get-FileHash -LiteralPath $tempPath -Algorithm SHA256).Hash
    }

    if ($temp.Hash -ne $receipt.BeforeSha256) {
        Remove-Item -LiteralPath $tempPath -Force
        throw 'Staged restoration does not match original checksum.'
    }

    try {
        if ((Get-FileHash -LiteralPath $doc.Path -Algorithm SHA256).Hash -ne
            $receipt.AfterSha256) {
            throw 'Terminal settings changed before restore.'
        }

        Move-Item -LiteralPath $temp.Path `
            -Destination $doc.Path -Force -ErrorAction Stop

        $verified = Get-TypezeroTerminalFontStatus

        if ($verified.Face -cne $receipt.PreviousFont) {
            throw "Font restoration not verified. Backup: $folder"
        }

        [pscustomobject]@{
            Status = 'RESTORED'
            Font   = $verified.Face
        }
    }
    finally {
        if (Test-Path -LiteralPath $temp.Path) {
            Remove-Item -LiteralPath $temp.Path -Force
        }
    }
}
