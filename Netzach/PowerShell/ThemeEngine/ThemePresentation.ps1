# Typezero ThemeEngine - ANSI theme presentation
# Pure formatter. No theme application or settings writes.

function Format-TypezeroThemePreview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Theme,

        [Parameter(Mandatory)]
        [string]$Id
    )

    $sections = [ordered]@{
        STRUCTURE = @(
            'BG', 'SURFACE', 'SURFACE_ALT',
            'BORDER', 'TEXT', 'BRIGHT', 'MUTED'
        )
        IDENTITY = @(
            'ACCENT', 'ACCENT_BRIGHT', 'SECONDARY', 'INFO'
        )
        INTERACTION = @(
            'SELECTION', 'CURSOR', 'FOCUS'
        )
        FEEDBACK = @(
            'SUCCESS', 'WARNING', 'ERROR'
        )
    }

    $clean = {
        param($Value)

        $text = ([string]$Value) -replace '[\x00-\x1F\x7F-\x9F]', '?'

        if ($text.Length -gt 100) {
            return $text.Substring(0, 100)
        }

        return $text
    }

    $lines = [Collections.Generic.List[string]]::new()
    $esc = [char]27

    $name = & $clean $Theme['THEME_NAME']
    $idText = & $clean $Id
    $family = & $clean $Theme['FONT_FAMILY']
    $style = & $clean $Theme['FONT_STYLE']

    $lines.Add('')
    $lines.Add('TYPEZERO / THEMEENGINE')
    $lines.Add("THEME: $name ($idText)")
    $lines.Add('PREVIEW ONLY - no changes applied')

    foreach ($section in $sections.Keys) {
        $lines.Add('')
        $lines.Add("[$section]")

        foreach ($role in $sections[$section]) {
            $hex = [string]$Theme[$role]

            if ($hex -cnotmatch '^#[0-9A-Fa-f]{6}$') {
                throw "Invalid theme color: $role"
            }

            $r = [Convert]::ToInt32($hex.Substring(1, 2), 16)
            $g = [Convert]::ToInt32($hex.Substring(3, 2), 16)
            $b = [Convert]::ToInt32($hex.Substring(5, 2), 16)

            $swatch = "${esc}[48;2;${r};${g};${b}m    ${esc}[0m"

            $lines.Add(
                ('  {0,-16} {1}  {2}' -f $role, $swatch, $hex)
            )
        }
    }

    $lines.Add('')
    $lines.Add('[THEME TYPOGRAPHY]')
    $lines.Add("  Family: $family")
    $lines.Add("  Style:  $style")
    $lines.Add('  Source: theme.conf')
    $lines.Add('')
    $lines.Add('Windows Terminal typography is managed separately.')
    $lines.Add('Action: PREVIEW ONLY')
    $lines.Add('')

    return ($lines -join [Environment]::NewLine)
}

function Format-TypezeroThemeCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Entries,

        [string]$CurrentId = ''
    )

    if ($Entries.Count -eq 0) {
        throw 'Empty theme catalog.'
    }

    $lines = [Collections.Generic.List[string]]::new()
    $seen = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )
    $esc = [char]27

    $clean = {
        param($Value)
        return (([string]$Value) -replace '[\x00-\x1F\x7F-\x9F]', '?')
    }

    $selected = & $clean $CurrentId
    if (-not $selected) { $selected = 'none' }

    $lines.Add('')
    $lines.Add('TYPEZERO / THEME CATALOG')
    $lines.Add('-----------------------------------------------')
    $lines.Add("Available: $($Entries.Count)")
    $lines.Add("Selected: $selected")
    $lines.Add('')

    foreach ($entry in $Entries) {
        $id = [string]$entry.Id
        $theme = $entry.Theme

        if ([string]::IsNullOrWhiteSpace($id) -or
            $theme -isnot [Collections.IDictionary]) {
            throw 'Invalid theme catalog entry.'
        }

        if (-not $seen.Add($id)) {
            throw "Duplicate theme ID: $id"
        }

        $name = & $clean $theme['THEME_NAME']
        if (-not $name) { $name = & $clean $id }
        if ($name.Length -gt 25) {
            $name = $name.Substring(0, 25)
        }

        $swatches = @(
            foreach ($role in @('BG', 'ACCENT')) {
                $hex = [string]$theme[$role]

                if ($hex -cnotmatch '^#[0-9A-Fa-f]{6}$') {
                    throw "Invalid catalog color: $id/$role"
                }

                $r = [Convert]::ToInt32($hex.Substring(1, 2), 16)
                $g = [Convert]::ToInt32($hex.Substring(3, 2), 16)
                $b = [Convert]::ToInt32($hex.Substring(5, 2), 16)

                "${esc}[48;2;${r};${g};${b}m    ${esc}[0m"
            }
        )

        $marker = if ($id -ceq $CurrentId) { '*' } else { ' ' }
        $safeId = & $clean $id

        $lines.Add(
            ('{0} {1,-26} {2} {3}  {4}' -f
                $marker, $name, $swatches[0], $swatches[1], $safeId)
        )
    }

    $lines.Add('')
    $lines.Add('* = currently selected theme')
    $lines.Add('Swatches: background / accent')
    $lines.Add('Action: CATALOG PREVIEW ONLY')
    $lines.Add('')

    return ($lines -join [Environment]::NewLine)
}
