# MediaForge compatibility shim
$target = Join-Path $PSScriptRoot 'MediaForge\media-encoder-gui.ps1'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File $target @args
