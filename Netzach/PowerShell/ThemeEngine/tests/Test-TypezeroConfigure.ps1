# Interactive configure regressions. LOCALAPPDATA and theme application are fixtures.
# Run: pwsh -NoProfile -File .\tests\Test-TypezeroConfigure.ps1
[CmdletBinding()]
param([string]$FixtureParent = [IO.Path]::GetTempPath())
$ErrorActionPreference='Stop'
$source=Split-Path -Parent $PSScriptRoot
. (Join-Path $source 'Configure-WindowsTerminal.ps1')
$originalLocalAppData=$env:LOCALAPPDATA
$root=Join-Path ([IO.Path]::GetFullPath($FixtureParent)) ('typezero-configure-'+[guid]::NewGuid().ToString('N'))
$script:caseNumber=0; $script:passed=0
function Assert-True { param([bool]$Condition,[string]$Message) if (-not $Condition) { throw "FAIL: $Message" } }
function Assert-Throws { param([scriptblock]$Action,[string]$Message) $thrown=$false; try { & $Action | Out-Null } catch {$thrown=$true}; Assert-True $thrown $Message }
function Case { param([string]$Name,[scriptblock]$Action) & $Action; $script:passed++; Write-Host "PASS [$script:passed] $Name" }
function Write-Text { param([string]$Path,[string]$Text) [IO.File]::WriteAllText($Path,$Text,[Text.UTF8Encoding]::new($false)) }
function Snapshot { param([string]$Folder) (@(Get-ChildItem -LiteralPath $Folder -Recurse -File | Sort-Object FullName | ForEach-Object { $_.FullName+':'+(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }) -join "`n") }
function New-Fixture {
    $script:caseNumber++
    $caseRoot=Join-Path $root ('case-'+$script:caseNumber)
    $env:LOCALAPPDATA=Join-Path $caseRoot 'local-app-data'
    $themes=Join-Path $env:LOCALAPPDATA 'Typezero\ThemeEngine\themes'
    $settings=Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
    $fakeEngine=Join-Path $caseRoot 'fake-engine'
    foreach($folder in @((Split-Path -Parent $settings),$fakeEngine,(Join-Path $themes 'gruvbox'),(Join-Path $themes 'nord'))) { [IO.Directory]::CreateDirectory($folder)|Out-Null }
    foreach($id in @('gruvbox','nord')) {
        $palette="THEME_ID=$id`nTHEME_NAME=Fixture $id`nBG=#101010`nTEXT=#eeeeee`nCURSOR=#ffffff`nSELECTION=#555555`nACCENT=#88c0d0`nBORDER=#333333`nACCENT_BRIGHT=#aaddff`n"
        foreach($key in @('SURFACE','SURFACE_ALT','BRIGHT','MUTED','SECONDARY','INFO','FOCUS','SUCCESS','WARNING','ERROR')) {$palette+="$key=#999999`n"}
        foreach($key in @('BLACK','RED','GREEN','YELLOW','BLUE','PURPLE','CYAN','WHITE','BRIGHT_BLACK','BRIGHT_RED','BRIGHT_GREEN','BRIGHT_YELLOW','BRIGHT_BLUE','BRIGHT_PURPLE','BRIGHT_CYAN','BRIGHT_WHITE')) {$palette+="ANSI_$key=#999999`n"}
        Write-Text (Join-Path $themes "$id\theme.conf") $palette
    }
    Write-Text (Join-Path (Split-Path -Parent $themes) 'current-theme') 'nord'
    Write-Text $settings '{"profiles":{"defaults":{"font":{"face":"Courier New","size":12,"weight":"normal"}},"list":[{"guid":"{574e775e-4f2a-5b96-ac1e-a2962a402336}","name":"PowerShell 7","font":{"face":"Consolas","size":17.25,"weight":"medium"},"colorScheme":"User Colors"},{"guid":"unrelated","font":{"face":"Courier New","size":9},"colorScheme":"Keep"}]},"theme":"User Appearance","schemes":[{"name":"User Colors","background":"#282828"}]}'
    $applyScript=@'
param([string]$Command,[string]$Theme,[System.Collections.IDictionary]$TerminalFont,[string]$ExpectedSettingsSha256)
$ErrorActionPreference='Stop'
. '__CONTROL__'
$null=Set-TypezeroTerminalFontChoice -Family $TerminalFont['face'] -Size $TerminalFont['size'] -Weight $TerminalFont['weight'] -Confirm:$false
$target=Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
$data=[IO.File]::ReadAllText($target)|ConvertFrom-Json -AsHashtable
$data.profiles.list[0].colorScheme='Fixture '+$Theme
[IO.File]::WriteAllText($target,($data|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'apply-log.json'),([ordered]@{Theme=$Theme;Font=$TerminalFont}|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
if(Test-Path -LiteralPath (Join-Path $PSScriptRoot 'throw-after-write')) {throw 'Fixture theme failed after writing appearance.'}
'@
    Write-Text (Join-Path $fakeEngine 'ThemeEngine.ps1') ($applyScript.Replace('__CONTROL__',(Join-Path $source 'TerminalFontControl-WindowsTerminal.ps1')))
    Copy-Item -LiteralPath (Join-Path $source 'ThemePresentation.ps1') -Destination $fakeEngine
    [pscustomobject]@{Root=$caseRoot;Themes=$themes;Settings=$settings;Engine=$fakeEngine;Presets=(Join-Path (Split-Path -Parent $themes) 'custom-presets.json');Log=(Join-Path $fakeEngine 'apply-log.json')}
}
function Run-Menu {
    param($Fixture,[AllowEmptyCollection()][string[]]$Answers,[scriptblock]$BeforeRead)
    $queue=[Collections.Generic.Queue[string]]::new()
    foreach($answer in $Answers) {$queue.Enqueue($answer)}
    $lines=[Collections.Generic.List[string]]::new()
    $reader={param($Prompt) if($BeforeRead) {& $BeforeRead $Prompt $queue.Count}; if($queue.Count) {return $queue.Dequeue()}; return $null}.GetNewClosure()
    $writer={param($Text) $lines.Add([string]$Text)}.GetNewClosure()
    $result=Invoke-TypezeroThemeConfigure -EngineRoot $Fixture.Engine -ThemesRoot $Fixture.Themes -ReadInput $reader -WriteOutput $writer
    [pscustomobject]@{Result=$result;Lines=$lines.ToArray();Remaining=$queue.Count}
}
function Target {param($Fixture) ([IO.File]::ReadAllText($Fixture.Settings)|ConvertFrom-Json -AsHashtable).profiles.list[0]}
try {
    Assert-True (@(Get-TypezeroInstalledFontFamilies | Where-Object {$_ -ceq 'Consolas'}).Count -eq 1) 'Consolas must be installed for interactive fixtures.'
    Case 'Initial theme and complete typography come from current files; cancel is byte-identical' {
        $f=New-Fixture; $before=Snapshot $f.Root; $run=Run-Menu $f @('q')
        Assert-True ($run.Result.Theme -ceq 'nord' -and $run.Result.Family -ceq 'Consolas' -and $run.Result.Size -eq 17.25 -and $run.Result.Weight -ceq 'medium') 'Initial choices were hard-coded.'
        Assert-True ($run.Result.Status -ceq 'Cancelled' -and -not $run.Result.SessionChanged -and (Snapshot $f.Root) -ceq $before) 'Cancel wrote files.'
    }
    Case 'EOF at main and each pending picker/name/size cancels without writes' {
        foreach($answers in @(@(),@('1'),@('2'),@('3'),@('4'),@('8'),@('10'),@('11'))) {
            $f=New-Fixture; $before=Snapshot $f.Root; $run=Run-Menu $f $answers
            Assert-True ($run.Result.Status -ceq 'Cancelled' -and -not $run.Result.SessionChanged -and (Snapshot $f.Root) -ceq $before) 'EOF wrote files or failed to return.'
        }
    }
    Case 'Invalid menu, theme numbers, font names, sizes and weights cannot change choices or files' {
        $f=New-Fixture; $before=Snapshot $f.Root
        $run=Run-Menu $f @('bogus','1','3','q','2','NoSuchFont-Typezero','q','3','NaN','3','5.99','3','12.001','4','heavy','q','q')
        Assert-True ($run.Result.Theme -ceq 'nord' -and $run.Result.Family -ceq 'Consolas' -and $run.Result.Size -eq 17.25 -and $run.Result.Weight -ceq 'medium') 'Bad input became a choice.'
        Assert-True (($run.Lines -join "`n") -match 'Invalid selection number' -and (Snapshot $f.Root) -ceq $before) 'Invalid input was accepted or wrote files.'
    }
    Case 'Search and numbered choices select actual items; Preview stays read-only' {
        $f=New-Fixture; $before=Snapshot $f.Root
        $run=Run-Menu $f @('1','/gruv','1','2','/Consolas','1','3','15.25','4','/medium','1','5','q')
        Assert-True ($run.Result.Theme -ceq 'gruvbox' -and $run.Result.Family -ceq 'Consolas' -and $run.Result.Size -eq 15.25 -and $run.Result.Weight -ceq 'medium') 'Filtered number failed to resolve an installed item.'
        Assert-True (($run.Lines -join "`n") -match 'Preview only' -and (Snapshot $f.Root) -ceq $before) 'Preview changed files.'
    }
    Case 'Picker pages contain at most fifteen rows and preserve filtered numbering' {
        $answers=[Collections.Generic.Queue[string]]::new(); @('n','/Font 35','1')|ForEach-Object {$answers.Enqueue($_)}
        $lines=[Collections.Generic.List[string]]::new()
        $selection=Select-TypezeroConfigureItem -Label Test -Items @(1..40|ForEach-Object {'Font {0:00}' -f $_}) -ReadInput {$answers.Dequeue()} -WriteOutput {param($Text) $lines.Add([string]$Text)}
        Assert-True ($selection.Value -ceq 'Font 35' -and ($lines -join "`n").Contains('page 2/3')) 'Paging/search selection differs.'
        Assert-True (@($lines|Where-Object {$_ -match '^  \d+\.'}).Count -eq 31) 'Picker dumped an unbounded font list.'
    }
    Case 'Apply Font changes only fixture font and preserves exact backup; exit reports completed action' {
        $f=New-Fixture; $themes=Snapshot $f.Themes; $original=[Convert]::ToBase64String([IO.File]::ReadAllBytes($f.Settings))
        $run=Run-Menu $f @('3','16.5','4','bold','6','q')
        $font=(Target $f).font; $data=[IO.File]::ReadAllText($f.Settings)|ConvertFrom-Json -AsHashtable
        Assert-True ($run.Result.SessionChanged -and $font.face -ceq 'Consolas' -and $font.size -eq 16.5 -and $font.weight -ceq 'bold') 'Font apply lost choices.'
        Assert-True ((Target $f).colorScheme -ceq 'User Colors' -and $data.theme -ceq 'User Appearance' -and $data.profiles.list[1].font.size -eq 9 -and (Snapshot $f.Themes) -ceq $themes -and -not (Test-Path $f.Presets) -and -not (Test-Path $f.Log)) 'Font apply changed unrelated appearance/preferences.'
        $backups=@(Get-ChildItem -LiteralPath (Split-Path $f.Settings) -File|Where-Object Name -ne 'settings.json')
        Assert-True ($backups.Count -eq 1 -and [Convert]::ToBase64String([IO.File]::ReadAllBytes($backups[0].FullName)) -ceq $original) 'Font backup differs.'
    }
    Case 'Theme plus font dispatches the shared public apply action with the chosen tuple' {
        $f=New-Fixture; $themes=Snapshot $f.Themes
        $run=Run-Menu $f @('1','gruvbox','3','18','4','semi-light','7','q')
        $log=[IO.File]::ReadAllText($f.Log)|ConvertFrom-Json
        Assert-True ($run.Result.SessionChanged -and $log.Theme -ceq 'gruvbox' -and $log.Font.face -ceq 'Consolas' -and $log.Font.size -eq 18 -and $log.Font.weight -ceq 'semi-light') 'Theme apply lost choices.'
        Assert-True ((Snapshot $f.Themes) -ceq $themes -and -not (Test-Path $f.Presets)) 'Theme apply changed base themes or saved a preference.'
    }
    Case 'Partial theme failure remains explicit when the user cancels the menu' {
        $f=New-Fixture; $themes=Snapshot $f.Themes
        Write-Text (Join-Path $f.Engine 'throw-after-write') 'fixture failure after apply'
        $run=Run-Menu $f @('1','gruvbox','3','18','7','q')
        Assert-True ($run.Result.Status -ceq 'Cancelled' -and -not $run.Result.SessionChanged -and $run.Result.AppearanceMayHaveChanged -and $run.Result.LastError -like '*appearance may be partial*') 'Cancellation concealed partial theme failure.'
        Assert-True ((Target $f).font.size -eq 18 -and (Target $f).colorScheme -ceq 'Fixture gruvbox' -and (Snapshot $f.Themes) -ceq $themes) 'Partial-failure fixture did not exercise a completed appearance write.'
    }
    Case 'Named Save/List/Load restores actual saved tuple without activating it' {
        $f=New-Fixture; $settings=Snapshot (Split-Path $f.Settings); $themes=Snapshot $f.Themes
        $run=Run-Menu $f @('1','gruvbox','3','14.5','4','light','8','desk','9','3','22','4','black','10','/desk','1','q')
        Assert-True ($run.Result.Theme -ceq 'gruvbox' -and $run.Result.Size -eq 14.5 -and $run.Result.Weight -ceq 'light' -and $run.Result.PresetName -ceq 'desk' -and $run.Result.PreferencesSaved -and -not $run.Result.SessionChanged) 'Load did not restore the saved tuple.'
        Assert-True (($run.Lines -join "`n").Contains('desk: gruvbox') -and (Snapshot (Split-Path $f.Settings)) -ceq $settings -and (Snapshot $f.Themes) -ceq $themes -and -not (Test-Path $f.Log)) 'Save/List/Load changed appearance or base themes.'
    }
    Case 'Invalid preset names and cancelled replacement leave all bytes unchanged' {
        $f=New-Fixture; $null=Save-TypezeroAppearancePreset -Name desk -Theme nord -Family Consolas -Size 17.25 -Weight medium -Confirm:$false
        $before=Snapshot $f.Root
        $run=Run-Menu $f @('8','../escape','8','desk','no','8','q','q')
        Assert-True ((Snapshot $f.Root) -ceq $before -and -not $run.Result.PreferencesSaved) 'Bad save or cancelled replacement wrote files.'
    }
    Case 'Apply preset loads exact saved theme and font through shared action' {
        $f=New-Fixture; $null=Save-TypezeroAppearancePreset -Name desk -Theme gruvbox -Family Consolas -Size 14.75 -Weight medium -Confirm:$false
        $preset=Snapshot (Split-Path $f.Presets); $themes=Snapshot $f.Themes
        $run=Run-Menu $f @('11','desk','q'); $log=[IO.File]::ReadAllText($f.Log)|ConvertFrom-Json
        Assert-True ($run.Result.SessionChanged -and $log.Theme -ceq 'gruvbox' -and $log.Font.size -eq 14.75 -and $log.Font.weight -ceq 'medium') 'Apply preset did not load typography.'
        Assert-True ((Snapshot $f.Themes) -ceq $themes -and (Snapshot (Split-Path $f.Presets)) -ceq $preset) 'Apply preset changed theme definitions or saved preferences.'
    }
    Case 'A stale Preview refuses font apply before creating a backup' {
        $f=New-Fixture
        $hook={param($Prompt,$Count) if($Prompt -ceq 'Action' -and $Count -eq 2) {[IO.File]::AppendAllText($f.Settings,"`n// external fixture change")}}.GetNewClosure()
        $run=Run-Menu $f @('5','6','q') $hook
        Assert-True (($run.Lines -join "`n") -match 'changed since Preview' -and -not $run.Result.SessionChanged -and (Target $f).font.size -eq 17.25) 'Stale Preview was applied.'
        Assert-True (@(Get-ChildItem -LiteralPath (Split-Path $f.Settings) -File).Count -eq 1) 'Stale apply created backup.'
    }
    Case 'Public CLI preview-theme, load-preset and apply-font retain direct command parity' {
        $f=New-Fixture; $before=Snapshot $f.Root
        $engine=Join-Path $source 'ThemeEngine.ps1'
        $preview=& $engine font preview-theme gruvbox Consolas 15.25 medium
        Assert-True ($preview.Family -ceq 'Consolas' -and $preview.Size -eq 15.25 -and $preview.Weight -ceq 'medium' -and (Snapshot $f.Root) -ceq $before) 'Public preview-theme differs or writes.'
        $null=& $engine font save-preset desk gruvbox Consolas 15.25 medium
        $before=Snapshot $f.Root
        $loaded=& $engine font load-preset desk
        Assert-True ($loaded.Theme -ceq 'gruvbox' -and $loaded.Family -ceq 'Consolas' -and $loaded.Size -eq 15.25 -and $loaded.Weight -ceq 'medium' -and (Snapshot $f.Root) -ceq $before) 'Public load-preset failed to return exact read-only choices.'
        $applied=& $engine font apply-font Consolas 15.25 medium -ExpectedSettingsSha256 $preview.ExpectedSha256
        Assert-True ($applied.FontActivated -and (Target $f).font.weight -ceq 'medium' -and (Target $f).colorScheme -ceq 'User Colors') 'Public apply-font lost typography or changed colors.'
        $combined=Invoke-TypezeroFontCommand -Action apply-theme -Arguments @('gruvbox','Consolas','16.5','medium') -EngineRoot $f.Engine -ThemesRoot $f.Themes
        $log=[IO.File]::ReadAllText($f.Log)|ConvertFrom-Json
        Assert-True ($combined.Status -ceq 'ThemeApplied' -and $log.Theme -ceq 'gruvbox' -and $log.Font.size -eq 16.5 -and $log.Font.weight -ceq 'medium') 'Direct apply-theme dispatcher differs.'
    }
    Case 'Direct commands reject uninstalled fonts, missing themes, malformed sizes and weights before writes' {
        $f=New-Fixture; $before=Snapshot $f.Root
        foreach($argsList in @(@('gruvbox','Missing-Typezero-Font','12','medium'),@('missing','Consolas','12','medium'),@('3','Consolas','12','medium'),@('gruvbox','Consolas','NaN','medium'),@('gruvbox','Consolas','12.001','medium'),@('gruvbox','Consolas','12','heavy'))) {
            Assert-Throws {Invoke-TypezeroFontCommand -Action apply-theme -Arguments $argsList -EngineRoot $f.Engine -ThemesRoot $f.Themes} 'Invalid direct theme apply was accepted.'
        }
        Assert-Throws {& (Join-Path $source 'ThemeEngine.ps1') font apply-font Missing-Typezero-Font 12 medium} 'Public font apply accepted an uninstalled family.'
        Assert-True ((Snapshot $f.Root) -ceq $before) 'Bad direct arguments wrote files.'
    }
    Case 'Preset load validates saved font installation and keeps invalid choices inactive' {
        $f=New-Fixture
        Write-Text $f.Presets '{"Version":1,"Presets":[{"Name":"bad","Theme":"gruvbox","Family":"Missing-Typezero-Font","Size":14.5,"Weight":"medium"}]}'
        $before=Snapshot $f.Root; $run=Run-Menu $f @('10','bad','q')
        Assert-True ($run.Result.Theme -ceq 'nord' -and $run.Result.Family -ceq 'Consolas' -and $run.Result.Size -eq 17.25 -and ($run.Lines -join "`n") -match 'installed' -and (Snapshot $f.Root) -ceq $before) 'Invalid preset font became active or wrote files.'
    }
    Write-Host "All $script:passed configure regression groups passed ($script:caseNumber disposable fixtures). Fixtures: $root"
}
finally {if($null -eq $originalLocalAppData) {Remove-Item Env:\LOCALAPPDATA -ErrorAction SilentlyContinue} else {$env:LOCALAPPDATA=$originalLocalAppData}}
