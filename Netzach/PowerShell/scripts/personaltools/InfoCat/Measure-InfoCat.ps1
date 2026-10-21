#Requires -Version 7.0
<#
.SYNOPSIS
    Compare the InfoCat 1.8.3 baseline against 2.0 RC performance on the same Windows host.
.DESCRIPTION
    No writes or configuration changes. Warm-up runs are excluded, medians are
    calculated from individual Total elapsed values reported by -Timing.
    Cold PowerShell startup is not included. The result is a relative collector
    benchmark, not a guarantee or a hardware benchmark.
#>
[CmdletBinding()]
param(
    [ValidateRange(2, 20)][int]$Count = 5,
    [ValidateRange(0, 5)][int]$Warmup = 1,
    [switch]$Full
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $PSCommandPath
$versions = [ordered]@{
    '1.8.3 baseline' = Join-Path $here 'infocat-v1.8.3-baseline.ps1'
    '2.0 RC' = Join-Path (Split-Path -Parent $here) 'infocat.ps1'
}
function Get-TimeSample {
    param([string]$File, [bool]$UseCompact)
    # Capture the Information stream emitted by Write-Host, without showing
    # pages of artwork for every timing sample.
    $output = if ($UseCompact) {
        & $File -Compact -Timing -NoColor 6>&1 | Out-String
    } else {
        & $File -Timing -NoColor 6>&1 | Out-String
    }
    $match = [regex]::Match($output, '(?m)^\s*Total elapsed\s+([0-9,.]+)\s+ms\s*$')
    if (-not $match.Success) {
        throw "Failed to read Total elapsed from $File. Run it manually with -Timing."
    }
    $number = $match.Groups[1].Value.Replace(',', '')
    [double]::Parse($number, [Globalization.CultureInfo]::InvariantCulture)
}
function Get-Median {
    param([double[]]$Data)
    $sorted = @($Data | Sort-Object)
    $i = [int][Math]::Floor($sorted.Count / 2)
    if ($sorted.Count % 2) { return [double]$sorted[$i] }
    return ([double]$sorted[$i - 1] + [double]$sorted[$i]) / 2
}
$compact = -not $Full
Write-Host ("InfoCat native A/B timings: {0}, {1} measured runs, {2} warmup(s)." -f `
    $(if ($compact) { 'Compact' } else { 'Full' }), $Count, $Warmup)
Write-Host 'Hardware load and first-run overhead affect results; compare medians.'
$results = [ordered]@{}
foreach ($name in $versions.Keys) {
    $path = $versions[$name]
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing script $path" }
    for ($w=0; $w -lt $Warmup; $w++) { $null = Get-TimeSample -File $path -UseCompact $compact }
    $times = [System.Collections.Generic.List[double]]::new()
    for ($i=0; $i -lt $Count; $i++) {
        $times.Add((Get-TimeSample -File $path -UseCompact $compact))
    }
    $median = Get-Median -Data $times.ToArray()
    $results[$name] = $median
    Write-Host ('  {0,-17} median {1,8:N1} ms  samples: {2}' -f `
        $name, $median, (($times | ForEach-Object { '{0:0.0}' -f $_ }) -join ', '))
}
$new = [double]$results['2.0 RC']
$old = [double]$results['1.8.3 baseline']
if ($old -gt 0) {
    $change = 100 * ($old - $new) / $old
    Write-Host ('  Change versus v1.8.3: {0:+0.0;-0.0;0.0}% faster (positive means faster)' -f $change)
}
