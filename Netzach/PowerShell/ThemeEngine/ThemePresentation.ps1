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

function Format-TypezeroCurrentTheme {
    [CmdletBinding()]
    param(
        [string]$Id = '',
        [System.Collections.IDictionary]$Theme = $null
    )

    $clean = {
        param($Value)
        return (([string]$Value) -replace
            '[\x00-\x1F\x7F-\x9F]', '?').Trim()
    }

    $lines = [Collections.Generic.List[string]]::new()

    $lines.Add('')
    $lines.Add('TYPEZERO / CURRENT THEME')
    $lines.Add('-----------------------------------------------')

    if ([string]::IsNullOrWhiteSpace($Id)) {
        if ($null -ne $Theme) {
            throw 'Theme data supplied without selected ID.'
        }

        $lines.Add('Selected ID: none')
        $lines.Add('No theme is currently selected.')
        $lines.Add('Action: READ ONLY')
        $lines.Add('')

        return ($lines -join [Environment]::NewLine)
    }

    if ($null -eq $Theme) {
        throw 'Selected theme data is missing.'
    }

    $safeId = & $clean $Id
    $name = & $clean $Theme['THEME_NAME']

    if (-not $name) {
        $name = $safeId
    }

    $esc = [char]27

    $swatches = @(
        foreach ($role in @('BG', 'SURFACE', 'ACCENT', 'TEXT')) {
            $hex = [string]$Theme[$role]

            if ($hex -cnotmatch '^#[0-9A-Fa-f]{6}$') {
                throw "Invalid current theme color: $safeId/$role"
            }

            $r = [Convert]::ToInt32($hex.Substring(1, 2), 16)
            $g = [Convert]::ToInt32($hex.Substring(3, 2), 16)
            $b = [Convert]::ToInt32($hex.Substring(5, 2), 16)

            "${esc}[48;2;${r};${g};${b}m    ${esc}[0m"
        }
    )

    $fontFamily = & $clean $Theme['FONT_FAMILY']
    $fontStyle = & $clean $Theme['FONT_STYLE']

    if (-not $fontFamily) { $fontFamily = 'unspecified' }
    if (-not $fontStyle) { $fontStyle = 'unspecified' }

    $lines.Add("Selected ID: $safeId")
    $lines.Add("Theme name:  $name")
    $lines.Add('')
    $lines.Add('PALETTE')
    $lines.Add(($swatches -join '  '))
    $lines.Add('BG     SURFACE  ACCENT  TEXT')
    $lines.Add('')
    $lines.Add('THEME TYPOGRAPHY (DECLARED)')
    $lines.Add("Family: $fontFamily")
    $lines.Add("Style:  $fontStyle")
    $lines.Add('')
    $lines.Add('Selection and theme metadata only.')
    $lines.Add('Terminal activation and font application not verified.')
    $lines.Add('Action: READ ONLY')
    $lines.Add('')

    return ($lines -join [Environment]::NewLine)
}

function Format-TypezeroDoctor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Sections
    )

    if ($Sections.Count -eq 0) {
        throw 'Doctor report has no sections.'
    }

    $clean = {
        param($Value)
        return (([string]$Value) -replace
            '[\x00-\x1F\x7F-\x9F]', '?').Trim()
    }

    $esc = [char]27
    $reset = "${esc}[0m"

    $colors = @{
        PASS = "${esc}[92m"
        WARN = "${esc}[93m"
        FAIL = "${esc}[91m"
        INFO = "${esc}[96m"
    }

    $lines = [Collections.Generic.List[string]]::new()

    $lines.Add('')
    $lines.Add('TYPEZERO / SYSTEM DOCTOR')
    $lines.Add('-----------------------------------------------')
    $lines.Add('')

    foreach ($section in $Sections) {
        if ($null -eq $section) {
            throw 'Invalid doctor section.'
        }

        $heading = & $clean $section.Name

        if ([string]::IsNullOrWhiteSpace($heading) -or
            $null -eq $section.Items) {
            throw 'Invalid doctor section.'
        }

        $items = @($section.Items)

        if ($items.Count -eq 0) {
            throw "Empty doctor section: $heading"
        }

        $lines.Add("[$heading]")

        foreach ($item in $items) {
            if ($null -eq $item) {
                throw 'Invalid doctor check.'
            }

            $status = [string]$item.Status

            if ($status -cnotin @('PASS', 'WARN', 'FAIL', 'INFO')) {
                throw "Unsupported doctor status: $status"
            }

            $label = & $clean $item.Label
            $value = & $clean $item.Value

            if ([string]::IsNullOrWhiteSpace($label)) {
                throw 'Doctor check label is missing.'
            }

            $lines.Add(
                ('  {0}{1}{2}  {3,-24} {4}' -f
                    $colors[$status],
                    $status,
                    $reset,
                    $label,
                    $value)
            )
        }

        $lines.Add('')
    }

    $lines.Add('Presentation only; findings supplied by caller.')
    $lines.Add('Action: READ ONLY')
    $lines.Add('')

    return ($lines -join [Environment]::NewLine)
}

function ConvertTo-TypezeroDoctorSections {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [AllowEmptyCollection()]
        [string[]]$Lines
    )

    if ($null -eq $Lines -or $Lines.Count -eq 0) {
        throw 'Doctor transcript is empty.'
    }

    # Pure adapter: no system probes or configuration writes.
    $fields = [ordered]@{
        'CORE' = @(
            'themes', 'current', 'renderer',
            'current.ps1', 'terminal'
        )
        'WINDOWS APPEARANCE' = @(
            'native provider', 'accent policy',
            'accent mode', 'windows theme',
            'transparency', 'titlebar accent',
            'taskbar accent', 'DisplayFusion'
        )
        'WALLPAPER / DISPLAYFUSION' = @(
            'CLI module', 'integration', 'mapped themes',
            'active profile', 'wallpaper status',
            'wallpaper provider'
        )
    }

    $sections = @(
        foreach ($name in $fields.Keys) {
            [pscustomobject]@{
                Name = $name
                Items = [Collections.Generic.List[object]]::new()
            }
        }
    )

    $sectionName = 'CORE'
    $headerSeen = $false
    $seen = @{}

    foreach ($entry in $Lines) {
        foreach ($raw in (([string]$entry) -split "\r\n|\n|\r")) {
            $line = $raw.Trim()

            if (-not $line) { continue }

            if ($line -ceq 'ThemeEngine doctor') {
                if ($headerSeen) {
                    throw 'Duplicate doctor transcript header.'
                }
                $headerSeen = $true
                $sectionName = 'CORE'
                continue
            }

            if (-not $headerSeen) {
                throw 'Doctor transcript header is missing.'
            }

            if ($line -ceq 'Windows Appearance') {
                $sectionName = 'WINDOWS APPEARANCE'
                continue
            }

            if ($line -ceq 'Wallpaper Integration') {
                $sectionName = 'WALLPAPER / DISPLAYFUSION'
                continue
            }

            $matched = $false

            foreach ($label in $fields[$sectionName]) {
                $pattern = '^' + [regex]::Escape($label) + '\s+(.+)$'

                $hit = [regex]::Match(
                    $line,
                    $pattern,
                    [Text.RegularExpressions.RegexOptions]::IgnoreCase
                )

                if (-not $hit.Success) { continue }

                $value = $hit.Groups[1].Value.Trim()
                $key = "$sectionName|$label"

                if ($seen.ContainsKey($key)) {
                    throw "Duplicate doctor finding: $key"
                }

                $seen[$key] = $true
                $status = 'INFO'

                if ($label -cin @('themes', 'current.ps1')) {
                    if ($value -ceq 'PASS') {
                        $status = 'PASS'
                    }
                    elseif ($value -ceq 'MISSING') {
                        $status = 'FAIL'
                    }
                    else {
                        $status = 'WARN'
                    }
                }
                elseif ($label -cin @(
                    'terminal', 'native provider',
                    'CLI module', 'wallpaper provider'
                )) {
                    if ($value -ceq 'PASS') {
                        $status = 'PASS'
                    }
                    elseif ($value -cin @('MISSING', 'NOT FOUND')) {
                        $status = 'WARN'
                    }
                }
                elseif ($label -ceq 'accent policy') {
                    if ($value -match '^INVALID\b') {
                        $status = 'WARN'
                    }
                }
                elseif ($label -ceq 'accent mode') {
                    if ($value -match '^PASS\b') {
                        $status = 'PASS'
                    }
                    elseif ($value -match '^WARN\b') {
                        $status = 'WARN'
                    }
                }
                elseif ($label -ceq 'wallpaper status') {
                    if ($value -match '^ERROR:') {
                        $status = 'FAIL'
                    }
                    else {
                        $status = 'WARN'
                    }
                }

                $target = @($sections | Where-Object {
                    $_.Name -ceq $sectionName
                })

                if ($target.Count -ne 1) {
                    throw 'Doctor section inventory mismatch.'
                }

                $target[0].Items.Add([pscustomobject]@{
                    Status = $status
                    Label = $label
                    Value = $value
                })

                $matched = $true
                break
            }

            if (-not $matched) {
                throw "Unrecognized doctor output: $line"
            }
        }
    }

    if (-not $headerSeen) {
        throw 'Doctor transcript header is missing.'
    }

    foreach ($section in $sections) {
        if ($section.Items.Count -eq 0) {
            throw "Doctor section has no findings: $($section.Name)"
        }
    }

    # Require every diagnostic emitted on all legacy paths.
    # Use the adapter's existing seen map; no system probes.
    $required = [ordered]@{
        'CORE' = @(
            'themes', 'current', 'renderer',
            'current.ps1', 'terminal'
        )
        'WINDOWS APPEARANCE' = @(
            'native provider', 'accent policy', 'accent mode',
            'windows theme', 'transparency', 'titlebar accent',
            'taskbar accent', 'DisplayFusion'
        )
        'WALLPAPER / DISPLAYFUSION' = @(
            'CLI module'
        )
    }

    foreach ($sectionNameRequired in $required.Keys) {
        foreach ($labelRequired in $required[$sectionNameRequired]) {
            $keyRequired = "$sectionNameRequired|$labelRequired"

            if (-not $seen.ContainsKey($keyRequired)) {
                throw "Missing doctor finding: $keyRequired"
            }
        }
    }

    # Legacy wallpaper logic has exactly three valid outcomes:
    # success (three fields), missing provider, or provider error.
    $wpSection = 'WALLPAPER / DISPLAYFUSION'

    $successLabels = @(
        'integration', 'mapped themes', 'active profile'
    )

    $successCount = 0

    foreach ($labelRequired in $successLabels) {
        if ($seen.ContainsKey("$wpSection|$labelRequired")) {
            $successCount++
        }
    }

    $providerMissing = $seen.ContainsKey(
        "$wpSection|wallpaper provider"
    )

    $providerError = $seen.ContainsKey(
        "$wpSection|wallpaper status"
    )

    if ($providerMissing -and $providerError) {
        throw 'Ambiguous doctor wallpaper branch.'
    }

    $validSuccess = (
        $successCount -eq 3 -and
        -not $providerMissing -and
        -not $providerError
    )

    $validAlternative = (
        $successCount -eq 0 -and
        ($providerMissing -xor $providerError)
    )

    if (-not ($validSuccess -or $validAlternative)) {
        throw 'Incomplete or conflicting doctor wallpaper branch.'
    }
    return $sections
}
