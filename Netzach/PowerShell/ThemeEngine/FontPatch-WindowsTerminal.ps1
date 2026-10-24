# Typezero FontEngine v2
# Pure JSONC transformation. No disk writes.

function New-TypezeroTerminalFontJsonCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$JsonText,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Face,
        [Parameter(Mandatory)][ValidateRange(6,36)][double]$Size,
        [Parameter(Mandatory)]
        [ValidateSet('normal','semi-bold')]
        [string]$Weight
    )

    $guid = '{574e775e-4f2a-5b96-ac1e-a2962a402336}'
    $marker = '/* TYPEZERO_FONT_V2 */'

    $options = [Text.Json.JsonDocumentOptions]::new()
    $options.CommentHandling = [Text.Json.JsonCommentHandling]::Skip
    $options.AllowTrailingCommas = $true

    $doc = [Text.Json.JsonDocument]::Parse($JsonText, $options)
    $candidateDoc = $null

    try {
        $profiles = $doc.RootElement.
            GetProperty('profiles').GetProperty('list')

        $matches = @(
            foreach ($item in $profiles.EnumerateArray()) {
                if ($item.GetProperty('guid').GetString() -ieq $guid) {
                    $item
                }
            }
        )

        if ($matches.Count -ne 1) {
            throw 'PowerShell 7 profile was not uniquely identified.'
        }

        $profile = $matches[0]
        $raw = $profile.GetRawText()

        $first = $JsonText.IndexOf($raw, [StringComparison]::Ordinal)
        $last = $JsonText.LastIndexOf($raw, [StringComparison]::Ordinal)

        if ($first -lt 0 -or $first -ne $last -or
            -not $raw.StartsWith('{')) {
            throw 'PowerShell 7 source block was not uniquely located.'
        }

        $fontJson = ConvertTo-Json -InputObject ([ordered]@{
            face   = $Face
            size   = $Size
            weight = $Weight
        }) -Depth 10 -Compress

        $newBlock = $marker + '"font":' + $fontJson + ','

        $existingFont = [Text.Json.JsonElement]::new()
        $hasFont = $profile.TryGetProperty('font', [ref]$existingFont)

        if (-not $hasFont) {
            if ($raw.Substring(1).StartsWith($marker)) {
                throw 'Orphaned Typezero marker detected.'
            }

            $newRaw = $raw.Insert(1, $newBlock)
        }
        else {
            $fragment = $raw.Substring(1)

            if (-not $fragment.StartsWith($marker)) {
                throw 'Existing font setting is not Typezero-managed.'
            }

            $pattern = '^' + [regex]::Escape($marker) +
                '"font":\{"face":"(?:\\.|[^"\\])*",' +
                '"size":\d+(?:\.\d+)?,' +
                '"weight":"(?:\\.|[^"\\])*"\},'

            $match = [regex]::Match($fragment, $pattern)

            if (-not $match.Success) {
                throw 'Typezero-managed font block is malformed.'
            }

            $newRaw = $raw.Remove(1, $match.Length).
                Insert(1, $newBlock)
        }

        $candidate = $JsonText.Substring(0, $first) +
            $newRaw +
            $JsonText.Substring($first + $raw.Length)

        $candidateDoc = [Text.Json.JsonDocument]::Parse(
            $candidate, $options
        )

        $updatedProfiles = $candidateDoc.RootElement.
            GetProperty('profiles').GetProperty('list')

        $updated = @(
            foreach ($item in $updatedProfiles.EnumerateArray()) {
                if ($item.GetProperty('guid').GetString() -ieq $guid) {
                    $item
                }
            }
        )

        if ($updated.Count -ne 1) {
            throw 'Updated PowerShell profile is not unique.'
        }

        $font = $updated[0].GetProperty('font')

        if ($font.GetProperty('face').GetString() -cne $Face -or
            $font.GetProperty('size').GetDouble() -ne $Size -or
            $font.GetProperty('weight').GetString() -cne $Weight) {
            throw 'Candidate font properties failed verification.'
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
