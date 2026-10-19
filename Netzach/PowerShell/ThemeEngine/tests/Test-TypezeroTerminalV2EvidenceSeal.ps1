$ErrorActionPreference = 'Stop'
$engine = Split-Path -Parent $PSScriptRoot

foreach ($name in @(
    'FontPatch-WindowsTerminal.ps1'
    'TerminalColorPatch-WindowsTerminal.ps1'
    'TerminalCombinedPatch-WindowsTerminal.ps1'
    'TerminalTransaction-WindowsTerminal.ps1'
    'TerminalReplace-WindowsTerminal.ps1'
    'TerminalTransactionV2-WindowsTerminal.ps1'
    'TerminalTransactionV2Lock-WindowsTerminal.ps1'
    'TerminalEvidenceSealV2-WindowsTerminal.ps1'
)) {
    . (Join-Path $engine $name)
}

$root = Join-Path ([IO.Path]::GetTempPath()) (
    'typezero-terminal-txn-' + [guid]::NewGuid().ToString('N')
)
New-Item -ItemType Directory -Path $root -ErrorAction Stop | Out-Null
$paths = Get-TypezeroOfflineTerminalV2Paths -TestRoot $root
New-Item -ItemType Directory -Path (Split-Path -Parent $paths.Settings) -Force | Out-Null

$theme = @{
    THEME_NAME = 'Obsidian Silver'
    BG = '#123456'
    TEXT = '#eeeeee'
    CURSOR = '#ffffff'
    SELECTION = '#445566'
}
foreach ($name in @(
    'BLACK','RED','GREEN','YELLOW','BLUE','PURPLE','CYAN','WHITE',
    'BRIGHT_BLACK','BRIGHT_RED','BRIGHT_GREEN','BRIGHT_YELLOW',
    'BRIGHT_BLUE','BRIGHT_PURPLE','BRIGHT_CYAN','BRIGHT_WHITE'
)) {
    $theme["ANSI_$name"] = '#778899'
}

$synthetic = [ordered]@{
    theme = 'Typezero ThemeEngine'
    schemes = @(@{ name = 'Typezero Obsidian Silver'; background = '#000000' })
    themes = @(@{
        name = 'Typezero ThemeEngine'
        window = @{ applicationTheme = 'dark' }
        tab = @{ background = 'terminalBackground' }
        tabRow = @{ background = '#000000' }
    })
    profiles = @{
        defaults = @{}
        list = @(@{
            guid = '{574e775e-4f2a-5b96-ac1e-a2962a402336}'
            name = 'PowerShell'
            colorScheme = 'Typezero Obsidian Silver'
        })
    }
}

$utf8 = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText(
    $paths.Settings,
    ($synthetic | ConvertTo-Json -Depth 20),
    $utf8
)

[byte[]]$key = [byte[]]::new(32)
[Security.Cryptography.RandomNumberGenerator]::Fill($key)

$applied = Invoke-TypezeroOfflineTerminalV2Locked `
    -TestRoot $root -Theme $theme `
    -FontFace 'JetBrainsMono Nerd Font' -FontSize 13 `
    -FontWeight normal -Execute -Confirm:$false

if ($applied.Status -cne 'VERIFIED') {
    throw 'FAIL: Initial disposable transaction.'
}

$folder = $applied.BackupDirectory
$receipt = Join-Path $folder 'receipt.json'
$backup = Join-Path $folder 'settings-pre-replace.json'
$seal = Join-Path $folder 'evidence.seal'
$originalReceipt = [IO.File]::ReadAllBytes($receipt)
$originalBackup = [IO.File]::ReadAllBytes($backup)
$originalSeal = $null
$checks = 0

function Assert-Status {
    param([string]$Expected, [string]$Label)
    $result = Get-TypezeroOfflineTerminalV2SealResult `
        -TestRoot $root -BackupDirectory $folder -IndependentKey $key

    if ($result.Status -cne $Expected -or
        $result.RecoveryAuthorized -ne $false -or
        $result.LiveActivationAuthorized -ne $false -or
        $result.OperationPhase -cne 'UNKNOWN') {
        throw "FAIL: $Label (actual $($result.Status))"
    }
    $script:checks++
    Write-Host "PASS [$script:checks] $Label"
}

try {
    $preview = New-TypezeroOfflineTerminalV2EvidenceSeal `
        -TestRoot $root -BackupDirectory $folder -IndependentKey $key

    if ($preview.Status -cne 'PREVIEW' -or
        -not $preview.ReadOnly -or (Test-Path -LiteralPath $seal)) {
        throw 'FAIL: Read-only preview.'
    }
    $checks++; Write-Host "PASS [$checks] Preview does not create seal"

    $null = New-TypezeroOfflineTerminalV2EvidenceSeal `
        -TestRoot $root -BackupDirectory $folder `
        -IndependentKey $key -Execute -WhatIf

    if (Test-Path -LiteralPath $seal) {
        throw 'FAIL: WhatIf created a seal.'
    }
    $checks++; Write-Host "PASS [$checks] WhatIf does not create seal"

    $created = New-TypezeroOfflineTerminalV2EvidenceSeal `
        -TestRoot $root -BackupDirectory $folder `
        -IndependentKey $key -Execute -Confirm:$false

    if ($created.Status -cne 'SEALED') {
        throw 'FAIL: Evidence seal creation.'
    }
    $originalSeal = [IO.File]::ReadAllBytes($seal)
    $checks++; Write-Host "PASS [$checks] Verified evidence sealed"

    Assert-Status 'AUTHENTICATED' 'Authentic V2 receipt and backup'

    [byte[]]$wrongKey = [byte[]]::new(32)
    [Security.Cryptography.RandomNumberGenerator]::Fill($wrongKey)
    $wrong = Get-TypezeroOfflineTerminalV2SealResult `
        -TestRoot $root -BackupDirectory $folder -IndependentKey $wrongKey
    if ($wrong.Status -cne 'INVALID') { throw 'FAIL: Wrong key.' }
    $checks++; Write-Host "PASS [$checks] Wrong key rejected"

    $duplicateBlocked = $false
    try {
        $null = New-TypezeroOfflineTerminalV2EvidenceSeal `
            -TestRoot $root -BackupDirectory $folder `
            -IndependentKey $key -Execute -Confirm:$false
    }
    catch {
        $duplicateBlocked = $_.Exception.Message -like '*already exists*'
    }
    if (-not $duplicateBlocked) { throw 'FAIL: Duplicate seal.' }
    $checks++; Write-Host "PASS [$checks] Duplicate seal refused"

    [IO.File]::AppendAllText($receipt, ' ', $utf8)
    Assert-Status 'INVALID' 'Receipt tampering rejected'
    [IO.File]::WriteAllBytes($receipt, $originalReceipt)

    [IO.File]::AppendAllText($backup, ' ', $utf8)
    Assert-Status 'INVALID' 'Backup tampering rejected'
    [IO.File]::WriteAllBytes($backup, $originalBackup)

    [IO.File]::WriteAllText(
        $receipt,
        '{"Version":2,"Operation":"APPLY","BeforeSha256":"forged"}',
        $utf8
    )
    [IO.File]::WriteAllText($backup, '{"forged":true}', $utf8)
    Assert-Status 'INVALID' 'Coordinated evidence tampering rejected'
    [IO.File]::WriteAllBytes($receipt, $originalReceipt)
    [IO.File]::WriteAllBytes($backup, $originalBackup)

    [byte[]]$fakeSeal = [byte[]]::new(32)
    [Security.Cryptography.RandomNumberGenerator]::Fill($fakeSeal)
    [IO.File]::WriteAllBytes($seal, $fakeSeal)
    Assert-Status 'INVALID' 'Replaced seal rejected'

    [IO.File]::Delete($seal)
    Assert-Status 'INCOMPLETE' 'Missing seal refused'
    [IO.File]::WriteAllBytes($seal, $originalSeal)

    [IO.File]::Delete($backup)
    Assert-Status 'INCOMPLETE' 'Missing backup refused'
    [IO.File]::WriteAllBytes($backup, $originalBackup)

    Assert-Status 'AUTHENTICATED' 'Original evidence re-authenticated'

    $diagnostic = Get-TypezeroOfflineTerminalCombinedV2RecoveryDiagnostic `
        -TestRoot $root -BackupDirectory $folder
    if (-not $diagnostic.ReadOnly -or
        $diagnostic.RecoveryAllowed -ne $false -or
        $diagnostic.OperationPhase -cne 'UNKNOWN') {
        throw 'FAIL: Recovery diagnostic authorization boundary.'
    }
    $checks++; Write-Host "PASS [$checks] Diagnostic remains unauthorized"

    if ($checks -ne 14) {
        throw "FAIL: Expected 14 checks, observed $checks."
    }

    Write-Host "`nPASS: $checks/14 permanent evidence-sealing checks."
}
finally {
    [IO.File]::WriteAllBytes($receipt, $originalReceipt)
    [IO.File]::WriteAllBytes($backup, $originalBackup)
    if ($null -ne $originalSeal) {
        [IO.File]::WriteAllBytes($seal, $originalSeal)
    }
    [array]::Clear($key, 0, $key.Length)
    Write-Host "Fixture retained: $root"
    Write-Host 'RecoveryAuthorized=False; LiveActivationAuthorized=False'
}