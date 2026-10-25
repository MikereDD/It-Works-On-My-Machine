# Scoped-apply integration regressions. Every runtime file and settings backup
# belongs to a unique disposable LOCALAPPDATA. Native, wallpaper and Vim
# providers are replaced in the fixture before the real CLI is executed.
[CmdletBinding()]
param([string]$FixtureParent=[IO.Path]::GetTempPath(),[string]$RepositoryRoot)
$ErrorActionPreference='Stop'
$source=Split-Path -Parent $PSScriptRoot
if (-not $RepositoryRoot) {
    $candidate=$source
    while ($candidate) {
        if (Test-Path -LiteralPath (Join-Path $candidate 'ThemeEngine\themes\gruvbox\theme.conf')) { $RepositoryRoot=$candidate; break }
        $candidate=Split-Path -Parent $candidate
    }
}
if (-not $RepositoryRoot) { throw 'Repository theme data is required.' }
$originalLocalData=$env:LOCALAPPDATA
$root=Join-Path ([IO.Path]::GetFullPath($FixtureParent)) ('typezero-scoped-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root)|Out-Null
$script:passed=0
$script:caseNumber=0
$targetGuid='{574e775e-4f2a-5b96-ac1e-a2962a402336}'
$fontFragment='"font": {"face":"Original Mono","size":11,"weight":350,"features":{"ss01":1},"axes":{"wdth":90}}'
$otherFragment='{"guid":"{11111111-1111-1111-1111-111111111111}","font":{"face":"Other","size":9},"colorScheme":"Other Colors"}'
$chromeFragment='"theme":"User Chrome","themes":[{"name":"User Chrome","window":{"applicationTheme":"system"},"custom":true}]'
$settingsText=@'
{
 // retain comments, Unicode Ω, formatting, other profiles, defaults and chrome
 "profiles":{"defaults":{"font":{"face":"Default Mono","size":10},"opacity":82},"list":[
 {"guid":"{574e775e-4f2a-5b96-ac1e-a2962a402336}","name":"Renamed PowerShell","colorScheme":"User Colors",__FONT__,"backgroundImage":"C:\\fixture\\keep.png"},
 __OTHER__]},
 "schemes":[{"name":"User Colors","background":"#123456","foreground":"#abcdef"}],
 __CHROME__,
 "copyOnSelect" : false,"actions":[{"command":"copy","keys":"ctrl+shift+c"}]
}
'@
$settingsText=$settingsText.Replace('__FONT__',$fontFragment).Replace('__OTHER__',$otherFragment).Replace('__CHROME__',$chromeFragment)
function Assert-True { param([bool]$Condition,[string]$Message) if(-not $Condition){throw "FAIL: $Message"} }
function Case { param([string]$Name,[scriptblock]$Action) & $Action; $script:passed++; Write-Host "PASS [$script:passed] $Name" }
function Write-Text { param([string]$Path,[string]$Text) [IO.Directory]::CreateDirectory((Split-Path -Parent $Path))|Out-Null; [IO.File]::WriteAllText($Path,$Text,[Text.UTF8Encoding]::new($false)) }
function Bytes { param([string]$Path) [Convert]::ToBase64String([IO.File]::ReadAllBytes($Path)) }
function Snapshot { param([string]$Path) @(Get-ChildItem -LiteralPath $Path -Recurse -File|Sort-Object FullName|ForEach-Object {$_.FullName.Substring($Path.Length)+':'+(Bytes $_.FullName)}) -join "`n" }
function Target { param($Fixture) $data=[IO.File]::ReadAllText($Fixture.Settings)|ConvertFrom-Json -AsHashtable; @($data.profiles.list|Where-Object {$_.guid -ieq $targetGuid})[0] }
function Target-Result { param($Result,[string]$Name) $items=@($Result.Targets|Where-Object Target -ceq $Name); Assert-True ($items.Count -eq 1) "Expected exactly one '$Name' result."; $items[0] }
function New-Fixture {
    $script:caseNumber++
    $folder=Join-Path $root ('case-'+$script:caseNumber)
    $engine=Join-Path $folder 'engine'
    [IO.Directory]::CreateDirectory($engine)|Out-Null
    Get-ChildItem -LiteralPath $source -File -Filter '*.ps1'|ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination $engine}
    # Replace precisely the native Vim renderer; retain all command and apply
    # orchestration code. This stub never evaluates the HOME-based destination.
    $tokens=$null; $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $source 'ThemeEngine.ps1'),[ref]$tokens,[ref]$errors)
    Assert-True ($errors.Count -eq 0) 'Engine has syntax errors.'
    $renderer=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Write-ThemeTemplate'},$false))
    Assert-True ($renderer.Count -eq 1) 'Expected one native Vim renderer.'
    $safeRenderer=@'
function Write-ThemeTemplate {
 param($Source,$Destination,$Theme)
 $fixture=Join-Path $env:LOCALAPPDATA 'Typezero\ThemeEngine'
 if(Test-Path -LiteralPath (Join-Path $fixture 'vim-fail')) {throw 'Fixture Vim rendering failed.'}
 [IO.File]::AppendAllText((Join-Path $fixture 'vim-log'),(Split-Path -Leaf $Source)+"`n")
}
'@
    $public=[IO.File]::ReadAllText((Join-Path $source 'ThemeEngine.ps1')).Replace($renderer[0].Extent.Text,$safeRenderer)
    Write-Text (Join-Path $engine 'ThemeEngine.ps1') $public
    Write-Text (Join-Path $engine 'WindowsAppearance.ps1') @'
function Set-TypezeroWindowsNativeTheme {
 param($Id,$Name,$Accent)
 $fixture=Join-Path $env:LOCALAPPDATA 'Typezero\ThemeEngine'
 [IO.File]::AppendAllText((Join-Path $fixture 'native-log'),$Id+"`n")
 if(Test-Path -LiteralPath (Join-Path $fixture 'native-fail')) {throw 'Fixture native activation not confirmed.'}
 [IO.File]::WriteAllText((Join-Path $fixture 'active-native'),$Id)
}
'@
    Write-Text (Join-Path $engine 'WallpaperProvider-DisplayFusion.ps1') '# Disposable provider; no processes or registry access.'
    Write-Text (Join-Path $engine 'WallpaperMapping-DisplayFusion.ps1') @'
function Get-TypezeroWallpaperMappings {
 $fixture=Join-Path $env:LOCALAPPDATA 'Typezero\ThemeEngine'
 $action=if(Test-Path -LiteralPath (Join-Path $fixture 'wallpaper-action')) {[IO.File]::ReadAllText((Join-Path $fixture 'wallpaper-action'))}else{''}
 [pscustomobject]@{Enabled=($action -cne 'DISABLED - no changes');Profiles=$(if($action -ceq 'UNMAPPED - no changes'){@{}}else{@{gruvbox='Fixture Wallpaper'}})}
}
function Test-TypezeroWallpaperThemeMapping {
 param($ThemeId)
 $fixture=Join-Path $env:LOCALAPPDATA 'Typezero\ThemeEngine'
 $action='ELIGIBLE FOR EXPLICIT SWITCH'
 if(Test-Path -LiteralPath (Join-Path $fixture 'wallpaper-action')) {$action=[IO.File]::ReadAllText((Join-Path $fixture 'wallpaper-action'))}
 if((Test-Path -LiteralPath (Join-Path $fixture 'active-wallpaper')) -and [IO.File]::ReadAllText((Join-Path $fixture 'active-wallpaper')) -ceq $ThemeId) {$action='ALREADY ACTIVE - no changes'}
 [pscustomobject]@{Action=$action;IntegrationEnabled=$true;MappedProfile='Fixture Wallpaper';ProfileFound=$true}
}
function Invoke-TypezeroWallpaperThemeMapping {
 [CmdletBinding(SupportsShouldProcess)]param($ThemeId,[switch]$Execute)
 $fixture=Join-Path $env:LOCALAPPDATA 'Typezero\ThemeEngine'
 [IO.File]::AppendAllText((Join-Path $fixture 'wallpaper-log'),$ThemeId+"`n")
 if(Test-Path -LiteralPath (Join-Path $fixture 'wallpaper-fail')) {throw 'Fixture wallpaper activation failed.'}
 [IO.File]::WriteAllText((Join-Path $fixture 'active-wallpaper'),$ThemeId)
 [pscustomobject]@{Status='VERIFIED';ProfileName='Fixture Wallpaper'}
}
'@
    $env:LOCALAPPDATA=Join-Path $folder 'local-app-data'
    $runtime=Join-Path $env:LOCALAPPDATA 'Typezero\ThemeEngine'
    $settings=Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
    Write-Text $settings ($settingsText+"`n")
    # Include a BOM, exercising preserved bytes through the real writer.
    [IO.File]::WriteAllText($settings,($settingsText+"`n"),[Text.UTF8Encoding]::new($true))
    foreach($id in @('gruvbox','nord')) {Write-Text (Join-Path $runtime "themes\$id\theme.conf") ([IO.File]::ReadAllText((Join-Path $RepositoryRoot "ThemeEngine\themes\$id\theme.conf")))}
    Write-Text (Join-Path $runtime 'current-theme') 'nord'
    Write-Text (Join-Path $runtime 'previous-theme') 'fixture-previous'
    Write-Text (Join-Path $runtime 'current.ps1') '# fixture existing generated shell'
    Write-Text (Join-Path $runtime 'font-windows-terminal.json') '{"Version":2,"Enabled":false,"ManualOverride":null,"Mappings":{"gruvbox":{"family":"Saved Mono","size":17.25,"weight":"semi-bold"}}}'
    Write-Text (Join-Path $runtime 'custom-presets.json') '{"Version":1,"Presets":[{"Name":"desk","Theme":"gruvbox","Family":"Preset Mono","Size":15,"Weight":"medium"}]}'
    [pscustomobject]@{Root=$folder;Engine=(Join-Path $engine 'ThemeEngine.ps1');EngineDir=$engine;Runtime=$runtime;Settings=$settings;Mapping=(Join-Path $runtime 'font-windows-terminal.json');Presets=(Join-Path $runtime 'custom-presets.json');Themes=(Join-Path $runtime 'themes')}
}
function Invoke-Apply {
 param($Fixture,[string]$Command,[hashtable]$Extra=@{})
 $records=@(& $Fixture.Engine -Command $Command -Theme gruvbox @Extra)
 $results=@($records|Where-Object {$_.PSObject.Properties['Complete'] -and $_.PSObject.Properties['Targets']})
 Assert-True ($results.Count -eq 1) "Command '$Command' did not return one structured result."
 $results[0]
}
function Assert-Unrelated {
 param($Fixture,[string]$Mapping,[string]$Presets,[string]$Themes)
 $text=[IO.File]::ReadAllText($Fixture.Settings)
 Assert-True ($text.Contains($otherFragment) -and $text.Contains('"font":{"face":"Default Mono","size":10},"opacity":82') -and $text.Contains('"copyOnSelect" : false') -and $text.Contains('"features":{"ss01":1}') -and $text.Contains('"axes":{"wdth":90}') -and $text.Contains('Unicode Ω')) 'An unrelated Terminal property or comment changed.'
 Assert-True ((Bytes $Fixture.Mapping) -ceq $Mapping -and (Bytes $Fixture.Presets) -ceq $Presets -and (Snapshot $Fixture.Themes) -ceq $Themes) 'Apply rewrote saved mappings, presets or base themes.'
}
try {
    foreach($command in @('apply-shell','apply-font','apply-desktop','apply-shell-font','apply-desktop-shell','apply-all')) {
        Case "$command dispatches only its requested targets" {
            $f=New-Fixture; $original=Bytes $f.Settings; $mapping=Bytes $f.Mapping; $presets=Bytes $f.Presets; $themes=Snapshot $f.Themes
            $history=Snapshot $f.Runtime
            $result=Invoke-Apply $f $command
            Assert-True ($result.Complete -and $result.Status -in @('Applied','NoChange')) "$command failed: $($result|ConvertTo-Json -Depth 8 -Compress)"
            $withShell=$command -in @('apply-shell','apply-shell-font','apply-desktop-shell','apply-all')
            $withFont=$command -in @('apply-font','apply-shell-font','apply-all')
            $withDesktop=$command -in @('apply-desktop','apply-desktop-shell','apply-all')
            $profile=Target $f; $text=[IO.File]::ReadAllText($f.Settings)
            Assert-True (($profile.colorScheme -like 'Typezero *') -eq $withShell) "$command changed or failed to change terminal colors."
            if($withFont) {Assert-True ($profile.font.face -ceq 'Saved Mono' -and $profile.font.size -eq 17.25 -and $profile.font.weight -ceq 'semi-bold') 'Saved v2 tuple was not applied.'}
            else {Assert-True ($text.Contains($fontFragment)) "$command changed font bytes."}
            Assert-True ((Test-Path (Join-Path $f.Runtime 'native-log')) -eq $withDesktop -and (Test-Path (Join-Path $f.Runtime 'wallpaper-log')) -eq $withDesktop) "$command dispatched an excluded desktop target."
            Assert-True ((Test-Path (Join-Path $f.Runtime 'vim-log')) -eq ($command -ceq 'apply-all')) "$command dispatched an excluded Vim integration."
            if($command -cne 'apply-all') {
                Assert-True ($text.Contains($chromeFragment)) "$command changed terminal chrome."
                Assert-True ([IO.File]::ReadAllText((Join-Path $f.Runtime 'current-theme')) -ceq 'nord' -and [IO.File]::ReadAllText((Join-Path $f.Runtime 'previous-theme')) -ceq 'fixture-previous' -and [IO.File]::ReadAllText((Join-Path $f.Runtime 'current.ps1')) -ceq '# fixture existing generated shell') 'Scoped operation advanced whole-theme state.'
            } else {Assert-True ([IO.File]::ReadAllText((Join-Path $f.Runtime 'current-theme')).Trim() -ceq 'gruvbox' -and [IO.File]::ReadAllText((Join-Path $f.Runtime 'previous-theme')).Trim() -ceq 'nord') 'Full apply lost theme history.'}
            if($withShell -or $withFont) {
                $backup=@($result.Targets|Where-Object {$_.BackupPath}|Select-Object -ExpandProperty BackupPath -Unique)
                Assert-True ($backup.Count -eq 1 -and (Bytes $backup[0]) -ceq $original) 'Settings backup did not retain exact original bytes.'
            } else {Assert-True ((Bytes $f.Settings) -ceq $original) 'Desktop operation changed Terminal settings.'}
            Assert-Unrelated $f $mapping $presets $themes
        }
    }
    Case 'Normal apply gruvbox keeps original full integration and font behavior' {
        $f=New-Fixture; $r=Invoke-Apply $f apply
        Assert-True ($r.Complete -and $r.Operation -ceq 'All' -and (Target $f).font.face -ceq 'Saved Mono') 'Legacy apply no longer performs full apply with saved font.'
        Assert-True ([IO.File]::ReadAllLines((Join-Path $f.Runtime 'vim-log')).Count -eq 2 -and (Test-Path (Join-Path $f.Runtime 'active-native')) -and (Test-Path (Join-Path $f.Runtime 'active-wallpaper'))) 'Legacy apply lost an integration.'
    }
    Case 'One-use font override wins saved mapping without persisting it' {
        foreach($command in @('apply-font','apply-shell-font','apply-all','apply')) {
            $f=New-Fixture; $mapping=Bytes $f.Mapping; $presets=Bytes $f.Presets
            $r=Invoke-Apply $f $command @{TerminalFont=[ordered]@{face='Explicit Mono';size=14.5;weight='medium'}}
            Assert-True ($r.Complete -and (Target $f).font.face -ceq 'Explicit Mono' -and (Target $f).font.size -eq 14.5 -and (Bytes $f.Mapping) -ceq $mapping -and (Bytes $f.Presets) -ceq $presets) 'Explicit override lost precedence or persisted a preference.'
        }
    }
    Case 'Shell ignores malformed font mappings rather than introducing a font dependency' {
        foreach($command in @('apply-shell','apply-desktop-shell')) {
            $f=New-Fixture; Write-Text $f.Mapping '{invalid mapping'
            $r=Invoke-Apply $f $command
            Assert-True ($r.Complete -and [IO.File]::ReadAllText($f.Settings).Contains($fontFragment)) 'Excluded mapping failure blocked shell apply or changed font.'
        }
    }
    Case 'Desktop has no settings, palette or font dependency' {
        $f=New-Fixture; Write-Text $f.Settings '{not valid terminal JSON'; Write-Text $f.Mapping '{not valid font JSON'
        Write-Text (Join-Path $f.Themes 'gruvbox\theme.conf') ('THEME_ID=gruvbox'+"`n"+'THEME_NAME=Gruvbox'+"`n"+'ACCENT=#fe8019')
        $before=Bytes $f.Settings; $r=Invoke-Apply $f apply-desktop
        Assert-True ($r.Complete -and (Bytes $f.Settings) -ceq $before) 'Desktop improperly depended on terminal/font palette.'
    }
    Case 'Legacy v1 mapping changes only font family in every font-including operation' {
        foreach($command in @('apply-font','apply-shell-font','apply-all','apply')) {
            $f=New-Fixture; Write-Text $f.Mapping '{"Version":1,"Enabled":false,"Mappings":{"gruvbox":"Legacy Mono"}}'
            $r=Invoke-Apply $f $command; $font=(Target $f).font
            Assert-True ($r.Complete -and $font.face -ceq 'Legacy Mono' -and $font.size -eq 11 -and $font.weight -eq 350) 'Legacy v1 mapping did not preserve font size or weight.'
            if($command -ceq 'apply-font') {Assert-True ((Target $f).colorScheme -ceq 'User Colors') 'Legacy font-only apply changed colors.'}
        }
    }
    Case 'Unmapped font is an explicit no-op with no backup' {
        $f=New-Fixture; Write-Text $f.Mapping '{"Version":2,"Enabled":false,"ManualOverride":null,"Mappings":{}}'
        $before=Snapshot $f.Root; $r=Invoke-Apply $f apply-font
        Assert-True ($r.Complete -and -not $r.Changed -and (Target-Result $r Font).Status -ceq 'Skipped' -and (Snapshot $f.Root) -ceq $before) 'Unmapped font was guessed, backed up or reported changed.'
    }
    Case 'Unmapped Font still rejects invalid or ambiguous settings without creating a backup' {
        foreach($text in @('{"profiles":{"list":[}',('{"profiles":{"list":[{"guid":"'+$targetGuid+'"},{"guid":"'+$targetGuid+'"}]}}'))) {
            $f=New-Fixture; Write-Text $f.Mapping '{"Version":2,"Enabled":false,"ManualOverride":null,"Mappings":{}}'
            Write-Text $f.Settings $text; $before=Snapshot $f.Root
            $r=Invoke-Apply $f apply-font
            Assert-True (-not $r.Complete -and $r.Status -ceq 'Failed' -and (Target-Result $r Font).Status -ceq 'Failed' -and (Snapshot $f.Root) -ceq $before) 'Unmapped Font concealed invalid/ambiguous settings or wrote files.'
        }
    }
    Case 'Combined Shell+Font reports which component actually changed' {
        foreach($first in @('apply-shell','apply-font')) {
            $f=New-Fixture; $null=Invoke-Apply $f $first
            $r=Invoke-Apply $f apply-shell-font
            $shell=Target-Result $r Shell; $font=Target-Result $r Font
            Assert-True ($r.Complete -and $r.Changed) 'Combined operation failed or missed the remaining component.'
            if($first -ceq 'apply-shell') {Assert-True ($shell.Status -ceq 'NoChange' -and -not $shell.Changed -and $font.Status -ceq 'Applied' -and $font.Changed) 'Combined font-only change incorrectly reported Shell changed.'}
            else {Assert-True ($font.Status -ceq 'NoChange' -and -not $font.Changed -and $shell.Status -ceq 'Applied' -and $shell.Changed) 'Combined scheme-only change incorrectly reported Font changed.'}
        }
    }
    Case 'Reapplying scoped Shell and Font is byte-identical without extra backup' {
        foreach($command in @('apply-shell','apply-font','apply-shell-font')) {
            $f=New-Fixture; $null=Invoke-Apply $f $command; $before=Snapshot $f.Root
            $r=Invoke-Apply $f $command
            Assert-True ($r.Complete -and -not $r.Changed -and $r.Status -ceq 'NoChange' -and (Snapshot $f.Root) -ceq $before) "$command created a change/backup on no-op."
        }
    }
    Case 'Native failure still executes wallpaper and requested independent Terminal targets' {
        foreach($command in @('apply-desktop','apply-desktop-shell','apply-all')) {
            $f=New-Fixture; Write-Text (Join-Path $f.Runtime 'native-fail') 'fail'
            $r=Invoke-Apply $f $command
            Assert-True (-not $r.Complete -and $r.Status -ceq 'Partial' -and (Target-Result $r Desktop).Status -ceq 'Failed' -and (Target-Result $r Wallpaper).Status -ceq 'Applied') 'Native failure concealed or prevented wallpaper result.'
            if($command -cne 'apply-desktop') {Assert-True ((Target-Result $r Shell).Status -ceq 'Applied' -and (Target $f).colorScheme -like 'Typezero *') 'Native failure blocked independent Terminal success.'}
            Assert-True ([IO.File]::ReadAllText((Join-Path $f.Runtime 'current-theme')) -ceq 'nord') 'Partial apply recorded whole theme as current.'
        }
    }
    Case 'Configured wallpaper failure remains partial after native and shell success' {
        $f=New-Fixture; Write-Text (Join-Path $f.Runtime 'wallpaper-fail') 'fail'; $r=Invoke-Apply $f apply-desktop-shell
        Assert-True (-not $r.Complete -and $r.Status -ceq 'Partial' -and (Target-Result $r Wallpaper).Status -ceq 'Failed' -and (Target-Result $r Desktop).Status -ceq 'Applied' -and (Target-Result $r Shell).Status -ceq 'Applied') 'Wallpaper failure was hidden or blocked other targets.'
    }
    Case 'Disabled and unmapped wallpaper are explicit optional no-ops' {
        foreach($action in @('DISABLED - no changes','UNMAPPED - no changes')) {
            $f=New-Fixture; Write-Text (Join-Path $f.Runtime 'wallpaper-action') $action; $r=Invoke-Apply $f apply-desktop
            Assert-True ($r.Complete -and (Target-Result $r Wallpaper).Status -in @('Skipped','NoChange') -and -not (Test-Path (Join-Path $f.Runtime 'wallpaper-log'))) 'Disabled/unmapped wallpaper was invoked or marked failed.'
        }
    }
    Case 'Invalid configured wallpaper cannot become full success' {
        $f=New-Fixture; Write-Text (Join-Path $f.Runtime 'wallpaper-action') 'INVALID PROFILE - no changes'; $r=Invoke-Apply $f apply-all
        Assert-True (-not $r.Complete -and (Target-Result $r Wallpaper).Status -ceq 'Failed' -and [IO.File]::ReadAllText((Join-Path $f.Runtime 'current-theme')) -ceq 'nord') 'Invalid configured wallpaper was treated as fully applied.'
    }
    Case 'Terminal failure cannot prevent requested desktop and wallpaper targets' {
        $f=New-Fixture; Write-Text $f.Settings '{"profiles":{"list":[}'; $before=Bytes $f.Settings; $r=Invoke-Apply $f apply-desktop-shell
        Assert-True (-not $r.Complete -and $r.Status -ceq 'Partial' -and (Target-Result $r Shell).Status -ceq 'Failed' -and (Target-Result $r Desktop).Status -ceq 'Applied' -and (Target-Result $r Wallpaper).Status -ceq 'Applied' -and (Bytes $f.Settings) -ceq $before) 'Terminal failure blocked desktop or changed invalid settings.'
    }
    Case 'Single failed target is Failed and preserves settings/history' {
        $f=New-Fixture; Write-Text $f.Settings '{"profiles":{"list":[}'; $before=Snapshot $f.Root; $r=Invoke-Apply $f apply-shell
        Assert-True (-not $r.Complete -and $r.Status -ceq 'Failed' -and (Target-Result $r Shell).Status -ceq 'Failed' -and (Snapshot $f.Root) -ceq $before) 'Single target failure falsely succeeded or wrote files.'
    }
    Case 'Stale settings snapshot is rejected before backups or excluded writes' {
        $f=New-Fixture; $hash=(Get-FileHash -LiteralPath $f.Settings).Hash; [IO.File]::AppendAllText($f.Settings,"`n// fixture external edit")
        $before=Snapshot $f.Root
        $thrown=$false
        try {$null=Invoke-Apply $f apply-shell-font @{ExpectedSettingsSha256=$hash}}catch{$thrown=$_.Exception.Message -like '*changed since Preview*'}
        Assert-True ($thrown -and (Snapshot $f.Root) -ceq $before) 'Stale apply created settings/backups or other writes.'
    }
    Case 'Missing palette is an explicit failed Shell target and never advances whole-theme history' {
        $f=New-Fixture; $themePath=Join-Path $f.Themes 'gruvbox\theme.conf'; Write-Text $themePath (([IO.File]::ReadAllText($themePath))-replace '(?m)^ANSI_BLACK=.*(?:\r?\n|$)','')
        $before=Bytes $f.Settings; $r=Invoke-Apply $f apply-all
        Assert-True (-not $r.Complete -and (Target-Result $r Shell).Status -ceq 'Failed' -and (Bytes $f.Settings) -ceq $before -and [IO.File]::ReadAllText((Join-Path $f.Runtime 'current-theme')) -ceq 'nord') 'Missing palette was treated as complete or changed Terminal.'
    }
    Case 'Scoped commands reject excluded explicit font overrides without changes' {
        foreach($command in @('apply-shell','apply-desktop','apply-desktop-shell')) {
            $f=New-Fixture; $before=Snapshot $f.Root; $thrown=$false
            try {$null=Invoke-Apply $f $command @{TerminalFont=@{face='Explicit';size=12;weight='normal'}}}catch{$thrown=$true}
            Assert-True ($thrown -and (Snapshot $f.Root) -ceq $before) 'Excluded font override was silently accepted or wrote files.'
        }
    }
    Case 'Failed whole-theme metadata generation restores all prior metadata bytes' {
        $f=New-Fixture
        $paths=@('current.ps1','current-theme','previous-theme')|ForEach-Object {Join-Path $f.Runtime $_}
        $before=@($paths|ForEach-Object {Bytes $_})
        $tokens=$null; $errors=$null
        $ast=[Management.Automation.Language.Parser]::ParseFile($f.Engine,[ref]$tokens,[ref]$errors)
        $metadata=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Write-CurrentTheme'},$false))[0]
        $failedWriter=@'
function Write-CurrentTheme {
 param($T)
 [IO.File]::WriteAllText($CurrentPs1,'fixture partial metadata write')
 throw 'Fixture metadata generation failed after writing current.ps1.'
}
'@
        Write-Text $f.Engine ([IO.File]::ReadAllText($f.Engine).Replace($metadata.Extent.Text,$failedWriter))
        $r=Invoke-Apply $f apply-all
        Assert-True (-not $r.Complete -and $r.Status -ceq 'Partial' -and (Target-Result $r CurrentTheme).Status -ceq 'Failed') 'Metadata failure was marked fully applied.'
        foreach($index in 0..2) {Assert-True ((Bytes $paths[$index]) -ceq $before[$index]) 'Metadata generation failure left a changed current/history file.'}
        Assert-True ((Target-Result $r Shell).Status -ceq 'Applied' -and (Target-Result $r Desktop).Status -ceq 'Applied' -and (Target $f).font.face -ceq 'Saved Mono') 'Metadata failure concealed completed independent targets.'
    }
    Case 'Invalid explicit font tuple fails before desktop, settings or history changes' {
        $f=New-Fixture; $before=Snapshot $f.Root; $thrown=$false
        try {$null=Invoke-Apply $f apply-all @{TerminalFont=@{face='Explicit';size=12;weight='normal';unexpected='ignore me'}}}catch{$thrown=$true}
        Assert-True ($thrown -and (Snapshot $f.Root) -ceq $before) 'Malformed explicit tuple was silently accepted or produced side effects.'
    }
    Case 'Same-ID full apply reports repaired generated metadata and then exact metadata no-op' {
        $f=New-Fixture; $null=Invoke-Apply $f apply-all
        $current=Join-Path $f.Runtime 'current.ps1'; $correct=Bytes $current
        Write-Text $current '# fixture damaged generated shell palette'
        $repaired=Invoke-Apply $f apply-all; $metadata=Target-Result $repaired CurrentTheme
        Assert-True ($repaired.Complete -and $metadata.Status -ceq 'Applied' -and $metadata.Changed -and (Bytes $current) -ceq $correct) 'Repairing same-ID generated metadata was reported as unchanged.'
        $before=Bytes $current; $again=Invoke-Apply $f apply-all; $metadata=Target-Result $again CurrentTheme
        Assert-True ($again.Complete -and $metadata.Status -ceq 'NoChange' -and -not $metadata.Changed -and (Bytes $current) -ceq $before) 'Byte-identical same-ID metadata was reported changed.'
    }
}
finally {$env:LOCALAPPDATA=$originalLocalData; Write-Host "Disposable scoped fixtures retained: $root"}
Write-Host "Passed $script:passed scoped apply regressions."
