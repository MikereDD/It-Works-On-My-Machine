# InfoCat in It-Works-On-My-Machine

**Production script:** `Netzach/PowerShell/scripts/personaltools/infocat.ps1`.

The existing `Netzach/PowerShell/profile.d/aliases.ps1` already defines `Invoke-InfoCat` for that path. **Do not edit the alias or PowerShell profile.** InfoCat is a standalone read-only PowerShell 7 script; Fastfetch is not used.

## Options

```powershell
infocat
infocat -Compact
infocat -Timing
infocat -Theme Gruvbox
infocat -Theme Nord
infocat -Theme Auto
infocat -Theme 'OLED Black'
infocat -NoColor
```

When installed, `%LOCALAPPDATA%\Typezero\ThemeEngine\current-theme` and matching `themes/<id>/theme.conf` are read as data, not executed. Without ThemeEngine, fallback palettes work.

## Validation

See `Test-InfoCat.ps1` and `Measure-InfoCat.ps1` in this directory. The two new v2.0 RC cases target machine-name deduplication and label geometry. Execute the complete tests on NETZACH before merging this candidate into `main`. No automatic GitHub release is created by this overlay.

## Packaging / rollback

Commit the script and these tests on a dedicated `feature/infocat-v2.0` branch, then review the diff before merging. `infocat-v1.8.3-baseline.ps1` is retained for benchmark comparisons. Restore an older script through Git history if needed.
