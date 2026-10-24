# Typezero ThemeEngine: Windows Terminal fonts and custom presets

For independent Shell, Font, Desktop and combined apply commands, see
[APPLY.md](APPLY.md). The menu and existing WPF window expose all six scopes.
The older whole-theme action is now labeled **Apply All**; legacy `ApplyTheme`,
`font apply-theme` and `font apply-preset` keep their full-theme behavior.

Run the repository's `ThemeEngine.ps1` with PowerShell 7 on NETZACH.
Open the permanent shell menu with `configure` or `font configure`.
The existing WPF window is `font theme-preview` (run with `pwsh -STA`).

| Action | Effect |
| --- | --- |
| Preview | Shows choices; changes no files or live settings |
| Apply Font | Activates family, size and weight for the PowerShell 7 Terminal profile only |
| Apply All | Uses full theme application with the displayed font for this invocation |
| Apply Shell / Desktop / Shell+Font / Desktop+Shell | Applies only the components named; see APPLY.md |
| Save Preset | Persists a named base-theme/font combination; activates nothing |

Both shell and WPF actions use `AppearanceSelection-WindowsTerminal.ps1` and
`TerminalFontControl-WindowsTerminal.ps1`. The existing palette, specimen and
font dropdown preview is retained. A WPF action completes when the window closes.
The shell menu stays open after each explicit action.

## Configure menu

```powershell
$engine = 'G:\Forgejo\It-Works-On-My-Machine\Netzach\PowerShell\ThemeEngine\ThemeEngine.ps1'
& $engine configure
# Equivalent entry point:
& $engine font configure
```

The menu starts from the recorded current theme and the effective PowerShell 7
Terminal family, size and weight. A missing current theme falls back to the first
installed theme with a message; it is not applied. If Terminal settings cannot be
read, select a font before applying. Numeric current weights that match a standard
named weight are shown with that name.

Theme, installed font, weight and preset selection show 15 numbered matches per
page. Enter a displayed number or exact name, `/search` to filter, `/` to clear
the filter, and `n`/`p` for next/previous page. Plain text also filters by name.
Numbers select from the current filtered results; they are never accepted as
arbitrary theme IDs. Enter or `q` returns from a selector. Invalid choices leave
the menu available for correction.

Choose family, size and weight independently, then Preview, Apply Font, Apply
Theme + Font, or Save preset. List presets displays saved tuples; Load preset
fills all editable choices without activation. Apply preset loads the selected
preset and explicitly applies its theme and font. Replacing a saved name requires
typing `replace` in the menu. `q`, Enter, or end of input at the main menu closes
configure and discards unsaved choices. Previously completed Apply or Save
actions remain in effect; cancellation does not undo them.

## Shell commands

```powershell
$engine = 'G:\Forgejo\It-Works-On-My-Machine\Netzach\PowerShell\ThemeEngine\ThemeEngine.ps1'
& $engine font list
& $engine font current
& $engine font preview-font 'Consolas' 14.25 medium
& $engine font theme-preview # launch from pwsh -NoProfile -STA
& $engine font preview-theme gruvbox 'Consolas' 14.25 medium
& $engine font save-preset reading gruvbox 'Consolas' 14.25 medium
& $engine font presets
$choices = & $engine font load-preset reading # returns editable choices; applies nothing
& $engine font preview-preset reading
```

These commands only inspect/preview or save a preset. The following commands
activate settings; run them only when you intend to change your appearance:

```powershell
& $engine font apply-font 'Consolas' 14.25 medium
& $engine font apply-theme gruvbox 'Consolas' 14.25 medium
& $engine font apply-preset reading # normal theme application plus preset font
```

A CLI preview returns `ExpectedSha256`. To reject changes since that preview:

```powershell
$preview = & $engine font preview-font 'Consolas' 14.25 semi-bold
& $engine font apply-font 'Consolas' 14.25 semi-bold -ExpectedSettingsSha256 $preview.ExpectedSha256
# apply-theme and apply-preset accept the same optional snapshot argument.
```

Direct theme commands use `font preview-theme <theme> "<family>" <size> <weight>`
and `font apply-theme <theme> "<family>" <size> <weight>`. Installed theme and font
names are validated before an action executes. `font load-preset <name>` validates
and returns the saved choices without needing Terminal settings or applying them.

Font sizes support 6–36 points with at most two decimal places. Standard Windows
Terminal weight names are `thin`, `extra-light`, `light`, `semi-light`, `normal`,
`medium`, `semi-bold`, `bold`, `extra-bold`, `black`, and `extra-black`. These names
are shared by CLI, WPF, presets, v2 mappings and the Terminal writer. Enter the
canonical lowercase names. Arbitrary numeric weight input is not exposed here.

Shell preview shows the palette plus requested/current typography using the
terminal's current font; it cannot render an unsaved selected family in the shell.
Use the WPF specimen for a visual approximation of family, size and weight. WPF
uses the corresponding OpenType weight; actual faces, synthesis and exact glyph
rendering depend on the font and Windows Terminal. A weight name does not install
a missing face or guarantee that every font provides that exact weight.

## Saved choices

Named presets live in `%LOCALAPPDATA%\Typezero\ThemeEngine\custom-presets.json`,
separately from immutable base `themes\<id>\theme.conf` files and existing
`font-windows-terminal.json` mappings. Names use lowercase letters, digits and
hyphens. Saving an existing name refuses replacement; the CLI accepts an
explicit trailing `--replace`; the GUI has an explicit replace checkbox.
Replacing backs up the previous preset file.

Applying a preset or the GUI's displayed choices never updates a base theme or
saved mapping. A later ordinary `apply gruvbox` still uses Gruvbox's established
saved font mapping. Existing `font map`, `font map-v2`, and ordinary theme
application remain available. Legacy fixture-only commands retain their guards.

## Backups and scope

The older guarded fixture/recovery commands (`font check-apply`, fixture-only
`font apply`, and rehearsal) retain their historical `normal`/`semi-bold`
weight limits. The configure, WPF, direct font/theme and custom preset actions
described above support all eleven named weights. This increment does not
extend the recovery transaction formats.

Independent font Apply edits only `font.face`, `font.size` and `font.weight` on
the profile with GUID `{574e775e-4f2a-5b96-ac1e-a2962a402336}`. It preserves
profile names, colors, defaults, other profiles, font axes/features, JSONC
comments, UTF-8 BOM and line endings. Changed settings receive an exact backup
through the existing settings writer; a no-op creates none. The result includes
`BackupPath`. Preset Save never touches Terminal or theme activation/history.

Apply All and apply-preset use the established whole-theme path,
including its existing native appearance, Vim and wallpaper behavior. Failures
can leave partial appearance changes and are reported as such. Independent
Apply Font avoids those consumers. No live settings were changed by automated
validation of this increment.

## Disposable validation

Run each script under `tests` with `-FixtureParent` pointing to a writable
scratch directory. Fixtures are retained. The configure and weight suites use
disposable `LOCALAPPDATA`; theme application is stubbed where needed to avoid
active appearance changes. Use `-STA` for the GUI and weight suites:

```powershell
pwsh -NoProfile -File .\tests\Test-TypezeroTerminalAppearance.ps1 -FixtureParent $env:TEMP
pwsh -NoProfile -STA -File .\tests\Test-TypezeroThemeFontSelection.ps1 -FixtureParent $env:TEMP
pwsh -NoProfile -File .\tests\Test-TypezeroTerminalFontControl.ps1 -FixtureParent $env:TEMP
pwsh -NoProfile -STA -File .\tests\Test-TypezeroThemeFontPreviewActions.ps1 -FixtureParent $env:TEMP
pwsh -NoProfile -File .\tests\Test-TypezeroAppearanceActions.ps1 -FixtureParent $env:TEMP
pwsh -NoProfile -File .\tests\Test-TypezeroConfigure.ps1 -FixtureParent $env:TEMP
pwsh -NoProfile -STA -File .\tests\Test-TypezeroFontWeights.ps1 -FixtureParent $env:TEMP
```
