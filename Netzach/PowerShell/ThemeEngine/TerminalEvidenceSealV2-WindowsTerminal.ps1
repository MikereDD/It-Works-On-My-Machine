# Typezero ThemeEngine - Fixture-only V2 evidence authentication.
# Not a recovery, activation, or production authorization mechanism.

if (-not ('TypezeroEvidenceSealCryptoV2' -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;

public static class TypezeroEvidenceSealCryptoV2
{
    public static byte[] Compute(byte[] key, byte[] receipt, byte[] backup)
    {
        if (key == null || key.Length != 32)
            throw new ArgumentException("A 32-byte independent key is required.");

        using (var stream = new MemoryStream())
        {
            byte[][] parts = {
                Encoding.ASCII.GetBytes("TYPEZERO-V2-EVIDENCE-SEAL-1"),
                receipt,
                backup
            };

            foreach (byte[] part in parts)
            {
                byte[] length = BitConverter.GetBytes((long)part.Length);
                if (!BitConverter.IsLittleEndian) Array.Reverse(length);
                stream.Write(length, 0, length.Length);
                stream.Write(part, 0, part.Length);
            }

            using (var hmac = new HMACSHA256(key))
                return hmac.ComputeHash(stream.ToArray());
        }
    }

    public static bool Equal(byte[] expected, byte[] actual)
    {
        if (expected == null || actual == null ||
            expected.Length != 32 || actual.Length != 32)
            return false;

        return CryptographicOperations.FixedTimeEquals(expected, actual);
    }
}
"@
}

function Get-TypezeroOfflineTerminalV2SealContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TestRoot,
        [Parameter(Mandatory)][string]$BackupDirectory
    )

    $paths = Get-TypezeroOfflineTerminalV2Paths -TestRoot $TestRoot
    $folder = Assert-TypezeroOfflineTerminalV2Folder `
        -Paths $paths -BackupDirectory $BackupDirectory

    $receipt = Join-Path $folder 'receipt.json'
    $backup = Join-Path $folder 'settings-pre-replace.json'
    $seal = Join-Path $folder 'evidence.seal'

    foreach ($path in @($receipt, $backup, $seal)) {
        Assert-TypezeroOfflineReplacePlainPath -Path $path
        if ([IO.File]::Exists($path)) {
            Assert-TypezeroOfflineReplaceSingleLink -Path $path
        }
    }

    [pscustomobject]@{
        Paths = $paths
        Folder = $folder
        Receipt = $receipt
        Backup = $backup
        Seal = $seal
    }
}

function Get-TypezeroOfflineTerminalV2SealResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TestRoot,
        [Parameter(Mandatory)][string]$BackupDirectory,
        [byte[]]$IndependentKey
    )

    $context = Get-TypezeroOfflineTerminalV2SealContext `
        -TestRoot $TestRoot -BackupDirectory $BackupDirectory

    $status = 'INCOMPLETE'
    $reason = 'Required evidence is missing.'

    if (-not [IO.File]::Exists($context.Receipt) -or
        -not [IO.File]::Exists($context.Backup) -or
        -not [IO.File]::Exists($context.Seal)) {
        $status = 'INCOMPLETE'
    }
    elseif ($null -eq $IndependentKey -or $IndependentKey.Length -ne 32) {
        $status = 'UNTRUSTED'
        $reason = 'An independent 32-byte verification key is required.'
    }
    else {
        $receiptBytes = [IO.File]::ReadAllBytes($context.Receipt)
        $backupBytes = [IO.File]::ReadAllBytes($context.Backup)
        $sealBytes = [IO.File]::ReadAllBytes($context.Seal)

        if ($receiptBytes.Length -gt 65536 -or $sealBytes.Length -ne 32) {
            $status = 'INVALID'
            $reason = 'Malformed evidence size.'
        }
        else {
            # Check V2 receipt structure and required transaction identity.
            try {
                $receipt = Read-TypezeroOfflineTerminalV2ApplyReceipt `
                    -Paths $context.Paths -Folder $context.Folder

                $backupHash = (
                    Get-FileHash -LiteralPath $context.Backup -Algorithm SHA256
                ).Hash

                if ($backupHash -cne $receipt.BeforeSha256) {
                    $status = 'INVALID'
                    $reason = 'Backup checksum does not match the receipt.'
                }
                else {
                    [byte[]]$actual = [TypezeroEvidenceSealCryptoV2]::Compute(
                        $IndependentKey, $receiptBytes, $backupBytes
                    )

                    if ([TypezeroEvidenceSealCryptoV2]::Equal(
                        $sealBytes, $actual
                    )) {
                        $status = 'AUTHENTICATED'
                        $reason = 'Receipt and backup bytes match the independent key.'
                    }
                    else {
                        $status = 'INVALID'
                        $reason = 'Evidence authentication failed.'
                    }
                }
            }
            catch {
                $status = 'INVALID'
                $reason = 'Evidence validation failed.'
            }
        }
    }

    [pscustomobject]@{
        Status = $status
        Reason = $reason
        ReadOnly = $true
        ReceiptAuthenticated = ($status -ceq 'AUTHENTICATED')
        RecoveryAuthorized = $false
        LiveActivationAuthorized = $false
        OperationPhase = 'UNKNOWN'
        FixtureOnly = $true
        BackupDirectory = $context.Folder
    }
}

function New-TypezeroOfflineTerminalV2EvidenceSeal {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][string]$TestRoot,
        [Parameter(Mandatory)][string]$BackupDirectory,
        [Parameter(Mandatory)][byte[]]$IndependentKey,
        [switch]$Execute
    )

    $context = Get-TypezeroOfflineTerminalV2SealContext `
        -TestRoot $TestRoot -BackupDirectory $BackupDirectory

    if ($IndependentKey.Length -ne 32) {
        throw 'REFUSED: Independent key must contain exactly 32 bytes.'
    }

    if (-not [IO.File]::Exists($context.Receipt) -or
        -not [IO.File]::Exists($context.Backup)) {
        throw 'REFUSED: Existing V2 receipt and backup are required.'
    }

    if ([IO.File]::Exists($context.Seal) -or
        [IO.Directory]::Exists($context.Seal)) {
        throw 'REFUSED: Evidence seal already exists.'
    }

    $receipt = Read-TypezeroOfflineTerminalV2ApplyReceipt `
        -Paths $context.Paths -Folder $context.Folder

    $backupHash = (
        Get-FileHash -LiteralPath $context.Backup -Algorithm SHA256
    ).Hash

    if ($backupHash -cne $receipt.BeforeSha256) {
        throw 'REFUSED: Backup does not match V2 receipt.'
    }

    $currentHash = (
        Get-FileHash -LiteralPath $context.Paths.Settings -Algorithm SHA256
    ).Hash

    if ($currentHash -cne $receipt.AfterSha256) {
        throw 'REFUSED: Current fixture settings do not match applied transaction.'
    }

    if (-not $Execute) {
        return [pscustomobject]@{
            Status = 'PREVIEW'
            WouldCreateSeal = $true
            ReadOnly = $true
            RecoveryAuthorized = $false
            LiveActivationAuthorized = $false
        }
    }

    if (-not $PSCmdlet.ShouldProcess(
        $context.Seal, 'Seal verified disposable V2 transaction evidence'
    )) {
        return
    }

    [byte[]]$receiptBytes = [IO.File]::ReadAllBytes($context.Receipt)
    [byte[]]$backupBytes = [IO.File]::ReadAllBytes($context.Backup)

    if ($receiptBytes.Length -gt 65536) {
        throw 'REFUSED: Receipt exceeds 64 KiB.'
    }

    # Revalidate the evidence immediately before seal creation.
    if ((Get-TypezeroOfflineTerminalV2Sha256 $context.Receipt) -ne
        [Convert]::ToHexString(
            [Security.Cryptography.SHA256]::HashData($receiptBytes)
        ) -or
        (Get-TypezeroOfflineTerminalV2Sha256 $context.Backup) -ne
        $receipt.BeforeSha256 -or
        (Get-TypezeroOfflineTerminalV2Sha256 $context.Paths.Settings) -ne
        $receipt.AfterSha256) {
        throw 'REFUSED: Evidence changed before sealing.'
    }

    [byte[]]$mac = [TypezeroEvidenceSealCryptoV2]::Compute(
        $IndependentKey, $receiptBytes, $backupBytes
    )

    # Existing CreateNew primitive rejects overwrite and flushes to disk.
    Write-TypezeroOfflineTerminalV2NewFile `
        -Path $context.Seal -Bytes $mac

    [pscustomobject]@{
        Status = 'SEALED'
        ReceiptAuthenticated = $true
        RecoveryAuthorized = $false
        LiveActivationAuthorized = $false
        FixtureOnly = $true
        SealPath = $context.Seal
    }
}