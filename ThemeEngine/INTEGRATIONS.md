# ThemeEngine Integrations

ThemeEngine is the shared semantic theming subsystem used by **It-Works-On-My-Machine** across Netzach and Arakiel.

This document records how ThemeEngine connects to the rest of the repository: which files define theme data, which renderers consume it, which native configuration files are generated, and which application or shell components ultimately use those generated outputs.

The goal is to make ThemeEngine understandable without requiring someone to trace every reference manually.

---

## Integration Model

ThemeEngine follows a simple pipeline:

```text
theme.conf
    ↓
bootstrap installs themes + templates
    ↓
platform renderer
    ↓
generated native files
    ↓
application / shell consumers
    ↓
runtime refresh where supported
```

Themes describe **semantic roles** such as background, text, accent, warning, error, border, and ANSI colors.

Renderers translate those roles into the native configuration formats expected by each platform.

Applications and platform configuration files consume the generated outputs.

---

## Repository Layout

```text
ThemeEngine/
├── README.md
├── INTEGRATIONS.md
├── theme.conf.template
├── themes/
│   ├── catppuccin-mocha/
│   │   └── theme.conf
│   ├── everforest-dark/
│   │   └── theme.conf
│   ├── gruvbox/
│   │   └── theme.conf
│   ├── kanagawa-paper/
│   │   └── theme.conf
│   ├── obsidian-silver/
│   │   └── theme.conf
│   └── onedark/
│       └── theme.conf
└── templates/
    ├── arakiel/
    │   ├── Xresources.tpl
    │   ├── i3-theme.conf.tpl
    │   ├── i3blocks.conf.tpl
    │   └── tmux.conf.tpl
    └── shared/
        ├── vim-colors.vim.tpl
        └── vim-lightline.vim.tpl
```

The `ThemeEngine/` tree contains the portable theme definitions and templates.

Platform-specific renderers and integration hooks remain under their machine trees because they also encode machine-specific paths, application behavior, and runtime refresh logic.

---

## Theme Definitions

Each theme lives under:

```text
ThemeEngine/themes/<theme-id>/theme.conf
```

The theme file is the canonical source for:

- theme identity
- typography metadata
- background and surface roles
- text and muted foregrounds
- accent colors
- success, warning, error, secondary, and informational roles
- i3-focused, active, inactive, and urgent roles
- complete normal and bright ANSI terminal palettes

The documented authoring contract lives at:

```text
ThemeEngine/theme.conf.template
```

New themes should be based on that file rather than created from memory.

The parser expects `KEY=VALUE` assignments and treats everything after the first `=` as the value. For that reason, comments belong on their own lines rather than after assignments.

---

## Shared Templates

### Vim colors

Source:

```text
ThemeEngine/templates/shared/vim-colors.vim.tpl
```

Purpose:

- renders ThemeEngine semantic roles into a native Vim colorscheme
- keeps Vim independent from third-party colorscheme plugins
- provides the same semantic appearance on both platforms
- uses the generated colorscheme name `typezero`

Generated output on Arakiel:

```text
~/.config/vim/colors/typezero.vim
```

Generated output on Netzach:

```text
$HOME\config\vim\colors\typezero.vim
```

Consumers:

```text
Arakiel/config/vim/vimrc
Netzach/config/vim/vimrc
```

Both Vim configurations add their existing local runtime trees to `runtimepath`, enable true-color support when available, and load the generated `typezero` colorscheme with a safe fallback when ThemeEngine has not yet been bootstrapped.

Existing Vim processes do not automatically reload a newly generated theme. A new Vim instance loads the current palette.

---

### Lightline colors

Source:

```text
ThemeEngine/templates/shared/vim-lightline.vim.tpl
```

Purpose:

- renders a ThemeEngine-aware Lightline palette
- maps Vim mode colors to semantic roles
- keeps the Lightline status line synchronized with the generated Vim colorscheme

Generated output on Arakiel:

```text
~/.config/vim/autoload/lightline/colorscheme/typezero.vim
```

Generated output on Netzach:

```text
$HOME\config\vim\autoload\lightline\colorscheme\typezero.vim
```

Consumers:

```text
Arakiel/config/vim/vimrc
Netzach/config/vim/vimrc
```

---

# Arakiel Integration

## Renderer

Repository source:

```text
Arakiel/local/bin/themeengine
```

Expected live command:

```text
~/.local/bin/themeengine
```

The Arakiel renderer is a Bash implementation.

Its responsibilities include:

- reading installed `theme.conf` files
- rendering Arakiel-specific templates
- rendering shared Vim and Lightline templates
- generating shell UI state
- maintaining current and previous theme state
- refreshing supported runtime surfaces after a theme change

---

## Installed ThemeEngine Data

The Arakiel renderer installs ThemeEngine data under:

```text
~/.local/share/typezero/themeengine/
```

Important paths:

```text
~/.local/share/typezero/themeengine/themes/
~/.local/share/typezero/themeengine/templates/
```

Bootstrap command from the repository root:

```bash
themeengine bootstrap "$PWD"
```

Bootstrap replaces the installed themes and templates with the current repository copies.

Normal theme application uses the installed ThemeEngine data rather than reading directly from the development repository.

---

## Arakiel State

ThemeEngine state lives under:

```text
~/.config/typezero/themeengine/
```

Important files:

```text
~/.config/typezero/themeengine/current-theme
~/.config/typezero/themeengine/previous-theme
~/.config/typezero/themeengine/current.sh
```

### `current-theme`

Contains the current theme ID.

It is the backing state for:

```bash
themeengine current
```

### `previous-theme`

Contains the previously active theme ID when available.

It supports:

```bash
themeengine rollback
```

### `current.sh`

Generated shell palette consumed by the shared Arakiel shell UI layer.

It exposes the selected ThemeEngine palette through existing `UI_*` shell variables so maintained scripts do not need to know which theme is active.

Consumer:

```text
Arakiel/lib/ui.sh
```

---

## Arakiel Xresources / URxvt

Template:

```text
ThemeEngine/templates/arakiel/Xresources.tpl
```

Generated output:

```text
~/.Xresources.theme
```

The generated file owns theme-dependent URxvt appearance, including:

- background
- foreground
- cursor color
- font
- terminal tint
- transparency shading
- ANSI palette

Static repository configuration:

```text
Arakiel/config/x11/Xresources
```

That file intentionally does **not** define theme-dependent URxvt values. ThemeEngine is the authoritative owner of those settings.

The i3 configuration also merges the generated file during startup:

```text
Arakiel/config/i3/config
```

Relevant runtime behavior:

```text
xrdb -merge ~/.Xresources.theme
```

The ThemeEngine renderer also merges the generated Xresources file when applying or reloading a theme.

Additional consumer:

```text
Arakiel/scripts/personaltools/infocat-pi.sh
```

That tool reads `~/.Xresources.theme` when reporting terminal/font information.

---

## Arakiel i3

Template:

```text
ThemeEngine/templates/arakiel/i3-theme.conf.tpl
```

Generated output:

```text
~/.config/i3/theme.conf
```

Consumer:

```text
Arakiel/config/i3/config
```

The main i3 configuration contains:

```text
include ~/.config/i3/theme.conf
```

This keeps static i3 behavior separate from theme-dependent appearance.

ThemeEngine owns the generated theme fragment while the repository's main i3 config continues to own:

- keybindings
- workspace behavior
- terminal selection
- launcher behavior
- startup commands
- other non-theme window-manager behavior

When a theme is applied, ThemeEngine re-executes i3 with:

```text
i3-msg restart
```

This preserves the running i3 session and window layout while loading the newly generated theme configuration.

When ThemeEngine is invoked over SSH for the live graphical session, the X session must be targetable through the appropriate `DISPLAY` and `XAUTHORITY` values.

For the current Arakiel setup:

```bash
export DISPLAY=:0
export XAUTHORITY="$HOME/.Xauthority"
```

---

## Arakiel i3blocks

Template:

```text
ThemeEngine/templates/arakiel/i3blocks.conf.tpl
```

Generated output:

```text
~/.config/i3/i3blocks.conf
```

ThemeEngine owns the theme-aware status bar configuration.

The renderer terminates the existing `i3blocks` process during runtime refresh so i3 can start a fresh instance using the newly generated configuration.

---

## Arakiel tmux

Template:

```text
ThemeEngine/templates/arakiel/tmux.conf.tpl
```

Generated output:

```text
~/.config/tmux/theme.conf
```

When tmux is available and has active sessions, ThemeEngine reloads that generated theme file after application:

```text
tmux source-file ~/.config/tmux/theme.conf
```

This allows existing tmux sessions to adopt the active palette without requiring a new tmux server.

---

## Arakiel Shell UI

Repository consumer:

```text
Arakiel/lib/ui.sh
```

`ui.sh` defines safe fallback ANSI colors first.

It then checks for:

```text
~/.config/typezero/themeengine/current.sh
```

When present, the generated file overrides the legacy `UI_*` color variables with ThemeEngine semantic values.

This preserves the existing shell-script API while allowing maintained scripts to inherit the selected theme automatically.

---

## Arakiel Runtime Refresh

Unless explicitly suppressed, applying or reloading a theme performs the following runtime work where the related tools are available:

```text
xrdb       → merges ~/.Xresources.theme
tmux       → reloads ~/.config/tmux/theme.conf
i3blocks   → existing process is terminated
i3         → restarted with i3-msg restart
```

Runtime refresh may be suppressed by setting:

```bash
THEMEENGINE_NO_RELOAD=1
```

This is useful when rendering/testing ThemeEngine data without touching the active graphical session.

---

# Netzach Integration

## Renderer

Repository source:

```text
Netzach/PowerShell/ThemeEngine/ThemeEngine.ps1
```

The Netzach renderer is a PowerShell implementation.

Its responsibilities include:

- reading installed themes
- generating PowerShell theme state
- rendering shared Vim and Lightline templates
- updating the ThemeEngine-owned Windows Terminal color scheme
- updating ThemeEngine-owned Windows Terminal chrome
- associating the PowerShell 7 profile with the active ThemeEngine scheme
- maintaining current and previous theme state

---

## ThemeEngine PowerShell Bridge

Repository source:

```text
Netzach/PowerShell/profile.d/theme.ps1
```

This file provides the user-facing:

```powershell
themeengine
```

PowerShell command.

It points to the renderer under the installed PowerShell tree and imports the generated current theme state.

After:

```text
apply
reload
rollback
```

the bridge re-imports the generated ThemeEngine state so the current PowerShell process can see the newly selected palette.

---

## Netzach Installed Data and State

ThemeEngine uses:

```text
%LOCALAPPDATA%\Typezero\ThemeEngine
```

as its local runtime root.

Important content includes:

```text
themes\
templates\
current-theme
previous-theme
current.ps1
```

Bootstrap command from the repository root:

```powershell
themeengine bootstrap -RepoRoot $PWD
```

Bootstrap replaces the installed theme and template copies with the current repository versions.

---

## Netzach PowerShell Theme State

Generated file:

```text
%LOCALAPPDATA%\Typezero\ThemeEngine\current.ps1
```

Loaded by:

```text
Netzach/PowerShell/profile.d/theme.ps1
```

Consumed by:

```text
Netzach/PowerShell/profile.d/ui.ps1
```

The generated state exposes a semantic `TE_Theme` palette.

`ui.ps1` prefers that semantic palette when available and otherwise falls back to its established legacy ANSI defaults.

This allows maintained console scripts to consume semantic roles such as:

```text
Accent
Title
Success
Warning
Error
Muted
Text
Secondary
Info
```

without knowing which specific theme is active.

---

## Netzach PowerShell Profile Load Order

Repository source:

```text
Netzach/PowerShell/profile.ps1
```

The profile loads the ThemeEngine bridge before the main UI presentation layer.

This order matters because the generated ThemeEngine state must be available before `ui.ps1` creates its semantic `UI_Theme` mapping.

Conceptually:

```text
base environment
    ↓
profile.d/theme.ps1
    ↓
generated current.ps1
    ↓
profile.d/ui.ps1
    ↓
maintained console scripts
```

---

## Windows Terminal

The Netzach renderer updates Windows Terminal directly.

ThemeEngine creates or replaces the scheme associated with the selected theme while leaving unrelated user-defined schemes intact.

The generated scheme maps ThemeEngine roles into Windows Terminal fields including:

```text
background
foreground
cursorColor
selectionBackground
black / brightBlack
red / brightRed
green / brightGreen
yellow / brightYellow
blue / brightBlue
purple / brightPurple
cyan / brightCyan
white / brightWhite
```

The scheme name follows:

```text
Typezero <Theme Name>
```

Examples:

```text
Typezero OneDark
Typezero Kanagawa Paper
```

ThemeEngine also owns a Windows Terminal application theme named:

```text
Typezero ThemeEngine
```

That application theme coordinates terminal chrome such as:

- active tab background behavior
- unfocused tab background
- tab-row background
- close-button visibility
- dark application mode

ThemeEngine deliberately leaves unrelated profile-specific preferences untouched, including the user's wallpaper, opacity, and other non-theme settings.

---

## Windows Terminal PowerShell Profile

ThemeEngine targets the PowerShell 7 Windows Terminal profile by its stable GUID:

```text
{574e775e-4f2a-5b96-ac1e-a2962a402336}
```

Using the stable GUID avoids depending on a profile display name that may be renamed by the user.

The renderer updates that profile's:

```text
colorScheme
```

association to the selected Typezero ThemeEngine scheme.

---

## Windows Terminal Backup

Before ThemeEngine performs its first Windows Terminal write, it preserves the original settings file as a stable pre-ThemeEngine backup:

```text
settings.json.typezero-backup
```

This is intentionally not a rotating snapshot.

It represents the user's Windows Terminal configuration from before ThemeEngine first modified it.

---

# Cross-Platform Consumers

The following repository files intentionally depend on ThemeEngine while remaining outside the `ThemeEngine/` directory:

```text
Arakiel/local/bin/themeengine
Arakiel/lib/ui.sh
Arakiel/config/x11/Xresources
Arakiel/config/i3/config
Arakiel/config/vim/vimrc
Arakiel/scripts/personaltools/infocat-pi.sh

Netzach/PowerShell/ThemeEngine/ThemeEngine.ps1
Netzach/PowerShell/profile.ps1
Netzach/PowerShell/profile.d/theme.ps1
Netzach/PowerShell/profile.d/ui.ps1
Netzach/config/vim/vimrc
```

These files should be reviewed when changing ThemeEngine behavior, paths, state names, generated-file locations, or semantic role definitions.

---

# Ownership Boundaries

ThemeEngine owns **appearance**, not general application behavior.

Examples:

### ThemeEngine owns

- semantic palette values
- terminal ANSI palettes
- generated Vim and Lightline colors
- i3 theme colors
- i3blocks visual colors
- tmux theme colors
- URxvt theme-dependent colors and typography
- Windows Terminal ThemeEngine schemes
- PowerShell semantic UI palette state

### ThemeEngine does not own

- i3 keybindings
- workspace names and navigation behavior
- application business logic
- shell command behavior
- tmux workflow behavior
- Vim editing behavior
- arbitrary Windows Terminal profile preferences unrelated to theming
- wallpaper files or wallpaper rotation logic

This boundary is intentional.

A renderer may touch an application configuration file when necessary to activate ThemeEngine output, but it should avoid taking ownership of unrelated behavior.

---

# Safe Change Checklist

When modifying ThemeEngine architecture rather than adding only a new palette, inspect all connected surfaces.

At minimum:

```text
ThemeEngine/theme.conf.template
ThemeEngine/templates/
Arakiel/local/bin/themeengine
Arakiel/lib/ui.sh
Arakiel/config/x11/Xresources
Arakiel/config/i3/config
Arakiel/config/vim/vimrc
Netzach/PowerShell/ThemeEngine/ThemeEngine.ps1
Netzach/PowerShell/profile.ps1
Netzach/PowerShell/profile.d/theme.ps1
Netzach/PowerShell/profile.d/ui.ps1
Netzach/config/vim/vimrc
```

Then test:

```text
themeengine list
themeengine current
themeengine preview <theme>
themeengine apply <theme>
themeengine reload
themeengine rollback
themeengine doctor
```

And visually verify the relevant platform surfaces.

For changes that affect generated Vim files, verify that the generated files have clean line endings on both systems and start a fresh Vim process before judging the result.

---

# Design Principle

The central ThemeEngine contract is:

> Define appearance once by semantic role, then render it natively for each platform.

The shared palette should remain portable.

Platform renderers should remain explicit.

Generated outputs should remain disposable and reproducible.

Applications should consume generated ThemeEngine state rather than independently inventing theme colors.

That separation is what allows ThemeEngine to remain a subsystem today while still being structured cleanly enough to become a standalone project later if that ever becomes desirable.
