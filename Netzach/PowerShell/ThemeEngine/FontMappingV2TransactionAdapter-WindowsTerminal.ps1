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

    $config = Get-TypezeroWindowsFontMappings -Path $fixture.ConfigPath

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

    Invoke-TypezeroOfflineTerminalV2Locked `
        @arguments -Execute -Confirm:$false
}