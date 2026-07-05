# MediaForge compatibility shim
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$RemainingArgs
)

$localTarget  = Join-Path $PSScriptRoot 'mediaforge-gui.ps1'
$nestedTarget = Join-Path $PSScriptRoot 'MediaForge\mediaforge-gui.ps1'

if (Test-Path -LiteralPath $localTarget) {
    $target = $localTarget
}
elseif (Test-Path -LiteralPath $nestedTarget) {
    $target = $nestedTarget
}
else {
    throw "Cannot find MediaForge GUI. Checked: $localTarget and $nestedTarget"
}

$pwsh  = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
$winps = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
$hostExe = if ($pwsh) { $pwsh } else { $winps }

if (-not $hostExe) { throw 'No pwsh.exe or powershell.exe found.' }

$launchArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-File',$target)
if ($RemainingArgs) { $launchArgs += $RemainingArgs }
& $hostExe @launchArgs
