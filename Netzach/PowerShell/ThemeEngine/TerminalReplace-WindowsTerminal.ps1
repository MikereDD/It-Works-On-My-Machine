function Assert-TypezeroOfflineReplacePlainPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $cursor = [IO.Path]::GetFullPath($Path)

    while ($true) {
        try {
            $attributes = [IO.File]::GetAttributes($cursor)

            if (($attributes -band
                [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Redirected filesystem path rejected: $cursor"
            }
        }
        catch [IO.FileNotFoundException] {
        }
        catch [IO.DirectoryNotFoundException] {
        }

        $parent = [IO.Path]::GetDirectoryName($cursor)

        if ([string]::IsNullOrEmpty($parent) -or
            [string]::Equals(
                $parent, $cursor,
                [StringComparison]::OrdinalIgnoreCase
            )) {
            break
        }

        $cursor = $parent
    }
}

function Assert-TypezeroOfflineReplaceSingleLink {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not $IsWindows) {
        throw 'Native hard-link verification requires Windows.'
    }

    if (-not ('TypezeroOfflineReplaceLinkCountV1' -as [type])) {
        $nativeCode = @"
using System;
using System.IO;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public static class TypezeroOfflineReplaceLinkCountV1
{
    [StructLayout(LayoutKind.Sequential)]
    public struct FileTime
    {
        public uint Low;
        public uint High;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct FileInformation
    {
        public uint Attributes;
        public FileTime CreationTime;
        public FileTime LastAccessTime;
        public FileTime LastWriteTime;
        public uint VolumeSerial;
        public uint SizeHigh;
        public uint SizeLow;
        public uint NumberOfLinks;
        public uint FileIndexHigh;
        public uint FileIndexLow;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetFileInformationByHandle(
        SafeFileHandle handle,
        out FileInformation information
    );

    public static uint GetLinkCount(string path)
    {
        using (var stream = new FileStream(
            path, FileMode.Open, FileAccess.Read,
            FileShare.ReadWrite | FileShare.Delete))
        {
            FileInformation info;

            if (!GetFileInformationByHandle(
                stream.SafeFileHandle, out info))
            {
                throw new Win32Exception(
                    Marshal.GetLastWin32Error()
                );
            }

            if (info.NumberOfLinks == 0)
                throw new IOException("Invalid hard-link count.");

            return info.NumberOfLinks;
        }
    }
}
"@

        Add-Type -TypeDefinition $nativeCode -ErrorAction Stop
    }

    $count = [TypezeroOfflineReplaceLinkCountV1]::GetLinkCount(
        [IO.Path]::GetFullPath($Path)
    )

    if ($count -ne 1) {
        throw "Hard-linked file rejected: $Path (links=$count)"
    }
}

function Invoke-TypezeroOfflineTerminalVerifiedReplace {
    [CmdletBinding(
        SupportsShouldProcess = $true,
        ConfirmImpact = 'High'
    )]
    param(
        [Parameter(Mandatory)]
        [string]$TestRoot,

        [Parameter(Mandatory)]
        [string]$StagePath,

        [Parameter(Mandatory)]
        [string]$BackupPath,

        [Parameter(Mandatory)]
        [ValidatePattern('\A[a-fA-F0-9]{64}\z')]
        [string]$ExpectedBeforeSha256,

        [Parameter(Mandatory)]
        [ValidatePattern('\A[a-fA-F0-9]{64}\z')]
        [string]$ExpectedStageSha256,

        [switch]$Execute
    )

    # Offline-only: require a specially named direct child of TEMP.
    $root = [IO.Path]::GetFullPath($TestRoot).TrimEnd('\', '/')
    $temp = [IO.Path]::GetFullPath(
        [IO.Path]::GetTempPath()
    ).TrimEnd('\', '/')

    if (-not [string]::Equals(
        [IO.Path]::GetDirectoryName($root),
        $temp,
        [StringComparison]::OrdinalIgnoreCase
    ) -or
        [IO.Path]::GetFileName($root) -cnotmatch
        '\Atypezero-terminal-txn-[a-f0-9]{32}\z') {
        throw 'Replacement requires a direct disposable TEMP fixture.'
    }

    $settings = [IO.Path]::GetFullPath(
        (Join-Path $root (
            'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe' +
            '\LocalState\settings.json'
        ))
    )

    $settingsDir = [IO.Path]::GetDirectoryName($settings)
    $stage = [IO.Path]::GetFullPath($StagePath)
    $backup = [IO.Path]::GetFullPath($BackupPath)

    # Stage must be an owned candidate in the settings directory.
    if (-not [string]::Equals(
        [IO.Path]::GetDirectoryName($stage),
        $settingsDir,
        [StringComparison]::OrdinalIgnoreCase
    ) -or
        [IO.Path]::GetFileName($stage) -cnotmatch
        '\A\.typezero-combined-(?:restore-)?[a-f0-9]{32}\.tmp\z') {
        throw 'Unexpected replacement staging path.'
    }

    # Backup must be in one exact transaction backup folder.
    $backupBase = [IO.Path]::GetFullPath(
        (Join-Path $root (
            'Typezero\ThemeEngine\backups\terminal-combined'
        ))
    )

    $backupDir = [IO.Path]::GetDirectoryName($backup)

    if ([IO.Path]::GetFileName($backup) -cne
        'settings-pre-replace.json' -or
        -not [string]::Equals(
            [IO.Path]::GetDirectoryName($backupDir),
            $backupBase,
            [StringComparison]::OrdinalIgnoreCase
        ) -or
        [IO.Path]::GetFileName($backupDir) -cnotmatch
        '\A[0-9]{8}-[0-9]{6}-[0-9]{7}-[a-f0-9]{32}\z') {
        throw 'Unexpected replacement backup path.'
    }

    foreach ($path in @(
        $root, $settings, $stage, $backupDir, $backup
    )) {
        Assert-TypezeroOfflineReplacePlainPath -Path $path
    }

    if (-not [IO.Directory]::Exists($backupDir)) {
        throw 'Transaction backup directory must already exist.'
    }

    if (-not [IO.File]::Exists($settings) -or
        -not [IO.File]::Exists($stage)) {
        throw 'Settings or stage file is missing.'
    }

    if ([IO.File]::Exists($backup) -or
        [IO.Directory]::Exists($backup)) {
        throw 'Replacement backup collision. Refusing overwrite.'
    }

    Assert-TypezeroOfflineReplaceSingleLink -Path $settings
    Assert-TypezeroOfflineReplaceSingleLink -Path $stage

    $beforeHash = (
        Get-FileHash -LiteralPath $settings -Algorithm SHA256
    ).Hash

    $stageHash = (
        Get-FileHash -LiteralPath $stage -Algorithm SHA256
    ).Hash

    if ($beforeHash -ine $ExpectedBeforeSha256) {
        throw 'Settings checksum differs from expected original.'
    }

    if ($stageHash -ine $ExpectedStageSha256) {
        throw 'Staging checksum differs from expected candidate.'
    }

    if (-not $Execute) {
        return [pscustomobject]@{
            Status             = 'PREVIEW'
            WouldReplace       = $true
            SettingsPath       = $settings
            StagePath          = $stage
            BackupPath         = $backup
            BeforeSha256       = $beforeHash
            CandidateSha256    = $stageHash
            ReadOnly           = $true
        }
    }

    if (-not $PSCmdlet.ShouldProcess(
        $settings,
        'Replace disposable Terminal settings with preserved backup'
    )) {
        return
    }

    # Repeat checks immediately before replacement.
    # These reduce exposure but are not an atomic compare-and-swap.
    foreach ($path in @($settings, $stage, $backup)) {
        Assert-TypezeroOfflineReplacePlainPath -Path $path
    }

    if ([IO.File]::Exists($backup) -or
        [IO.Directory]::Exists($backup)) {
        throw 'Backup collision immediately before replacement.'
    }

    Assert-TypezeroOfflineReplaceSingleLink -Path $settings
    Assert-TypezeroOfflineReplaceSingleLink -Path $stage

    if ((Get-FileHash -LiteralPath $settings -Algorithm SHA256).Hash -ine
        $ExpectedBeforeSha256) {
        throw 'Settings changed immediately before replacement.'
    }

    if ((Get-FileHash -LiteralPath $stage -Algorithm SHA256).Hash -ine
        $ExpectedStageSha256) {
        throw 'Stage changed immediately before replacement.'
    }

    # No automatic rollback or deletion on failure.
    # Preserve evidence for inspection.
    [IO.File]::Replace(
        $stage,
        $settings,
        $backup,
        $false
    )

    $actualSettings = (
        Get-FileHash -LiteralPath $settings -Algorithm SHA256
    ).Hash

    $actualBackup = (
        Get-FileHash -LiteralPath $backup -Algorithm SHA256
    ).Hash

    if ($actualSettings -ine $ExpectedStageSha256 -or
        $actualBackup -ine $ExpectedBeforeSha256) {
        throw (
            'Replacement verification failed. Preserve files for ' +
            "manual inspection. Backup: $backup"
        )
    }

    [pscustomobject]@{
        Status          = 'VERIFIED'
        SettingsPath    = $settings
        BackupPath      = $backup
        BeforeSha256    = $actualBackup
        AfterSha256     = $actualSettings
        BackupVerified  = $true
        TestRoot        = $root
    }
}