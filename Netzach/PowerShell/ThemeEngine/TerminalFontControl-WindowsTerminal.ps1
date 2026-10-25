# Shared font-only preview/apply and named custom presets for shell and WPF.
# Loading this file never writes settings or preferences.
. (Join-Path $PSScriptRoot 'TerminalSettings-WindowsTerminal.ps1')
. (Join-Path $PSScriptRoot 'FontProvider-WindowsTerminal.ps1')

. (Join-Path $PSScriptRoot 'FontWeights-WindowsTerminal.ps1')

function Assert-TypezeroTerminalFontChoice {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Family,
        [Parameter(Mandatory)][double]$Size,
        [Parameter(Mandatory)][string]$Weight)
    if ([string]::IsNullOrWhiteSpace($Family) -or $Family -cne $Family.Trim() -or
        $Family.IndexOfAny([char[]]@([char]0,[char]10,[char]13)) -ge 0) { throw 'Select a nonempty font family without surrounding whitespace or line breaks.' }
    if (-not [double]::IsFinite($Size) -or $Size -lt 6 -or $Size -gt 36 -or $Size -ne [math]::Round($Size,2)) {
        throw 'Select a font size from 6 to 36 with at most two decimal places.'
    }
    Assert-TypezeroTerminalFontWeight -Weight $Weight
    [pscustomobject]@{ Family=$Family; Size=$Size; Weight=$Weight }
}

function Get-TypezeroTerminalFontPreview {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Family,
        [Parameter(Mandatory)][double]$Size,
        [Parameter(Mandatory)][string]$Weight,
        [string]$SettingsPath = (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        [switch]$ValidateInstalled)
    $choice = Assert-TypezeroTerminalFontChoice -Family $Family -Size $Size -Weight $Weight
    $bytes = [IO.File]::ReadAllBytes($SettingsPath)
    $utf8 = [Text.UTF8Encoding]::new($false,$true)
    $offset = if ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) { 3 } else { 0 }
    $text = $utf8.GetString($bytes,$offset,$bytes.Length-$offset)
    $font = [ordered]@{ face=$choice.Family; size=$choice.Size; weight=$choice.Weight }
    $candidate = New-TypezeroTerminalFontText -Text $text -Font $font
    $settings = ConvertFrom-Json -InputObject $text -AsHashtable
    $profile = @($settings.profiles.list | Where-Object { $_.guid -ieq '{574e775e-4f2a-5b96-ac1e-a2962a402336}' })[0]
    $defaultFont = $settings.profiles.defaults.font
    $current = [ordered]@{}
    foreach ($key in @('face','size','weight')) {
        $fallback = switch ($key) { face { 'Cascadia Mono' } size { 12 } weight { 'normal' } }
        $current[$key] = if ($profile.font -and $profile.font.Contains($key)) { $profile.font[$key] }
            elseif ($defaultFont -and $defaultFont.Contains($key)) { $defaultFont[$key] } else { $fallback }
    }
    if ($ValidateInstalled -and $Family -cne 'JetBrainsMono Nerd Font' -and $Family -cne $current.face -and
        @(@(Get-TypezeroInstalledFontFamilies) | Where-Object { $_ -ceq $Family }).Count -ne 1) {
        throw "Unrecognized Windows Terminal font: $Family"
    }
    [pscustomobject]@{
        Family=$choice.Family; Size=$choice.Size; Weight=$choice.Weight; SettingsPath=$SettingsPath
        ExpectedSha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
        CurrentFamily=$current.face; CurrentSize=$current.size; CurrentWeight=$current.weight
        WouldChange=($candidate -cne $text); PreviewOnly=$true; SettingsChanged=$false
        Message="Preview only: $Family, $Size pt, $Weight. No settings or saved choices changed."
    }
}

function Set-TypezeroTerminalFontChoice {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([Parameter(Mandatory)][string]$Family,
        [Parameter(Mandatory)][double]$Size,
        [Parameter(Mandatory)][string]$Weight,
        [string]$SettingsPath = (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        [string]$ExpectedSha256,
        [switch]$ValidateInstalled)
    $preview = Get-TypezeroTerminalFontPreview -Family $Family -Size $Size -Weight $Weight -SettingsPath $SettingsPath -ValidateInstalled:$ValidateInstalled
    if ($ExpectedSha256 -and $preview.ExpectedSha256 -ine $ExpectedSha256) { throw 'Terminal settings changed since the preview; preview again before applying.' }
    $result = [ordered]@{
        Status='NotExecuted'; Path=$SettingsPath; Family=$Family; Size=$Size; Weight=$Weight
        Changed=$false; BackupPath=$null; BeforeSha256=$preview.ExpectedSha256; AfterSha256=$preview.ExpectedSha256
        FontActivated=$false; PreviewOnly=$false; SettingsChanged=$false; Message='No changes executed.'
    }
    if ($PSCmdlet.ShouldProcess($SettingsPath,"Apply Windows Terminal font: $Family, $Size pt, $Weight")) {
        $written = Set-TypezeroWindowsTerminalFont -Path $SettingsPath -Font ([ordered]@{ face=$Family; size=$Size; weight=$Weight }) -ExpectedSha256 $preview.ExpectedSha256
        foreach ($key in @('Path','Changed','BackupPath','BeforeSha256','AfterSha256')) { $result[$key]=$written.$key }
        $result.Status='FontApplied'; $result.FontActivated=$true; $result.SettingsChanged=[bool]$written.Changed
        $result.Message=if ($written.Changed) { "Windows Terminal font applied: $Family, $Size pt, $Weight. Saved choices were not changed." }
            else { "Windows Terminal already uses $Family, $Size pt, $Weight. No settings or saved choices changed." }
    }
    [pscustomobject]$result
}

function Get-TypezeroAppearancePresets {
    [CmdletBinding()]
    param([string]$Path = (Join-Path $env:LOCALAPPDATA 'Typezero\ThemeEngine\custom-presets.json'))
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $text = [IO.File]::ReadAllText($Path)
    $null = Get-TypezeroJsoncTree $text # Also rejects duplicate keys.
    $data = ConvertFrom-Json -InputObject $text -AsHashtable
    if ($data.Count -ne 2 -or ($data.Version -isnot [int] -and $data.Version -isnot [long]) -or
        $data.Version -ne 1 -or $data.Presets -isnot [array]) { throw "Invalid custom preset file: $Path" }
    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $data.Presets) {
        if ($entry -isnot [System.Collections.IDictionary] -or $entry.Count -ne 5 -or
            $entry.Name -isnot [string] -or $entry.Name -cnotmatch '\A[a-z0-9][a-z0-9-]{0,63}\z' -or
            $entry.Theme -isnot [string] -or $entry.Theme -cnotmatch '\A[a-z0-9][a-z0-9-]*\z' -or
            $entry.Family -isnot [string] -or $entry.Weight -isnot [string] -or
            ($entry.Size -isnot [int] -and $entry.Size -isnot [long] -and $entry.Size -isnot [double] -and $entry.Size -isnot [decimal]) -or
            -not $names.Add($entry.Name)) { throw "Invalid custom preset entry: $Path" }
        $choice = Assert-TypezeroTerminalFontChoice -Family $entry.Family -Size $entry.Size -Weight $entry.Weight
        [pscustomobject]@{ Name=[string]$entry.Name; Theme=[string]$entry.Theme; Family=$choice.Family; Size=$choice.Size; Weight=$choice.Weight }
    }
}

function Save-TypezeroAppearancePreset {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([Parameter(Mandatory)][ValidatePattern('\A[a-z0-9][a-z0-9-]{0,63}\z')][string]$Name,
        [Parameter(Mandatory)][ValidatePattern('\A[a-z0-9][a-z0-9-]*\z')][string]$Theme,
        [Parameter(Mandatory)][string]$Family,
        [Parameter(Mandatory)][double]$Size,
        [Parameter(Mandatory)][string]$Weight,
        [string]$ThemesRoot = (Join-Path $env:LOCALAPPDATA 'Typezero\ThemeEngine\themes'),
        [string]$Path = (Join-Path $env:LOCALAPPDATA 'Typezero\ThemeEngine\custom-presets.json'),
        [switch]$Force)
    $choice = Assert-TypezeroTerminalFontChoice -Family $Family -Size $Size -Weight $Weight
    if ($Name -cnotmatch '\A[a-z0-9][a-z0-9-]{0,63}\z' -or $Theme -cnotmatch '\A[a-z0-9][a-z0-9-]*\z') { throw 'Use lowercase letters, digits and hyphens for preset and theme IDs.' }
    if (-not (Test-Path -LiteralPath (Join-Path $ThemesRoot "$Theme\theme.conf") -PathType Leaf)) { throw "Theme not found: $Theme" }
    $originalExists = Test-Path -LiteralPath $Path -PathType Leaf
    $originalHash = if ($originalExists) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash } else { $null }
    $existing = @(Get-TypezeroAppearancePresets -Path $Path)
    if (@($existing | Where-Object { $_.Name -ceq $Name }).Count -and -not $Force) { throw "Preset '$Name' already exists. Use -Force to replace it." }
    $entries = @($existing | Where-Object { $_.Name -cne $Name }) + @([pscustomobject]@{ Name=$Name; Theme=$Theme; Family=$choice.Family; Size=$choice.Size; Weight=$choice.Weight })
    $entries = @($entries | Sort-Object Name)
    $json = ([ordered]@{ Version=1; Presets=@($entries) } | ConvertTo-Json -Depth 6) + "`n"
    if (-not $PSCmdlet.ShouldProcess($Path,"Save custom preset '$Name' without activation")) { return }
    $folder = Split-Path -Parent ([IO.Path]::GetFullPath($Path))
    [IO.Directory]::CreateDirectory($folder) | Out-Null
    $stage = Join-Path $folder ('.typezero-preset-' + [guid]::NewGuid().ToString('N') + '.tmp')
    $backup = $null
    try {
        [IO.File]::WriteAllText($stage,$json,[Text.UTF8Encoding]::new($false))
        $verified = @(Get-TypezeroAppearancePresets -Path $stage)
        if ($verified.Count -ne $entries.Count -or @($verified | Where-Object { $_.Name -ceq $Name -and $_.Theme -ceq $Theme -and $_.Family -ceq $Family -and $_.Size -eq $Size -and $_.Weight -ceq $Weight }).Count -ne 1) { throw 'Custom preset verification failed.' }
        if ($originalExists) {
            if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -cne $originalHash) { throw 'Custom presets changed during preparation.' }
            $backup = "$Path.typezero-$([guid]::NewGuid().ToString('N')).bak"
            [IO.File]::Replace($stage,$Path,$backup)
            if ((Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash -cne $originalHash) { throw "Custom preset backup differs from the original; inspect $backup" }
        }
        else {
            if (Test-Path -LiteralPath $Path) { throw 'Custom presets appeared during preparation.' }
            [IO.File]::Move($stage,$Path)
        }
        $saved = @(Get-TypezeroAppearancePresets -Path $Path | Where-Object { $_.Name -ceq $Name })
        if ($saved.Count -ne 1) { throw 'Saved custom preset could not be read back.' }
        [pscustomobject]@{ Status='PresetSaved'; Name=$Name; Theme=$Theme; Family=$Family; Size=$Size; Weight=$Weight; BackupPath=$backup; Message="Custom preset '$Name' saved. No appearance settings changed." }
    }
    finally { if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Force } }
}
