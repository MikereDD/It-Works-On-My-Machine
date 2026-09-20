<p align="center">
  <img src="assets/it-works-on-my-machine-avatar.png" alt="It Works On My Machine — Netzach and Arakiel" width="700">
</p>

# It-Works-On-My-Machine

> **If it defines or helps operate Netzach or Arakiel, it belongs here. If it grows into a standalone application or project, it graduates out.**

`It-Works-On-My-Machine` is the working systems repository for **Netzach**, the Windows development workstation, and **Arakiel**, the Arch Linux / Raspberry Pi 5 server and automation node.

This is where dotfiles, shell environments, administration scripts, personal tools, machine setup, reusable pieces, experiments, and prototypes live.

The repository is intentionally machine-aware rather than generic. Windows and Linux keep their native tools and behavior, while shared conventions make moving between the two environments feel as familiar as practical.

A shared ThemeEngine coordinates supported visual surfaces across both systems, and the shell environments aim for comparable navigation, naming, status language, and day-to-day workflow without hiding platform differences.

## Systems

### Netzach — Development Workstation

Windows development, build, testing, media tooling, and daily workstation automation.

- PowerShell profile and modular `profile.d` configuration
- Administration and utility scripts
- Personal tools and historical PowerShell prototypes
- Vim configuration
- ThemeEngine integration for PowerShell, Windows Terminal, Vim, and Lightline
- Machine setup and workstation-specific experiments

The PowerShell versions of projects such as **Cadence**, **MediaForge**, **Parallax**, and **AtomicClock** remain here as part of their development lineage even when their modern descendants live in standalone repositories.

### Arakiel — Server / Automation Node

Arch Linux on Raspberry Pi 5, providing the always-on side of the environment.

- Bash and Zsh environments
- Shared shell libraries used by both shells
- tmux, Vim, i3, X11, and Wi-Fi configuration
- Raspberry Pi administration and health tools
- Network, backup, update, and system utilities
- Media and personal shell tools
- ThemeEngine integration for URxvt, i3, i3blocks, tmux, shell UI, Vim, and Lightline
- Service and setup material for the server

## Repository Layout

```text
It-Works-On-My-Machine/
├── Netzach/
│   ├── PowerShell/
│   │   ├── ThemeEngine/
│   │   ├── profile.d/
│   │   ├── scripts/
│   │   └── profile.ps1
│   ├── config/
│   │   └── vim/
│   ├── setup/
│   └── experiments/
├── Arakiel/
│   ├── bash.d/
│   ├── zsh.d/
│   ├── bin/
│   ├── scripts/
│   ├── lib/
│   ├── local/
│   ├── config/
│   │   ├── i3/
│   │   ├── shell/
│   │   ├── tmux/
│   │   ├── vim/
│   │   ├── wifi-menu/
│   │   └── x11/
│   ├── services/
│   └── setup/
├── ThemeEngine/
│   ├── README.md
│   ├── INTEGRATIONS.md
│   ├── RUNTIME.md
│   ├── theme.conf.template
│   ├── themes/
│   └── templates/
├── Shared/
│   ├── scripts/
│   ├── tools/
│   ├── dotfiles/
│   └── templates/
├── Experiments/
│   ├── 3D-Printing/
│   ├── Android/
│   ├── Games/
│   └── prototypes/
├── assets/
├── docs/
├── .gitattributes
├── .gitignore
├── LICENSE
└── README.md
```

## Shell Environment

Netzach and Arakiel are different operating systems, but the interactive shell experience is intended to remain familiar between them.

The goal is **consistency of intent**, not artificial implementation symmetry.

Examples include:

- familiar prompt structure and Git context
- comparable navigation helpers
- shared naming where commands serve the same purpose
- semantic status and diagnostic colors
- small shell-specific loaders around shared implementations where practical
- explicit documentation where native platform behavior must differ

On Arakiel, Bash and Zsh loaders under `bash.d/` and `zsh.d/` intentionally stay small while shared implementations live under `Arakiel/lib/`.

On Netzach, the PowerShell environment is modularized under `Netzach/PowerShell/profile.d/`, with the main profile controlling load order.

Platform-specific behavior should remain visible and documented rather than hidden behind fragile abstraction.

## ThemeEngine

`ThemeEngine/` is the shared cross-platform theming subsystem for Netzach and Arakiel.

Themes define semantic appearance once and the platform renderers translate those roles into native configuration.

ThemeEngine currently coordinates:

- Windows Terminal and PowerShell semantic UI on Netzach
- Xresources / URxvt, i3, i3blocks, tmux, and shell UI on Arakiel
- Vim and Lightline on both systems

Current themes:

- **Obsidian Silver**
- **Catppuccin Mocha**
- **Everforest Dark**
- **Gruvbox**
- **Kanagawa Paper**
- **OneDark**
- **Dusty's Pink AF Theme**

ThemeEngine also supports optional interaction-state roles:

```text
SELECTION → BORDER
CURSOR    → ACCENT_BRIGHT
FOCUS     → ACCENT
```

Themes that do not define those roles retain their existing appearance through the documented fallbacks.

ThemeEngine documentation is split by purpose:

- [`ThemeEngine/README.md`](ThemeEngine/README.md) — overview, architecture, and quick start
- [`ThemeEngine/INTEGRATIONS.md`](ThemeEngine/INTEGRATIONS.md) — source, renderer, generated-output, and consumer map
- [`ThemeEngine/RUNTIME.md`](ThemeEngine/RUNTIME.md) — installed state, runtime behavior, reloads, and troubleshooting
- [`ThemeEngine/theme.conf.template`](ThemeEngine/theme.conf.template) — authoritative theme authoring contract

The ownership rule is simple:

> **ThemeEngine owns appearance. Applications and platforms own behavior.**

## Shared

`Shared/` is reserved for material that genuinely belongs to both machines: reusable scripts, common tools, portable dotfiles, and templates.

Machine-specific files stay with their machine rather than being forced into a common abstraction merely to make the directory tree look symmetrical.

## Experiments

`Experiments/` is the workshop. It preserves 3D-printing projects, Android work, games, and space for new prototypes.

An experiment does not need to become a product.

If one grows into a maintained standalone application or tool, it can graduate into its own repository while useful prototype or lineage material may remain here when it explains how the project began.

## Documentation Standard

Maintained configuration files and scripts should be documented well enough that someone unfamiliar with the environment can understand:

- what the file is for
- what loads or consumes it
- important dependencies
- non-obvious behavior
- platform-specific decisions
- safety considerations
- why a configuration choice exists when the reason is not obvious

Comments should explain intent and operational context rather than merely restating commands.

The repository should be understandable without requiring commit-history archaeology or private knowledge of Netzach and Arakiel.

## Philosophy

This repository is intentionally practical rather than generic. The files here are built around the machines they actually run on.

**Discover → Build → Use → Refine → Graduate**

The name remains the rule:

> Everything in here works. On my machine.

## License

[WTFPL](./LICENSE) — do what the fuck you want.
