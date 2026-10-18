# Typezero ThemeEngine / Step 57F.21
# Pure preview-only bridge between Read-ThemeFile's semantic dictionary and
# existing JSONC-preserving font/color helpers. NO FILESYSTEM WRITES.
# No CLI registration, no opt-in mutation and no production activation.
# Dot-source FontWriter, TerminalColorCompat, and TerminalUnified first.

function New-TypezeroTerminalThemeBridgeText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Theme,
        [Parameter(Mandatory)][psobject]$FontConfig,
        [ValidateRange(6,36)][double]$InheritedSize = 12,
        [ValidateSet('normal','semi-bold')][string]$InheritedWeight = 'normal',
        [switch]$PreviewMappedFont
    )

    foreach ($key in @('THEME_ID','THEME_NAME','BG','TEXT','CURSOR','SELECTION',
        'ANSI_BLACK','ANSI_RED','ANSI_GREEN','ANSI_YELLOW','ANSI_BLUE',
        'ANSI_PURPLE','ANSI_CYAN','ANSI_WHITE','ANSI_BRIGHT_BLACK',
        'ANSI_BRIGHT_RED','ANSI_BRIGHT_GREEN','ANSI_BRIGHT_YELLOW',
        'ANSI_BRIGHT_BLUE','ANSI_BRIGHT_PURPLE','ANSI_BRIGHT_CYAN',
        'ANSI_BRIGHT_WHITE')) {
        if (-not $Theme.Contains($key)) { throw "Theme lacks required Terminal role: $key" }
    }

    $themeId = [string]$Theme['THEME_ID']
    $themeName = [string]$Theme['THEME_NAME']
    if ($themeId -cnotmatch '\A[a-z0-9][a-z0-9-]*\z') {
        throw 'Invalid ThemeEngine theme ID.'
    }
    $schemeName = 'Typezero ' + $themeName
    if ($schemeName -cnotmatch '\ATypezero [A-Za-z0-9][A-Za-z0-9 ._\x27-]*\z') {
        throw 'Unsupported managed Terminal scheme name.'
    }

    $roles = [ordered]@{
        background          = 'BG'
        foreground          = 'TEXT'
        cursorColor         = 'CURSOR'
        selectionBackground = 'SELECTION'
        black               = 'ANSI_BLACK'
        red                 = 'ANSI_RED'
        green               = 'ANSI_GREEN'
        yellow              = 'ANSI_YELLOW'
        blue                = 'ANSI_BLUE'
        purple              = 'ANSI_PURPLE'
        cyan                = 'ANSI_CYAN'
        white               = 'ANSI_WHITE'
        brightBlack         = 'ANSI_BRIGHT_BLACK'
        brightRed           = 'ANSI_BRIGHT_RED'
        brightGreen         = 'ANSI_BRIGHT_GREEN'
        brightYellow        = 'ANSI_BRIGHT_YELLOW'
        brightBlue          = 'ANSI_BRIGHT_BLUE'
        brightPurple        = 'ANSI_BRIGHT_PURPLE'
        brightCyan          = 'ANSI_BRIGHT_CYAN'
        brightWhite         = 'ANSI_BRIGHT_WHITE'
    }
    foreach ($key in $roles.Keys) {
        if ([string]$Theme[$roles[$key]] -cnotmatch '\A#[0-9A-Fa-f]{6}\z') {
            throw "Invalid RGB color for $($roles[$key])"
        }
    }

    $version = [int]$FontConfig.Version
    if ($version -notin @(1,2) -or $FontConfig.Enabled -isnot [bool] -or
        $FontConfig.Mappings -isnot [System.Collections.IDictionary]) {
        throw 'Invalid validated font configuration.'
    }
    if ($FontConfig.Enabled -and -not $PreviewMappedFont) {
        throw 'Mapped typography preview requires explicit -PreviewMappedFont.'
    }
    if (-not $FontConfig.Enabled -and $PreviewMappedFont) {
        throw 'Typography preview refused while font integration is disabled.'
    }

    $options = [Text.Json.JsonDocumentOptions]::new()
    $options.AllowTrailingCommas = $true
    $options.CommentHandling = [Text.Json.JsonCommentHandling]::Skip
    $doc = [Text.Json.JsonDocument]::Parse($Text, $options)
    try {
        $root = $doc.RootElement
        if ($root.GetProperty('theme').GetString() -cne 'Typezero ThemeEngine') {
            throw 'Active Terminal application theme is not Typezero-managed.'
        }
    }
    finally { $doc.Dispose() }

    # Refresh the full existing managed scheme from Read-ThemeFile's palette.
    # Never add a scheme implicitly, overwrite a foreign scheme, or reformat
    # unrelated JSONC. Preserve any extra user properties on the owned entry.
    $oldSchemeRaw = Get-TypezeroUnifiedOwnedEntry -Text $Text `
        -Collection schemes -Name $schemeName
    $scheme = ConvertFrom-Json -InputObject $oldSchemeRaw -Depth 100
    foreach ($key in $roles.Keys) {
        $property = $scheme.PSObject.Properties[[string]$key]
        if ($null -eq $property) { throw "Owned color scheme lacks field: $key" }
        $property.Value = [string]$Theme[$roles[$key]]
    }
    $newSchemeRaw = ConvertTo-Json -InputObject $scheme -Compress -Depth 100
    $candidate = $Text
    if ($oldSchemeRaw -cne $newSchemeRaw) {
        $candidate = Set-TypezeroTerminalOwnedElementText -Text $candidate `
            -Collection schemes -Name $schemeName -Replacement $newSchemeRaw
    }

    # Update only chrome colors controlled by the old ThemeEngine writer.
    # Keep tab behavior, window properties, extras and other themes intact.
    $appName = 'Typezero ThemeEngine'
    $oldAppRaw = Get-TypezeroUnifiedOwnedEntry -Text $candidate `
        -Collection themes -Name $appName
    $app = ConvertFrom-Json -InputObject $oldAppRaw -Depth 100
    foreach ($field in @('background','unfocusedBackground')) {
        if ($null -eq $app.tabRow -or
            $null -eq $app.tabRow.PSObject.Properties[$field]) {
            throw "Managed Terminal tabRow lacks $field"
        }
        $app.tabRow.PSObject.Properties[$field].Value = [string]$Theme['BG']
    }
    if ($null -eq $app.tab -or
        $null -eq $app.tab.PSObject.Properties['unfocusedBackground']) {
        throw 'Managed Terminal tab lacks unfocusedBackground.'
    }
    $app.tab.PSObject.Properties['unfocusedBackground'].Value = [string]$Theme['BG']
    $newAppRaw = ConvertTo-Json -InputObject $app -Compress -Depth 100
    if ($oldAppRaw -cne $newAppRaw) {
        $candidate = Set-TypezeroTerminalOwnedElementText -Text $candidate `
            -Collection themes -Name $appName -Replacement $newAppRaw
    }

    $oldSchemeRef = (Get-TypezeroTerminalColorSchemeTextSpan -Text $candidate).Value
    if ($oldSchemeRef -cne $schemeName) {
        $candidate = Set-TypezeroTerminalProfileColorSchemeText `
            -Text $candidate -SchemeName $schemeName
    }

    $beforeFont = Get-TypezeroFontProfileTextSnapshot -Text $candidate
    if ($FontConfig.Enabled) {
        if (-not $FontConfig.Mappings.Contains($themeId)) {
            throw "Enabled font mapping missing for theme: $themeId"
        }
        $mapped = $FontConfig.Mappings[$themeId]
        if ($version -eq 1) {
            if ($mapped -isnot [string]) { throw 'Invalid v1 font mapping.' }
            $family = [string]$mapped
            $size = $InheritedSize
            $weight = $InheritedWeight
        }
        else {
            if ($null -eq $mapped -or
                $null -eq $mapped.PSObject.Properties['Family'] -or
                $null -eq $mapped.PSObject.Properties['Size'] -or
                $null -eq $mapped.PSObject.Properties['Weight']) {
                throw 'Invalid v2 font mapping.'
            }
            $family = [string]$mapped.Family
            $size = [double]$mapped.Size
            $weight = [string]$mapped.Weight
        }
        if ($beforeFont.HasFont) {
            $candidate = Restore-TypezeroMappedFontOverrideText -Text $candidate
        }
        $candidate = New-TypezeroMappedFontOverrideText -Text $candidate `
            -Family $family -Size $size -Weight $weight
        $afterFont = Get-TypezeroFontProfileTextSnapshot -Text $candidate
        if (-not $afterFont.HasFont -or $afterFont.Face -cne $family -or
            $afterFont.Size -ne $size -or $afterFont.Weight -cne $weight) {
            throw 'Mapped font preview does not match resolved mapping.'
        }
    }
    else {
        # When disabled, no font override, marker or inheritance is changed.
        $afterFont = Get-TypezeroFontProfileTextSnapshot -Text $candidate
        if ($afterFont.HasFont -ne $beforeFont.HasFont -or
            $afterFont.Face -cne $beforeFont.Face -or
            $afterFont.Size -ne $beforeFont.Size -or
            $afterFont.Weight -cne $beforeFont.Weight -or
            $candidate.Contains('/* TYPEZERO_FONT_V2 */') -ne
                $Text.Contains('/* TYPEZERO_FONT_V2 */')) {
            throw 'Disabled mapping must not change typography.'
        }
    }

    # Semantic verification after all transforms. The palette is now the
    # installed theme dictionary, not merely a reference to a stale scheme.
    $verifiedScheme = Get-TypezeroUnifiedOwnedEntry -Text $candidate `
        -Collection schemes -Name $schemeName
    $actual = ConvertFrom-Json -InputObject $verifiedScheme -Depth 100
    foreach ($key in $roles.Keys) {
        if ([string]$actual.$key -cne [string]$Theme[$roles[$key]]) {
            throw "Final Terminal palette mismatch: $key"
        }
    }
    if ((Get-TypezeroTerminalColorSchemeTextSpan -Text $candidate).Value -cne
        $schemeName) {
        throw 'Final profile color scheme reference mismatch.'
    }
    return $candidate
}
