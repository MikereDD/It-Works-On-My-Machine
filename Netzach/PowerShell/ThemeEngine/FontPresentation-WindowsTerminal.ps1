# Typezero ThemeEngine - Windows Terminal typography presentation
# Pure presentation function. No filesystem or Terminal writes.

function Format-TypezeroTerminalFontPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Plan
    )

    $required = @(
        'Theme',
        'MappingVersion',
        'IntegrationEnabled',
        'CurrentFont',
        'RequestedFont',
        'CurrentSize',
        'RequestedSize',
        'CurrentWeight',
        'RequestedWeight',
        'WouldChange',
        'Action'
    )

    foreach ($field in $required) {
        if ($null -eq $Plan.PSObject.Properties[$field]) {
            throw "Incomplete font plan: $field"
        }
    }

    if ($Plan.Action -cne 'PREVIEW ONLY - no changes') {
        throw 'Formatter accepts preview plans only.'
    }

    $version = [int]$Plan.MappingVersion

    if ($version -notin @(1, 2)) {
        throw "Unsupported font mapping version: $version"
    }

    $safe = {
        param($Value)
        return ([string]$Value) -replace '[\x00-\x1F\x7F-\x9F]', '?'
    }

    $theme = & $safe $Plan.Theme
    $currentFont = & $safe $Plan.CurrentFont
    $requestedFont = & $safe $Plan.RequestedFont
    $currentSize = & $safe $Plan.CurrentSize
    $requestedSize = & $safe $Plan.RequestedSize
    $currentWeight = & $safe $Plan.CurrentWeight
    $requestedWeight = & $safe $Plan.RequestedWeight

    $mapping = if ($version -eq 2) {
        'V2 (experimental)'
    } else {
        'V1 (family mapping)'
    }

    $integration = if ($Plan.IntegrationEnabled) {
        'Enabled'
    } else {
        'Disabled'
    }

    $change = if ($Plan.WouldChange) { 'YES' } else { 'NO' }

    $lines = @(
        'TYPEZERO / WINDOWS TERMINAL'
        'FONT PLAN - PREVIEW ONLY'
        '----------------------------------------'
        "Theme:            $theme"
        "Mapping:          $mapping"
        "Integration flag: $integration"
        ''
        'CURRENT'
        "  Family: $currentFont"
        "  Size:   $currentSize"
        "  Weight: $currentWeight"
        ''
        'REQUESTED'
        "  Family: $requestedFont"
        "  Size:   $requestedSize"
        "  Weight: $requestedWeight"
        ''
        '----------------------------------------'
        "Would change: $change"
        'Execution:    NONE'
        'Windows Terminal settings remain unchanged.'
    )

    if ($version -eq 2) {
        $lines += 'Note: V2 typography is experimental.'
    }

    return ($lines -join [Environment]::NewLine)
}
