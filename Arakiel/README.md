# Arakiel

Arakiel is the Raspberry Pi 5 Linux host configuration tracked in `It-Works-On-My-Machine`.

This directory is the canonical repo-side reference for the machine's shared shell environment, ThemeEngine integration, i3, tmux, Vim, and supporting tools.

## Configuration model

Arakiel uses three kinds of files. They should not be treated as equivalent during audits.

### 1. Canonical repo-managed configuration

These files are intended to match the live machine directly:

- `Arakiel/lib/env.sh` -> `~/lib/env.sh`
- `Arakiel/lib/core.sh` -> `~/lib/core.sh`
- `Arakiel/lib/ui.sh` -> `~/lib/ui.sh`
- `Arakiel/lib/motd.sh` -> `~/lib/motd.sh`
- `Arakiel/bash.d/*` -> `~/.bash.d/*`
- `Arakiel/config/i3/config` -> `~/.config/i3/config`
- `Arakiel/config/vim/vimrc` -> `~/.config/vim/vimrc`
- `Arakiel/config/tmux/tmux.conf` -> `~/.config/tmux/tmux.conf`

These are appropriate for direct `cmp` or `diff` checks.

### 2. Compatibility loaders

Some traditional config paths exist only to load the canonical XDG-style configuration:

- `~/.vimrc` loads `~/.config/vim/vimrc`
  - repo reference: `Arakiel/config/vim/vimrc.legacy`
- `~/.tmux.conf` loads `~/.config/tmux/tmux.conf`
  - repo reference: `Arakiel/config/tmux/tmux.legacy.conf`

Do not compare the loader files directly against the canonical Vim or tmux configuration.

### 3. ThemeEngine-generated output

ThemeEngine renders the currently active theme into live configuration files.

Important generated targets include:

- `~/.config/typezero/themeengine/current.sh`
- `~/.config/i3/theme.conf`
- `~/.config/i3/i3blocks.conf`
- `~/.Xresources.theme`
- `~/.config/tmux/theme.conf`
- ThemeEngine-generated Vim color assets under `~/.config/vim`

Generated files may legitimately differ from repo snapshots when another theme is active.

Do not compare ThemeEngine templates directly against rendered output.

## i3blocks snapshot

`Arakiel/config/i3/i3blocks.conf` is a rendered snapshot, not the primary ThemeEngine source.

The authoritative source is `ThemeEngine/templates/arakiel/i3blocks.conf.tpl`.

A live `~/.config/i3/i3blocks.conf` may differ from the snapshot solely because another ThemeEngine theme is currently active.

## Shared shell UI

Arakiel shell tools use the shared UI layer in `~/lib/core.sh` and `~/lib/ui.sh`.

ThemeEngine exposes the active semantic palette through `~/.config/typezero/themeengine/current.sh`.

Tools should prefer shared `UI_*` roles instead of defining independent color palettes.

Current integrations include:

- Bash prompt
- SSH MOTD
- system information tools
- firewall tools
- infocat
- Blu-ray helper library

Hard-coded ANSI values should generally be limited to fallback palettes, terminal reset/clear controls, text attributes such as bold/dim, terminal capability definitions, and ThemeEngine generation logic.

## Audit

Useful live-vs-repo checks:

```bash
cmp ~/lib/env.sh Arakiel/lib/env.sh
cmp ~/lib/core.sh Arakiel/lib/core.sh
cmp ~/lib/ui.sh Arakiel/lib/ui.sh
cmp ~/lib/motd.sh Arakiel/lib/motd.sh
```

Canonical Vim:

```bash
cmp ~/.config/vim/vimrc Arakiel/config/vim/vimrc
```

Canonical tmux:

```bash
cmp ~/.config/tmux/tmux.conf Arakiel/config/tmux/tmux.conf
```

Active ThemeEngine theme:

```bash
grep -E '^TE_THEME_(ID|NAME)=' ~/.config/typezero/themeengine/current.sh
```

## Deployment practice

Before replacing a live configuration file:

1. Inspect the diff.
2. Create a dated backup.
3. Copy the repo version into place.
4. Run syntax validation where applicable.
5. Compare live and repo copies.
6. Test the feature interactively.
7. Commit only after the live test succeeds.

Useful validation commands:

```bash
bash -n path/to/script
zsh -n path/to/script
git diff --check
```

## ThemeEngine

ThemeEngine is the preferred presentation layer for Arakiel.

Theme-specific appearance should flow from ThemeEngine rather than being duplicated independently across shell tools and applications.

The goal is:

**one theme source -> generated targets -> consistent system appearance**
