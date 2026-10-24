# Small JSONC edits for the existing ThemeEngine apply path. PowerShell 7 required.
# The saved font belongs to the PowerShell 7 profile; defaults and other profiles
# are never rewritten. Existing font features/axes and comments are retained.

. (Join-Path $PSScriptRoot 'FontWeights-WindowsTerminal.ps1')

function Read-TypezeroJsoncNode {
    param([hashtable]$State)
    $token = $State.Tokens[$State.Index++]
    $node = @{ Start = $token.Index; End = $token.Index + $token.Length; Kind = 'Value' }
    if ($token.Value -eq '{') {
        $node.Kind = 'Object'
        $node.Properties = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
        while ($State.Tokens[$State.Index].Value -ne '}') {
            $name = ConvertFrom-Json -InputObject $State.Tokens[$State.Index++].Value
            $State.Index++ # colon; JsonDocument has already validated the grammar
            $value = Read-TypezeroJsoncNode $State
            if (-not $node.Properties.TryAdd($name, $value)) { throw "Duplicate JSONC property: $name" }
            if ($State.Tokens[$State.Index].Value -eq ',') { $State.Index++ }
        }
        $closing = $State.Tokens[$State.Index++]
        $node.End = $closing.Index + 1
    }
    elseif ($token.Value -eq '[') {
        $node.Kind = 'Array'
        $node.Items = [Collections.Generic.List[object]]::new()
        while ($State.Tokens[$State.Index].Value -ne ']') {
            $node.Items.Add((Read-TypezeroJsoncNode $State))
            if ($State.Tokens[$State.Index].Value -eq ',') { $State.Index++ }
        }
        $closing = $State.Tokens[$State.Index++]
        $node.End = $closing.Index + 1
    }
    return $node
}

function Get-TypezeroJsoncTree {
    param([string]$Text)
    $options = [Text.Json.JsonDocumentOptions]::new()
    $options.CommentHandling = [Text.Json.JsonCommentHandling]::Skip
    $options.AllowTrailingCommas = $true
    $doc = [Text.Json.JsonDocument]::Parse($Text, $options)
    $doc.Dispose()
    # Tokenize validated JSONC so offsets refer to characters in the original
    # text, including Unicode. Comments and quoted braces are not structural.
    $tokens = @([regex]::Matches($Text,
        '(?s)//[^\r\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|[{}\[\]:,]|[^\s{}\[\]:,/]+') |
        Where-Object { -not $_.Value.StartsWith('//') -and -not $_.Value.StartsWith('/*') })
    Read-TypezeroJsoncNode @{ Tokens = $tokens; Index = 0 }
}

function Set-TypezeroJsoncObjectText {
    param([string]$Text, [System.Collections.IDictionary]$Values)
    $root = Get-TypezeroJsoncTree $Text
    if ($root.Kind -ne 'Object') { throw 'Expected a JSONC object.' }
    $edits = [Collections.Generic.List[object]]::new()
    $added = [Collections.Generic.List[string]]::new()
    foreach ($key in $Values.Keys) {
        $value = $Values[$key]
        $json = ConvertTo-Json -InputObject $value -Depth 30 -Compress
        if ($root.Properties.ContainsKey($key)) {
            $node = $root.Properties[$key]
            $old = $Text.Substring($node.Start, $node.End - $node.Start)
            if ($value -is [System.Collections.IDictionary] -and $node.Kind -eq 'Object') {
                $json = Set-TypezeroJsoncObjectText -Text $old -Values $value
            }
            if ($old -cne $json) { $edits.Add(@{ Start=$node.Start; Length=$node.End-$node.Start; Text=$json }) }
        }
        else { $added.Add((ConvertTo-Json -InputObject ([string]$key) -Compress) + ':' + $json) }
    }
    if ($added.Count) {
        $insertion = ($added -join ',') + $(if ($root.Properties.Count) { ',' } else { '' })
        $edits.Add(@{ Start=$root.Start+1; Length=0; Text=$insertion })
    }
    foreach ($edit in ($edits | Sort-Object Start -Descending)) {
        $Text = $Text.Remove($edit.Start, $edit.Length).Insert($edit.Start, $edit.Text)
    }
    return $Text
}

function Set-TypezeroJsoncNamedEntry {
    param([string]$Text, [string]$Collection, [System.Collections.IDictionary]$Values)
    $root = Get-TypezeroJsoncTree $Text
    if (-not $root.Properties.ContainsKey($Collection)) {
        return Set-TypezeroJsoncObjectText $Text ([ordered]@{ $Collection = @($Values) })
    }
    $array = $root.Properties[$Collection]
    if ($array.Kind -ne 'Array') { throw "Expected Terminal $Collection array." }
    $matches = @($array.Items | Where-Object {
        $_.Kind -eq 'Object' -and $_.Properties.ContainsKey('name') -and
        (ConvertFrom-Json -InputObject $Text.Substring($_.Properties['name'].Start,
            $_.Properties['name'].End-$_.Properties['name'].Start)) -ceq $Values['name']
    })
    if ($matches.Count -gt 1) { throw "Ambiguous Terminal $Collection entry: $($Values['name'])" }
    if ($matches.Count) {
        $node = $matches[0]
        $new = Set-TypezeroJsoncObjectText $Text.Substring($node.Start,$node.End-$node.Start) $Values
        return $Text.Remove($node.Start,$node.End-$node.Start).Insert($node.Start,$new)
    }
    $new = (ConvertTo-Json -InputObject $Values -Depth 30 -Compress) + $(if ($array.Items.Count) { ',' } else { '' })
    return $Text.Insert($array.Start+1,$new)
}

function Assert-TypezeroTerminalValues {
    param([System.Collections.IDictionary]$Actual, [System.Collections.IDictionary]$Expected)
    foreach ($key in $Expected.Keys) {
        if ($Expected[$key] -is [System.Collections.IDictionary]) {
            if ($Actual[$key] -isnot [System.Collections.IDictionary]) { throw "Terminal object verification failed: $key" }
            Assert-TypezeroTerminalValues $Actual[$key] $Expected[$key]
        }
        elseif (-not $Actual.Contains($key) -or $Actual[$key] -cne $Expected[$key]) {
            throw "Terminal setting verification failed: $key"
        }
    }
}

function New-TypezeroTerminalThemeText {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Scheme,
        [AllowNull()][System.Collections.IDictionary]$TerminalTheme,
        [AllowNull()][System.Collections.IDictionary]$Font)
    $root = Get-TypezeroJsoncTree $Text
    $list = $root.Properties['profiles'].Properties['list']
    if ($list.Kind -ne 'Array') { throw 'Expected Terminal profiles.list array.' }
    $profiles = @($list.Items | Where-Object {
        $_.Kind -eq 'Object' -and $_.Properties.ContainsKey('guid') -and
        (ConvertFrom-Json -InputObject $Text.Substring($_.Properties['guid'].Start,
            $_.Properties['guid'].End-$_.Properties['guid'].Start)) -ieq '{574e775e-4f2a-5b96-ac1e-a2962a402336}'
    })
    if ($profiles.Count -ne 1) { throw 'Expected exactly one PowerShell 7 Terminal profile.' }
    $values = [ordered]@{ colorScheme = $Scheme['name'] }
    if ($null -ne $Font -and $Font.Count) {
        if (-not $Font.Contains('face') -or [string]::IsNullOrWhiteSpace($Font['face'])) { throw 'Saved font family is empty.' }
        if ($Font.Contains('size') -and (-not [double]::IsFinite([double]$Font['size']) -or
            [double]$Font['size'] -lt 6 -or [double]$Font['size'] -gt 36)) { throw 'Invalid saved font size.' }
        if ($Font.Contains('weight') -and $Font['weight'] -cnotin @((Get-TypezeroTerminalFontWeights).Keys)) { throw 'Invalid saved font weight.' }
        $values['font'] = $Font
    }
    $profile = $profiles[0]
    $replacement = Set-TypezeroJsoncObjectText $Text.Substring($profile.Start,$profile.End-$profile.Start) $values
    $result = $Text.Remove($profile.Start,$profile.End-$profile.Start).Insert($profile.Start,$replacement)
    $result = Set-TypezeroJsoncNamedEntry $result 'schemes' $Scheme
    if ($null -ne $TerminalTheme) {
        $result = Set-TypezeroJsoncNamedEntry $result 'themes' $TerminalTheme
        $result = Set-TypezeroJsoncObjectText $result ([ordered]@{ theme = $TerminalTheme['name'] })
    }
    $null = Get-TypezeroJsoncTree $result
    # Verify requested settings independently of the text editor.
    $settings = ConvertFrom-Json -InputObject $result -AsHashtable
    $actual = @($settings.profiles.list | Where-Object { $_.guid -ieq '{574e775e-4f2a-5b96-ac1e-a2962a402336}' })[0]
    if ($actual.colorScheme -cne $Scheme['name']) { throw 'Terminal color verification failed.' }
    $entries = @(@{ Items=$settings.schemes; Values=$Scheme })
    if ($null -ne $TerminalTheme) {
        if ($settings.theme -cne $TerminalTheme['name']) { throw 'Terminal chrome verification failed.' }
        $entries += @{ Items=$settings.themes; Values=$TerminalTheme }
    }
    foreach ($entry in $entries) {
        $matches = @($entry.Items | Where-Object { $_.name -ceq $entry.Values['name'] })
        if ($matches.Count -ne 1) { throw 'Terminal named entry verification failed.' }
        Assert-TypezeroTerminalValues $matches[0] $entry.Values
    }
    if ($null -ne $Font) {
        Assert-TypezeroTerminalValues $actual.font $Font
    }
    return $result
}

function Write-TypezeroTerminalSettingsBytes {
    param([string]$Path, [byte[]]$Bytes, [Parameter(Mandatory)][string]$ExpectedSha256)
    $before = [IO.File]::ReadAllBytes($Path)
    $beforeHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($before))
    if ($beforeHash -ine $ExpectedSha256) { throw 'Terminal settings changed since the expected snapshot.' }
    $afterHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes))
    $result = [ordered]@{ Path=$Path; Changed=$false; BackupPath=$null; BeforeSha256=$beforeHash; AfterSha256=$afterHash }
    if ($beforeHash -ceq $afterHash) { return [pscustomobject]$result }
    $token = [guid]::NewGuid().ToString('N')
    $backup = "$Path.typezero-$token.bak"
    $stage = "$Path.typezero-$token.tmp"
    # A complete, verified backup exists before replacement. File.Replace also
    # preserves the actual displaced bytes in this backup if a writer raced us.
    [IO.File]::WriteAllBytes($backup,$before)
    [IO.File]::WriteAllBytes($stage,$Bytes)
    if ((Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash -cne $beforeHash -or
        (Get-FileHash -LiteralPath $stage -Algorithm SHA256).Hash -cne $afterHash) { throw 'Terminal backup/staging verification failed.' }
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -cne $beforeHash) { throw 'Terminal settings changed during preparation.' }
    [IO.File]::Replace($stage,$Path,$backup)
    if ((Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash -cne $beforeHash -or
        (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -cne $afterHash) {
        throw "Terminal update could not be verified; inspect settings and backup: $backup"
    }
    $result.Changed = $true
    $result.BackupPath = $backup
    [pscustomobject]$result
}

function Set-TypezeroWindowsTerminalAppearance {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Scheme,
        [AllowNull()][System.Collections.IDictionary]$TerminalTheme,
        [AllowNull()][System.Collections.IDictionary]$Font,
        [string]$ExpectedSha256)
    $bytes = [IO.File]::ReadAllBytes($Path)
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
    if ($ExpectedSha256 -and $hash -ine $ExpectedSha256) { throw 'Terminal settings changed since the expected snapshot.' }
    $utf8 = [Text.UTF8Encoding]::new($false,$true)
    $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191
    $offset = if ($bom) { 3 } else { 0 }
    $text = $utf8.GetString($bytes,$offset,$bytes.Length-$offset)
    $candidate = New-TypezeroTerminalThemeText -Text $text -Scheme $Scheme -TerminalTheme $TerminalTheme -Font $Font
    $newBytes = $utf8.GetBytes($candidate)
    if ($bom) { $newBytes = [byte[]](@(239,187,191) + $newBytes) }
    Write-TypezeroTerminalSettingsBytes -Path $Path -Bytes $newBytes -ExpectedSha256 $hash
}

# Font-only changes share the same JSONC editor and exact-byte backup writer as
# normal theme apply. Colors, chrome, defaults and other profiles are untouched.
function New-TypezeroTerminalFontText {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Font)
    if (-not $Font.Contains('face') -or [string]::IsNullOrWhiteSpace($Font['face']) -or
        [string]$Font['face'] -cne ([string]$Font['face']).Trim() -or
        ($Font.Contains('size') -and (-not [double]::IsFinite([double]$Font['size']) -or
        [double]$Font['size'] -lt 6 -or [double]$Font['size'] -gt 36 -or
        [double]$Font['size'] -ne [math]::Round([double]$Font['size'],2))) -or
        ($Font.Contains('weight') -and $Font['weight'] -cnotin @((Get-TypezeroTerminalFontWeights).Keys)) -or
        @($Font.Keys | Where-Object { $_ -cnotin @('face','size','weight') }).Count) {
        throw 'A font family and optional valid size/weight are required; other font fields are preserved.'
    }
    $root = Get-TypezeroJsoncTree $Text
    if ($root.Kind -ne 'Object' -or -not $root.Properties.ContainsKey('profiles') -or
        $root.Properties['profiles'].Kind -ne 'Object' -or
        -not $root.Properties['profiles'].Properties.ContainsKey('list')) {
        throw 'Expected Terminal profiles.list array.'
    }
    $list = $root.Properties['profiles'].Properties['list']
    if ($list.Kind -ne 'Array') { throw 'Expected Terminal profiles.list array.' }
    $profiles = @($list.Items | Where-Object {
        $_.Kind -eq 'Object' -and $_.Properties.ContainsKey('guid') -and
        (ConvertFrom-Json -InputObject $Text.Substring($_.Properties['guid'].Start,
            $_.Properties['guid'].End-$_.Properties['guid'].Start)) -ieq '{574e775e-4f2a-5b96-ac1e-a2962a402336}'
    })
    if ($profiles.Count -ne 1) { throw 'Expected exactly one PowerShell 7 Terminal profile.' }
    $profile = $profiles[0]
    if ($profile.Properties.ContainsKey('font') -and $profile.Properties['font'].Kind -ne 'Object') {
        throw 'Expected the PowerShell 7 profile font to be an object.'
    }
    $replacement = Set-TypezeroJsoncObjectText $Text.Substring($profile.Start,$profile.End-$profile.Start) ([ordered]@{ font=$Font })
    $result = $Text.Remove($profile.Start,$profile.End-$profile.Start).Insert($profile.Start,$replacement)
    $null = Get-TypezeroJsoncTree $result
    $settings = ConvertFrom-Json -InputObject $result -AsHashtable
    $actual = @($settings.profiles.list | Where-Object { $_.guid -ieq '{574e775e-4f2a-5b96-ac1e-a2962a402336}' })[0]
    Assert-TypezeroTerminalValues $actual.font $Font
    return $result
}

function Set-TypezeroWindowsTerminalFont {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Font,
        [string]$ExpectedSha256)
    $bytes = [IO.File]::ReadAllBytes($Path)
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
    if ($ExpectedSha256 -and $hash -ine $ExpectedSha256) { throw 'Terminal settings changed since the preview; preview again before applying.' }
    $utf8 = [Text.UTF8Encoding]::new($false,$true)
    $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191
    $offset = if ($bom) { 3 } else { 0 }
    $candidate = New-TypezeroTerminalFontText -Text $utf8.GetString($bytes,$offset,$bytes.Length-$offset) -Font $Font
    $newBytes = $utf8.GetBytes($candidate)
    if ($bom) { $newBytes = [byte[]](@(239,187,191) + $newBytes) }
    Write-TypezeroTerminalSettingsBytes -Path $Path -Bytes $newBytes -ExpectedSha256 $hash
}

function Restore-TypezeroWindowsTerminalAppearance {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$BackupPath,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedSha256)
    $bytes = [IO.File]::ReadAllBytes($BackupPath)
    $utf8 = [Text.UTF8Encoding]::new($false,$true)
    $offset = if ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) { 3 } else { 0 }
    $null = Get-TypezeroJsoncTree $utf8.GetString($bytes,$offset,$bytes.Length-$offset)
    Write-TypezeroTerminalSettingsBytes -Path $Path -Bytes $bytes -ExpectedSha256 $ExpectedSha256
}
