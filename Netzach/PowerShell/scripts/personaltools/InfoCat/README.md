# InfoCat regression tests (Windows / PowerShell 7)

The production entry point remains `../infocat.ps1`, which is called by the existing `Invoke-InfoCat` alias in IWOMM. These files support read-only validation and benchmarks.

Run from this directory:

```powershell
.\Test-InfoCat.ps1
.\Test-InfoCat.ps1 -HardwareProbe
..\infocat.ps1 -Theme Auto
..\infocat.ps1 -Theme Gruvbox
..\infocat.ps1 -Theme Nord
..\infocat.ps1 -Theme OneDark
..\infocat.ps1 -Theme 'OLED Black'
..\infocat.ps1 -Compact -Timing
.\Measure-InfoCat.ps1
.\Measure-InfoCat.ps1 -Full
```

The original v1.4.2 art baseline and v1.8.3 performance baseline are retained as read-only test fixtures. The test only executes native probes when `-HardwareProbe` is explicitly selected. None of the scripts changes ThemeEngine, profile files, Windows Terminal settings, or hardware configuration.
