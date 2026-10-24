# Component-scoped apply operations

Run the existing NETZACH script with PowerShell 7. These are explicit activation
commands; selecting, loading, previewing or saving choices does not activate them.

```powershell
$engine = 'G:\Forgejo\It-Works-On-My-Machine\Netzach\PowerShell\ThemeEngine\ThemeEngine.ps1'
& $engine apply-shell gruvbox
& $engine apply-font gruvbox
& $engine apply-desktop gruvbox
& $engine apply-shell-font gruvbox
& $engine apply-desktop-shell gruvbox
& $engine apply-all gruvbox
& $engine apply gruvbox # existing full apply command
```

| Operation | Terminal palette | Terminal font | Native desktop + configured wallpaper | Vim, Lightline, generated shell palette and full-theme history |
| --- | --- | --- | --- | --- |
| Apply Shell | Apply | Preserve | Preserve | Preserve |
| Apply Font | Preserve | Apply | Preserve | Preserve |
| Apply Desktop | Preserve | Preserve | Apply | Preserve |
| Apply Shell+Font | Apply | Apply | Preserve | Preserve |
| Apply Desktop+Shell | Apply | Preserve | Apply | Preserve |
| Apply All / existing apply | Apply | Apply when configured | Apply | Apply |

Shell means only the named Typezero Windows Terminal color scheme and the
PowerShell 7 profile's `colorScheme`. It does not recolor the PowerShell prompt,
Vim, Terminal window/tab chrome, or other profiles. Apply All retains the existing
Terminal window/tab theme integration. Font edits affect only `font.face`,
`font.size` and `font.weight` (legacy family-only mappings preserve size/weight).
The target profile GUID is `{574e775e-4f2a-5b96-ac1e-a2962a402336}`, including renamed
profiles. Defaults, other profiles, font axes/features and unrelated settings stay
intact. Desktop uses the existing native Windows theme activation and existing
opt-in DisplayFusion mapping, without touching Terminal.

## Font choices and preset composition

For a font-including operation, an explicit one-use tuple takes precedence over
the theme's saved mapping. Otherwise the existing v1/v2 theme mapping is used,
including the historical behavior that an explicit apply uses it regardless of
the legacy `Enabled` flag. A missing mapping leaves the font unchanged. No apply
operation saves or migrates mappings, presets or base theme files.

```powershell
$font = [ordered]@{ face='Consolas'; size=14.25; weight='medium' }
& $engine apply-font gruvbox -TerminalFont $font
& $engine apply-shell-font gruvbox -TerminalFont $font
& $engine apply-all gruvbox -TerminalFont $font
# Existing font-only command without a base theme:
& $engine font apply-font 'Consolas' 14.25 medium
```

Shell, Desktop and Desktop+Shell reject an explicit `-TerminalFont`; their
excluded font component must remain unchanged. In the menu and WPF dialog,
loading a named preset fills theme/family/size/weight choices. The operation
determines which choices apply: Shell and Desktop+Shell ignore the loaded font,
Desktop ignores all Terminal choices, and Font/Shell+Font/All use the displayed
tuple as a one-use override. Save Preset still saves choices without activation.
The existing `font apply-theme` and `font apply-preset` commands retain their
full-theme behavior (Apply All with the chosen or preset font).

```powershell
$choices = & $engine font load-preset reading # read-only
$font = [ordered]@{ face=$choices.Family; size=$choices.Size; weight=$choices.Weight }
& $engine apply-shell $choices.Theme # preset palette only
& $engine apply-desktop-shell $choices.Theme # preset desktop + palette, retain font
& $engine apply-shell-font $choices.Theme -TerminalFont $font
```

## Menu and WPF

`configure` (also `font configure`) exposes all six actions. Existing action
numbers stay stable: 6 Apply Font, 7 Apply All, 12 Apply Shell, 13 Apply Desktop,
14 Apply Shell+Font, 15 Apply Desktop+Shell. Apply preset (11) keeps its full-theme
behavior. The existing `font theme-preview` WPF window exposes the same six
actions; launch it from `pwsh -NoProfile -STA`. Each action uses the shared
selection dispatcher and the existing apply/writer/provider modules.

Preview remains read-only. The WPF window returns an action intent; the caller
executes it. Cancel makes no new changes and does not undo previously completed
actions. Desktop remains available when Terminal settings cannot be read.
Excluded font choices do not block a colors-only or desktop action.

## Results, failures and backups

Scoped/full apply returns `Status`, `Operation`, `Theme`, `Complete`, `Changed`,
`AppearanceMayHaveChanged` and `Targets`. Each target reports its status, message,
change flag and settings backup path when applicable. `Partial` means at least
one independent requested target succeeded and another failed. A native desktop
failure does not prevent requested Terminal, wallpaper or other independent
integrations from running. Failed and partial operations never claim that the
whole theme was applied. There is no automatic rollback of successful targets.

Disabled/unmapped DisplayFusion integration is explicitly skipped. An enabled
mapping with a missing/ambiguous profile, provider error or unverified activation
is a failure. An already active mapping needs no wallpaper switch. Only a
complete Apply All writes generated `current.ps1` and full-theme history.
Scoped operations leave those files unchanged: `current-theme` records the last
completed full apply, rather than an audit of a later mixed component state.

Terminal edits reuse the existing JSONC writer with exact-byte backup, snapshot
checks and readback. Colors+font share one settings replacement and backup.
Unchanged settings create no backup. JSONC comments, BOM and line endings are
preserved. `-ExpectedSettingsSha256` optionally pins a direct Terminal operation
to a prior preview; stale settings are refused before its settings write. It
does not make separate native/wallpaper targets transactional.

```powershell
$preview = & $engine font preview-font 'Consolas' 14.25 medium
& $engine apply-shell-font gruvbox -TerminalFont $font `
    -ExpectedSettingsSha256 $preview.ExpectedSha256
```

## Offline verification

The focused suites use disposable `LOCALAPPDATA`/settings and stub desktop,
wallpaper and integration effects; they do not activate live Windows themes,
Terminal, wallpaper or Vim. Retain the fixtures for inspection. Supply a writable
workspace fixture parent when the temporary directory is restricted.

```powershell
$tests = Split-Path $engine
pwsh -NoProfile -File "$tests\tests\Test-TypezeroScopedApply.ps1" -FixtureParent '<workspace>'
pwsh -NoProfile -STA -File "$tests\tests\Test-TypezeroScopedApplyUI.ps1" -FixtureParent '<workspace>'
```
