# ============================================================
#  miNfo Configuration
#  $HOME\PS\profile.d\minforc.ps1
#
#  by MikereDD / Dumb Terminal Team
# ============================================================

# ── OMDB API Key ─────────────────────────────────────────────
$global:OMDB_API_KEY = "ADD_OMDB_API_KEY"

# ── Ensure DT paths exist (fallback if env.ps1 not loaded) ────
if (-not $global:DT_ROOT) {
    if (Test-Path "G:\Rip") {
        $global:DT_ROOT = "G:\Rip"
    } else {
        $global:DT_ROOT = Join-Path $HOME "Rip"
    }
}

if (-not $global:DT_DONE)   { $global:DT_DONE   = Join-Path $DT_ROOT "done" }
if (-not $global:DT_META)   { $global:DT_META   = Join-Path $DT_ROOT "meta" }
if (-not $global:DT_NFO)    { $global:DT_NFO    = Join-Path $DT_ROOT "nfo" }
if (-not $global:DT_POSTER) { $global:DT_POSTER = Join-Path $DT_META "posters" }

# ── miNfoCreate Paths (use shared globals) ────────────────────
$global:MINFO_VIDEODIR  = $global:DT_DONE
$global:MINFO_NFODIR    = $global:DT_NFO
$global:MINFO_POSTERDIR = $global:DT_POSTER

# ── Ensure folders exist ──────────────────────────────────────
$paths = @(
    $global:MINFO_VIDEODIR,
    $global:MINFO_NFODIR,
    $global:MINFO_POSTERDIR
)

foreach ($path in $paths) {
    if (-not (Test-Path $path)) {
        New-Item -ItemType Directory -Force -Path $path | Out-Null
    }
}