# ThemeEngine

ThemeEngine is the shared cross-platform theming subsystem of **It-Works-On-My-Machine**.

A theme is defined once using semantic roles and rendered into native configuration for Netzach and Arakiel. The systems keep their platform-specific tools while sharing a consistent visual identity.

## Current Themes

- **Obsidian Silver**
- **Catppuccin Mocha**
- **Everforest Dark**
- **Gruvbox**

## Architecture

Theme definitions live in `themes/` and describe colors by purpose rather than by application.

Core semantic roles include:

- `BG`
- `SURFACE`
- `SURFACE_ALT`
- `BORDER_DARK`
- `BORDER`
- `MUTED`
- `TEXT`
- `BRIGHT`
- `ACCENT`
- `ACCENT_BRIGHT`
- `SUCCESS`
- `WARNING`
- `ERROR`
- `SECONDARY`
- `INFO`

Platform-specific values such as fonts and i3 bar geometry may live alongside the semantic palette when they are part of reproducing the complete theme.

Templates under `templates/` translate shared semantic roles into application-specific configuration. Themes and templates are the source of truth; generated files are deployment outputs.

## Netzach

Netzach uses the PowerShell renderer:

`Netzach/PowerShell/ThemeEngine/ThemeEngine.ps1`

ThemeEngine currently coordinates these supported surfaces:

- Windows Terminal application chrome
- PowerShell UI and startup presentation
- Vim colors
- Lightline colors

The generated Vim colorscheme and Lightline palette live inside the existing Netzach Vim configuration tree.

## Arakiel

Arakiel uses the shell renderer:

`Arakiel/local/bin/themeengine`

ThemeEngine currently coordinates these supported surfaces:

- Xresources and URxvt
- i3
- i3blocks
- tmux
- shell UI
- Vim colors
- Lightline colors

URxvt uses the active semantic background as its tint while retaining pseudo-transparency, allowing the rotating Arakiel wallpaper to remain visible without abandoning the active palette.

## Vim and Lightline

Vim is themed from the shared template:

`templates/shared/vim-colors.vim.tpl`

Lightline uses its own generated palette:

`templates/shared/vim-lightline.vim.tpl`

Both are rendered from the same semantic roles used elsewhere by ThemeEngine. This keeps syntax highlighting and the status line synchronized with the active theme without depending on a third-party Vim colorscheme.

The generated Vim colorscheme is named `typezero`.

Existing Vim instances do not automatically reload newly generated colors after a theme change. A newly started Vim instance loads the current palette.

## Commands

The ThemeEngine interface includes:

- `list`
- `current`
- `preview`
- `apply`
- `reload`
- `rollback`
- `doctor`
- `bootstrap`
- `help`

`current` is the canonical way to query the active theme.

Applying a theme updates ThemeEngine state, renders platform-specific outputs, and refreshes supported runtime surfaces where appropriate.

## Bootstrap

Bootstrap installs the shared themes and templates required by the local renderer.

Arakiel uses the positional repository-root form:

```bash
themeengine bootstrap "$PWD"
```

Netzach uses:

```powershell
themeengine bootstrap -RepoRoot $PWD
```

The two implementations intentionally retain native command syntax for their respective platforms.

## Design Rule

ThemeEngine owns **semantic appearance**, while applications and platforms retain ownership of their behavior.

A theme describes concepts such as background, text, accent, success, warning, and error once. Renderers and templates decide how those concepts map onto Windows Terminal, PowerShell, Xresources, i3, tmux, Vim, Lightline, and other supported surfaces.
