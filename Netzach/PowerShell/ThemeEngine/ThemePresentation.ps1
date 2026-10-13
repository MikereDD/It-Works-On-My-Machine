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
