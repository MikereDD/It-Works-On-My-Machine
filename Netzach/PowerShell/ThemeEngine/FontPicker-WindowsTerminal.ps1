
# Typezero ThemeEngine - Interactive Font Picker
# Preview-only: no configuration or Windows Terminal writes.
# Requires FontSpecimen-WindowsTerminal.ps1 for visual comparison.

function Invoke-TypezeroFontPicker {
    [CmdletBinding()]
    param(
        [string]$EngineRoot = $PSScriptRoot
    )

    $ErrorActionPreference = 'Stop'

    $provider = Join-Path $EngineRoot 'FontProvider-WindowsTerminal.ps1'
    $writer = Join-Path $EngineRoot 'FontWriter-WindowsTerminal.ps1'
    $specimen = Join-Path $EngineRoot 'FontSpecimen-WindowsTerminal.ps1'

    foreach ($file in @($provider, $writer, $specimen)) {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
            throw "Required font module missing: $file"
        }
    }

    # Load dependencies into this function's script scope.
    # The verification scriptblock must also resolve these functions.
    . $provider
    . $writer
    . $specimen

    $writerFunction = Get-Command `
        New-TypezeroMappedFontOverrideText `
        -CommandType Function `
        -ErrorAction SilentlyContinue

    if ($null -eq $writerFunction) {
        throw "Font writer failed to load: $writer"
    }

    $installed = @(
        Get-TypezeroInstalledFontFamilies |
            Sort-Object -Unique
    )

    if ($installed.Count -eq 0) {
        throw 'No installed font families were discovered.'
    }

    $preferred = @(
        'JetBrainsMono Nerd Font'
        'JetBrainsMono NF'
        'JetBrains Mono'
        'Cascadia Mono'
        'Cascadia Code'
        'Consolas'
    )

    $choices = [Collections.Generic.List[string]]::new()

    foreach ($name in $preferred) {
        if ($name -ceq 'JetBrainsMono Nerd Font' -or
            $installed -ccontains $name) {
            if (-not $choices.Contains($name)) {
                $choices.Add($name)
            }
        }
    }

    foreach ($name in $installed) {
        if (-not $choices.Contains($name)) {
            $choices.Add($name)
        }
    }

    # Typezero default. Selection is session-only.
    $family = 'JetBrainsMono Nerd Font'
    $size = 12.0
    $weight = 'normal'

    # Synthetic fixture used exclusively for in-memory verification.
    $original = @'
{
  "profiles": {
    "defaults": {
      "font": {
        "face": "Fixture Default",
        "size": 12,
        "weight": "normal"
      }
    },
    "list": [
      {
        "guid": "{574e775e-4f2a-5b96-ac1e-a2962a402336}",
        "name": "PowerShell 7"
      }
    ]
  }
}
'@

    $verify = {
        param(
            [string]$SelectedFamily,
            [double]$SelectedSize,
            [string]$SelectedWeight
        )

        if (-not $choices.Contains($SelectedFamily)) {
            throw "Font not recognized: $SelectedFamily"
        }

        if ([double]::IsNaN($SelectedSize) -or
            [double]::IsInfinity($SelectedSize) -or
            $SelectedSize -lt 6 -or $SelectedSize -gt 36) {
            throw 'Font size must be between 6 and 36.'
        }

        if ($SelectedWeight -cnotin @('normal', 'semi-bold')) {
            throw 'Unsupported font weight.'
        }

        $candidate = New-TypezeroMappedFontOverrideText `
            -Text $original `
            -Family $SelectedFamily `
            -Size $SelectedSize `
            -Weight $SelectedWeight

        $snapshot = Get-TypezeroFontProfileTextSnapshot `
            -Text $candidate

        $restored = Restore-TypezeroMappedFontOverrideText `
            -Text $candidate

        if ($snapshot.Face -cne $SelectedFamily -or
            [double]$snapshot.Size -ne $SelectedSize -or
            $snapshot.Weight -cne $SelectedWeight -or
            $restored -cne $original) {
            throw 'Font override or restoration verification failed.'
        }

        return $true
        }

    while ($true) {
        Write-Host ''
        Write-Host 'TYPEZERO FONT PICKER' -ForegroundColor Cyan
        Write-Host '----------------------------------------'
        Write-Host "Font:   $family"
        Write-Host "Size:   $size"
        Write-Host "Weight: $weight"
        Write-Host ''
        Write-Host '[1] Search / choose font'
        Write-Host '[2] Change font size'
        Write-Host '[3] Toggle font weight'
        Write-Host '[4] Visual preview / compare'
        Write-Host '[Q] Finish'
        Write-Host ''

        $action = (Read-Host 'Select').Trim().ToUpperInvariant()

        switch ($action) {
            '1' {
                $search = (
                    Read-Host 'Search font name (Enter for preferred fonts)'
                ).Trim()

                if ([string]::IsNullOrWhiteSpace($search)) {
                    $matches = @(
                        $choices | Where-Object {
                            $preferred -ccontains $_
                        }
                    )
                }
                else {
                    $matches = @(
                        $choices |
                            Where-Object {
                                $_.IndexOf(
                                    $search,
                                    [StringComparison]::OrdinalIgnoreCase
                                ) -ge 0
                            } |
                            Select-Object -First 40
                    )
                }

                if ($matches.Count -eq 0) {
                    Write-Warning 'No matching font families found.'
                    continue
                }

                Write-Host ''

                for ($i = 0; $i -lt $matches.Count; $i++) {
					Write-Host ('{0,3}. {1}' -f ($i + 1), $matches[$i])
				}

                if ($matches.Count -eq 40) {
                    Write-Host ''
                    Write-Host 'Showing first 40 matches; refine search for more.'
                }

                $selected = (
                    Read-Host 'Font number (Enter to cancel)'
                ).Trim()

                if ([string]::IsNullOrWhiteSpace($selected)) {
                    continue
                }

                $number = 0

                if ([int]::TryParse($selected, [ref]$number) -and
                    $number -ge 1 -and
                    $number -le $matches.Count) {
                    $family = [string]$matches[$number - 1]
                }
                else {
                    Write-Warning 'Invalid font number.'
                }
            }

            '2' {
                $selected = Read-Host 'Font size (6-36)'
                $number = 0.0

                $valid = [double]::TryParse(
                    $selected,
                    [Globalization.NumberStyles]::Float,
                    [Globalization.CultureInfo]::InvariantCulture,
                    [ref]$number
                )

                if ($valid -and
                    -not [double]::IsNaN($number) -and
                    -not [double]::IsInfinity($number) -and
                    $number -ge 6 -and $number -le 36) {
                    $size = $number
                }
                else {
                    Write-Warning 'Invalid font size.'
                }
            }

            '3' {
                $weight = if ($weight -ceq 'normal') {
                    'semi-bold'
                }
                else {
                    'normal'
                }
            }

            '4' {
                $null = & $verify $family $size $weight

                Write-Host ''
                Write-Host 'PASS: In-memory font verification.' `
                    -ForegroundColor Green

                $selection = Show-TypezeroFontSpecimen `
                    -Family $family `
                    -Size $size `
                    -Weight $weight

                if ($null -eq $selection -or
                    $selection.Accepted -ne $true) {
                    Write-Host 'Visual selection cancelled.'
                    continue
                }

                $newFamily = [string]$selection.Family
                $newSize = [double]$selection.Size
                $newWeight = [string]$selection.Weight

                # Reverify the WPF selection independently through
                # Typezero's existing reversible font writer.
                $null = & $verify `
                    $newFamily $newSize $newWeight

                $family = $newFamily
                $size = $newSize
                $weight = $newWeight

                Write-Host ''
                Write-Host 'PASS: Visual selection accepted.' `
                    -ForegroundColor Green
                Write-Host "Selected: $family / $size / $weight"
                Write-Host 'Windows Terminal settings unchanged.'
            }

            'Q' {
                $null = & $verify $family $size $weight

                return [pscustomobject]@{
                    Family = $family
                    Size = $size
                    Weight = $weight
                    PreviewOnly = $true
                    SettingsChanged = $false
                    IntegrationEnabled = $false
                }
            }

            default {
                Write-Warning 'Unknown option.'
            }
        }
    }
}
