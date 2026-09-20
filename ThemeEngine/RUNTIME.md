# ThemeEngine Runtime

This document describes how ThemeEngine behaves after repository data has been installed on Netzach or Arakiel.

It focuses on runtime state, generated files, command behavior, platform differences, live reload behavior, SSH/X-session handling, and troubleshooting.

For the source → renderer → generated output → consumer dependency map, see:

```text
ThemeEngine/INTEGRATIONS.md
```

For theme authoring, use:

```text
ThemeEngine/theme.conf.template
```

---

## Runtime Model

ThemeEngine separates repository source from installed runtime data.

```text
repository
    ↓
bootstrap
    ↓
installed themes + templates
    ↓
apply / reload / rollback
    ↓
generated native configuration + runtime state
    ↓
application refresh
```

The repository remains the source of truth.

Installed themes, installed templates, generated files, and current-theme state are runtime outputs.

---

# Commands

Both platform implementations expose the same high-level command set:

```text
list
current
preview
apply
reload
rollback
doctor
bootstrap
help
```

The command syntax differs slightly where native shell conventions require it.

---

## `bootstrap`

Bootstrap installs the repository copies of ThemeEngine themes and templates into the platform runtime-data location.

It does not itself select a new theme.

Use bootstrap after:

- adding a new theme
- changing an existing `theme.conf`
- changing a template
- pulling ThemeEngine source updates that affect themes or templates
- setting up ThemeEngine on a new machine

### Netzach

From the repository root:

```powershell
themeengine bootstrap -RepoRoot $PWD
```

### Arakiel

From the repository root:

```bash
themeengine bootstrap "$PWD"
```

Bootstrap replaces the installed themes and templates with the repository versions.

---

## `list`

Shows installed theme IDs.

The currently selected theme is marked.

Example:

```text
  catppuccin-mocha
  everforest-dark
  gruvbox
  kanagawa-paper
* obsidian-silver
  onedark
```

If a newly added theme does not appear, bootstrap has probably not been run since the repository was updated.

---

## `current`

Prints the currently selected theme ID.

Example:

```text
onedark
```

Use `themeengine current` instead of reading state files directly when a script or operator needs the active theme.

---

## `preview`

Displays the important semantic palette roles for a theme without applying it.

Example:

```powershell
themeengine preview onedark
```

or:

```bash
themeengine preview onedark
```

Preview is useful for confirming:

- the theme is installed
- semantic roles parsed correctly
- the expected palette is being read

It does not replace visual testing in the actual applications.

---

## `apply`

Applies a selected theme.

Conceptually, `apply`:

```text
load theme
    ↓
remember previous theme when appropriate
    ↓
render native configuration
    ↓
write current-theme state
    ↓
refresh supported runtime surfaces
```

### Netzach

```powershell
themeengine apply onedark
```

### Arakiel

```bash
themeengine apply onedark
```

---

## `reload`

Re-renders and reapplies the currently selected theme without intentionally changing theme history.

Use it after:

- modifying a template
- repairing a generated file
- updating integration code while keeping the same selected theme
- testing renderer behavior

```text
themeengine reload
```

---

## `rollback`

Applies the previously selected theme when previous-theme state exists.

```text
themeengine rollback
```

Rollback depends on recorded theme history.

It is not a general backup/restore mechanism for arbitrary application configuration.

---

## `doctor`

Checks whether important ThemeEngine runtime components are present.

Use it when:

- bootstrap appears incomplete
- generated files are missing
- a platform surface is not changing
- the current theme cannot be determined
- ThemeEngine was moved or reinstalled

```text
themeengine doctor
```

`doctor` is a diagnostic command. It should be preferred over guessing at missing files or paths.

---

# Netzach Runtime

## Renderer

Repository source:

```text
Netzach/PowerShell/ThemeEngine/ThemeEngine.ps1
```

User-facing command bridge:

```text
Netzach/PowerShell/profile.d/theme.ps1
```

The bridge exposes:

```powershell
themeengine
```

inside the normal PowerShell environment.

---

## Runtime Root

Netzach ThemeEngine runtime data lives under:

```text
%LOCALAPPDATA%\Typezero\ThemeEngine
```

The renderer derives this from:

```powershell
$env:LOCALAPPDATA
```

rather than hardcoding a user profile path.

---

## Installed Data

Bootstrap installs repository data under the ThemeEngine runtime root.

Conceptually:

```text
%LOCALAPPDATA%\Typezero\ThemeEngine\
├── themes\
├── templates\
├── current-theme
├── previous-theme
└── current.ps1
```

The exact generated state present depends on whether a theme has already been selected.

---

## `current-theme`

Stores the active theme ID.

Example:

```text
kanagawa-paper
```

This is the backing state used by:

```powershell
themeengine current
```

---

## `previous-theme`

Stores the previous theme ID when ThemeEngine has recorded a prior selection.

It supports:

```powershell
themeengine rollback
```

A rollback is only possible when valid previous-theme state exists.

---

## `current.ps1`

Generated PowerShell theme state.

Path:

```text
%LOCALAPPDATA%\Typezero\ThemeEngine\current.ps1
```

It is loaded by:

```text
Netzach/PowerShell/profile.d/theme.ps1
```

and consumed by:

```text
Netzach/PowerShell/profile.d/ui.ps1
```

The generated state exposes ThemeEngine semantic colors to the existing PowerShell UI layer.

After `apply`, `reload`, or `rollback`, the command bridge re-imports this generated state so the current PowerShell process can see the new palette.

---

## PowerShell Load Order

The main profile loads ThemeEngine before the UI layer.

Conceptually:

```text
Netzach/PowerShell/profile.ps1
    ↓
profile.d/theme.ps1
    ↓
%LOCALAPPDATA%\Typezero\ThemeEngine\current.ps1
    ↓
profile.d/ui.ps1
```

This order is intentional.

`ui.ps1` can use ThemeEngine semantic colors when they exist while retaining fallback colors when ThemeEngine has not yet been initialized.

---

## Netzach Vim Outputs

Applying a theme generates:

```text
$HOME\config\vim\colors\typezero.vim
```

and:

```text
$HOME\config\vim\autoload\lightline\colorscheme\typezero.vim
```

These files are generated from the shared templates:

```text
ThemeEngine/templates/shared/vim-colors.vim.tpl
ThemeEngine/templates/shared/vim-lightline.vim.tpl
```

The repository Vim configuration loads the generated `typezero` colorscheme.

Existing Vim processes do not automatically reload these files.

After changing themes, start a fresh Vim instance when validating the result.

---

## Vim Line Endings on Windows

Generated Vim runtime files must use clean line endings.

ThemeEngine normalizes template input before writing the generated Vim files so carriage-return characters do not survive as literal `^M` command text.

When modifying renderer or template-writing behavior, verify the generated Vim files again.

A useful validation is to confirm there are no unexpected carriage returns before committing renderer changes.

---

# Windows Terminal Runtime

ThemeEngine updates Windows Terminal directly on Netzach.

It does not replace the entire configuration conceptually; it manages specific ThemeEngine-owned portions of the settings.

---

## Theme Color Scheme

The active ThemeEngine palette is written as a Windows Terminal color scheme named:

```text
Typezero <Theme Name>
```

Examples:

```text
Typezero OneDark
Typezero Kanagawa Paper
```

The scheme includes:

- background
- foreground
- cursor color
- selection background
- normal ANSI colors
- bright ANSI colors

Other custom Windows Terminal schemes are preserved.

---

## Windows Terminal Application Theme

ThemeEngine also maintains an application-level Windows Terminal theme named:

```text
Typezero ThemeEngine
```

This coordinates ThemeEngine-owned chrome such as:

- application dark mode
- active tab behavior
- unfocused tab background
- tab-row background
- close-button visibility

ThemeEngine does not intentionally take ownership of unrelated profile preferences.

Examples of settings that remain outside the ThemeEngine appearance contract include user-specific wallpaper and other unrelated profile behavior.

---

## PowerShell 7 Profile Association

ThemeEngine targets the PowerShell 7 Windows Terminal profile using its stable GUID:

```text
{574e775e-4f2a-5b96-ac1e-a2962a402336}
```

The renderer updates that profile's:

```text
colorScheme
```

association to the active Typezero scheme.

Using the GUID avoids relying only on a mutable display name.

---

## Windows Terminal Backup

Before ThemeEngine's first Windows Terminal write, it preserves the original settings file as:

```text
settings.json.typezero-backup
```

This is a stable pre-ThemeEngine backup.

It is not intended to rotate on every theme change.

---

# Arakiel Runtime

## Renderer

Repository source:

```text
Arakiel/local/bin/themeengine
```

Expected live executable:

```text
~/.local/bin/themeengine
```

The Arakiel renderer is a Bash implementation.

---

## Installed Data Root

Arakiel installs ThemeEngine source data under:

```text
~/.local/share/typezero/themeengine
```

Important subdirectories:

```text
~/.local/share/typezero/themeengine/themes
~/.local/share/typezero/themeengine/templates
```

Bootstrap replaces those installed copies with the repository versions.

---

## Runtime State Root

Arakiel ThemeEngine state lives under:

```text
~/.config/typezero/themeengine
```

Important files:

```text
current-theme
previous-theme
current.sh
```

---

## `current-theme`

Stores the selected theme ID.

It is the state queried by:

```bash
themeengine current
```

---

## `previous-theme`

Stores the previously active theme ID when available.

It supports:

```bash
themeengine rollback
```

---

## `current.sh`

Generated shell UI state.

Path:

```text
~/.config/typezero/themeengine/current.sh
```

Consumer:

```text
Arakiel/lib/ui.sh
```

The generated file maps ThemeEngine semantic roles onto the existing `UI_*` variables used by maintained shell scripts.

This preserves compatibility with existing scripts while allowing them to inherit the selected theme automatically.

---

# Arakiel Generated Files

Applying a theme renders the following files.

---

## Xresources / URxvt

Template:

```text
ThemeEngine/templates/arakiel/Xresources.tpl
```

Generated:

```text
~/.Xresources.theme
```

Theme-dependent URxvt values live here rather than in the static:

```text
Arakiel/config/x11/Xresources
```

The generated Xresources file includes the selected palette, cursor, typography, and terminal appearance.

---

## i3

Template:

```text
ThemeEngine/templates/arakiel/i3-theme.conf.tpl
```

Generated:

```text
~/.config/i3/theme.conf
```

Consumer:

```text
Arakiel/config/i3/config
```

The main i3 config includes the generated theme file while retaining ownership of non-theme behavior.

---

## i3blocks

Template:

```text
ThemeEngine/templates/arakiel/i3blocks.conf.tpl
```

Generated:

```text
~/.config/i3/i3blocks.conf
```

ThemeEngine owns the theme-dependent status-bar configuration.

---

## tmux

Template:

```text
ThemeEngine/templates/arakiel/tmux.conf.tpl
```

Generated:

```text
~/.config/tmux/theme.conf
```

ThemeEngine can source this file into an existing tmux server after a theme change.

---

## Vim

Shared template:

```text
ThemeEngine/templates/shared/vim-colors.vim.tpl
```

Generated:

```text
~/.config/vim/colors/typezero.vim
```

---

## Lightline

Shared template:

```text
ThemeEngine/templates/shared/vim-lightline.vim.tpl
```

Generated:

```text
~/.config/vim/autoload/lightline/colorscheme/typezero.vim
```

As on Netzach, start a new Vim instance when visually validating a newly applied theme.

---

# Arakiel Runtime Refresh

Unless runtime reload is suppressed, ThemeEngine refreshes supported live surfaces after rendering.

Current behavior includes:

```text
xrdb       → merge ~/.Xresources.theme
tmux       → source ~/.config/tmux/theme.conf when sessions exist
i3blocks   → terminate existing i3blocks process
i3         → i3-msg restart
```

The i3 restart re-executes the window manager while preserving the active session and window layout.

A full operating-system reboot is not required for ordinary ThemeEngine changes.

---

## Suppressing Live Reload

Set:

```bash
THEMEENGINE_NO_RELOAD=1
```

to render/apply ThemeEngine state without performing the normal runtime refresh.

This is useful for:

- testing generated files
- inspecting renderer output
- avoiding changes to the currently displayed desktop during development

Example:

```bash
THEMEENGINE_NO_RELOAD=1 themeengine apply onedark
```

Remember that the theme state and generated files may then be newer than the currently visible graphical session.

---

# Arakiel over SSH

ThemeEngine may be invoked over SSH while Arakiel's graphical i3 session is running locally.

Commands that interact with the X session need the correct display and Xauthority context.

For the current setup:

```bash
export DISPLAY=:0
export XAUTHORITY="$HOME/.Xauthority"
```

Then apply or reload normally:

```bash
themeengine apply onedark
```

or:

```bash
themeengine reload
```

Without the correct X-session context, file generation may succeed while graphical runtime refreshes such as `xrdb` or `i3-msg` fail to reach the live desktop.

---

# Normal Update Workflow

## Adding or changing a theme

Repository:

```text
ThemeEngine/themes/<theme-id>/theme.conf
```

Then:

```text
1. edit the repository source
2. run git diff --check
3. bootstrap on the target system
4. confirm themeengine list
5. preview
6. apply
7. visually test
8. test Vim in a fresh process
9. verify rollback where appropriate
```

---

## Changing a template

After editing a template:

```text
1. bootstrap
2. reload the current theme
3. inspect the generated native file
4. inspect the live application
```

Example on Netzach:

```powershell
themeengine bootstrap -RepoRoot $PWD
themeengine reload
```

Example on Arakiel:

```bash
themeengine bootstrap "$PWD"

export DISPLAY=:0
export XAUTHORITY="$HOME/.Xauthority"

themeengine reload
```

---

## Changing a renderer

Renderer changes are not installed by ThemeEngine bootstrap itself.

Bootstrap installs themes and templates.

If the live renderer is maintained separately from the repository copy, deploy the renderer using the machine's normal configuration/deployment workflow before testing the renderer change.

Then:

```text
1. run doctor
2. bootstrap if theme/template data also changed
3. reload or apply
4. inspect generated files
5. inspect runtime behavior
```

---

# Troubleshooting

## New theme does not appear in `list`

Likely cause:

```text
repository theme exists
but installed theme data is stale
```

Fix:

### Netzach

```powershell
themeengine bootstrap -RepoRoot $PWD
themeengine list
```

### Arakiel

```bash
themeengine bootstrap "$PWD"
themeengine list
```

---

## `apply` says the theme does not exist

Confirm:

```text
ThemeEngine/themes/<theme-id>/theme.conf
```

exists in the repository and then bootstrap again.

Also verify that the requested ID matches the directory and `THEME_ID`.

---

## Theme state changed but Arakiel desktop did not

First check:

```bash
themeengine current
```

Then verify the SSH/X-session environment if operating remotely:

```bash
printf 'DISPLAY=%s\n' "${DISPLAY:-}"
printf 'XAUTHORITY=%s\n' "${XAUTHORITY:-}"
```

For the current live session:

```bash
export DISPLAY=:0
export XAUTHORITY="$HOME/.Xauthority"
```

Then:

```bash
themeengine reload
```

---

## URxvt did not change

Check that:

```text
~/.Xresources.theme
```

exists.

Then confirm the current X resource database has been refreshed.

A fresh URxvt process is the safest visual test after changing terminal resources.

---

## i3 did not change

Check:

```text
~/.config/i3/theme.conf
```

Then verify that the main i3 configuration still includes:

```text
include ~/.config/i3/theme.conf
```

If operating over SSH, verify `DISPLAY` and `XAUTHORITY`, then run:

```bash
themeengine reload
```

---

## i3blocks did not change

Check the generated:

```text
~/.config/i3/i3blocks.conf
```

ThemeEngine terminates the current i3blocks process during normal runtime refresh so i3 can start a new instance using the generated configuration.

If live refresh was suppressed, reload the theme normally afterward.

---

## tmux did not change

Confirm that:

```text
~/.config/tmux/theme.conf
```

exists and that a tmux server is actually running.

ThemeEngine only attempts to source the generated file into existing tmux sessions when tmux is available.

---

## Vim still shows the old theme

Close the old Vim process and start a new one.

ThemeEngine generates:

```text
typezero.vim
```

but existing Vim instances do not automatically re-source the colorscheme after ThemeEngine rewrites it.

---

## PowerShell still shows old semantic UI colors

After `apply`, `reload`, or `rollback`, the ThemeEngine command bridge re-imports `current.ps1`.

If a separately launched or unusually initialized shell does not reflect the change, verify:

```text
%LOCALAPPDATA%\Typezero\ThemeEngine\current.ps1
```

and start a fresh PowerShell process.

---

## Windows Terminal pane has old colors

Confirm that the active PowerShell profile is still associated with the expected:

```text
Typezero <Theme Name>
```

scheme.

A newly opened tab/pane is the safest validation target after modifying Terminal theme settings.

---

## `doctor` reports missing themes or templates

Run bootstrap from the repository root.

### Netzach

```powershell
themeengine bootstrap -RepoRoot $PWD
```

### Arakiel

```bash
themeengine bootstrap "$PWD"
```

Then rerun:

```text
themeengine doctor
```

---

# Runtime Safety Rules

Keep these rules when modifying ThemeEngine runtime behavior:

- repository themes and templates are the source of truth
- generated files should remain reproducible
- runtime state should not be hand-edited as a normal workflow
- bootstrap should install data, not silently redefine unrelated application behavior
- applying a theme should preserve non-theme application settings where practical
- rollback is theme-history rollback, not arbitrary system rollback
- Arakiel should not require a reboot for normal theme changes
- live X-session actions over SSH must target the correct display
- existing Vim instances should not be assumed to reload generated colors automatically
- platform-specific behavior should remain explicit rather than hidden behind fragile magic

---

# Related Documentation

Overview and quick start:

```text
ThemeEngine/README.md
```

Detailed integration map:

```text
ThemeEngine/INTEGRATIONS.md
```

Theme authoring contract:

```text
ThemeEngine/theme.conf.template
```

Together these files define:

```text
README.md             → what ThemeEngine is and how to use it
INTEGRATIONS.md       → what is connected to ThemeEngine
RUNTIME.md            → what happens when ThemeEngine runs
theme.conf.template   → how a theme is defined
```
