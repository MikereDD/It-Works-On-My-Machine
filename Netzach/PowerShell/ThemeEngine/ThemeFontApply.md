# Apply a theme's saved Windows Terminal font

See [APPLY.md](APPLY.md) for the six component-scoped operations, exact command
syntax, preset composition and per-target partial-success reporting. The former
whole-theme button is now labeled Apply All; existing whole-theme CLI aliases
retain their behavior.

The normal `ThemeEngine.ps1 apply <id>` path applies that theme's saved
Windows Terminal font together with its color scheme. The existing WPF dialog
now separates Preview, Apply Font, Apply All, and Save Preset.
The permanent `configure` (or `font configure`) menu uses the same shared actions.
See [FONTS.md](FONTS.md) for independent control, searchable selection and named
preset commands.
Apply All uses an unsaved one-use override; ordinary theme apply
continues to read the existing saved mappings described below.

This uses the existing `font-windows-terminal.json` mapping format and mapping
reader/writer. No V2 transaction, grant, or recovery service is involved.

- Version 2 mappings apply `family`, `size`, and `weight`.
- Legacy version 1 mappings apply the family and retain existing size/weight.
- A theme without a mapping leaves the current font unchanged.
- Explicit theme application uses a saved mapping regardless of the legacy
  `Enabled` field. The older fixture planners keep their existing behavior.
- The target is the PowerShell 7 Terminal profile with GUID
  `{574e775e-4f2a-5b96-ac1e-a2962a402336}`, including renamed profiles.
- Defaults, other profiles, font features/axes, comments, unrelated schemes,
  UTF-8 BOM, and existing line endings are preserved by targeted JSONC edits.

The writer validates the candidate's requested colors and typography before
writing, verifies a byte-for-byte backup, rechecks the original SHA-256, uses
same-directory replacement, and verifies both the displaced and resulting
bytes. Each changed apply prints the unique backup path; an unchanged apply
creates no backup. The replacement is not a filesystem compare-and-swap:
avoid editing Terminal settings during apply. A detected replacement race
reports failure and preserves the displaced contents in the printed/error
backup path; inspect them before restoring. Restore also requires an expected
current SHA-256 and backs up the settings it replaces.

## Configure and direct command parity

```powershell
$engine = 'G:\Forgejo\It-Works-On-My-Machine\Netzach\PowerShell\ThemeEngine\ThemeEngine.ps1'
& $engine configure # also: & $engine font configure
& $engine font preview-theme gruvbox 'Consolas' 14 medium
& $engine font preview-font 'Consolas' 14 medium
& $engine font save-preset reading gruvbox 'Consolas' 14 medium
& $engine font presets
$choices = & $engine font load-preset reading # loads choices without applying
& $engine font preview-preset reading
```

The following direct actions change active appearance:

```powershell
& $engine font apply-font 'Consolas' 14 medium
& $engine font apply-theme gruvbox 'Consolas' 14 medium
& $engine font apply-preset reading
```

The menu initializes from the current recorded theme and effective Terminal font.
Selectors show 15 numbered results with `/search`, `/` to clear, and `n`/`p`
paging. Enter or `q` returns from a selector; at the main menu it exits. Loading a
preset fills theme, family, size and weight for further edits. Cancel discards
unsaved edits; completed Apply and Save actions remain. Theme/font inputs and
preset loads validate installed names. Custom presets remain separate from base
themes and saved per-theme mappings.

All standard named weights are accepted: `thin`, `extra-light`, `light`,
`semi-light`, `normal`, `medium`, `semi-bold`, `bold`, `extra-bold`, `black`, and
`extra-black`. WPF specimens use the corresponding OpenType weights. Actual
faces and synthesis depend on the selected family and renderer. Shell preview
uses the current terminal font while displaying the requested tuple; open
`font theme-preview` in `pwsh -STA` to compare an unsaved font visually.

## Disposable validation (safe to run now)

Run from PowerShell 7 on NETZACH. These scripts create and retain separate
fixtures. They do not invoke native appearance, Vim, wallpaper, or live
Terminal changes.

```powershell
$repo = 'G:\Forgejo\It-Works-On-My-Machine'
$engineDir = Join-Path $repo 'Netzach\PowerShell\ThemeEngine'
pwsh -NoProfile -File "$engineDir\tests\Test-TypezeroTerminalAppearance.ps1"
pwsh -NoProfile -STA -File "$engineDir\tests\Test-TypezeroThemeFontSelection.ps1"
pwsh -NoProfile -File "$engineDir\tests\Test-TypezeroConfigure.ps1"
pwsh -NoProfile -STA -File "$engineDir\tests\Test-TypezeroFontWeights.ps1"
```

The appearance suite exercises the actual Terminal lookup/apply function
bodies with a disposable `LOCALAPPDATA` and saved font mappings. It proves
A → B → A changes both the palette and complete font tuple, with exact backups
and restore. The selection suite checks save-before-apply, verified font
readback, cancellation, and failed-save behavior. This is separate from the
older security/recovery suites and does not establish live visual success.

## Real NETZACH visual checks

The new menu and expanded weights still need real visual verification. The
following optional full-path checks change real theme colors, Windows appearance,
and saved font preferences; automated tests use disposable settings instead.
Use the repository script explicitly so an older installed copy is not used.
Do not run bootstrap or copy files over the installed tree for this test.

1. Open a PowerShell 7 tab using the target Terminal profile. Confirm that
   `gruvbox` and `nord` are installed, and that the two exact font families
   below appear in the font list. Substitute installed names if needed.

```powershell
$repo = 'G:\Forgejo\It-Works-On-My-Machine'
$engineDir = Join-Path $repo 'Netzach\PowerShell\ThemeEngine'
$engine = Join-Path $engineDir 'ThemeEngine.ps1'
& $engine list
& $engine font list
```

2. Save an explicit pre-test copy of Terminal settings. Then save contrasting
   font tuples for two themes using the existing mapping command. These
   mapping commands do not apply a theme. Existing version 1 mappings migrate
   to version 2; other family-only entries receive 12 pt / normal. The existing
   mapping writer backs up the previous configuration.

```powershell
$settings = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
$beforeTest = "$settings.before-font-test-$([guid]::NewGuid().ToString('N')).bak"
Copy-Item -LiteralPath $settings -Destination $beforeTest
if ((Get-FileHash -LiteralPath $settings).Hash -ne (Get-FileHash -LiteralPath $beforeTest).Hash) {
    throw 'Pre-test backup does not match settings; stop and retry.'
}
& $engine font map-v2 gruvbox 'Consolas' 12 normal
& $engine font map-v2 nord 'Cascadia Mono' 16 semi-bold
```

3. Switch A → B → A. After each apply, inspect the actual settings and observe
   the tab. The expected combinations are Typezero Gruvbox / Consolas / 12 /
   normal, then Typezero Nord / Cascadia Mono / 16 / semi-bold, then Gruvbox
   again. The exact scheme display names follow the installed theme.conf.
   Open a fresh tab using the same profile if Terminal has not refreshed the
   existing tab. Success requires visible color **and** font changes.

```powershell
function Show-AppliedTerminalAppearance {
    $data = Get-Content -LiteralPath $settings -Raw | ConvertFrom-Json -AsHashtable
    $profile = @($data.profiles.list | Where-Object {
        $_.guid -ieq '{574e775e-4f2a-5b96-ac1e-a2962a402336}'
    })[0]
    [pscustomobject]@{
        Scheme = $profile.colorScheme
        Family = $profile.font.face
        Size = $profile.font.size
        Weight = $profile.font.weight
    } | Format-List
}
& $engine apply gruvbox
Show-AppliedTerminalAppearance
& $engine apply nord
Show-AppliedTerminalAppearance
& $engine apply gruvbox
Show-AppliedTerminalAppearance
$afterTestHash = (Get-FileHash -LiteralPath $settings -Algorithm SHA256).Hash
```

4. To check the dialog, launch `pwsh -NoProfile -STA`, set `$engine` to the same
   repository script, and run `& $engine font theme-preview`. Changing themes
   should load their saved typography. Preview and cancellation leave settings
   alone. Apply Font activates only the displayed typography. Apply All
   applies the theme with that tuple without saving. Save Preset persists only
   the named choices. The separate `font picker` remains a preview.
   After any additional confirmed apply in the dialog, capture
   `$afterTestHash = (Get-FileHash -LiteralPath $settings -Algorithm SHA256).Hash`
   again before restoring.

## Simple Terminal restore

In the same session after the test, restore the pre-test bytes using the hash
captured immediately after the final apply. If settings changed since then,
restore refuses; inspect the intervening change first. This restores Terminal
settings only. It does not change saved mappings, theme history, native Windows
appearance, Vim, or wallpaper. Normal `apply <previous-id>` restores those
theme consumers using that theme's saved font.

```powershell
. (Join-Path $engineDir 'TerminalSettings-WindowsTerminal.ps1')
Restore-TypezeroWindowsTerminalAppearance -Path $settings `
    -BackupPath $beforeTest -ExpectedSha256 $afterTestHash
if ((Get-FileHash -LiteralPath $settings).Hash -ne (Get-FileHash -LiteralPath $beforeTest).Hash) {
    throw 'Restored settings differ from the pre-test backup.'
}
```

For a single apply, use its printed `Windows Terminal backup:` path instead of
`$beforeTest` and the hash captured after that apply. Backups are ordinary
settings files and require no journal or service to restore.
