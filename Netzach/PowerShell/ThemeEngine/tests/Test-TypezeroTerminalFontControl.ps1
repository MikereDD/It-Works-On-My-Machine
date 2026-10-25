# Offline regressions for shared font-only controls and separate custom presets.
# All writes are inside a unique disposable fixture; live settings are never read.
# Run: pwsh -NoProfile -File .\tests\Test-TypezeroTerminalFontControl.ps1
[CmdletBinding()]
param([string]$FixtureParent = [IO.Path]::GetTempPath())
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'TerminalFontControl-WindowsTerminal.ps1')
$root = Join-Path $FixtureParent ('typezero-font-control-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root) | Out-Null
$script:passed=0
$script:caseNumber=0
$guid='{574e775e-4f2a-5b96-ac1e-a2962a402336}'
function Assert-True { param([bool]$Condition,[string]$Message) if (-not $Condition) { throw "FAIL: $Message" } }
function Assert-Throws { param([scriptblock]$Action,[string]$Message) $thrown=$false; try { & $Action | Out-Null } catch { $thrown=$true }; Assert-True $thrown $Message }
function Invoke-Regression { param([string]$Name,[scriptblock]$Action) & $Action; $script:passed++; Write-Host "PASS [$script:passed] $Name" }
function Snapshot { param([string]$Folder) (@(Get-ChildItem -LiteralPath $Folder -Recurse -File | Sort-Object FullName | ForEach-Object { $_.FullName+':'+(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }) -join "`n") }
function New-Fixture {
    param([string]$Text=$baseText,[switch]$Bom)
    $script:caseNumber++
    $folder=Join-Path $root ('case-'+$script:caseNumber)
    [IO.Directory]::CreateDirectory($folder) | Out-Null
    $path=Join-Path $folder 'settings.json'
    [IO.File]::WriteAllText($path,$Text,[Text.UTF8Encoding]::new([bool]$Bom))
    [pscustomobject]@{ Root=$folder; Path=$path }
}
function Read-Target { param([string]$Path) $s=[IO.File]::ReadAllText($Path) | ConvertFrom-Json -AsHashtable; @($s.profiles.list | Where-Object { $_.guid -ieq $guid })[0] }
$defaults='"defaults": { "font":{"face":"Default Mono","size":10,"weight":350}, "opacity":82 },'
$other='{"guid":"{11111111-1111-1111-1111-111111111111}","font":{"face":"Keep Mono","size":9},"colorScheme":"Keep Colors"}'
$baseText=@'
{
 // keep comment and Unicode: Netzach נ
 "profiles": {
 __DEFAULTS__
 "list":[{"guid":"{574e775e-4f2a-5b96-ac1e-a2962a402336}","colorScheme":"Gruvbox", "font":{"face":"Old Mono","size":11/*size comment*/,"weight":350,"features":{"liga":0},"axes":{"wdth":90}}},__OTHER__]
 },
 "theme":"Typezero Gruvbox", "schemes":[{"name":"Gruvbox","background":"#282828"}], "themes":[{"name":"Typezero Gruvbox"}],
 "actions":[{"command":"copy","keys":"ctrl+shift+c"}]
}
'@
$baseText=($baseText.Replace('__DEFAULTS__',$defaults).Replace('__OTHER__',$other) -replace "`r?`n","`r`n")+"`r`n"
try {
    Invoke-Regression 'Preview and WhatIf leave every fixture byte unchanged and create no backup' {
        $f=New-Fixture -Bom
        $before=Snapshot $f.Root
        $p=Get-TypezeroTerminalFontPreview -Family 'New Mono' -Size 14.25 -Weight semi-bold -SettingsPath $f.Path
        Assert-True ($p.PreviewOnly -and -not $p.SettingsChanged -and $p.WouldChange -and $p.Family -ceq 'New Mono' -and $p.CurrentFamily -ceq 'Old Mono') 'Preview result is incorrect.'
        $r=Set-TypezeroTerminalFontChoice -Family 'New Mono' -Size 14.25 -Weight semi-bold -SettingsPath $f.Path -ExpectedSha256 $p.ExpectedSha256 -WhatIf
        Assert-True ($r.Status -ceq 'NotExecuted' -and -not $r.Changed -and -not $r.FontActivated) 'WhatIf claims activation.'
        Assert-True ((Snapshot $f.Root) -ceq $before) 'Preview or WhatIf wrote files.'
    }
    Invoke-Regression 'Font-only apply A -> B -> A retains colors, defaults, other profile and exact backups' {
        $f=New-Fixture -Bom
        foreach ($choice in @(@{Family='Fixture A';Size=12.5;Weight='normal'},@{Family='Fixture B';Size=17;Weight='semi-bold'},@{Family='Fixture A';Size=12.5;Weight='normal'})) {
            $before=[IO.File]::ReadAllBytes($f.Path)
            $p=Get-TypezeroTerminalFontPreview @choice -SettingsPath $f.Path
            $r=Set-TypezeroTerminalFontChoice @choice -SettingsPath $f.Path -ExpectedSha256 $p.ExpectedSha256 -Confirm:$false
            Assert-True ($r.FontActivated -and $r.Changed -and $r.SettingsChanged) 'Apply did not report the font write.'
            Assert-True ([Convert]::ToBase64String([IO.File]::ReadAllBytes($r.BackupPath)) -ceq [Convert]::ToBase64String($before)) 'Backup is not exact previous bytes.'
            $target=Read-Target $f.Path
            Assert-True ($target.font.face -ceq $choice.Family -and $target.font.size -eq $choice.Size -and $target.font.weight -ceq $choice.Weight) 'Applied tuple differs.'
            $after=[IO.File]::ReadAllText($f.Path)
            foreach ($fragment in @($defaults,$other,'"colorScheme":"Gruvbox"','"theme":"Typezero Gruvbox"','"schemes":[{"name":"Gruvbox","background":"#282828"}]','/*size comment*/','"features":{"liga":0}','"axes":{"wdth":90}','Netzach נ')) { Assert-True ($after.Contains($fragment)) "Unowned text changed: $fragment" }
            Assert-True (-not [regex]::IsMatch($after,'(?<!\r)\n')) 'Line endings changed.'
            $bytes=[IO.File]::ReadAllBytes($f.Path)
            Assert-True ($bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) 'BOM changed.'
        }
    }
    Invoke-Regression 'Reapplying same tuple is byte-identical without a second backup' {
        $f=New-Fixture
        $null=Set-TypezeroTerminalFontChoice -Family 'Fixture A' -Size 12 -Weight normal -SettingsPath $f.Path -Confirm:$false
        $before=Snapshot $f.Root
        $p=Get-TypezeroTerminalFontPreview -Family 'Fixture A' -Size 12 -Weight normal -SettingsPath $f.Path
        $r=Set-TypezeroTerminalFontChoice -Family 'Fixture A' -Size 12 -Weight normal -SettingsPath $f.Path -Confirm:$false
        Assert-True (-not $p.WouldChange -and -not $r.Changed -and $null -eq $r.BackupPath) 'Idempotent choice reported another write.'
        Assert-True ((Snapshot $f.Root) -ceq $before) 'Idempotent apply wrote files.'
    }
    Invoke-Regression 'Missing font inherits defaults in preview and apply adds only the target override' {
        $text='{"profiles":{'+$defaults+'"list":[{"guid":"'+$guid+'","colorScheme":"Keep"},'+$other+']}}'
        $f=New-Fixture $text
        $p=Get-TypezeroTerminalFontPreview -Family 'Fixture A' -Size 12 -Weight normal -SettingsPath $f.Path
        Assert-True ($p.CurrentFamily -ceq 'Default Mono' -and $p.CurrentSize -eq 10 -and $p.CurrentWeight -eq 350) 'Preview ignored inherited typography.'
        $null=Set-TypezeroTerminalFontChoice -Family 'Fixture A' -Size 12 -Weight normal -SettingsPath $f.Path -Confirm:$false
        Assert-True ([IO.File]::ReadAllText($f.Path).Contains($defaults)) 'Default typography changed.'
        $f2=New-Fixture ('{"profiles":{"list":[{"guid":"'+$guid+'"}]}}')
        $p=Get-TypezeroTerminalFontPreview -Family 'Fixture A' -Size 12 -Weight normal -SettingsPath $f2.Path
        Assert-True ($p.CurrentFamily -ceq 'Cascadia Mono' -and $p.CurrentSize -eq 12 -and $p.CurrentWeight -ceq 'normal') 'Built-in fallback differs.'
    }
    Invoke-Regression 'Stale preview refuses apply before settings or backups change' {
        $f=New-Fixture
        $p=Get-TypezeroTerminalFontPreview -Family 'Fixture A' -Size 12 -Weight normal -SettingsPath $f.Path
        [IO.File]::AppendAllText($f.Path,"`r`n// concurrent edit")
        $before=Snapshot $f.Root
        Assert-Throws { Set-TypezeroTerminalFontChoice -Family 'Fixture A' -Size 12 -Weight normal -SettingsPath $f.Path -ExpectedSha256 $p.ExpectedSha256 -Confirm:$false } 'Stale preview was accepted.'
        Assert-True ((Snapshot $f.Root) -ceq $before) 'Stale apply wrote files.'
    }
    Invoke-Regression 'Invalid tuples fail before all writes' {
        $f=New-Fixture
        $before=Snapshot $f.Root
        foreach ($bad in @(@{Family=' ';Size=12;Weight='normal'},@{Family=' Mono';Size=12;Weight='normal'},@{Family='Mono';Size=5;Weight='normal'},@{Family='Mono';Size=37;Weight='normal'},@{Family='Mono';Size=12.001;Weight='normal'},@{Family='Mono';Size=[double]::NaN;Weight='normal'},@{Family='Mono';Size=[double]::PositiveInfinity;Weight='normal'},@{Family='Mono';Size=12;Weight='heavy'})) {
            Assert-Throws { Set-TypezeroTerminalFontChoice @bad -SettingsPath $f.Path -Confirm:$false } 'Invalid tuple accepted.'
        }
        Assert-True ((Snapshot $f.Root) -ceq $before) 'Invalid tuple wrote files.'
    }
    Invoke-Regression 'Invalid JSONC, duplicate keys/targets and nonobject fonts fail before backups' {
        foreach ($text in @('{bad','{"profiles":{"list":[]}}',('{"profiles":{"list":[{"guid":"'+$guid+'"},{"guid":"'+$guid+'"}]}}'),('{"profiles":{"list":[{"guid":"'+$guid+'","font":null}]}}'),('{"profiles":{"list":[{"guid":"'+$guid+'","font":{"face":"A","face":"B"}}]}}'))) {
            $f=New-Fixture $text
            $before=Snapshot $f.Root
            Assert-Throws { Set-TypezeroTerminalFontChoice -Family 'Fixture A' -Size 12 -Weight normal -SettingsPath $f.Path -Confirm:$false } 'Invalid settings accepted.'
            Assert-True ((Snapshot $f.Root) -ceq $before) 'Invalid settings wrote files.'
        }
    }
    Invoke-Regression 'Optional provider validation uses existing exact family and known Terminal alias rules' {
        function Get-TypezeroInstalledFontFamilies { @('Fixture A') }
        $f=New-Fixture
        foreach ($family in @('Fixture A','Old Mono','JetBrainsMono Nerd Font')) { $null=Get-TypezeroTerminalFontPreview -Family $family -Size 12 -Weight normal -SettingsPath $f.Path -ValidateInstalled }
        Assert-Throws { Get-TypezeroTerminalFontPreview -Family 'Missing Font' -Size 12 -Weight normal -SettingsPath $f.Path -ValidateInstalled } 'Unknown font accepted by provider validation.'
    }
    $themes=Join-Path $root 'themes'
    foreach ($id in @('gruvbox','nord')) { [IO.Directory]::CreateDirectory((Join-Path $themes $id)) | Out-Null; [IO.File]::WriteAllText((Join-Path $themes "$id\theme.conf"),"THEME_ID=$id`nBG=#282828`n") }
    $themesBefore=Snapshot $themes
    $presets=Join-Path $root 'custom\custom-presets.json'
    Invoke-Regression 'Empty preset list and WhatIf create no preset directory' {
        Assert-True (@(Get-TypezeroAppearancePresets -Path $presets).Count -eq 0) 'Missing file did not return an empty list.'
        $null=Save-TypezeroAppearancePreset -Name work -Theme gruvbox -Family 'Fixture A' -Size 12.5 -Weight normal -ThemesRoot $themes -Path $presets -WhatIf
        Assert-True (-not (Test-Path -LiteralPath (Split-Path -Parent $presets))) 'WhatIf created preset folder.'
    }
    Invoke-Regression 'Preset save and list persist choices separately without activating or changing themes' {
        $f=New-Fixture
        $before=Snapshot $f.Root
        $r=Save-TypezeroAppearancePreset -Name work -Theme gruvbox -Family 'Fixture A' -Size 12.5 -Weight normal -ThemesRoot $themes -Path $presets -Confirm:$false
        $list=@(Get-TypezeroAppearancePresets -Path $presets)
        Assert-True ($r.Status -ceq 'PresetSaved' -and $list.Count -eq 1 -and $list[0].Name -ceq 'work' -and $list[0].Theme -ceq 'gruvbox' -and $list[0].Family -ceq 'Fixture A' -and $list[0].Size -eq 12.5 -and $list[0].Weight -ceq 'normal') 'Preset round trip differs.'
        Assert-True ((Snapshot $f.Root) -ceq $before -and (Snapshot $themes) -ceq $themesBefore) 'Preset save activated or changed base themes.'
        $null=Save-TypezeroAppearancePreset -Name focus -Theme nord -Family 'Fixture B' -Size 16 -Weight semi-bold -ThemesRoot $themes -Path $presets -Confirm:$false
        Assert-True (@(Get-TypezeroAppearancePresets -Path $presets).Count -eq 2) 'Second preset lost the first.'
    }
    Invoke-Regression 'Preset overwrite requires Force and preserves exact prior file backup' {
        $before=Snapshot (Split-Path -Parent $presets)
        Assert-Throws { Save-TypezeroAppearancePreset -Name work -Theme nord -Family 'Fixture B' -Size 15 -Weight semi-bold -ThemesRoot $themes -Path $presets -Confirm:$false } 'Duplicate preset overwritten without Force.'
        Assert-True ((Snapshot (Split-Path -Parent $presets)) -ceq $before) 'Refused overwrite wrote files.'
        $original=[Convert]::ToBase64String([IO.File]::ReadAllBytes($presets))
        $r=Save-TypezeroAppearancePreset -Name work -Theme nord -Family 'Fixture B' -Size 15 -Weight semi-bold -ThemesRoot $themes -Path $presets -Force -Confirm:$false
        Assert-True ([Convert]::ToBase64String([IO.File]::ReadAllBytes($r.BackupPath)) -ceq $original) 'Preset backup differs from exact previous file.'
        $list=@(Get-TypezeroAppearancePresets -Path $presets)
        Assert-True ($list.Count -eq 2 -and @($list | Where-Object { $_.Name -ceq 'work' -and $_.Theme -ceq 'nord' -and $_.Size -eq 15 }).Count -eq 1) 'Forced replacement lost entries or differs.'
    }
    Invoke-Regression 'Invalid preset names, missing base themes and invalid typography cannot save' {
        $before=Snapshot (Split-Path -Parent $presets)
        foreach ($bad in @(@{Name='../escape';Theme='nord';Family='Fixture A';Size=12;Weight='normal'},@{Name='MixedCase';Theme='nord';Family='Fixture A';Size=12;Weight='normal'},@{Name='missing';Theme='absent';Family='Fixture A';Size=12;Weight='normal'},@{Name='bad-font';Theme='nord';Family='Fixture A';Size=12.001;Weight='normal'})) {
            Assert-Throws { Save-TypezeroAppearancePreset @bad -ThemesRoot $themes -Path $presets -Confirm:$false } 'Invalid preset saved.'
        }
        Assert-True ((Snapshot (Split-Path -Parent $presets)) -ceq $before) 'Invalid preset changed files.'
    }
    Invoke-Regression 'Malformed preset document and duplicate entries are preserved and rejected' {
        foreach ($text in @('{bad','{"Version":true,"Presets":[]}','{"Version":"1","Presets":[]}','{"Version":1,"Presets":{}}','{"Version":1,"Presets":[{"Name":"bad","Theme":"nord","Family":"X","Size":"12","Weight":"normal"}]}','{"Version":1,"Presets":[],"Presets":[]}','{"Version":1,"Presets":[{"Name":"same","Theme":"nord","Family":"X","Size":12,"Weight":"normal"},{"Name":"same","Theme":"nord","Family":"X","Size":12,"Weight":"normal"}]}')) {
            $f=New-Fixture $text
            $before=Snapshot $f.Root
            Assert-Throws { Get-TypezeroAppearancePresets -Path $f.Path } 'Invalid preset file read succeeded.'
            Assert-Throws { Save-TypezeroAppearancePreset -Name good -Theme nord -Family 'Fixture A' -Size 12 -Weight normal -ThemesRoot $themes -Path $f.Path -Confirm:$false } 'Invalid preset file overwritten.'
            Assert-True ((Snapshot $f.Root) -ceq $before) 'Damaged preset was changed.'
        }
    }
    Write-Host "Passed $script:passed independent font/preset regressions."
}
finally { Write-Host "Disposable fixtures retained: $root" }
