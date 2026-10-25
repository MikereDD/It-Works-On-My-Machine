# Netzach

Netzach is the Windows 11 workstation configuration in the
It-Works-On-My-Machine repository.

This directory contains the tracked source for the PowerShell profile,
ThemeEngine integration, Vim configuration, scripts, and supporting Windows
configuration used on the live Netzach system.

## Canonical locations

### PowerShell

Repository source:

    Netzach/PowerShell/

Live deployment:

    $HOME\PS\

The standard PowerShell profile:

    $HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1

is a symbolic link to:

    $HOME\PS\profile.ps1

The profile loader imports configuration from:

    $HOME\PS\profile.d\

The tracked repository counterpart is:

    Netzach/PowerShell/profile.d/

Files that exist in both locations should remain byte-for-byte synchronized
unless explicitly documented as local-only.

## Local-only PowerShell state

profile.d/minforc.ps1 contains machine-local configuration and may contain
secrets or credentials.

The repository copy uses placeholders.

Do not overwrite the live copy with the repository version unless the local
values have first been preserved.

Do not commit live secret values.

## SSH and Arakiel helpers

SSH helper configuration lives in:

    Netzach/PowerShell/profile.d/ssh-aliases.ps1

The current Arakiel host is referenced by hostname:

    arakiel.local

The helper file contains only active paths and commands.

Obsolete local repository and bot-copy paths have been removed.

## ThemeEngine

Tracked Windows ThemeEngine source:

    Netzach/PowerShell/ThemeEngine/ThemeEngine.ps1

Live deployment:

    $HOME\PS\ThemeEngine\ThemeEngine.ps1

Shared ThemeEngine themes and templates live at the repository root:

    ThemeEngine/

ThemeEngine runtime state is stored under:

    $env:LOCALAPPDATA\Typezero\ThemeEngine\

Important runtime files include:

    current-theme
    current.ps1
    themes\<theme-id>\theme.conf

current.ps1 is generated runtime output and exposes the active semantic
PowerShell palette.

ThemeEngine currently manages PowerShell, Windows Terminal, and Vim theme
output.

Use:

    themeengine doctor

to verify the Windows ThemeEngine deployment.

## Vim

Repository configuration:

    Netzach/config/vim/_vimrc
    Netzach/config/vim/vimrc

Live loader:

    $HOME\_vimrc

Live canonical configuration:

    $HOME\config\vim\vimrc

_vimrc is only a compatibility loader. It sources:

    ~/config/vim/vimrc

Plugins and Vim runtime/plugin state live under:

    $HOME\vimfiles\

Persistent editing state lives under:

    $HOME\config\vim\

ThemeEngine generates the active Vim colorscheme at:

    $HOME\config\vim\colors\typezero.vim

and the Lightline palette at:

    $HOME\config\vim\autoload\lightline\colorscheme\typezero.vim

These are generated runtime artifacts, not hand-maintained canonical source.

## Scripts

Tracked scripts live under:

    Netzach/PowerShell/scripts/

Live scripts live under:

    $HOME\PS\scripts\

Shared files should remain byte-for-byte synchronized.

The following classes of files are intentionally local/runtime-only:

- log files
- application configuration generated at runtime
- artwork/cache files
- locally deployed native dependencies such as libmpv-2.dll

These should not be treated as source drift when excluded by .gitignore.

Historical local-only Pac-Man files and an obsolete MediaForge.zip deployment
archive were removed during the Netzach cleanup.

## Admin tools

The PowerShell admin tools under:

    Netzach/PowerShell/scripts/admintools/

use semantic ThemeEngine roles instead of hardcoded console colors.

The standalone admin dashboard also supports live ThemeEngine refresh without
requiring the GUI to be relaunched.

## Theme semantics

User-facing PowerShell UI should use semantic roles exposed through
$global:UI_Theme, including Text, Muted, Accent, Secondary, Info, Success,
Warning, Error, and Reset.

Avoid introducing new hardcoded console colors in user-facing UI.

Bootstrap/load messages that execute before the UI layer is available may use
a minimal fixed fallback where necessary.

## Line endings

The repository intentionally uses CRLF for Windows PowerShell files through
.gitattributes.

Do not normalize tracked .ps1, .psm1, or .psd1 files to LF.

When using .NET file APIs from PowerShell, resolve repository paths to absolute
paths first because [System.IO.File] relative paths use the process working
directory, which may differ from PowerShell's current location.

## Synchronization rules

When changing Netzach configuration:

1. Edit or update the canonical tracked source.
2. Preserve local secrets and runtime-only state.
3. Validate PowerShell files with the PowerShell parser.
4. Run git diff --check.
5. Deploy the canonical file to the live location.
6. Compare live and repository hashes where practical.
7. Test a fresh PowerShell profile load.
8. Run themeengine doctor after ThemeEngine-related changes.
9. Verify Vim loader and generated theme behavior after Vim-related changes.
10. Commit and push to both Forgejo and GitHub.

The intended end state is:

    repository source == live deployed source

except for explicitly documented local-only secrets, generated files, caches,
logs, and native runtime dependencies.
