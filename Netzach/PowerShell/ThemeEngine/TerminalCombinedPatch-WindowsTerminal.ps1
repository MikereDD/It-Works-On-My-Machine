# Typezero ThemeEngine
# Pure combined typography/color transformation. No disk writes.
# Requires FontPatch and TerminalColorPatch.

function New-TypezeroTerminalCombinedJsonCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$JsonText,
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Theme,
        [Parameter(Mandatory)][string]$FontFace,
        [Parameter(Mandatory)]
        [ValidateRange(6,36)][double]$FontSize,
        [Parameter(Mandatory)]
        [ValidateSet('normal','semi-bold')][string]$FontWeight
    )

    $fontFirst = New-TypezeroTerminalFontJsonCandidate `
        -JsonText $JsonText `
        -Face $FontFace `
        -Size $FontSize `
        -Weight $FontWeight

    $fontThenColor = New-TypezeroTerminalColorJsonCandidate `
        -JsonText $fontFirst -Theme $Theme

    $colorFirst = New-TypezeroTerminalColorJsonCandidate `
        -JsonText $JsonText -Theme $Theme

    $colorThenFont = New-TypezeroTerminalFontJsonCandidate `
        -JsonText $colorFirst `
        -Face $FontFace `
        -Size $FontSize `
        -Weight $FontWeight

    if (-not [string]::Equals(
        $fontThenColor,
        $colorThenFont,
        [StringComparison]::Ordinal
    )) {
        throw 'Font and color transformations produced different results.'
    }

    $marker = '/* TYPEZERO_FONT_V2 */'

    if ([regex]::Matches(
        $fontThenColor, [regex]::Escape($marker)
    ).Count -ne 1) {
        throw 'Combined candidate has an invalid font ownership marker.'
    }

    $options = [Text.Json.JsonDocumentOptions]::new()
    $options.CommentHandling = [Text.Json.JsonCommentHandling]::Skip
    $options.AllowTrailingCommas = $true

    $doc = [Text.Json.JsonDocument]::Parse(
        $fontThenColor, $options
    )

    try {
        $root = $doc.RootElement
        $guid = '{574e775e-4f2a-5b96-ac1e-a2962a402336}'
        $schemeName = 'Typezero ' + [string]$Theme['THEME_NAME']

        $profiles = @(
            foreach ($item in $root.GetProperty('profiles').
                GetProperty('list').EnumerateArray()) {

                $value = [Text.Json.JsonElement]::new()

                if ($item.TryGetProperty('guid', [ref]$value) -and
                    $value.GetString() -ieq $guid) {
                    $item
                }
            }
        )

        $schemes = @(
            foreach ($item in $root.GetProperty('schemes').
                EnumerateArray()) {

                if ($item.GetProperty('name').GetString() -ceq
                    $schemeName) {
                    $item
                }
            }
        )

        $terminalThemes = @(
            foreach ($item in $root.GetProperty('themes').
                EnumerateArray()) {

                if ($item.GetProperty('name').GetString() -ceq
                    'Typezero ThemeEngine') {
                    $item
                }
            }
        )

        if ($profiles.Count -ne 1 -or
            $schemes.Count -ne 1 -or
            $terminalThemes.Count -ne 1) {
            throw 'Combined candidate target objects are not unique.'
        }

        $font = $profiles[0].GetProperty('font')

        if ($font.GetProperty('face').GetString() -cne $FontFace -or
            $font.GetProperty('size').GetDouble() -ne $FontSize -or
            $font.GetProperty('weight').GetString() -cne $FontWeight -or
            $profiles[0].GetProperty('colorScheme').GetString() -cne
                $schemeName -or
            $schemes[0].GetProperty('background').GetString() -cne
                [string]$Theme['BG'] -or
            $terminalThemes[0].GetProperty('tabRow').
                GetProperty('background').GetString() -cne
                [string]$Theme['BG']) {
            throw 'Combined candidate failed property validation.'
        }

        return $fontThenColor
    }
    finally {
        $doc.Dispose()
    }
}
