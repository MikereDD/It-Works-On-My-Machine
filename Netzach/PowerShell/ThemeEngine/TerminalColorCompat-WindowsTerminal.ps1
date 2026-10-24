function Get-TypezeroTerminalColorSchemeTextSpan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Text
    )

    $snapshot = Get-TypezeroFontProfileTextSnapshot -Text $Text

    $options = [System.Text.Json.JsonDocumentOptions]::new()
    $options.AllowTrailingCommas = $true
    $options.CommentHandling =
        [System.Text.Json.JsonCommentHandling]::Skip

    $doc = [System.Text.Json.JsonDocument]::Parse(
        $Text, $options
    )

    try {
        $list = $doc.RootElement.GetProperty(
            'profiles'
        ).GetProperty('list')

        $guid = '{574e775e-4f2a-5b96-ac1e-a2962a402336}'
        $profiles = @()

        foreach ($entry in $list.EnumerateArray()) {
            $entryGuid = $null

            foreach ($property in $entry.EnumerateObject()) {
                if ($property.Name -ceq 'guid') {
                    $entryGuid = $property.Value.GetString()
                }
            }

            if ($entryGuid -ieq $guid) {
                $profiles += $entry
            }
        }

        if ($profiles.Count -ne 1) {
            throw 'Expected exactly one PowerShell 7 profile.'
        }

        $properties = @()

        foreach ($property in $profiles[0].EnumerateObject()) {
            if ($property.Name -ceq 'colorScheme') {
                $properties += $property
            }
        }

        if ($properties.Count -ne 1) {
            throw 'Expected exactly one colorScheme property.'
        }

        $scheme = $properties[0].Value

        if ($scheme.ValueKind -ne
            [System.Text.Json.JsonValueKind]::String) {
            throw 'Profile colorScheme must be a string.'
        }

        $pattern = (
            '"colorScheme"\s*:\s*' +
            '(?<value>"(?:\\.|[^"\\])*")'
        )

        $matches = [regex]::Matches(
            $snapshot.Raw, $pattern
        )

        if ($matches.Count -ne 1) {
            throw 'Color scheme text location is ambiguous.'
        }

        $span = $matches[0].Groups['value']

        if ($span.Value -cne $scheme.GetRawText()) {
            throw 'Located scheme does not match parsed JSON.'
        }

        [pscustomobject]@{
            Offset   = $snapshot.Offset + $span.Index
            Length   = $span.Length
            RawValue = $span.Value
            Value    = $scheme.GetString()
        }
    }
    finally {
        $doc.Dispose()
    }
}

function Set-TypezeroTerminalProfileColorSchemeText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Text,

        [Parameter(Mandatory)]
        [ValidatePattern('^Typezero [A-Za-z0-9][A-Za-z0-9 ._\x27-]*$')]
        [ValidateLength(1, 128)]
        [string]$SchemeName
    )

    $before = Get-TypezeroTerminalColorSchemeTextSpan `
        -Text $Text

    if ($before.Value -ceq $SchemeName) {
        throw 'Requested color scheme is already selected.'
    }

    # PowerShell 7-safe JSON string encoding.
    $encoded = ConvertTo-Json `
        -InputObject ([string]$SchemeName) `
        -Compress

    $result = (
        $Text.Substring(0, $before.Offset) +
        $encoded +
        $Text.Substring($before.Offset + $before.Length)
    )

    $after = Get-TypezeroTerminalColorSchemeTextSpan `
        -Text $result

    if ($after.Value -cne $SchemeName) {
        throw 'Updated colorScheme failed validation.'
    }

    $reconstructed = (
        $result.Substring(0, $after.Offset) +
        $before.RawValue +
        $result.Substring($after.Offset + $after.Length)
    )

    if ($reconstructed -cne $Text) {
        throw 'Color change modified unrelated JSONC text.'
    }

    return $result
}

function Set-TypezeroTerminalOwnedElementText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Text,

        [Parameter(Mandatory)]
        [ValidateSet('schemes', 'themes')]
        [string]$Collection,

        [Parameter(Mandatory)][string]$Name,

        [Parameter(Mandatory)][string]$Replacement
    )

    if ($Collection -ceq 'schemes') {
        if (-not $Name.StartsWith(
            'Typezero ', [StringComparison]::Ordinal
        )) {
            throw 'Only Typezero color schemes may be replaced.'
        }
    }
    elseif ($Name -cne 'Typezero ThemeEngine') {
        throw 'Only the Typezero application theme may be replaced.'
    }

    $options = [System.Text.Json.JsonDocumentOptions]::new()
    $options.AllowTrailingCommas = $true
    $options.CommentHandling =
        [System.Text.Json.JsonCommentHandling]::Skip

    $document = [System.Text.Json.JsonDocument]::Parse(
        $Text, $options
    )

    $candidate = $null

    try {
        $candidate = [System.Text.Json.JsonDocument]::Parse(
            $Replacement, $options
        )

        if ($candidate.RootElement.ValueKind -ne
            [System.Text.Json.JsonValueKind]::Object -or
            $candidate.RootElement.GetProperty('name').GetString() -cne
            $Name -or
            $candidate.RootElement.GetRawText() -cne $Replacement) {
            throw 'Replacement must be one matching JSON object.'
        }

        $matches = @(
            foreach ($entry in $document.RootElement.GetProperty(
                $Collection
            ).EnumerateArray()) {
                if ($entry.GetProperty('name').GetString() -ceq $Name) {
                    $entry.GetRawText()
                }
            }
        )

        if ($matches.Count -ne 1) {
            throw 'Managed object missing or duplicated.'
        }

        $old = [string]$matches[0]

        # Preserve comments by refusing to rewrite an object
        # that contains comments we cannot edit losslessly yet.
        if ($old.Contains('/*') -or $old.Contains('//')) {
            throw 'Managed object contains comments: edit refused.'
        }

        if ($old -ceq $Replacement) {
            throw 'Replacement is identical to existing object.'
        }

        $start = $Text.IndexOf(
            $old, [StringComparison]::Ordinal
        )

        if ($start -lt 0 -or
            $start -ne $Text.LastIndexOf(
                $old, [StringComparison]::Ordinal
            )) {
            throw 'Managed JSON object text span is ambiguous.'
        }

        $result = (
            $Text.Substring(0, $start) +
            $Replacement +
            $Text.Substring($start + $old.Length)
        )

        $verified = [System.Text.Json.JsonDocument]::Parse(
            $result, $options
        )

        try {
            $after = @(
                foreach ($entry in $verified.RootElement.GetProperty(
                    $Collection
                ).EnumerateArray()) {
                    if ($entry.GetProperty('name').GetString() -ceq
                        $Name) {
                        $entry.GetRawText()
                    }
                }
            )

            if ($after.Count -ne 1 -or
                $after[0] -cne $Replacement) {
                throw 'Managed JSON object update failed verification.'
            }
        }
        finally {
            $verified.Dispose()
        }

        $reconstructed = (
            $result.Substring(0, $start) +
            $old +
            $result.Substring($start + $Replacement.Length)
        )

        if ($reconstructed -cne $Text) {
            throw 'Unrelated Terminal text was modified.'
        }

        return $result
    }
    finally {
        if ($null -ne $candidate) {
            $candidate.Dispose()
        }
        $document.Dispose()
    }
}
