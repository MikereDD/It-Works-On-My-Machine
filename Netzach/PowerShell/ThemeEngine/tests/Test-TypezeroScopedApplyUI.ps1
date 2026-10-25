# Scoped dispatch fixtures. Windows and Terminal appearance are never activated.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$FixtureParent)
$ErrorActionPreference='Stop'
if([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {throw 'Run with pwsh -STA.'}
$source=Split-Path -Parent $PSScriptRoot
. (Join-Path $source 'Configure-WindowsTerminal.ps1')
. (Join-Path $source 'ThemeFontPreview-WindowsTerminal.ps1')
Add-Type -AssemblyName PresentationFramework
$originalLocalAppData=$env:LOCALAPPDATA
$root=Join-Path ([IO.Path]::GetFullPath($FixtureParent)) ('typezero-scoped-ui-'+[guid]::NewGuid().ToString('N'))
$script:caseNumber=0;$script:passed=0
function Assert-True {param([bool]$Condition,[string]$Message) if(-not $Condition){throw "FAIL: $Message"}}
function Case {param([string]$Name,[scriptblock]$Action) & $Action;$script:passed++;Write-Host "PASS [$script:passed] $Name"}
function Write-Text {param([string]$Path,[string]$Text) [IO.File]::WriteAllText($Path,$Text,[Text.UTF8Encoding]::new($false))}
function Snapshot {param([string]$Folder) (@(Get-ChildItem -LiteralPath $Folder -Recurse -File|Sort-Object FullName|ForEach-Object {$_.FullName+':'+(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}) -join "`n")}
function New-Fixture {
    $script:caseNumber++
    $folder=Join-Path $root ('case-'+$script:caseNumber)
    $env:LOCALAPPDATA=Join-Path $folder 'local-app-data'
    $themes=Join-Path $env:LOCALAPPDATA 'Typezero\ThemeEngine\themes'
    $settings=Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
    $engine=Join-Path $folder 'fake-engine'
    foreach($path in @((Split-Path $settings),$engine,(Join-Path $themes 'gruvbox'))) {[IO.Directory]::CreateDirectory($path)|Out-Null}
    $palette="THEME_ID=gruvbox`nTHEME_NAME=Fixture Gruvbox`n"
    foreach($key in @('BG','TEXT','CURSOR','SELECTION','ACCENT','BORDER','ACCENT_BRIGHT','SURFACE','SURFACE_ALT','BRIGHT','MUTED','SECONDARY','INFO','FOCUS','SUCCESS','WARNING','ERROR')) {$palette+="$key=#999999`n"}
    foreach($key in @('BLACK','RED','GREEN','YELLOW','BLUE','PURPLE','CYAN','WHITE','BRIGHT_BLACK','BRIGHT_RED','BRIGHT_GREEN','BRIGHT_YELLOW','BRIGHT_BLUE','BRIGHT_PURPLE','BRIGHT_CYAN','BRIGHT_WHITE')) {$palette+="ANSI_$key=#999999`n"}
    Write-Text (Join-Path $themes 'gruvbox\theme.conf') $palette
    Write-Text (Join-Path (Split-Path $themes) 'current-theme') 'gruvbox'
    Write-Text $settings '{"profiles":{"defaults":{},"list":[{"guid":"{574e775e-4f2a-5b96-ac1e-a2962a402336}","name":"Renamed PowerShell","font":{"face":"Consolas","size":17.25,"weight":"medium"},"colorScheme":"User Colors"}]},"theme":"User Appearance","schemes":[]}'
    $stub=@'
[CmdletBinding()]
param([string]$Command,[string]$Theme,[System.Collections.IDictionary]$TerminalFont,[string]$ExpectedSettingsSha256)
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'apply-log.json'),([ordered]@{Command=$Command;Theme=$Theme;Font=$TerminalFont;Expected=$ExpectedSettingsSha256;BoundKeys=@($PSBoundParameters.Keys)}|ConvertTo-Json -Depth 6))
$partial=Test-Path -LiteralPath (Join-Path $PSScriptRoot 'partial')
$noop=Test-Path -LiteralPath (Join-Path $PSScriptRoot 'no-change')
[pscustomobject]@{Status=$(if($partial){'Partial'}elseif($noop){'NoChange'}else{'Applied'});Operation=$Command;Theme=$Theme;
    Complete=(-not $partial);Changed=(-not $noop);AppearanceMayHaveChanged=(-not $noop);
    Targets=@([pscustomobject]@{Target='Shell';Status=$(if($noop){'NoChange'}else{'Applied'});Changed=(-not $noop);Message='Fixture colors verified.'},
        [pscustomobject]@{Target='Desktop';Status=$(if($partial){'Failed'}else{'Skipped'});Changed=$false;Message=$(if($partial){'Fixture native activation failed.'}else{'Not requested.'})})}
'@
    Write-Text (Join-Path $engine 'ThemeEngine.ps1') $stub
    [pscustomobject]@{Root=$folder;Themes=$themes;Settings=$settings;Engine=$engine;Log=(Join-Path $engine 'apply-log.json');Presets=(Join-Path (Split-Path $themes) 'custom-presets.json')}
}
function Selection {param([string]$Action,[string]$Expected) [pscustomobject]@{Action=$Action;Theme='gruvbox';Family='Consolas';Size=[double]14.25;Weight='medium';PresetName='';ExpectedSha256=$Expected;PreviewOnly=$true;SettingsChanged=$false}}
function Read-Log {param($Fixture) [IO.File]::ReadAllText($Fixture.Log)|ConvertFrom-Json}
function Run-Menu {
    param($Fixture,[string[]]$Answers)
    $queue=[Collections.Generic.Queue[string]]::new();foreach($answer in $Answers){$queue.Enqueue($answer)}
    $lines=[Collections.Generic.List[string]]::new()
    $reader={param($Prompt) if($queue.Count){return $queue.Dequeue()};return $null}.GetNewClosure()
    $writer={param($Text) $lines.Add([string]$Text)}.GetNewClosure()
    $result=Invoke-TypezeroThemeConfigure -EngineRoot $Fixture.Engine -ThemesRoot $Fixture.Themes -ReadInput $reader -WriteOutput $writer
    [pscustomobject]@{Result=$result;Lines=$lines.ToArray()}
}
function Click {param($Button) $Button.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))}
try {
    Case 'Shared dispatch forwards only included components and the displayed snapshot' {
        $commands=[ordered]@{ApplyShell='apply-shell';ApplyDesktop='apply-desktop';ApplyShellFont='apply-shell-font';ApplyDesktopShell='apply-desktop-shell';ApplyAll='apply-all'}
        foreach($action in $commands.Keys) {
            $f=New-Fixture;$expected=Get-TypezeroAppearanceSettingsSnapshot
            $result=Invoke-TypezeroAppearanceSelection -Selection (Selection $action $expected) -EngineRoot $f.Engine -ThemesRoot $f.Themes
            $log=Read-Log $f
            Assert-True ($result.Complete -and $result.Status -ceq 'Applied' -and $log.Command -ceq $commands[$action] -and $log.Theme -ceq 'gruvbox') "Wrong dispatch: $action"
            $hasFont=$action -in @('ApplyShellFont','ApplyAll')
            Assert-True (($log.BoundKeys -contains 'TerminalFont') -eq $hasFont) "Excluded font leaked into $action"
            if($hasFont){Assert-True ($log.Font.face -ceq 'Consolas' -and $log.Font.size -eq 14.25 -and $log.Font.weight -ceq 'medium') 'Chosen tuple changed.'}
            Assert-True (($log.BoundKeys -contains 'ExpectedSettingsSha256') -eq ($action -cne 'ApplyDesktop')) 'Wrong snapshot dependency.'
        }
    }
    Case 'Excluded invalid font choices cannot block shell or desktop' {
        foreach($action in @('ApplyShell','ApplyDesktop','ApplyDesktopShell')) {
            $f=New-Fixture;$selection=Selection $action (Get-TypezeroAppearanceSettingsSnapshot)
            $selection.Family='Unavailable Fixture Font';$selection.Size=[double]0;$selection.Weight='invalid'
            if($action -ceq 'ApplyDesktop'){Write-Text $f.Settings '{malformed fixture settings';$selection.ExpectedSha256=''}
            $result=Invoke-TypezeroAppearanceSelection -Selection $selection -EngineRoot $f.Engine -ThemesRoot $f.Themes
            Assert-True ($result.Complete -and (Read-Log $f).BoundKeys -notcontains 'TerminalFont') 'Excluded font blocked or leaked.'
        }
    }
    Case 'Stale snapshots reject dispatch and cancellation is byte-identical' {
        foreach($action in @('ApplyShell','ApplyShellFont','ApplyDesktopShell','ApplyAll')) {
            $f=New-Fixture;$selection=Selection $action (Get-TypezeroAppearanceSettingsSnapshot)
            [IO.File]::AppendAllText($f.Settings,"`n// intervening disposable edit")
            $before=Snapshot $f.Root;$rejected=$false
            try{Invoke-TypezeroAppearanceSelection -Selection $selection -EngineRoot $f.Engine -ThemesRoot $f.Themes|Out-Null}catch{$rejected=$true}
            Assert-True ($rejected -and (Snapshot $f.Root) -ceq $before -and -not (Test-Path $f.Log)) 'Stale snapshot accepted or wrote files.'
            $cancelled=Invoke-TypezeroAppearanceSelection -Selection $null -EngineRoot $f.Engine -ThemesRoot $f.Themes
            Assert-True ($cancelled.Status -ceq 'Cancelled' -and (Snapshot $f.Root) -ceq $before) 'Cancellation wrote files.'
        }
    }
    Case 'Partial target results survive dispatch and closing configure' {
        $f=New-Fixture;Write-Text (Join-Path $f.Engine 'partial') 'fixture'
        $run=Run-Menu $f @('15','q')
        Assert-True ($run.Result.LastResult.Status -ceq 'Partial' -and -not $run.Result.LastResult.Complete -and $run.Result.AppearanceMayHaveChanged -and $run.Result.LastError -match 'Desktop: Failed' -and $run.Result.LastResult.Targets[0].Status -ceq 'Applied') 'Partial result hidden or promoted to success.'
    }
    Case 'Every configure scope dispatches correctly; font-only verifies backup and readback' {
        foreach($row in @(@('7','apply'),@('12','apply-shell'),@('13','apply-desktop'),@('14','apply-shell-font'),@('15','apply-desktop-shell'))) {
            $f=New-Fixture;$run=Run-Menu $f @($row[0],'q');$log=Read-Log $f
            Assert-True ($log.Command -ceq $row[1] -and $run.Result.LastResult.Complete) "Menu $($row[0]) dispatched incorrectly."
        }
        $f=New-Fixture;$before=[IO.File]::ReadAllBytes($f.Settings);$run=Run-Menu $f @('3','15.5','6','q')
        $target=([IO.File]::ReadAllText($f.Settings)|ConvertFrom-Json -AsHashtable).profiles.list[0]
        Assert-True ($target.font.size -eq 15.5 -and $target.colorScheme -ceq 'User Colors' -and -not (Test-Path $f.Log)) 'Font scope changed colors or dispatched full apply.'
        $backup=@(Get-ChildItem -LiteralPath (Split-Path $f.Settings) -File|Where-Object Name -ne 'settings.json')
        Assert-True ($backup.Count -eq 1 -and [Convert]::ToBase64String([IO.File]::ReadAllBytes($backup[0].FullName)) -ceq [Convert]::ToBase64String($before)) 'Font backup differs.'
    }
    Case 'NoChange does not record a changed configure session' {
        $f=New-Fixture;Write-Text (Join-Path $f.Engine 'no-change') 'fixture'
        $run=Run-Menu $f @('12','q')
        Assert-True ($run.Result.LastResult.Status -ceq 'NoChange' -and $run.Result.LastResult.Complete -and -not $run.Result.SessionChanged -and -not $run.Result.AppearanceMayHaveChanged) 'No-op reported as change.'
    }
    Case 'Loaded preset values compose with scope without applying font or saving preferences' {
        $f=New-Fixture;$null=Save-TypezeroAppearancePreset -Name scoped -Theme gruvbox -Family Consolas -Size 16.5 -Weight bold -Confirm:$false
        $presetBefore=Snapshot (Split-Path $f.Presets)
        $run=Run-Menu $f @('10','scoped','12','q');$log=Read-Log $f
        Assert-True ($log.Command -ceq 'apply-shell' -and $log.Theme -ceq 'gruvbox' -and $log.BoundKeys -notcontains 'TerminalFont' -and $run.Result.Size -eq 16.5 -and (Snapshot (Split-Path $f.Presets)) -ceq $presetBefore) 'Preset scope composition changed preferences or typography.'
    }
    Case 'WhatIf keeps all scoped dispatch read-only' {
        foreach($action in @('ApplyShell','ApplyDesktop','ApplyShellFont','ApplyDesktopShell','ApplyAll')) {
            $f=New-Fixture;$before=Snapshot $f.Root
            $result=Invoke-TypezeroAppearanceSelection -Selection (Selection $action (Get-TypezeroAppearanceSettingsSnapshot)) -EngineRoot $f.Engine -ThemesRoot $f.Themes -WhatIf
            Assert-True ($result.Status -ceq 'NotExecuted' -and (Snapshot $f.Root) -ceq $before) 'WhatIf executed a scope.'
        }
    }
    Case 'Each real WPF button returns matching scope without writing files' {
        $buttons=[ordered]@{ApplyShellButton='ApplyShell';ApplyFontButton='ApplyFont';ApplyDesktopButton='ApplyDesktop';ApplyShellFontButton='ApplyShellFont';ApplyDesktopShellButton='ApplyDesktopShell';ApplyAllButton='ApplyTheme'}
        foreach($button in $buttons.Keys) {
            $f=New-Fixture;$before=Snapshot $f.Root;$expected=Get-TypezeroAppearanceSettingsSnapshot
            $result=Show-TypezeroThemeFontPreview -ThemesRoot $f.Themes -OnLoaded {param($window,$controls) Assert-True $controls[$button].IsEnabled "$button unavailable.";Click $controls[$button]}
            Assert-True ($result.Action -ceq $buttons[$button] -and $result.ExpectedSha256 -ceq $expected -and (Snapshot $f.Root) -ceq $before) "WPF $button wrote files or lost scope/snapshot."
        }
    }
    Case 'All WPF apply buttons and Cancel fit at the minimum window size' {
        $f=New-Fixture;$before=Snapshot $f.Root
        $null=Show-TypezeroThemeFontPreview -ThemesRoot $f.Themes -OnLoaded {
            param($window,$controls)
            # Measure the client content with conservative title-bar/frame space,
            # without showing a native window or activating an appearance target.
            $content=$window.Content
            $width=$window.MinWidth-16;$height=$window.MinHeight-39
            $content.Measure([Windows.Size]::new($width,$height))
            $content.Arrange([Windows.Rect]::new(0,0,$width,$height));$content.UpdateLayout()
            foreach($name in @('ApplyShellButton','ApplyFontButton','ApplyDesktopButton','ApplyShellFontButton','ApplyDesktopShellButton','ApplyAllButton','CancelButton')) {
                $button=$controls[$name]
                $position=$button.TransformToAncestor($content).Transform([Windows.Point]::new(0,0))
                Assert-True ($button.ActualWidth -gt 0 -and $button.ActualHeight -gt 0 -and
                    $position.X -ge 0 -and $position.Y -ge 0 -and
                    $position.X+$button.ActualWidth -le $content.ActualWidth+0.1 -and
                    $position.Y+$button.ActualHeight -le $content.ActualHeight+0.1) "$name is clipped at minimum window dimensions."
            }
        }
        Assert-True ((Snapshot $f.Root) -ceq $before) 'Layout inspection changed files.'
    }
    Case 'Real WPF excludes invalid typography from shell and desktop readiness' {
        foreach($button in @('ApplyShellButton','ApplyDesktopButton','ApplyDesktopShellButton')) {
            $f=New-Fixture;$before=Snapshot $f.Root
            $result=Show-TypezeroThemeFontPreview -ThemesRoot $f.Themes -OnLoaded {
                param($window,$controls)
                $controls.SizeBox.ApplyTemplate()|Out-Null
                $edit=$controls.SizeBox.Template.FindName('PART_EditableTextBox',$controls.SizeBox);$edit.Text='invalid'
                Assert-True (-not $controls.ApplyFontButton.IsEnabled -and -not $controls.ApplyShellFontButton.IsEnabled -and -not $controls.ApplyAllButton.IsEnabled) 'Invalid typography enabled font scope.'
                Assert-True $controls[$button].IsEnabled 'Excluded font disabled independent scope.'
                Click $controls[$button]
            }
            Assert-True ($null -ne $result -and (Snapshot $f.Root) -ceq $before) 'Excluded font prevented intent or changed files.'
        }
    }
    Case 'Real WPF Desktop works without Terminal; cancel is read-only' {
        $f=New-Fixture;Write-Text $f.Settings '{invalid disposable Terminal';$before=Snapshot $f.Root
        $result=Show-TypezeroThemeFontPreview -ThemesRoot $f.Themes -OnLoaded {
            param($window,$controls)
            Assert-True ($controls.ApplyDesktopButton.IsEnabled -and -not $controls.ApplyShellButton.IsEnabled -and -not $controls.ApplyDesktopShellButton.IsEnabled) 'Desktop depends on Terminal.'
            Click $controls.ApplyDesktopButton
        }
        Assert-True ($result.Action -ceq 'ApplyDesktop' -and (Snapshot $f.Root) -ceq $before) 'Desktop intent wrote files.'
        $cancel=Show-TypezeroThemeFontPreview -ThemesRoot $f.Themes -OnLoaded {param($window,$controls) Click $controls.CancelButton}
        Assert-True ($null -eq $cancel -and (Snapshot $f.Root) -ceq $before) 'WPF cancellation wrote files.'
    }
    Write-Host "All $script:passed scoped UI regression groups passed ($script:caseNumber disposable fixtures). Fixtures: $root"
}
finally {if($null -eq $originalLocalAppData){Remove-Item Env:\LOCALAPPDATA -ErrorAction SilentlyContinue}else{$env:LOCALAPPDATA=$originalLocalAppData}}
