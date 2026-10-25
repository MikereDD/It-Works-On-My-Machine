# InfoCat release notes

## v2.0-rc.1 (IWOMM integration candidate)

- Start from NETZACH-validated native v1.9, not the abandoned Fastfetch-based prototype.
- Normalize `Win32_ComputerSystem` manufacturer/model display, avoiding `Alienware Alienware m16 R2` while preserving nonduplicate vendors.
- Relabel the Windows accent as `Windows Accent`; ThemeEngine palette colors remain independent.
- Increase info-row label width to 14 characters, with corresponding wrapping and narrow-terminal geometry tests.
- Preserve the original cat artwork, read-only native collectors, existing PowerShell alias, Compact mode, timing diagnostics, and optional ThemeEngine integration.
- Package for IWOMM at the existing `Netzach/PowerShell/scripts/personaltools/infocat.ps1` entry point with colocated regression tests.

## v1.9 (previous validated baseline)

Read-only Typezero ThemeEngine palette integration, auto-selection and built-in fallbacks; five-run medians on NETZACH were 365.9 ms Compact and 1,176.9 ms Full. No Fastfetch dependency.
