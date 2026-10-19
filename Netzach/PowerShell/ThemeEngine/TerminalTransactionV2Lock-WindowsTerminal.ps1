# Typezero ThemeEngine - Fixture-only Terminal Transaction V2 locking.
# Locking serializes cooperating writers; it does not authorize live activation.

function Invoke-TypezeroOfflineTerminalV2Locked {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][string]$TestRoot,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Theme,
        [Parameter(Mandatory)][string]$FontFace,
        [Parameter(Mandatory)][ValidateRange(6,36)][double]$FontSize,
        [Parameter(Mandatory)][ValidateSet('normal','semi-bold')]
        [string]$FontWeight,
        [switch]$Execute
    )

    # Use the established V2 resolver, including its exact TEMP-root checks.
    $paths = Get-TypezeroOfflineTerminalV2Paths -TestRoot $TestRoot

    $arguments = @{
        TestRoot   = $paths.Root
        Theme      = $Theme
        FontFace   = $FontFace
        FontSize   = $FontSize
        FontWeight = $FontWeight
    }

    if (-not $Execute) {
        return Invoke-TypezeroOfflineTerminalCombinedTransactionV2 @arguments
    }

    if (-not $PSCmdlet.ShouldProcess(
        $paths.Settings, 'Apply locked transaction to disposable fixture'
    )) {
        return
    }

    $lockPath = Join-Path $paths.Root '.typezero-terminal-v2.lock'

    Assert-TypezeroOfflineReplacePlainPath -Path $lockPath

    $lock = $null

    try {
        $lock = [IO.FileStream]::new(
            $lockPath,
            [IO.FileMode]::OpenOrCreate,
            [IO.FileAccess]::ReadWrite,
            [IO.FileShare]::None
        )
    }
    catch [IO.IOException] {
        throw 'REFUSED: Disposable transaction lock is occupied.'
    }

    try {
        # Re-resolve paths after acquiring the lock.
        $lockedPaths = Get-TypezeroOfflineTerminalV2Paths `
            -TestRoot $paths.Root

        if ($lockedPaths.Settings -ine $paths.Settings) {
            throw 'REFUSED: Transaction settings path changed.'
        }

        Invoke-TypezeroOfflineTerminalCombinedTransactionV2 `
            @arguments -Execute -Confirm:$false
    }
    finally {
        if ($null -ne $lock) {
            $lock.Dispose()
        }
    }
}

function Restore-TypezeroOfflineTerminalV2Locked {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][string]$TestRoot,
        [Parameter(Mandatory)][string]$BackupDirectory,
        [switch]$Execute
    )

    $paths = Get-TypezeroOfflineTerminalV2Paths -TestRoot $TestRoot

    $arguments = @{
        TestRoot = $paths.Root
        BackupDirectory = $BackupDirectory
    }

    if (-not $Execute) {
        return Restore-TypezeroOfflineTerminalCombinedTransactionV2 @arguments
    }

    if (-not $PSCmdlet.ShouldProcess(
        $paths.Settings, 'Restore locked transaction in disposable fixture'
    )) {
        return
    }

    $lockPath = Join-Path $paths.Root '.typezero-terminal-v2.lock'
    Assert-TypezeroOfflineReplacePlainPath -Path $lockPath

    $lock = $null

    try {
        $lock = [IO.FileStream]::new(
            $lockPath,
            [IO.FileMode]::OpenOrCreate,
            [IO.FileAccess]::ReadWrite,
            [IO.FileShare]::None
        )
    }
    catch [IO.IOException] {
        throw 'REFUSED: Disposable transaction lock is occupied.'
    }

    try {
        $lockedPaths = Get-TypezeroOfflineTerminalV2Paths `
            -TestRoot $paths.Root

        if ($lockedPaths.Settings -ine $paths.Settings) {
            throw 'REFUSED: Transaction settings path changed.'
        }

        Restore-TypezeroOfflineTerminalCombinedTransactionV2 `
            @arguments -Execute -Confirm:$false
    }
    finally {
        if ($null -ne $lock) {
            $lock.Dispose()
        }
    }
}