# Typezero FontEngine v2
# Explicit activation only; automatic integration is not enabled.
# Requires FontProvider, FontMapping, and FontPatch to be loaded.

function Invoke-TypezeroTerminalFontSwitchV2 {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][string]$ThemeId,
        [Parameter(Mandatory)][string]$ConfigPath,
        [switch]$Execute
    )

    $plan = Get-TypezeroTerminalFontSwitchPlan `
        -ThemeId $ThemeId -ConfigPath $ConfigPath

    if ($plan.MappingVersion -ne 2) {
        throw 'Only v2 mappings are supported by this activation module.'
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
            Theme  = $ThemeId
        }
    }

    if (-not $PSCmdlet.ShouldProcess(
        'Windows Terminal PowerShell 7 profile',
        "Apply v2 typography for $ThemeId"
    )) {
        return
    }

    $status = Get-TypezeroTerminalFontStatus
    $path = $status.SettingsPath
    $beforeHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash

    $bytes = [IO.File]::ReadAllBytes($path)

    if ($bytes.Length -ge 3 -and
        $bytes[0] -eq 239 -and
        $bytes[1] -eq 187 -and
        $bytes[2] -eq 191) {
        throw 'UTF-8 BOM detected. Activation blocked.'
    }

    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    $original = $utf8.GetString($bytes)

    $candidate = New-TypezeroTerminalFontJsonCandidate `
        -JsonText $original `
        -Face $plan.RequestedFont `
        -Size $plan.RequestedSize `
        -Weight $plan.RequestedWeight

    $backupRoot = Join-Path $env:LOCALAPPDATA `
        'Typezero\ThemeEngine\backups\font-switch-v2'

    $folderName = (Get-Date -Format 'yyyyMMdd-HHmmss-fffffff') +
        '-' + [guid]::NewGuid().ToString('N')

    $backupDir = Join-Path $backupRoot $folderName

    New-Item -ItemType Directory -Path $backupDir -Force `
        -ErrorAction Stop | Out-Null

    $originalBackup = Join-Path $backupDir 'settings-original.json'
    Copy-Item -LiteralPath $path -Destination $originalBackup `
        -ErrorAction Stop

    if ((Get-FileHash -LiteralPath $originalBackup -Algorithm SHA256).Hash -ne
        $beforeHash) {
        throw 'Original backup checksum mismatch. Activation blocked.'
    }

    $temp = Join-Path (Split-Path -Parent $path) (
        '.typezero-v2-' + [guid]::NewGuid().ToString('N') + '.tmp'
    )

    try {
        [IO.File]::WriteAllText($temp, $candidate, $utf8)

        $afterHash = (
            Get-FileHash -LiteralPath $temp -Algorithm SHA256
        ).Hash

        $receipt = [ordered]@{
            Version        = 2
            Theme          = $ThemeId
            SettingsPath   = $path
            PreviousFont   = $plan.CurrentFont
            RequestedFont  = $plan.RequestedFont
            RequestedSize  = $plan.RequestedSize
            RequestedWeight = $plan.RequestedWeight
            BeforeSha256   = $beforeHash
            AfterSha256    = $afterHash
        }

        $receiptPath = Join-Path $backupDir 'receipt.json'

        [IO.File]::WriteAllText(
            $receiptPath,
            ($receipt | ConvertTo-Json -Depth 20),
            $utf8
        )

        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne
            $beforeHash) {
            throw 'Settings changed concurrently. Activation blocked.'
        }

        Move-Item -LiteralPath $temp -Destination $path `
            -Force -ErrorAction Stop

        $actualHash = (
            Get-FileHash -LiteralPath $path -Algorithm SHA256
        ).Hash

        $verified = Get-TypezeroTerminalFontStatus

        if ($actualHash -ne $afterHash -or
            $verified.Face -cne $plan.RequestedFont -or
            [double]$verified.Size -ne [double]$plan.RequestedSize -or
            [string]$verified.Weight -cne $plan.RequestedWeight) {
            throw "Activation verification failed. Backup: $backupDir"
        }

        [pscustomobject]@{
            Status          = 'VERIFIED'
            Theme           = $ThemeId
            Font            = $verified.Face
            Size            = $verified.Size
            Weight          = $verified.Weight
            BackupDirectory = $backupDir
        }
    }
    finally {
        if (Test-Path -LiteralPath $temp) {
            Remove-Item -LiteralPath $temp -Force
        }
    }
}

function Restore-TypezeroTerminalFontSwitchV2 {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][string]$BackupDirectory,
        [switch]$Execute
    )

    $root = [IO.Path]::GetFullPath(
        (Join-Path $env:LOCALAPPDATA `
            'Typezero\ThemeEngine\backups\font-switch-v2')
    )

    $folder = [IO.Path]::GetFullPath($BackupDirectory)

    if (-not $folder.StartsWith(
        $root + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw 'Restore directory is outside the v2 backup root.'
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
        throw 'Incomplete v2 font backup.'
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

    if ($receipt.Version -ne 2) {
        throw 'Unsupported backup receipt version.'
    }

    $settingsPath = (Get-TypezeroTerminalFontStatus).SettingsPath

    if ($receipt.SettingsPath -ine $settingsPath) {
        throw 'Backup belongs to a different Terminal settings path.'
    }

    $backupHash = $backupSnapshot.Sha256

    if ($backupHash -ne $receipt.BeforeSha256) {
        throw 'Original backup checksum mismatch.'
    }

    $currentHash = (
        Get-FileHash -LiteralPath $settingsPath -Algorithm SHA256
    ).Hash

    if ($currentHash -ne $receipt.AfterSha256) {
        throw 'Settings changed since activation. Restore blocked.'
    }

    if (-not $Execute) {
        return [pscustomobject]@{
            Action          = 'PREVIEW ONLY - no changes'
            ReceiptAuthenticated = $false
            Theme           = $receipt.Theme
            PreviousFont    = $receipt.PreviousFont
            BackupDirectory = $folder
        }
    }

    Write-Warning 'Receipt authenticity is not independently verified. RESTORE replaces the entire Windows Terminal settings document.'

    if (-not $PSCmdlet.ShouldProcess(
        'Windows Terminal settings',
        'Restore byte-exact pre-activation configuration'
    )) {
        return
    }

    $temp = Join-Path (Split-Path -Parent $settingsPath) (
        '.typezero-v2-restore-' +
        [guid]::NewGuid().ToString('N') + '.tmp'
    )

    try {
        [IO.File]::WriteAllBytes($temp, $backupSnapshot.Bytes)

        $stagedHash = (
            Get-FileHash -LiteralPath $temp -Algorithm SHA256
        ).Hash

        if ($stagedHash -ne $receipt.BeforeSha256) {
            throw 'Staged restoration checksum mismatch.'
        }

        if ((Get-FileHash -LiteralPath $settingsPath -Algorithm SHA256).Hash -ne
            $receipt.AfterSha256) {
            throw 'Settings changed before restoration. Restore blocked.'
        }

        Move-Item -LiteralPath $temp -Destination $settingsPath `
            -Force -ErrorAction Stop

        $verifiedHash = (
            Get-FileHash -LiteralPath $settingsPath -Algorithm SHA256
        ).Hash

        if ($verifiedHash -ne $receipt.BeforeSha256) {
            throw 'Restoration verification failed.'
        }

        [pscustomobject]@{
            Status          = 'RESTORED'
            OriginalHashMatch = $true
            BackupDirectory = $folder
        }
    }
    finally {
        if (Test-Path -LiteralPath $temp) {
            Remove-Item -LiteralPath $temp -Force
        }
    }
}
