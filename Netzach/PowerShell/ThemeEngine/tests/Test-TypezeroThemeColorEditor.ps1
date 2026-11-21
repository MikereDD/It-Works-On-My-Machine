# Offline color-editor regressions. Real windows are initialized but never displayed.
# Run: pwsh -NoProfile -STA -File .\tests\Test-TypezeroThemeColorEditor.ps1
[CmdletBinding()]
param([string]$FixtureParent = [IO.Path]::GetTempPath())
$ErrorActionPreference = 'Stop'
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw 'Run with pwsh -STA.' }
Add-Type -AssemblyName PresentationFramework
$engineSource = Split-Path -Parent $PSScriptRoot
$repoThemes = [IO.Path]::GetFullPath((Join-Path $engineSource '..\..\..\ThemeEngine\themes'))
. (Join-Path $engineSource 'ThemeFontPreview-WindowsTerminal.ps1')
$originalLocalAppData = $env:LOCALAPPDATA
$root = Join-Path $FixtureParent ('typezero-color-editor-' + [guid]::NewGuid().ToString('N'))
$script:passed = 0
$script:caseNumber = 0
$utf8 = [Text.UTF8Encoding]::new($false)
function Assert-True { param([bool]$Condition,[string]$Message) if (-not $Condition) { throw "FAIL: $Message" } }
function Assert-Throws { param([scriptblock]$Action,[string]$Like,[string]$Message)
    try { & $Action } catch { Assert-True ($_.Exception.Message -like $Like) "$Message (got: $($_.Exception.Message))"; return }
    throw "FAIL: $Message (no error)"
}
function Invoke-Regression { param([string]$Name,[scriptblock]$Action) & $Action; $script:passed++; Write-Host "PASS [$script:passed] $Name" }
function Snapshot { param([string]$Folder) (@(Get-ChildItem -LiteralPath $Folder -Recurse -File | Sort-Object FullName | ForEach-Object { $_.FullName + ':' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }) -join "`n") }
function Choose { param($Box,[string]$Value) $Box.SelectedItem = @($Box.Items | Where-Object { [string]$_.Tag -ceq $Value })[0] }
function Click { param($Button) $Button.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent)) }
function Get-Hash { param([string]$Path) (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
function New-Fixture {
    param([switch]$NoShared)
    $script:caseNumber++
    $caseRoot = Join-Path $root ('case-' + $script:caseNumber)
    $env:LOCALAPPDATA = Join-Path $caseRoot 'L'
    $themeRoot = Join-Path $env:LOCALAPPDATA 'Typezero\ThemeEngine\themes'
    $shared = Join-Path $caseRoot 'repo\ThemeEngine\themes'
    $settings = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
    foreach ($id in @('nord','gruvbox')) {
        foreach ($folder in @((Join-Path $themeRoot $id), (Join-Path $shared $id))) {
            [IO.Directory]::CreateDirectory($folder) | Out-Null
            [IO.File]::Copy((Join-Path $repoThemes "$id\theme.conf"), (Join-Path $folder 'theme.conf'))
        }
    }
    [IO.File]::WriteAllText((Join-Path (Split-Path -Parent $shared) 'theme.conf.template'), "# template`n", $utf8)
    if ($NoShared) { $shared = '' }
    [IO.Directory]::CreateDirectory((Split-Path -Parent $settings)) | Out-Null
    [IO.File]::WriteAllText((Join-Path (Split-Path -Parent $themeRoot) 'current-theme'), 'nord', $utf8)
    $terminal = [ordered]@{ profiles=[ordered]@{ defaults=[ordered]@{}; list=@([ordered]@{guid='{574e775e-4f2a-5b96-ac1e-a2962a402336}';name='PowerShell 7';font=[ordered]@{face='Consolas';size=12;weight='normal'}}) } }
    [IO.File]::WriteAllText($settings, ($terminal | ConvertTo-Json -Depth 8), $utf8)
    $presets = Join-Path (Split-Path -Parent $themeRoot) 'custom-presets.json'
    [pscustomobject]@{ Root=$caseRoot; ThemesRoot=$themeRoot; Shared=$shared; Settings=$settings; Presets=$presets }
}

try {
    Invoke-Regression 'Every repository theme exposes only #RRGGBB roles in grouped order' {
        foreach ($dir in Get-ChildItem -LiteralPath $repoThemes -Directory) {
            $roles = @(Get-TypezeroThemeColorRoles -Text ([IO.File]::ReadAllText((Join-Path $dir.FullName 'theme.conf'))))
            Assert-True ($roles.Count -ge 39) "$($dir.Name) exposed $($roles.Count) roles."
            Assert-True (@($roles | Where-Object { -not (Test-TypezeroThemeHexColor $_.Value) }).Count -eq 0) "$($dir.Name) exposed a non-color role."
            Assert-True ($roles[0].Key -ceq 'BG' -and @($roles | Where-Object Group -ceq 'ANSI terminal').Count -eq 16) "$($dir.Name) group order/ANSI coverage differs."
        }
    }
    Invoke-Regression 'Derivation changes only identity and edited lines for every repository theme' {
        foreach ($dir in Get-ChildItem -LiteralPath $repoThemes -Directory) {
            $src = [IO.File]::ReadAllText((Join-Path $dir.FullName 'theme.conf'))
            $out = New-TypezeroDerivedThemeText -SourceText $src -SourceId $dir.Name -NewId "$($dir.Name)-x" -DisplayName "X Test" -Colors @{ ACCENT='#a1b2c3'; ANSI_RED='#102030' }
            $a = $src -split "`n"; $b = @($out -split "`n" | Select-Object -Skip 1)
            Assert-True ($out.StartsWith("# Derived from '$($dir.Name)'")) 'Provenance header missing.'
            Assert-True ($a.Count -eq $b.Count) "$($dir.Name) line count changed."
            $changed = @(for ($i=0; $i -lt $a.Count; $i++) { if ($a[$i] -cne $b[$i]) { ($b[$i] -split '=')[0].Trim() } })
            Assert-True ((($changed | Sort-Object) -join ',') -ceq 'ACCENT,ANSI_RED,THEME_ID,THEME_NAME') "$($dir.Name) changed: $($changed -join ',')"
            $v = ConvertFrom-TypezeroThemeConfText -Text $out
            Assert-True ($v.ACCENT -ceq '#A1B2C3' -and $v.THEME_ID -ceq "$($dir.Name)-x" -and $v.THEME_NAME -ceq 'X Test') 'Parsed derived values differ.'
            Assert-True (-not $out.Contains("`r")) 'Derived LF theme gained CR.'
        }
    }
    Invoke-Regression 'Invalid ids, names, colors and roles are refused' {
        $src = [IO.File]::ReadAllText((Join-Path $repoThemes 'nord\theme.conf'))
        $ok = @{ SourceText=$src; SourceId='nord'; NewId='nord-y'; DisplayName='Nord Y' }
        Assert-Throws { New-TypezeroDerivedThemeText @ok -NewId 'Nord_Bad' } '*Invalid theme id*' 'Uppercase id accepted.'
        Assert-Throws { New-TypezeroDerivedThemeText @ok -NewId 'nord' } '*source theme is never modified*' 'Source id accepted.'
        foreach ($bad in @('Bad\Name','Bad"Name','Bad$(x)','Bad|Name',' Lead')) {
            Assert-Throws { New-TypezeroDerivedThemeText @ok -DisplayName $bad } '*display name*' "Name '$bad' accepted."
        }
        Assert-Throws { New-TypezeroDerivedThemeText @ok -DisplayName '' } '*DisplayName*' 'Empty name accepted.'
        Assert-Throws { New-TypezeroDerivedThemeText @ok -Colors @{ BG='#12345' } } '*Invalid color*' 'Short hex accepted.'
        Assert-Throws { New-TypezeroDerivedThemeText @ok -Colors @{ BG='red' } } '*Invalid color*' 'Named color accepted.'
        Assert-Throws { New-TypezeroDerivedThemeText @ok -Colors @{ FONT_FAMILY='#123456' } } '*Not an editable color role*' 'Non-color key accepted.'
    }
    Invoke-Regression 'Save creates identical LF copies in shared and installed roots and leaves the source untouched' {
        $f = New-Fixture
        $srcHashes = @((Get-Hash (Join-Path $f.ThemesRoot 'nord\theme.conf')), (Get-Hash (Join-Path $f.Shared 'nord\theme.conf')))
        $settingsHash = Get-Hash $f.Settings
        $r = Save-TypezeroDerivedTheme -InstalledThemesRoot $f.ThemesRoot -SharedThemesRoot $f.Shared -SourceId nord -NewId nord-dusk -DisplayName 'Nord Dusk' -Colors @{ BG='#202530' }
        Assert-True ($r.Status -ceq 'Saved' -and (Get-Hash $r.SharedPath) -ceq (Get-Hash $r.InstalledPath) -and (Get-Hash $r.SharedPath) -ceq $r.Sha256) 'Copies differ or status wrong.'
        $bytes = [IO.File]::ReadAllBytes($r.SharedPath)
        Assert-True ($bytes[0] -ne 0xEF -and -not ([Text.Encoding]::UTF8.GetString($bytes).Contains("`r"))) 'Saved file has BOM or CR.'
        Assert-True ((Get-Hash (Join-Path $f.ThemesRoot 'nord\theme.conf')) -ceq $srcHashes[0] -and (Get-Hash (Join-Path $f.Shared 'nord\theme.conf')) -ceq $srcHashes[1]) 'Source theme changed.'
        Assert-True ((Get-Hash $f.Settings) -ceq $settingsHash) 'Terminal settings changed.'
        $v = ConvertFrom-TypezeroThemeConfText -Text ([IO.File]::ReadAllText($r.InstalledPath))
        Assert-True ($v.BG -ceq '#202530' -and $v.THEME_ID -ceq 'nord-dusk') 'Saved values differ.'
    }
    Invoke-Regression 'Existing ids in either root and a missing shared source are refused without writes' {
        $f = New-Fixture
        [IO.Directory]::CreateDirectory((Join-Path $f.Shared 'taken')) | Out-Null
        [IO.Directory]::CreateDirectory((Join-Path $f.ThemesRoot 'mine')) | Out-Null
        $before = Snapshot $f.Root
        Assert-Throws { Save-TypezeroDerivedTheme -InstalledThemesRoot $f.ThemesRoot -SharedThemesRoot $f.Shared -SourceId nord -NewId gruvbox -DisplayName 'G' } '*already exists*' 'Existing theme overwritten.'
        Assert-Throws { Save-TypezeroDerivedTheme -InstalledThemesRoot $f.ThemesRoot -SharedThemesRoot $f.Shared -SourceId nord -NewId taken -DisplayName 'T' } '*already exists*' 'Shared-only id accepted.'
        Assert-Throws { Save-TypezeroDerivedTheme -InstalledThemesRoot $f.ThemesRoot -SharedThemesRoot $f.Shared -SourceId nord -NewId mine -DisplayName 'M' } '*already exists*' 'Installed-only id accepted.'
        Assert-Throws { Save-TypezeroDerivedTheme -InstalledThemesRoot $f.ThemesRoot -SharedThemesRoot '' -SourceId nord -NewId fresh -DisplayName 'F' } '*Shared ThemeEngine/themes source not found*' 'Missing shared source accepted.'
        Assert-True ((Snapshot $f.Root) -ceq $before) 'A refused save wrote files.'
    }
    Invoke-Regression 'Arakiel load_theme parses the derived file identically (bash)' {
        $bash = Join-Path (Split-Path -Parent (Split-Path -Parent (Get-Command git).Source)) 'bin\bash.exe'
        if (-not (Test-Path -LiteralPath $bash)) { $bash = 'C:\Program Files\Git\bin\bash.exe' }
        Assert-True (Test-Path -LiteralPath $bash) 'Git Bash not found.'
        $f = New-Fixture
        $r = Save-TypezeroDerivedTheme -InstalledThemesRoot $f.ThemesRoot -SharedThemesRoot $f.Shared -SourceId nord -NewId nord-bash -DisplayName "Dusty's (Mix) & Co." -Colors @{ ACCENT='#ABCDEF' }
        $script = (Join-Path $engineSource '..\..\..\Arakiel\local\bin\themeengine') -replace '\\','/'
        $themesDir = $f.Shared -replace '\\','/'
        # Load only strip_quotes/load_theme from the real Arakiel script, then dump the table.
        $cmd = "set -e; die(){ echo `"`$*`" >&2; exit 1; }; THEMES_DIR='$themesDir'; eval `"`$(sed -n '/^strip_quotes()/,/^}/p;/^load_theme()/,/^}/p' '$script')`"; declare -A T=(); load_theme nord-bash; for k in `"`${!T[@]}`"; do printf '%s=%s\n' `"`$k`" `"`${T[`$k]}`"; done"
        $lines = & $bash -c $cmd
        Assert-True ($LASTEXITCODE -eq 0) "bash load_theme failed: $lines"
        $bashValues = @{}; foreach ($l in $lines) { $i = $l.IndexOf('='); $bashValues[$l.Substring(0,$i)] = $l.Substring($i+1) }
        $psValues = ConvertFrom-TypezeroThemeConfText -Text ([IO.File]::ReadAllText($r.SharedPath))
        foreach ($k in $psValues.Keys) { Assert-True ([string]$bashValues[$k] -ceq [string]$psValues[$k]) "bash/PowerShell differ for ${k}: '$($bashValues[$k])' vs '$($psValues[$k])'" }
        Assert-True ($bashValues.THEME_NAME -ceq "Dusty's (Mix) & Co." -and $bashValues.ACCENT -ceq '#ABCDEF') 'bash values differ.'
    }
    Invoke-Regression 'Editor: live preview, invalid color blocks Save, Reset restores, taken id blocks Save; Cancel writes nothing' {
        $f = New-Fixture; $before = Snapshot $f.Root
        $seen = @{}
        $result = Show-TypezeroThemeColorEditor -InstalledThemesRoot $f.ThemesRoot -SharedThemesRoot $f.Shared -ThemeId nord -OnLoaded {
            param($w,$c)
            $seen.Roles = $c.Rows.Count; $seen.SuggestedId = $c.NewIdBox.Text; $seen.InitialSave = $c.SaveButton.IsEnabled
            $c.Rows['BG'].Box.Text = '#010203'
            $seen.PreviewBg = $c.PreviewBorder.Background.Color.ToString()
            $seen.ResetEnabled = $c.Rows['BG'].Reset.IsEnabled
            $c.Rows['TEXT'].Box.Text = '#12'
            $seen.InvalidSave = $c.SaveButton.IsEnabled; $seen.InvalidHint = $c.SaveHint.Text
            Click $c.Rows['TEXT'].Reset
            $seen.TextRestored = $c.Rows['TEXT'].Box.Text; $seen.ValidAgain = $c.SaveButton.IsEnabled
            $c.NewIdBox.Text = 'gruvbox'
            $seen.TakenSave = $c.SaveButton.IsEnabled; $seen.TakenHint = $c.SaveHint.Text
            Click $c.CancelButton
        }
        Assert-True ($seen.Roles -eq 42 -and $seen.SuggestedId -ceq 'nord-custom' -and $seen.InitialSave) "Initial editor state wrong: $($seen | ConvertTo-Json -Compress)"
        Assert-True ($seen.PreviewBg -ceq '#FF010203' -and $seen.ResetEnabled) 'Preview did not follow BG edit.'
        Assert-True (-not $seen.InvalidSave -and $seen.InvalidHint -like '*TEXT*') 'Invalid color did not block Save.'
        Assert-True ($seen.TextRestored -ceq '#D8DEE9' -and $seen.ValidAgain) 'Reset did not restore the original.'
        Assert-True (-not $seen.TakenSave -and $seen.TakenHint -like '*already exists*') 'Existing id did not block Save.'
        Assert-True ($null -eq $result -and (Snapshot $f.Root) -ceq $before) 'Cancel returned a result or wrote files.'
    }
    Invoke-Regression 'Editor without a shared source explains why Save is unavailable' {
        $f = New-Fixture -NoShared
        $seen = @{}
        $null = Show-TypezeroThemeColorEditor -InstalledThemesRoot $f.ThemesRoot -SharedThemesRoot '' -ThemeId nord -OnLoaded {
            param($w,$c) $seen.Save = $c.SaveButton.IsEnabled; $seen.Hint = $c.SaveHint.Text
        }
        Assert-True (-not $seen.Save -and $seen.Hint -like '*shared ThemeEngine/themes source was not found*') 'Missing shared source not explained.'
    }
    Invoke-Regression 'Theme + Font window: Edit Colors saves a new theme, lists and selects it, returns no action' {
        $f = New-Fixture
        $settingsHash = Get-Hash $f.Settings
        $sourceHash = Get-Hash (Join-Path $f.ThemesRoot 'nord\theme.conf')
        $seen = @{}
        $result = Show-TypezeroThemeFontPreview -ThemesRoot $f.ThemesRoot -SharedThemesRoot $f.Shared -PresetsPath $f.Presets -OnColorEditorLoaded {
            param($w,$c)
            $c.Rows['ACCENT'].Box.Text = '#E0A0C0'
            $c.NewIdBox.Text = 'nord-rose'; $c.NameBox.Text = 'Nord Rose'
            Click $c.SaveButton
        } -OnLoaded {
            param($window,$c)
            Choose $c.ThemeBox 'nord'
            Click $c.EditColorsButton
            $seen.Selected = [string]$c.ThemeBox.SelectedItem.Tag
            $seen.Listed = @($c.ThemeBox.Items | ForEach-Object { [string]$_.Tag })
            $seen.Status = $c.StatusLabel.Text
            $seen.ShellReady = $c.ApplyShellButton.IsEnabled
            $seen.Tag = $window.Tag
        }
        Assert-True ($seen.Selected -ceq 'nord-rose' -and $seen.Listed -contains 'nord-rose') "New theme not listed/selected: $($seen.Listed -join ',')"
        Assert-True ($seen.Status -like "*Saved new theme 'nord-rose'*" -and $seen.ShellReady) 'Status/Apply readiness wrong after save.'
        Assert-True ($null -eq $seen.Tag -and $null -eq $result) 'Editing produced an apply action.'
        $v = ConvertFrom-TypezeroThemeConfText -Text ([IO.File]::ReadAllText((Join-Path $f.Shared 'nord-rose\theme.conf')))
        Assert-True ($v.ACCENT -ceq '#E0A0C0' -and $v.THEME_NAME -ceq 'Nord Rose') 'Shared copy values differ.'
        Assert-True ((Get-Hash (Join-Path $f.Shared 'nord-rose\theme.conf')) -ceq (Get-Hash (Join-Path $f.ThemesRoot 'nord-rose\theme.conf'))) 'Installed copy differs.'
        Assert-True ((Get-Hash $f.Settings) -ceq $settingsHash -and (Get-Hash (Join-Path $f.ThemesRoot 'nord\theme.conf')) -ceq $sourceHash) 'Settings or source theme changed.'
    }
    Invoke-Regression 'Theme + Font window still loads without the editor modules and disables Edit Colors' {
        $f = New-Fixture
        $partial = Join-Path $f.Root 'partial engine'
        [IO.Directory]::CreateDirectory($partial) | Out-Null
        foreach ($name in @('ThemeFontPreview-WindowsTerminal.ps1','AppearanceSelection-WindowsTerminal.ps1','TerminalFontControl-WindowsTerminal.ps1',
                            'TerminalSettings-WindowsTerminal.ps1','FontProvider-WindowsTerminal.ps1','FontWeights-WindowsTerminal.ps1','FontMapping-WindowsTerminal.ps1')) {
            Copy-Item -LiteralPath (Join-Path $engineSource $name) -Destination $partial
        }
        $child = Join-Path $f.Root 'partial-check.ps1'
        [IO.File]::WriteAllText($child, @"
`$ErrorActionPreference = 'Stop'
. '$partial\ThemeFontPreview-WindowsTerminal.ps1'
if (Get-Command Show-TypezeroThemeColorEditor -ErrorAction SilentlyContinue) { throw 'editor unexpectedly loaded' }
`$state = @{}
`$null = Show-TypezeroThemeFontPreview -ThemesRoot '$($f.ThemesRoot)' -PresetsPath '$($f.Presets)' -OnLoaded { param(`$w,`$c) `$state.Enabled = `$c.EditColorsButton.IsEnabled; `$state.Tip = [string]`$c.EditColorsButton.ToolTip }
if (`$state.Enabled -or `$state.Tip -notlike '*not installed*') { throw "Edit Colors not disabled: `$(`$state | ConvertTo-Json -Compress)" }
'PARTIAL-OK'
"@, $utf8)
        $out = & (Get-Process -Id $PID).Path -NoProfile -NonInteractive -STA -File $child 2>&1
        Assert-True ($LASTEXITCODE -eq 0 -and ($out -join "`n") -like '*PARTIAL-OK*') "Partial engine check failed: $($out -join ' ')"
    }
    Invoke-Regression 'Edit Colors works when launched like themeengine-dev (function -> & script -> dot-sourced modules)' {
        $f = New-Fixture
        $launcher = Join-Path $f.Root 'nested launch.ps1'
        # Mirrors ThemeEngine.ps1 'font theme-preview': modules dot-sourced into a nested
        # script scope that closures (GetNewClosure) cannot see by name.
        [IO.File]::WriteAllText($launcher, @"
param(`$Probe)
. '$engineSource\ThemeFontPreview-WindowsTerminal.ps1'
`$null = Show-TypezeroThemeFontPreview -ThemesRoot '$($f.ThemesRoot)' -SharedThemesRoot '$($f.Shared)' -PresetsPath '$($f.Presets)' -OnColorEditorLoaded {
    param(`$w,`$c)
    `$Probe.Opened = `$true
    `$c.Rows['ACCENT'].Box.Text = '#123456'
    `$Probe.SwatchFollows = (`$c.Rows['ACCENT'].Swatch.Background.Color.ToString() -ceq '#FF123456')
    `$Probe.Hint = `$c.SaveHint.Text
    `$c.CancelButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
} -OnLoaded {
    param(`$w,`$c)
    `$c.EditColorsButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    `$Probe.Status = `$c.StatusLabel.Text
}
"@, $utf8)
        $child = Join-Path $f.Root 'nested-check.ps1'
        # The live window resolved these pre-existing helpers; make only them global so the
        # window loads and the editor's functions remain reachable solely via the nested scope.
        [IO.File]::WriteAllText($child, @"
`$ErrorActionPreference = 'Stop'
. '$engineSource\FontWeights-WindowsTerminal.ps1'
. '$engineSource\AppearanceSelection-WindowsTerminal.ps1'
if (Get-Command Show-TypezeroThemeColorEditor -ErrorAction SilentlyContinue) { throw 'editor must not be global in this case' }
function global:Invoke-NestedLaunch { param(`$Probe) & '$launcher' -Probe `$Probe }
`$probeNested = @{ Opened = `$false }
Invoke-NestedLaunch -Probe `$probeNested
`$probeNested | ConvertTo-Json -Compress
"@, $utf8)
        $out = (& (Get-Process -Id $PID).Path -NoProfile -NonInteractive -STA -File $child 2>&1) -join "`n"
        Assert-True ($LASTEXITCODE -eq 0) "Nested launch failed: $out"
        $probe = ($out -split "`n" | Where-Object { $_.Trim().StartsWith('{') } | Select-Object -Last 1) | ConvertFrom-Json
        Assert-True ($probe.Opened -and $probe.Status -notlike '*not recognized*') "Editor did not open from nested launch: $out"
        Assert-True ($probe.SwatchFollows -and $probe.Hint -like "Ready:*1 changed*") "Editor closures failed in nested launch: $out"
    }
    Write-Host "PASS: $script:passed color editor regressions. Fixtures retained: $root"
}
finally {
    $env:LOCALAPPDATA = $originalLocalAppData
}
