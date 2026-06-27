# ============================================================================
#  setup-naudio.ps1  -  fetch playback deps into .\lib  (direct nupkg download)
# ----------------------------------------------------------------------------
#  Downloads NAudio (Core/WinMM/Wasapi) + TagLibSharp straight from the NuGet
#  v3 flat-container as .nupkg (= zip), extracts the netstandard2.0 / net4x
#  assemblies into lib\, and Unblock-File's them. No PackageManagement, no
#  source registration, no TLS surprises. Re-run any time; it's idempotent.
# ============================================================================
[CmdletBinding()]
param(
    [string]$NAudioVersion = '2.2.1',
    [string]$TagLibVersion = '2.3.0'
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$lib     = Join-Path $PSScriptRoot 'lib'
$staging = Join-Path $env:TEMP ("cadence-deps-{0}" -f ([guid]::NewGuid().ToString('N')))
New-Item -ItemType Directory -Force -Path $lib, $staging | Out-Null
try { Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue } catch {}

Write-Host "Cadence dependency setup" -ForegroundColor Cyan

# id ; version ; required (NAudio.* needed; TagLibSharp optional for tags+art)
$packages = @(
    @{ Id = 'NAudio.Core';   Ver = $NAudioVersion; Need = $true  }
    @{ Id = 'NAudio.WinMM';  Ver = $NAudioVersion; Need = $true  }   # WaveOutEvent
    @{ Id = 'NAudio.Wasapi'; Ver = $NAudioVersion; Need = $true  }   # MediaFoundationReader
    @{ Id = 'TagLibSharp';   Ver = $TagLibVersion; Need = $false }
)

# Frameworks loadable by Windows PowerShell 5.1 (.NET 4.x). netstandard2.0
# loads on both 5.1 and pwsh; net6/net8 are deliberately NOT accepted.
$tfmPref = 'netstandard2.0','net472','net462','net461','net45','net40'

function Get-Nupkg {
    param($Id, $Ver, $Dest)
    $low = $Id.ToLower()
    $url = "https://api.nuget.org/v3-flatcontainer/$low/$Ver/$low.$Ver.nupkg"
    $out = Join-Path $Dest "$low.$Ver.nupkg"
    Write-Host "  -> $Id $Ver" -ForegroundColor DarkGray
    Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing
    $out
}

function Expand-Dll {
    param($Nupkg, $WorkDir, $LibOut)
    $ex = Join-Path $WorkDir ([IO.Path]::GetFileNameWithoutExtension($Nupkg))
    [System.IO.Compression.ZipFile]::ExtractToDirectory($Nupkg, $ex)
    $libRoot = Join-Path $ex 'lib'
    if (-not (Test-Path $libRoot)) { return $false }

    $picked = $null
    foreach ($tfm in $tfmPref) {
        $d = Join-Path $libRoot $tfm
        if (Test-Path $d) {
            $dll = Get-ChildItem -Path $d -Filter *.dll -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($dll) { $picked = $dll.FullName; break }
        }
    }
    if (-not $picked) {
        $dll = Get-ChildItem -Path $libRoot -Recurse -Filter *.dll -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($dll) { $picked = $dll.FullName }
    }
    if (-not $picked) { return $false }

    $dest = Join-Path $LibOut ([IO.Path]::GetFileName($picked))
    Copy-Item -LiteralPath $picked -Destination $dest -Force
    Unblock-File -LiteralPath $dest
    Write-Host "     extracted $([IO.Path]::GetFileName($picked))" -ForegroundColor DarkGray
    $true
}

$failed = @()
foreach ($p in $packages) {
    try {
        $nupkg = Get-Nupkg -Id $p.Id -Ver $p.Ver -Dest $staging
        if (-not (Expand-Dll -Nupkg $nupkg -WorkDir $staging -LibOut $lib) -and $p.Need) {
            $failed += $p.Id
        }
    } catch {
        Write-Host "     FAILED: $($_.Exception.Message)" -ForegroundColor Red
        if ($p.Need) { $failed += $p.Id }
    }
}

Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
if ($failed.Count) {
    Write-Host "Missing required: $($failed -join ', ')" -ForegroundColor Red
    Write-Host "Confirm internet access to api.nuget.org, then re-run." -ForegroundColor Yellow
} else {
    Write-Host "Done. lib\ now contains:" -ForegroundColor Green
    Get-ChildItem $lib -Filter *.dll | ForEach-Object { Write-Host "   $($_.Name)" -ForegroundColor Gray }
    Write-Host "(TagLibSharp optional - tags + album art; NAudio.* required.)" -ForegroundColor DarkGray
}
