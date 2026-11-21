# Typezero ThemeEngine - theme.conf color editing (shared Windows/Linux data)
#
# A derived theme is a new ThemeEngine/themes/<id>/theme.conf. Existing themes
# are never modified. Only the edited KEY=#RRGGBB lines, THEME_ID and
# THEME_NAME change; comments, order, typography and unknown keys are kept
# byte-for-byte so Netzach (PowerShell) and Arakiel (bash) read the same file.
#
# Saving is create-only. The shared repository source is written first because
# both hosts' `bootstrap` replace their installed theme folders from it; the
# installed copy is written second so the existing Apply actions see the theme
# immediately. Nothing is deleted on failure.

$script:TypezeroThemeColorGroups = [ordered]@{
    'Surfaces and text' = @('BG','SURFACE','SURFACE_ALT','BORDER_DARK','BORDER','MUTED','TEXT','BRIGHT','ACCENT','ACCENT_BRIGHT')
    'Interaction'       = @('SELECTION','CURSOR','FOCUS')
    'Semantic'          = @('SUCCESS','WARNING','ERROR','SECONDARY','INFO')
    'i3 window states'  = @('FOCUSED_BORDER','FOCUSED_BG','ACTIVE_BORDER','ACTIVE_BG','INACTIVE_BORDER','INACTIVE_BG','URGENT_BORDER','URGENT_BG')
    'ANSI terminal'     = @('ANSI_BLACK','ANSI_RED','ANSI_GREEN','ANSI_YELLOW','ANSI_BLUE','ANSI_PURPLE','ANSI_CYAN','ANSI_WHITE',
                            'ANSI_BRIGHT_BLACK','ANSI_BRIGHT_RED','ANSI_BRIGHT_GREEN','ANSI_BRIGHT_YELLOW','ANSI_BRIGHT_BLUE','ANSI_BRIGHT_PURPLE','ANSI_BRIGHT_CYAN','ANSI_BRIGHT_WHITE')
}

function Test-TypezeroThemeHexColor {
    param([AllowEmptyString()][string]$Value)
    return $Value -cmatch '\A#[0-9A-Fa-f]{6}\z'
}

function Test-TypezeroThemeId {
    param([AllowEmptyString()][string]$Id)
    return $Id -cmatch '\A[a-z0-9][a-z0-9-]{0,63}\z'
}

function Test-TypezeroThemeDisplayName {
    # Written inside double quotes. Arakiel's renderer substitutes values with
    # sed, so backslashes, quotes and control characters are excluded.
    param([AllowEmptyString()][string]$Name)
    return $Name -cmatch "\A[A-Za-z0-9][A-Za-z0-9 ._()&+'-]{0,63}\z" -and $Name -ceq $Name.Trim()
}

# Parse with the same rules as ThemeEngine.ps1 Read-ThemeFile and Arakiel
# load_theme: skip blank/# lines, split on the first '=', trim, strip one pair
# of enclosing quotes, last occurrence wins. Interaction fallbacks are not
# applied here; callers that need effective values apply them explicitly.
function ConvertFrom-TypezeroThemeConfText {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $result = [ordered]@{}
    foreach ($raw in ($Text -split "`r?`n")) {
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith('#') -or -not $line.Contains('=')) { continue }
        $idx = $line.IndexOf('=')
        $key = $line.Substring(0, $idx).Trim()
        $val = $line.Substring($idx + 1).Trim()
        if ($val.Length -ge 2 -and (($val.StartsWith('"') -and $val.EndsWith('"')) -or
            ($val.StartsWith("'") -and $val.EndsWith("'")))) {
            $val = $val.Substring(1, $val.Length - 2)
        }
        $result[$key] = $val
    }
    return $result
}

function Get-TypezeroThemeColorRoles {
    # Editable roles are exactly the keys this theme defines as #RRGGBB, in a
    # stable grouped order; keys outside the known groups follow as 'Other'.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $values = ConvertFrom-TypezeroThemeConfText -Text $Text
    $roles = [Collections.Generic.List[object]]::new()
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($group in $script:TypezeroThemeColorGroups.Keys) {
        foreach ($key in $script:TypezeroThemeColorGroups[$group]) {
            if ($values.Contains($key) -and (Test-TypezeroThemeHexColor $values[$key])) {
                $roles.Add([pscustomobject]@{ Group = $group; Key = $key; Value = [string]$values[$key] })
                [void]$seen.Add($key)
            }
        }
    }
    foreach ($key in $values.Keys) {
        if (-not $seen.Contains($key) -and (Test-TypezeroThemeHexColor $values[$key])) {
            $roles.Add([pscustomobject]@{ Group = 'Other'; Key = [string]$key; Value = [string]$values[$key] })
        }
    }
    return $roles.ToArray()
}

function New-TypezeroDerivedThemeText {
    param(
        [Parameter(Mandatory)][string]$SourceText,
        [Parameter(Mandatory)][string]$SourceId,
        [Parameter(Mandatory)][string]$NewId,
        [Parameter(Mandatory)][string]$DisplayName,
        [Collections.IDictionary]$Colors = @{}
    )
    if (-not (Test-TypezeroThemeId $NewId)) { throw "Invalid theme id: '$NewId'. Use 1-64 lowercase letters, numbers or hyphens." }
    if ($NewId -ceq $SourceId) { throw 'A derived theme needs a new id; the source theme is never modified.' }
    if (-not (Test-TypezeroThemeDisplayName $DisplayName)) {
        throw "Invalid display name: '$DisplayName'. Use 1-64 letters, numbers, spaces and . _ ( ) & + ' -"
    }
    $editable = @{}
    foreach ($role in (Get-TypezeroThemeColorRoles -Text $SourceText)) { $editable[$role.Key] = $true }
    $changes = @{}
    foreach ($key in $Colors.Keys) {
        $k = [string]$key
        $v = [string]$Colors[$key]
        if (-not $editable.ContainsKey($k)) { throw "Not an editable color role of '$SourceId': $k" }
        if (-not (Test-TypezeroThemeHexColor $v)) { throw "Invalid color for ${k}: '$v'. Use #RRGGBB." }
        $changes[$k] = $v.ToUpperInvariant()
    }

    $newline = if ($SourceText.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = [Collections.Generic.List[string]]::new()
    $lines.AddRange([string[]]($SourceText -split "`r?`n"))
    if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq '') { $lines.RemoveAt($lines.Count - 1) }

    $assignment = [regex]'\A(?<lead>\s*)(?<key>[A-Za-z_][A-Za-z0-9_]*)(?<eq>\s*=\s*)(?<value>.*?)(?<trail>\s*)\z'
    $replace = {
        param([string]$Line, [string]$NewValue, [bool]$ForceDoubleQuote)
        $m = $assignment.Match($Line)
        $raw = $m.Groups['value'].Value
        $quote = ''
        if ($raw.Length -ge 2 -and (($raw.StartsWith('"') -and $raw.EndsWith('"')) -or ($raw.StartsWith("'") -and $raw.EndsWith("'")))) {
            $quote = $raw.Substring(0, 1)
        }
        if ($ForceDoubleQuote) { $quote = '"' }
        return $m.Groups['lead'].Value + $m.Groups['key'].Value + $m.Groups['eq'].Value + $quote + $NewValue + $quote + $m.Groups['trail'].Value
    }
    $sawId = $false; $sawName = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $trimmed = $lines[$i].Trim()
        if (-not $trimmed -or $trimmed.StartsWith('#')) { continue }
        $m = $assignment.Match($lines[$i])
        if (-not $m.Success) { continue }
        $key = $m.Groups['key'].Value
        if ($key -ceq 'THEME_ID') { $lines[$i] = & $replace $lines[$i] $NewId $false; $sawId = $true }
        elseif ($key -ceq 'THEME_NAME') { $lines[$i] = & $replace $lines[$i] $DisplayName $true; $sawName = $true }
        elseif ($changes.ContainsKey($key)) { $lines[$i] = & $replace $lines[$i] $changes[$key] $false }
    }
    $header = [Collections.Generic.List[string]]::new()
    $header.Add("# Derived from '$SourceId' by the Typezero ThemeEngine color editor.")
    if (-not $sawId) { $header.Add("THEME_ID=$NewId") }
    if (-not $sawName) { $header.Add("THEME_NAME=`"$DisplayName`"") }
    $lines.InsertRange(0, $header)
    $text = ($lines -join $newline) + $newline

    # Self-check: the result must parse to the source values plus exactly the
    # requested changes, under the shared parsing rules.
    $before = ConvertFrom-TypezeroThemeConfText -Text $SourceText
    $after = ConvertFrom-TypezeroThemeConfText -Text $text
    foreach ($key in $before.Keys) {
        $expected = if ($key -ceq 'THEME_ID') { $NewId } elseif ($key -ceq 'THEME_NAME') { $DisplayName }
                    elseif ($changes.ContainsKey($key)) { $changes[$key] } else { $before[$key] }
        if (-not $after.Contains($key) -or [string]$after[$key] -cne [string]$expected) {
            throw "Derived theme verification failed for $key."
        }
    }
    if ($after['THEME_ID'] -cne $NewId -or $after['THEME_NAME'] -cne $DisplayName) { throw 'Derived theme identity verification failed.' }
    return $text
}

function Resolve-TypezeroSharedThemesRoot {
    # The editor module lives in <repo>\Netzach\PowerShell\ThemeEngine.
    param([string]$EngineDirectory = $PSScriptRoot)
    $candidate = [IO.Path]::GetFullPath((Join-Path $EngineDirectory '..\..\..\ThemeEngine\themes'))
    $template = Join-Path (Split-Path -Parent $candidate) 'theme.conf.template'
    if ((Test-Path -LiteralPath $candidate -PathType Container) -and (Test-Path -LiteralPath $template -PathType Leaf)) {
        return $candidate
    }
    return $null
}

function Write-TypezeroNewThemeFile {
    param([Parameter(Mandatory)][string]$Directory, [Parameter(Mandatory)][byte[]]$Bytes)
    if (Test-Path -LiteralPath $Directory) { throw "Theme folder already exists: $Directory" }
    [void][IO.Directory]::CreateDirectory($Directory)
    $path = Join-Path $Directory 'theme.conf'
    $stream = [IO.FileStream]::new($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($Bytes, 0, $Bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
    $readBack = [IO.File]::ReadAllBytes($path)
    if ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($readBack)) -cne
        [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes))) {
        throw "Read-back verification failed: $path"
    }
    return $path
}

function Save-TypezeroDerivedTheme {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$InstalledThemesRoot,
        [AllowEmptyString()][string]$SharedThemesRoot,
        [Parameter(Mandatory)][string]$SourceId,
        [Parameter(Mandatory)][string]$NewId,
        [Parameter(Mandatory)][string]$DisplayName,
        [Collections.IDictionary]$Colors = @{}
    )
    if (-not $SharedThemesRoot -or -not (Test-Path -LiteralPath $SharedThemesRoot -PathType Container)) {
        throw 'Shared ThemeEngine/themes source not found. Run ThemeEngine from the repository checkout so the new theme survives bootstrap and reaches Arakiel.'
    }
    if (-not (Test-Path -LiteralPath $InstalledThemesRoot -PathType Container)) { throw "Installed themes not found: $InstalledThemesRoot" }
    if (-not (Test-TypezeroThemeId $SourceId)) { throw "Invalid source theme id: '$SourceId'." }
    if (-not (Test-TypezeroThemeId $NewId)) { throw "Invalid theme id: '$NewId'. Use 1-64 lowercase letters, numbers or hyphens." }
    $sharedTarget = Join-Path $SharedThemesRoot $NewId
    $installedTarget = Join-Path $InstalledThemesRoot $NewId
    foreach ($target in @($sharedTarget, $installedTarget)) {
        if (Test-Path -LiteralPath $target) { throw "Theme '$NewId' already exists: $target" }
    }
    # Edit what the window displays: the installed copy of the source theme.
    $sourcePath = Join-Path (Join-Path $InstalledThemesRoot $SourceId) 'theme.conf'
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw "Source theme not found: $sourcePath" }
    $sourceBytes = [IO.File]::ReadAllBytes($sourcePath)
    $sourceHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($sourceBytes))
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    $offset = if ($sourceBytes.Length -ge 3 -and $sourceBytes[0] -eq 0xEF -and $sourceBytes[1] -eq 0xBB -and $sourceBytes[2] -eq 0xBF) { 3 } else { 0 }
    $sourceText = $utf8.GetString($sourceBytes, $offset, $sourceBytes.Length - $offset)
    # Shared files are LF (.gitattributes eol=lf) and read by bash on Arakiel.
    $text = New-TypezeroDerivedThemeText -SourceText ($sourceText -replace "`r`n", "`n") -SourceId $SourceId `
        -NewId $NewId -DisplayName $DisplayName -Colors $Colors
    $bytes = $utf8.GetBytes($text)

    $sharedPath = Write-TypezeroNewThemeFile -Directory $sharedTarget -Bytes $bytes
    try {
        $installedPath = Write-TypezeroNewThemeFile -Directory $installedTarget -Bytes $bytes
    } catch {
        return [pscustomobject]@{
            Status = 'SavedSharedOnly'; Id = $NewId; SharedPath = $sharedPath; InstalledPath = $null
            Sha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
            Message = "Saved '$NewId' to the shared source, but the installed copy failed: $($_.Exception.Message) Run bootstrap to install it."
        }
    }
    if ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes($sourcePath))) -cne $sourceHash) {
        throw "Source theme '$SourceId' changed during save; review both copies of '$NewId'."
    }
    return [pscustomobject]@{
        Status = 'Saved'; Id = $NewId; SharedPath = $sharedPath; InstalledPath = $installedPath
        Sha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
        Message = "Saved new theme '$NewId'. Use the Apply buttons to activate it."
    }
}
