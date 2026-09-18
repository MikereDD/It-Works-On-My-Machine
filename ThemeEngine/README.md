# ThemeEngine

ThemeEngine is a cross-platform theming subsystem of **It Works On My Machine**.

A theme is defined once with semantic roles and rendered appropriately for
Arakiel/Linux and Netzach/PowerShell.

## Theme semantics

The core palette intentionally describes purpose rather than application:

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

Platform-specific layout values such as i3 bar height and font are kept in the
same theme definition so a named theme remains reproducible.

## First theme

`obsidian-silver` is the reference theme for v0.1-dev.
