# ThemeEngine

ThemeEngine is the shared cross-platform theming subsystem of **It-Works-On-My-Machine**.

It defines a theme once using semantic roles, then renders that theme into the native formats used by Netzach and Arakiel.

The intent is simple:

> Define appearance once by semantic role, then render it natively for each platform.

ThemeEngine owns appearance. Applications and platforms keep ownership of their behavior.

---

## Current Themes

ThemeEngine currently includes:

- **Obsidian Silver**
- **Catppuccin Mocha**
- **Everforest Dark**
- **Gruvbox**
- **Kanagawa Paper**
- **OneDark**

Each theme is stored as:

```text
ThemeEngine/themes/<theme-id>/theme.conf
```

Theme definitions describe colors by purpose rather than by application-specific settings.

---

## What ThemeEngine Controls

### Netzach

ThemeEngine currently coordinates:

- Windows Terminal color scheme
- Windows Terminal application chrome
- PowerShell semantic UI colors
- Vim colors
- Lightline colors

Renderer:

```text
Netzach/PowerShell/ThemeEngine/ThemeEngine.ps1
```

PowerShell bridge:

```text
Netzach/PowerShell/profile.d/theme.ps1
```

---

### Arakiel

ThemeEngine currently coordinates:

- Xresources / URxvt
- i3
- i3blocks
- tmux
- shell UI colors
- Vim colors
- Lightline colors

Renderer:

```text
Arakiel/local/bin/themeengine
```

---

## Architecture

ThemeEngine follows this flow:

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

A theme defines semantic roles such as:

```text
BG
SURFACE
SURFACE_ALT
BORDER_DARK
BORDER
MUTED
TEXT
BRIGHT
ACCENT
ACCENT_BRIGHT
SUCCESS
WARNING
ERROR
SECONDARY
INFO
```

It also defines:

- focused / active / inactive / urgent desktop roles
- typography metadata
- a complete 16-color ANSI palette

Platform renderers decide how those roles map into native application configuration.

---

## Repository Layout

```text
ThemeEngine/
├── README.md
├── INTEGRATIONS.md
├── theme.conf.template
├── themes/
│   ├── catppuccin-mocha/
│   ├── everforest-dark/
│   ├── gruvbox/
│   ├── kanagawa-paper/
│   ├── obsidian-silver/
│   └── onedark/
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

The `ThemeEngine/` directory contains the portable theme definitions, templates, and documentation.

Platform-specific renderers remain under the Netzach and Arakiel trees because they also contain machine-specific paths, runtime behavior, and application integration logic.

---

## Theme Definitions

Theme files use simple `KEY=VALUE` assignments.

Example:

```text
THEME_ID=onedark
THEME_NAME="OneDark"

BG=#282C34
TEXT=#ABB2BF
ACCENT=#61AFEF
SUCCESS=#98C379
WARNING=#E5C07B
ERROR=#E86671
```

The complete documented authoring contract is:

```text
ThemeEngine/theme.conf.template
```

Use that file as the starting point for new themes.

Important parser rule:

> Keep comments on their own lines.

ThemeEngine treats everything after the first `=` as the value, so inline comments should not be appended to assignments.

---

## Templates

Templates translate semantic roles into application-specific configuration.

### Shared templates

```text
ThemeEngine/templates/shared/vim-colors.vim.tpl
ThemeEngine/templates/shared/vim-lightline.vim.tpl
```

These are used by both Netzach and Arakiel.

They generate the native Vim colorscheme and Lightline palette named:

```text
typezero
```

---

### Arakiel templates

```text
ThemeEngine/templates/arakiel/Xresources.tpl
ThemeEngine/templates/arakiel/i3-theme.conf.tpl
ThemeEngine/templates/arakiel/i3blocks.conf.tpl
ThemeEngine/templates/arakiel/tmux.conf.tpl
```

These generate the native files consumed by URxvt, i3, i3blocks, and tmux.

---

## Quick Start

ThemeEngine uses installed copies of the repository themes and templates.

After changing or adding themes, bootstrap the current repository data before testing.

### Netzach

From the repository root:

```powershell
themeengine bootstrap -RepoRoot $PWD
```

List installed themes:

```powershell
themeengine list
```

Preview a theme:

```powershell
themeengine preview onedark
```

Apply a theme:

```powershell
themeengine apply onedark
```

Show the current theme:

```powershell
themeengine current
```

Rollback:

```powershell
themeengine rollback
```

Run diagnostics:

```powershell
themeengine doctor
```

---

### Arakiel

From the repository root:

```bash
themeengine bootstrap "$PWD"
```

List installed themes:

```bash
themeengine list
```

Preview a theme:

```bash
themeengine preview onedark
```

Apply a theme:

```bash
themeengine apply onedark
```

Show the current theme:

```bash
themeengine current
```

Rollback:

```bash
themeengine rollback
```

Run diagnostics:

```bash
themeengine doctor
```

When applying a theme over SSH to Arakiel's live X session, target that session explicitly:

```bash
export DISPLAY=:0
export XAUTHORITY="$HOME/.Xauthority"

themeengine apply onedark
```

---

## Commands

The ThemeEngine interface includes:

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

`current` is the canonical way to query the active theme.

`reload` reapplies the currently selected theme without changing theme history.

`rollback` returns to the previously active theme when previous-theme state exists.

---

## Generated Outputs

Generated files are deployment outputs.

They are not the source of truth.

The source of truth is:

```text
ThemeEngine/themes/
ThemeEngine/templates/
```

### Arakiel generated outputs

Theme application currently generates:

```text
~/.config/i3/theme.conf
~/.config/i3/i3blocks.conf
~/.Xresources.theme
~/.config/tmux/theme.conf
~/.config/vim/colors/typezero.vim
~/.config/vim/autoload/lightline/colorscheme/typezero.vim
~/.config/typezero/themeengine/current.sh
```

ThemeEngine also maintains current and previous theme state under:

```text
~/.config/typezero/themeengine/
```

Installed themes and templates live under:

```text
~/.local/share/typezero/themeengine/
```

---

### Netzach generated state

ThemeEngine runtime data lives under:

```text
%LOCALAPPDATA%\Typezero\ThemeEngine
```

This includes installed themes and templates, current / previous theme state, and the generated PowerShell theme state.

Generated Vim files live under the existing Netzach Vim configuration tree:

```text
$HOME\config\vim\colors\typezero.vim
$HOME\config\vim\autoload\lightline\colorscheme\typezero.vim
```

ThemeEngine also updates its own Windows Terminal color scheme and application theme.

---

## Vim and Lightline

Vim and Lightline use shared ThemeEngine templates on both platforms.

Vim colors:

```text
ThemeEngine/templates/shared/vim-colors.vim.tpl
```

Lightline colors:

```text
ThemeEngine/templates/shared/vim-lightline.vim.tpl
```

Both are rendered from the same semantic roles used by the rest of ThemeEngine.

This keeps terminal, shell, desktop, Vim, and Lightline colors synchronized without depending on a third-party Vim colorscheme at runtime.

Existing Vim processes do not automatically reload newly generated colors.

Start a fresh Vim instance after applying a new theme.

---

## Creating a Theme

Start with:

```text
ThemeEngine/theme.conf.template
```

Then:

1. copy it to `ThemeEngine/themes/<theme-id>/theme.conf`
2. replace every placeholder
3. preserve the upstream/source palette where practical
4. map source colors into ThemeEngine semantic roles
5. bootstrap the repository data
6. preview and apply the theme
7. test it on both Netzach and Arakiel
8. verify rollback
9. run `git diff --check` before committing

A good ThemeEngine theme should preserve the identity of its source palette while still respecting ThemeEngine's semantic contract.

---

## Ownership Rule

ThemeEngine owns **semantic appearance**.

Applications and platforms own **behavior**.

Examples of ThemeEngine-owned concerns:

- semantic palette values
- ANSI palettes
- terminal colors
- Vim colors
- Lightline colors
- i3 theme colors
- i3blocks colors
- tmux colors
- URxvt theme-dependent appearance
- PowerShell semantic UI colors
- ThemeEngine-managed Windows Terminal scheme/chrome

Examples of application-owned concerns:

- i3 keybindings
- workspace behavior
- Vim editing behavior
- shell command behavior
- tmux workflow behavior
- application business logic
- unrelated Windows Terminal profile preferences
- wallpaper content and wallpaper rotation logic

This boundary prevents ThemeEngine from becoming a general configuration manager.

---

## Integration Reference

The complete source → renderer → generated output → consumer map is documented in:

```text
ThemeEngine/INTEGRATIONS.md
```

That document should be reviewed when changing:

- ThemeEngine paths
- state-file names
- renderer behavior
- generated-file locations
- semantic role names
- application integration points
- runtime refresh behavior

---

## Design Direction

ThemeEngine currently belongs to **It-Works-On-My-Machine** because it directly coordinates the visual environment of Netzach and Arakiel.

Its internal structure intentionally keeps portable pieces separate from platform-specific integration:

```text
portable:
    themes
    templates
    theme authoring contract

platform-specific:
    renderers
    application paths
    runtime refresh logic
    machine integration
```

That separation keeps the subsystem understandable and reusable without requiring it to become a standalone project.

If ThemeEngine ever graduates into its own repository, its theme definitions, templates, authoring contract, and architecture are already separated cleanly enough to make that transition practical.
