# Typezero ThemeEngine - Font Mapping V2 Transaction Adapter
# Fixture-only: no live Windows Terminal activation or automatic recovery.

function Assert-TypezeroFontV2AdapterFixture {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TestRoot,
        [Parameter(Mandatory)][string]$ConfigPath
    )

    $root = [IO.Path]::GetFullPath($TestRoot).TrimEnd(
        [IO.Path]::DirectorySeparatorChar
    )
    $temp = [IO.Path]::GetFullPath($env:TEMP).TrimEnd(
        [IO.Path]::DirectorySeparatorChar
    )
    $prefix = $temp + [IO.Path]::DirectorySeparatorChar

    if (-not $root.StartsWith(
        $prefix, [StringComparison]::OrdinalIgnoreCase
    )) {
        throw 'REFUSED: Transaction root is outside TEMP.'
    }

    if ([IO.Path]::GetFileName($root) -cnotmatch
        '^typezero-terminal-txn-[a-f0-9]{32}$') {
        throw 'REFUSED: Transaction root is not a dedicated adapter fixture.'
    }

    if (-not [IO.Directory]::Exists($root)) {
        throw 'REFUSED: Fixture root does not exist.'
    }

    $config = [IO.Path]::GetFullPath($ConfigPath)

    if (-not $config.StartsWith(
        $root + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw 'REFUSED: Mapping config is outside the fixture.'
    }

    if (-not [IO.File]::Exists($config)) {
        throw 'REFUSED: Fixture mapping config is missing.'
    }

    # Reject reparse points from TEMP through the fixture's contents.
    $cursor = $root

    while ($cursor.Length -ge $temp.Length) {
        $item = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop

        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'REFUSED: Fixture path contains a reparse point.'
        }

        if ($cursor -ieq $temp) { break }

        $parent = [IO.Directory]::GetParent($cursor)
        if ($null -eq $parent) { break }
        $cursor = $parent.FullName
    }

    $cursor = Split-Path -Parent $config

    while ($cursor.Length -gt $root.Length) {
        $item = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop

        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'REFUSED: Config path contains a reparse point.'
        }

        $cursor = [IO.Directory]::GetParent($cursor).FullName
    }

    $configItem = Get-Item -LiteralPath $config -Force

    if (($configItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'REFUSED: Config is a reparse point.'
    }

    # Reuse the native Windows hardlink guard from TerminalReplace.
    if (-not (Get-Command Assert-TypezeroOfflineReplaceSingleLink `
        -CommandType Function -ErrorAction SilentlyContinue)) {
        throw 'REFUSED: Native single-link validator is not loaded.'
    }

    Assert-TypezeroOfflineReplacePlainPath -Path $config
    Assert-TypezeroOfflineReplaceSingleLink -Path $config

    # The transaction resolver enforces its own disposable-root contract.
    $transactionPaths = Get-TypezeroOfflineTerminalV2Paths -TestRoot $root

    if ($transactionPaths.Root -ine $root) {
        throw 'REFUSED: Transaction root identity mismatch.'
    }

    [pscustomobject]@{
        TestRoot    = $root
        ConfigPath  = $config
        FixtureOnly = $true
    }
}

function Invoke-TypezeroOfflineFontMappingV2Transaction {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][string]$TestRoot,
        [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)]
        [ValidatePattern('^[a-z0-9][a-z0-9-]*$')]
        [string]$ThemeId,
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Theme,
        [switch]$Execute
    )

    $fixture = Assert-TypezeroFontV2AdapterFixture `
        -TestRoot $TestRoot -ConfigPath $ConfigPath

    # Pin the complete configuration, not just the selected mapping. Hold a
    # read handle without write/delete sharing while hashing and parsing it.
    $configHandle = [IO.FileStream]::new(
        $fixture.ConfigPath, [IO.FileMode]::Open,
        [IO.FileAccess]::Read, [IO.FileShare]::Read
    )
    try {
        $configSha256 = [Convert]::ToHexString(
            [Security.Cryptography.SHA256]::HashData($configHandle)
        )
        $config = Get-TypezeroWindowsFontMappings -Path $fixture.ConfigPath
    }
    finally { $configHandle.Dispose() }

    if ($config.Version -ne 2) {
        throw 'REFUSED: Font mapping must be V2.'
    }

    if ($null -ne $config.ManualOverride) {
        throw 'REFUSED: Manual override is not supported.'
    }

    if (-not $config.Mappings.Contains($ThemeId)) {
        throw "REFUSED: No font mapping for theme '$ThemeId'."
    }

    $mapping = $config.Mappings[$ThemeId]

    if ([string]::IsNullOrWhiteSpace($mapping.Family) -or
        [double]$mapping.Size -lt 6 -or
        [double]$mapping.Size -gt 36 -or
        $mapping.Weight -notin @('normal', 'semi-bold')) {
        throw 'REFUSED: Invalid V2 font mapping.'
    }

    if ($Execute -and -not $config.Enabled) {
        throw 'REFUSED: Font integration is disabled.'
    }

    $arguments = @{
        TestRoot   = $fixture.TestRoot
        Theme      = $Theme
        FontFace   = [string]$mapping.Family
        FontSize   = [double]$mapping.Size
        FontWeight = [string]$mapping.Weight
    }

    if (-not $Execute) {
        return Invoke-TypezeroOfflineTerminalV2Locked @arguments
    }

    if (-not $PSCmdlet.ShouldProcess(
        $fixture.TestRoot,
        "Execute fixture-only combined transaction for '$ThemeId'"
    )) {
        return
    }

    # Own the same fixed lock used by all cooperating V2 fixture writers.
    # Calling the locked wrapper here would nest its exclusive lock, while
    # reading the mapping before that wrapper leaves a stale-input window.
    $lockPath = Join-Path $fixture.TestRoot '.typezero-terminal-v2.lock'
    Assert-TypezeroOfflineReplacePlainPath -Path $lockPath
    $lock = $null
    try {
        $lock = [IO.FileStream]::new(
            $lockPath, [IO.FileMode]::OpenOrCreate,
            [IO.FileAccess]::ReadWrite, [IO.FileShare]::None
        )
    }
    catch [IO.IOException] {
        throw 'REFUSED: Disposable transaction lock is occupied.'
    }

    $configHandle = $null
    try {
        # Resolve all fixture fences again under the transaction lock, then
        # keep configuration bytes stable through candidate creation/write.
        $lockedFixture = Assert-TypezeroFontV2AdapterFixture `
            -TestRoot $fixture.TestRoot -ConfigPath $fixture.ConfigPath
        $configHandle = [IO.FileStream]::new(
            $lockedFixture.ConfigPath, [IO.FileMode]::Open,
            [IO.FileAccess]::Read, [IO.FileShare]::Read
        )
        $lockedSha256 = [Convert]::ToHexString(
            [Security.Cryptography.SHA256]::HashData($configHandle)
        )
        if ($lockedSha256 -cne $configSha256) {
            throw 'REFUSED: Font mapping configuration changed during transaction preparation.'
        }
        $lockedConfig = Get-TypezeroWindowsFontMappings `
            -Path $lockedFixture.ConfigPath
        if ($lockedConfig.Version -ne 2 -or
            $null -ne $lockedConfig.ManualOverride -or
            -not $lockedConfig.Enabled -or
            -not $lockedConfig.Mappings.Contains($ThemeId)) {
            throw 'REFUSED: Font configuration is no longer eligible for execution.'
        }
        $lockedMapping = $lockedConfig.Mappings[$ThemeId]
        $arguments.FontFace = [string]$lockedMapping.Family
        $arguments.FontSize = [double]$lockedMapping.Size
        $arguments.FontWeight = [string]$lockedMapping.Weight

        Invoke-TypezeroOfflineTerminalCombinedTransactionV2 `
            @arguments -Execute -Confirm:$false
    }
    finally {
        if ($null -ne $configHandle) { $configHandle.Dispose() }
        if ($null -ne $lock) { $lock.Dispose() }
    }
}
