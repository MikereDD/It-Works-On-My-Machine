# Typezero ThemeEngine
# Pure Windows Terminal JSONC color transformation. No disk writes.
# Existing Typezero-owned objects only. Fails closed on unsupported layouts.

function New-TypezeroTerminalColorJsonCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JsonText,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Theme
    )

    $required = @(
        'THEME_NAME', 'BG', 'TEXT', 'CURSOR', 'SELECTION',
        'ANSI_BLACK', 'ANSI_RED', 'ANSI_GREEN', 'ANSI_YELLOW',
        'ANSI_BLUE', 'ANSI_PURPLE', 'ANSI_CYAN', 'ANSI_WHITE',
        'ANSI_BRIGHT_BLACK', 'ANSI_BRIGHT_RED',
        'ANSI_BRIGHT_GREEN', 'ANSI_BRIGHT_YELLOW',
        'ANSI_BRIGHT_BLUE', 'ANSI_BRIGHT_PURPLE',
        'ANSI_BRIGHT_CYAN', 'ANSI_BRIGHT_WHITE'
    )

    foreach ($key in $required) {
        if (-not $Theme.Contains($key) -or
            [string]::IsNullOrWhiteSpace([string]$Theme[$key])) {
            throw "Incomplete Terminal color theme: $key"
        }
    }

    $schemeName = 'Typezero ' + [string]$Theme['THEME_NAME']
    $terminalThemeName = 'Typezero ThemeEngine'
    $guid = '{574e775e-4f2a-5b96-ac1e-a2962a402336}'

    $scheme = [ordered]@{
        name                = $schemeName
        background          = $Theme['BG']
        foreground          = $Theme['TEXT']
        cursorColor         = $Theme['CURSOR']
        selectionBackground = $Theme['SELECTION']
        black               = $Theme['ANSI_BLACK']
        red                 = $Theme['ANSI_RED']
        green               = $Theme['ANSI_GREEN']
        yellow              = $Theme['ANSI_YELLOW']
        blue                = $Theme['ANSI_BLUE']
        purple              = $Theme['ANSI_PURPLE']
        cyan                = $Theme['ANSI_CYAN']
        white               = $Theme['ANSI_WHITE']
        brightBlack         = $Theme['ANSI_BRIGHT_BLACK']
        brightRed           = $Theme['ANSI_BRIGHT_RED']
        brightGreen         = $Theme['ANSI_BRIGHT_GREEN']
        brightYellow        = $Theme['ANSI_BRIGHT_YELLOW']
        brightBlue          = $Theme['ANSI_BRIGHT_BLUE']
        brightPurple        = $Theme['ANSI_BRIGHT_PURPLE']
        brightCyan          = $Theme['ANSI_BRIGHT_CYAN']
        brightWhite         = $Theme['ANSI_BRIGHT_WHITE']
    }

    $terminalTheme = [ordered]@{
        name = $terminalThemeName
        window = [ordered]@{
            applicationTheme = 'dark'
        }
        tab = [ordered]@{
            background          = 'terminalBackground'
            unfocusedBackground = $Theme['BG']
            showCloseButton     = 'hover'
        }
        tabRow = [ordered]@{
            background          = $Theme['BG']
            unfocusedBackground = $Theme['BG']
        }
    }

    $options = [Text.Json.JsonDocumentOptions]::new()
    $options.CommentHandling = [Text.Json.JsonCommentHandling]::Skip
    $options.AllowTrailingCommas = $true

    $doc = [Text.Json.JsonDocument]::Parse($JsonText, $options)
    $candidateDoc = $null

    try {
        $root = $doc.RootElement

        if ($root.GetProperty('theme').GetString() -cne
            $terminalThemeName) {
            throw 'Unexpected active Terminal application theme.'
        }

        $schemeMatches = @(
            foreach ($item in $root.GetProperty('schemes').EnumerateArray()) {
                if ($item.GetProperty('name').GetString() -ceq $schemeName) {
                    $item
                }
            }
        )

        $themeMatches = @(
            foreach ($item in $root.GetProperty('themes').EnumerateArray()) {
                if ($item.GetProperty('name').GetString() -ceq
                    $terminalThemeName) {
                    $item
                }
            }
        )

        $profileMatches = @(
            foreach ($item in $root.GetProperty('profiles').
                GetProperty('list').EnumerateArray()) {

                $profileGuid = [Text.Json.JsonElement]::new()

                if ($item.TryGetProperty('guid', [ref]$profileGuid) -and
                    $profileGuid.GetString() -ieq $guid) {
                    $item
                }
            }
        )

        if ($schemeMatches.Count -ne 1 -or
            $themeMatches.Count -ne 1 -or
            $profileMatches.Count -ne 1) {
            throw 'Target Terminal objects were not uniquely identified.'
        }

        $oldScheme = $schemeMatches[0].GetRawText()
        $oldTheme = $themeMatches[0].GetRawText()
        $oldProfile = $profileMatches[0].GetRawText()

        # Preserve additional Typezero-owned properties.
        # Only known ThemeEngine palette and chrome fields are updated.
        # Comments inside these objects remain unsupported and are
        # rejected by the existing safety guard above.
        $mergedScheme = $oldScheme | ConvertFrom-Json -AsHashtable
        $mergedTheme = $oldTheme | ConvertFrom-Json -AsHashtable

        foreach ($entry in $scheme.GetEnumerator()) {
            $mergedScheme[$entry.Key] = $entry.Value
        }

        foreach ($section in $terminalTheme.GetEnumerator()) {
            if ($section.Value -is [System.Collections.IDictionary] -and
                $mergedTheme[$section.Key] -is [System.Collections.IDictionary]) {

                foreach ($field in $section.Value.GetEnumerator()) {
                    $mergedTheme[$section.Key][$field.Key] = $field.Value
                }
            }
            else {
                $mergedTheme[$section.Key] = $section.Value
            }
        }

        $scheme = $mergedScheme
        $terminalTheme = $mergedTheme

        # Replacing a Typezero-owned object must not destroy comments.
        if ($oldScheme -match '//|/\*' -or
            $oldTheme -match '//|/\*') {
            throw 'Comments inside a Typezero-owned object need a narrower patch.'
        }

        $currentColor = [Text.Json.JsonElement]::new()

        if (-not $profileMatches[0].TryGetProperty(
            'colorScheme', [ref]$currentColor
        )) {
            throw 'PowerShell profile has no colorScheme property.'
        }

        $pattern = '(?<prefix>"colorScheme"\s*:\s*)' +
            '(?<value>"(?:\\.|[^"\\])*")'

        $colorMatches = [regex]::Matches($oldProfile, $pattern)

        if ($colorMatches.Count -ne 1) {
            throw 'PowerShell colorScheme text is ambiguous.'
        }

        $valueMatch = $colorMatches[0].Groups['value']

        if ($valueMatch.Value -cne $currentColor.GetRawText()) {
            throw 'PowerShell colorScheme source did not match JSONC.'
        }

        $newColorValue = ConvertTo-Json `
            -InputObject $schemeName -Compress

        $newProfile = $oldProfile.Substring(0, $valueMatch.Index) +
            $newColorValue +
            $oldProfile.Substring($valueMatch.Index + $valueMatch.Length)

        $patches = @(
            [pscustomobject]@{
                Name = 'Scheme'
                Old  = $oldScheme
                New  = (ConvertTo-Json -InputObject $scheme -Depth 20 -Compress)
            }
            [pscustomobject]@{
                Name = 'Application theme'
                Old  = $oldTheme
                New  = (ConvertTo-Json -InputObject $terminalTheme -Depth 20 -Compress)
            }
            [pscustomobject]@{
                Name = 'PowerShell profile'
                Old  = $oldProfile
                New  = $newProfile
            }
        )

        $ranges = @(
            foreach ($patch in $patches) {
                $index = $JsonText.IndexOf(
                    $patch.Old, [StringComparison]::Ordinal
                )

                if ($index -lt 0 -or $index -ne $JsonText.LastIndexOf(
                    $patch.Old, [StringComparison]::Ordinal
                )) {
                    throw "Source block not unique: $($patch.Name)"
                }

                [pscustomobject]@{
                    Name   = $patch.Name
                    Start  = $index
                    Length = $patch.Old.Length
                    Text   = $patch.New
                }
            }
        )

        $ascending = @($ranges | Sort-Object Start)

        for ($i = 1; $i -lt $ascending.Count; $i++) {
            if ($ascending[$i].Start -lt (
                $ascending[$i - 1].Start + $ascending[$i - 1].Length
            )) {
                throw 'JSONC replacement ranges overlap.'
            }
        }

        $candidate = $JsonText

        foreach ($patch in ($ranges | Sort-Object Start -Descending)) {
            $candidate = $candidate.Substring(0, $patch.Start) +
                $patch.Text +
                $candidate.Substring($patch.Start + $patch.Length)
        }

        $candidateDoc = [Text.Json.JsonDocument]::Parse(
            $candidate, $options
        )

        $resultRoot = $candidateDoc.RootElement

        $resultProfile = @(
            foreach ($item in $resultRoot.GetProperty('profiles').
                GetProperty('list').EnumerateArray()) {

                $profileGuid = [Text.Json.JsonElement]::new()

                if ($item.TryGetProperty('guid', [ref]$profileGuid) -and
                    $profileGuid.GetString() -ieq $guid) {
                    $item
                }
            }
        )

        if ($resultProfile.Count -ne 1 -or
            $resultProfile[0].GetProperty('colorScheme').GetString() -cne
            $schemeName) {
            throw 'Updated profile failed validation.'
        }

        if ($JsonText.Contains('/* TYPEZERO_FONT_V2 */') -and
            -not $candidate.Contains('/* TYPEZERO_FONT_V2 */')) {
            throw 'Font ownership marker was lost.'
        }

        return $candidate
    }
    finally {
        if ($null -ne $candidateDoc) {
            $candidateDoc.Dispose()
        }
        $doc.Dispose()
    }
}
