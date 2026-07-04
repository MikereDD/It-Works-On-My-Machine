# ============================================================================
#  player.engine.ps1  -  Cadence playback engine (NAudio wrapper)
# ----------------------------------------------------------------------------
#  Function-based engine over a script-scope state bag. NAudio types are
#  referenced ONLY inside function bodies (resolved at call time), never in
#  parameter signatures, so dot-source parse order never bites us.
# ============================================================================

$script:Engine = @{
    Reader      = $null    # NAudio.Wave.MediaFoundationReader
    Output      = $null    # NAudio.Wave.WaveOutEvent
    Path        = $null
    Volume      = 0.80
    TagLib      = $false
    Spectrum    = $null    # SpectrumTap instance (current track)
    HasSpectrum     = $false   # whether the spectrum tap compiled
    OnlineArtLookup = $true    # if no embedded/sidecar art exists, try online metadata lookup
    ArtCacheDir     = Join-Path $PSScriptRoot 'cadence.art-cache'
}

function Write-EngineLog {
    param($Message)
    try {
        if (Get-Command Write-CadenceLog -ErrorAction SilentlyContinue) {
            Write-CadenceLog -Level 'ENGINE' -Message $Message
        } else {
            Add-Content -Path (Join-Path $PSScriptRoot 'cadence-startup.log') `
                -Value ("[{0}] [ENGINE] {1}" -f (Get-Date -Format s), $Message)
        }
    } catch {}
}

function Initialize-AudioBackend {
    # Loads NAudio (required) and TagLibSharp (optional, for tags + art).
    param($LibDir)

    $naudio = Get-ChildItem -Path $LibDir -Filter 'NAudio*.dll' -ErrorAction SilentlyContinue
    if (-not $naudio) {
        throw "NAudio assemblies not found in '$LibDir'. Run setup-naudio.ps1 first."
    }

    # Flatten any mark-of-the-web - your GPO stamps browser/NuGet pulls.
    Get-ChildItem -Path $LibDir -Filter *.dll -ErrorAction SilentlyContinue |
        ForEach-Object { try { Unblock-File -Path $_.FullName -ErrorAction SilentlyContinue } catch {} }

    # Load every NAudio.*.dll so WaveOutEvent + MediaFoundationReader resolve.
    Get-ChildItem -Path $LibDir -Filter 'NAudio*.dll' -ErrorAction SilentlyContinue |
        ForEach-Object { try { Add-Type -Path $_.FullName -ErrorAction Stop } catch {} }

    $taglib = Join-Path $LibDir 'TagLibSharp.dll'
    if (Test-Path $taglib) {
        try { Add-Type -Path $taglib -ErrorAction Stop; $script:Engine.TagLib = $true }
        catch { $script:Engine.TagLib = $false }
    }

    # Compile the spectrum tap. SpectrumTap.Build does the NAudio chain wiring
    # in C# (compiler-validated), so a wrong type name fails the COMPILE (logged)
    # instead of silently throwing at runtime. SampleTap holds the ring buffer +
    # self-contained FFT. If this can't compile, playback still works; the
    # visualizer just stays idle.
    $script:Engine.HasSpectrum = $false
    $core = Join-Path $LibDir 'NAudio.Core.dll'
    if (Test-Path $core) {
        $cs = @'
using System;
using NAudio.Wave;
using NAudio.Wave.SampleProviders;

public class SampleTap : ISampleProvider {
    private readonly ISampleProvider source;
    private readonly int fftSize;
    private readonly float[] ring;
    private int ringPos;

    public SampleTap(ISampleProvider source, int fftSize) {
        this.source = source;
        this.fftSize = fftSize;
        this.ring = new float[fftSize];
    }

    public WaveFormat WaveFormat { get { return source.WaveFormat; } }

    public int Read(float[] buffer, int offset, int count) {
        int read = source.Read(buffer, offset, count);
        int ch = source.WaveFormat.Channels;
        if (ch < 1) ch = 1;
        {   // no lock: torn ring read is harmless for a visualizer
            for (int i = 0; i + ch <= read; i += ch) {
                float mono = 0f;
                for (int c = 0; c < ch; c++) mono += buffer[offset + i + c];
                ring[ringPos] = mono / ch;
                ringPos = (ringPos + 1) % fftSize;
            }
        }
        return read;
    }

    public double[] GetBars(int bands) {
        double[] re = new double[fftSize];
        double[] im = new double[fftSize];
        {   // no lock: torn ring read is harmless for a visualizer
            int p = ringPos;
            for (int i = 0; i < fftSize; i++) {
                double w = 0.5 * (1 - Math.Cos(2 * Math.PI * i / (fftSize - 1))); // Hann
                re[i] = ring[(p + i) % fftSize] * w;
                im[i] = 0;
            }
        }
        FFT(re, im);
        int half = fftSize / 2;
        double[] bars = new double[bands];
        for (int b = 0; b < bands; b++) {
            int lo = (int)Math.Floor(Math.Pow(half, (double)b / bands));
            int hi = (int)Math.Ceiling(Math.Pow(half, (double)(b + 1) / bands));
            if (hi <= lo) hi = lo + 1;
            if (hi > half) hi = half;
            double sum = 0; int n = 0;
            for (int k = lo; k < hi; k++) {
                sum += Math.Sqrt(re[k] * re[k] + im[k] * im[k]);
                n++;
            }
            double v = (n > 0) ? sum / n : 0;
            double db = 20 * Math.Log10(v + 1e-6);
            double norm = (db + 58) / 58.0;            // ~ -58dB..0dB -> 0..1
            bars[b] = norm < 0 ? 0 : (norm > 1 ? 1 : norm);
        }
        return bars;
    }

    private static void FFT(double[] re, double[] im) {
        int n = re.Length;
        for (int i = 1, j = 0; i < n; i++) {
            int bit = n >> 1;
            for (; (j & bit) != 0; bit >>= 1) j ^= bit;
            j ^= bit;
            if (i < j) {
                double t = re[i]; re[i] = re[j]; re[j] = t;
                t = im[i]; im[i] = im[j]; im[j] = t;
            }
        }
        for (int len = 2; len <= n; len <<= 1) {
            double ang = -2 * Math.PI / len;
            double wlenRe = Math.Cos(ang), wlenIm = Math.Sin(ang);
            for (int i = 0; i < n; i += len) {
                double wRe = 1, wIm = 0;
                for (int k = 0; k < len / 2; k++) {
                    int a = i + k, b = i + k + len / 2;
                    double vRe = re[b] * wRe - im[b] * wIm;
                    double vIm = re[b] * wIm + im[b] * wRe;
                    re[b] = re[a] - vRe; im[b] = im[a] - vIm;
                    re[a] += vRe; im[a] += vIm;
                    double nWRe = wRe * wlenRe - wIm * wlenIm;
                    wIm = wRe * wlenIm + wIm * wlenRe;
                    wRe = nWRe;
                }
            }
        }
    }
}

public class SpectrumTap {
    private SampleTap tap;

    // Wire the chain in C# where ToSampleProvider / SampleToWaveProvider16 are
    // compiler-checked. Returns the IWaveProvider to hand to WaveOutEvent.Init.
    public IWaveProvider Build(IWaveProvider reader, int fftSize) {
        ISampleProvider sample = reader.ToSampleProvider();
        tap = new SampleTap(sample, fftSize);
        return new SampleToWaveProvider16(tap);
    }

    public double[] GetBars(int bands) {
        return tap == null ? null : tap.GetBars(bands);
    }
}
'@
        # Compiling against netstandard2.0 NAudio DLLs needs an explicit
        # netstandard.dll reference (type-forwards for Object/Monitor/etc),
        # otherwise the .NET 4.x compiler errors CS0012/CS0656.
        $refs = @($core)
        try {
            Add-Type -AssemblyName netstandard -ErrorAction Stop
            $nsAsm = [AppDomain]::CurrentDomain.GetAssemblies() |
                Where-Object { $_.GetName().Name -eq 'netstandard' } | Select-Object -First 1
            if ($nsAsm -and $nsAsm.Location) { $refs += $nsAsm.Location }
        } catch {}
        try {
            Add-Type -TypeDefinition $cs -ReferencedAssemblies $refs -ErrorAction Stop
            $script:Engine.HasSpectrum = $true
            Write-EngineLog "spectrum tap compiled OK"
        } catch {
            $script:Engine.HasSpectrum = $false
            Write-EngineLog ("spectrum compile FAILED: " + $_.Exception.Message)
        }
    }
}

function Open-Track {
    param($Path)
    Close-Track
    $script:Engine.Reader = [NAudio.Wave.MediaFoundationReader]::new($Path)
    $script:Engine.Output = [NAudio.Wave.WaveOutEvent]::new()

    $built = $false
    if ($script:Engine.HasSpectrum) {
        try {
            $tap = [SpectrumTap]::new()
            $wp  = $tap.Build($script:Engine.Reader, 1024)
            $script:Engine.Output.Init($wp)
            $script:Engine.Spectrum = $tap
            $built = $true
        } catch {
            $script:Engine.Spectrum = $null
            Write-EngineLog ("spectrum chain FAILED: " + $_.Exception.Message)
        }
    }
    if (-not $built) {
        $script:Engine.Spectrum = $null
        $script:Engine.Output.Init($script:Engine.Reader)
    }

    $script:Engine.Output.Volume = [float]$script:Engine.Volume
    $script:Engine.Path = $Path
}

function Start-Playback {
    if ($script:Engine.Output) { $script:Engine.Output.Play() }
}

function Suspend-Playback {
    if ($script:Engine.Output) { $script:Engine.Output.Pause() }
}

function Stop-Playback {
    # Rewinds; keeps the reader open so the same track can replay.
    if ($script:Engine.Output) { $script:Engine.Output.Stop() }
    if ($script:Engine.Reader) { $script:Engine.Reader.CurrentTime = [TimeSpan]::Zero }
}

function Close-Track {
    # Null the refs first so any timer tick sees a closed engine, then stop and
    # dispose (each guarded) to ride out NAudio's WaveOutEvent disposal race.
    $out = $script:Engine.Output
    $rdr = $script:Engine.Reader
    $script:Engine.Output   = $null
    $script:Engine.Reader   = $null
    $script:Engine.Spectrum = $null
    if ($out) { try { $out.Stop() } catch {} ; try { $out.Dispose() } catch {} }
    if ($rdr) { try { $rdr.Dispose() } catch {} }
    $script:Engine.Path = $null
}

function Get-SpectrumBars {
    param($Bands)
    if ($script:Engine.Spectrum) {
        try { return $script:Engine.Spectrum.GetBars($Bands) } catch { return $null }
    }
    return $null
}

function Set-Volume {
    param($Level)   # 0.0 .. 1.0
    $Level = [Math]::Max(0.0, [Math]::Min(1.0, [double]$Level))
    $script:Engine.Volume = $Level
    if ($script:Engine.Output) { $script:Engine.Output.Volume = [float]$Level }
}

function Seek-To {
    param($Fraction)   # 0.0 .. 1.0
    if (-not $script:Engine.Reader) { return }
    $total = $script:Engine.Reader.TotalTime.TotalSeconds
    $secs  = [Math]::Max(0.0, [Math]::Min($total, $total * [double]$Fraction))
    $script:Engine.Reader.CurrentTime = [TimeSpan]::FromSeconds($secs)
}

function Get-Position { if ($script:Engine.Reader) { $script:Engine.Reader.CurrentTime } else { [TimeSpan]::Zero } }
function Get-Duration { if ($script:Engine.Reader) { $script:Engine.Reader.TotalTime  } else { [TimeSpan]::Zero } }

function Get-PlaybackState {
    if (-not $script:Engine.Output) { return 'Stopped' }
    try { "$($script:Engine.Output.PlaybackState)" } catch { 'Stopped' }   # Stopped | Playing | Paused
}

function Get-PositionFraction {
    if (-not $script:Engine.Reader) { return 0.0 }
    $t = $script:Engine.Reader.TotalTime.TotalSeconds
    if ($t -le 0) { return 0.0 }
    [Math]::Max(0.0, [Math]::Min(1.0, $script:Engine.Reader.CurrentTime.TotalSeconds / $t))
}

function New-CadenceImageFromBytes {
    # System.Drawing.Image.FromStream keeps a dependency on the source stream.
    # Clone to a Bitmap so the caller can freely dispose the MemoryStream.
    param([byte[]]$Bytes)
    if (-not $Bytes -or $Bytes.Length -le 0) { return $null }
    $ms = $null
    $raw = $null
    try {
        $ms = [IO.MemoryStream]::new($Bytes, $false)
        $raw = [System.Drawing.Image]::FromStream($ms, $true, $true)
        return [System.Drawing.Bitmap]::new($raw)
    } catch {
        Write-EngineLog ("album art byte decode failed: " + $_.Exception.Message)
        return $null
    } finally {
        if ($raw) { try { $raw.Dispose() } catch {} }
        if ($ms)  { try { $ms.Dispose()  } catch {} }
    }
}

function New-CadenceImageFromFile {
    # Load and clone sidecar cover art without locking cover.jpg/folder.jpg.
    param([string]$ImagePath)
    if (-not $ImagePath -or -not (Test-Path -LiteralPath $ImagePath -PathType Leaf)) { return $null }
    $fs = $null
    $raw = $null
    try {
        $fs = [IO.File]::Open($ImagePath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        $raw = [System.Drawing.Image]::FromStream($fs, $true, $true)
        return [System.Drawing.Bitmap]::new($raw)
    } catch {
        Write-EngineLog ("sidecar album art decode failed for '$ImagePath': " + $_.Exception.Message)
        return $null
    } finally {
        if ($raw) { try { $raw.Dispose() } catch {} }
        if ($fs)  { try { $fs.Dispose()  } catch {} }
    }
}

function Get-TagPictureBytes {
    # TagLibSharp exposes picture bytes differently between versions/hosts.
    # Try every safe route instead of assuming .Data.Data is always enough.
    param($Picture)
    if (-not $Picture -or -not $Picture.Data) { return $null }

    foreach ($getter in @(
        { param($p) $p.Data.Data },
        { param($p) $p.Data.ToArray() },
        { param($p) $p.Data }
    )) {
        try {
            $raw = & $getter $Picture
            if (-not $raw) { continue }
            if ($raw -is [byte[]]) { return $raw }
            return [byte[]]$raw
        } catch {}
    }
    return $null
}

function Get-AlbumArtSearchDirs {
    # Search beside the track first. Then step up a little because some
    # libraries keep Folder.jpg at the artist folder while tracks live deeper.
    param([string]$AudioPath)
    $dirs = New-Object System.Collections.Generic.List[string]
    try { $dir = [IO.Path]::GetDirectoryName($AudioPath) } catch { $dir = $null }
    $cur = $dir
    for ($i = 0; $i -lt 3 -and $cur; $i++) {
        if ((Test-Path -LiteralPath $cur -PathType Container) -and -not $dirs.Contains($cur)) {
            [void]$dirs.Add($cur)
        }
        try { $parent = [IO.Directory]::GetParent($cur) } catch { $parent = $null }
        if ($parent) { $cur = $parent.FullName } else { $cur = $null }
    }
    return $dirs
}

function Find-SidecarAlbumArt {
    # Common music-library cover conventions. Also handles Windows Media Player
    # hidden AlbumArt_{guid}_Large.jpg files and folders with a single image.
    param(
        [string]$AudioPath,
        [string]$Album = ''
    )

    $exts = @('.jpg', '.jpeg', '.png', '.bmp', '.gif', '.jfif', '.tif', '.tiff')
    $preferredNames = @(
        'cover', 'folder', 'front', 'album', 'albumart', 'artwork',
        'AlbumArt', 'AlbumArtSmall', 'AlbumArtLarge'
    )
    if ($Album) { $preferredNames += $Album }

    foreach ($dir in (Get-AlbumArtSearchDirs -AudioPath $AudioPath)) {
        # Exact-name candidates first.
        foreach ($name in $preferredNames) {
            foreach ($ext in $exts) {
                $candidate = Join-Path $dir ($name + $ext)
                if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
            }
        }

        try {
            $images = @(Get-ChildItem -LiteralPath $dir -File -Force -ErrorAction SilentlyContinue |
                Where-Object { $exts -contains $_.Extension.ToLowerInvariant() })
            if ($images.Count -le 0) { continue }

            # Strong fuzzy candidates: cover/folder/front/artwork/AlbumArt.
            $match = $images |
                Where-Object { $_.BaseName.ToLowerInvariant() -match 'cover|folder|front|albumart|artwork|album' } |
                Sort-Object @{ Expression = { $_.Name.Length } }, Name |
                Select-Object -First 1
            if ($match) { return $match.FullName }

            # If an album folder only has one image, that is almost always the cover.
            if ($images.Count -eq 1) { return $images[0].FullName }
        } catch {}
    }

    return $null
}

function Set-AlbumArtOnlineLookup {
    param([bool]$Enabled)
    $script:Engine.OnlineArtLookup = [bool]$Enabled
}

function Normalize-CadenceText {
    param([string]$Text)
    if (-not $Text) { return '' }
    return (($Text.ToLowerInvariant() -replace '[^a-z0-9]+', ' ').Trim())
}

function Get-CadenceCacheKey {
    param([string]$Text)
    $sha = [System.Security.Cryptography.SHA1]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$Text)
        return (([BitConverter]::ToString($sha.ComputeHash($bytes))) -replace '-', '').ToLowerInvariant()
    } finally {
        if ($sha) { try { $sha.Dispose() } catch {} }
    }
}

function Get-OnlineAlbumArtCachePath {
    param([string]$Artist, [string]$Album)
    $key = Get-CadenceCacheKey (([string]$Artist).Trim() + '|' + ([string]$Album).Trim())
    try {
        if (-not (Test-Path -LiteralPath $script:Engine.ArtCacheDir -PathType Container)) {
            New-Item -ItemType Directory -Path $script:Engine.ArtCacheDir -Force | Out-Null
        }
    } catch {}
    return (Join-Path $script:Engine.ArtCacheDir ($key + '.jpg'))
}

function Find-OnlineAlbumArt {
    # Last-resort cover lookup for tracks that have no embedded art and no
    # local cover.jpg/folder.jpg. Uses Apple's public iTunes Search endpoint
    # because it needs no API key, then caches the image beside Cadence so the
    # same album is not looked up repeatedly.
    param(
        [string]$Artist = '',
        [string]$Album = ''
    )

    if (-not $script:Engine.OnlineArtLookup) { return $null }
    $artist = ([string]$Artist).Trim()
    $album  = ([string]$Album).Trim()
    if (-not $album) { return $null }

    $cachePath = Get-OnlineAlbumArtCachePath -Artist $artist -Album $album
    if (Test-Path -LiteralPath $cachePath -PathType Leaf) {
        return [pscustomobject]@{ Path = $cachePath; Source = 'online cache' }
    }

    $term = if ($artist) { "$artist $album" } else { $album }
    try {
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
        $encoded = [System.Uri]::EscapeDataString($term)
        $uri = "https://itunes.apple.com/search?term=$encoded&entity=album&media=music&limit=12"
        $resp = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
        $results = @($resp.results)
        if (-not $results -or $results.Count -le 0) { return $null }

        $wantArtist = Normalize-CadenceText $artist
        $wantAlbum  = Normalize-CadenceText $album
        $pick = $null

        foreach ($r in $results) {
            $ra = Normalize-CadenceText ([string]$r.artistName)
            $rc = Normalize-CadenceText ([string]$r.collectionName)
            if ($wantArtist -and $ra -eq $wantArtist -and ($rc -eq $wantAlbum -or $rc.Contains($wantAlbum) -or $wantAlbum.Contains($rc))) {
                $pick = $r; break
            }
        }
        if (-not $pick) {
            foreach ($r in $results) {
                $rc = Normalize-CadenceText ([string]$r.collectionName)
                if ($rc -eq $wantAlbum -or $rc.Contains($wantAlbum) -or $wantAlbum.Contains($rc)) {
                    $pick = $r; break
                }
            }
        }
        if (-not $pick) { $pick = $results[0] }

        $artUrl = [string]$pick.artworkUrl100
        if (-not $artUrl) { return $null }
        $artUrl = $artUrl -replace '100x100bb', '600x600bb'
        $artUrl = $artUrl -replace '100x100', '600x600'

        Invoke-WebRequest -Uri $artUrl -OutFile $cachePath -TimeoutSec 8 -UseBasicParsing -ErrorAction Stop | Out-Null
        if (Test-Path -LiteralPath $cachePath -PathType Leaf) {
            return [pscustomobject]@{ Path = $cachePath; Source = 'online iTunes lookup' }
        }
    } catch {
        Write-EngineLog ("online album art lookup failed for '$artist - $album': " + $_.Exception.Message)
    }
    return $null
}

function Get-EmbeddedAlbumArt {
    param($TagFile)
    try {
        if (-not $TagFile -or -not $TagFile.Tag -or -not $TagFile.Tag.Pictures) { return $null }
        $pictures = @($TagFile.Tag.Pictures)
        if ($pictures.Count -le 0) { return $null }

        # Prefer front cover, then try every embedded picture until one decodes.
        $ordered = @()
        $front = $pictures | Where-Object { "$($_.Type)" -eq 'FrontCover' } | Select-Object -First 1
        if ($front) { $ordered += $front }
        foreach ($pic in $pictures) { if (-not $front -or -not [object]::ReferenceEquals($pic, $front)) { $ordered += $pic } }

        $n = 0
        foreach ($pic in $ordered) {
            $n++
            $bytes = Get-TagPictureBytes -Picture $pic
            if (-not $bytes -or $bytes.Length -le 0) { continue }
            $img = New-CadenceImageFromBytes -Bytes $bytes
            if ($img) {
                $ptype = 'embedded'
                try { $ptype = "$($pic.Type)" } catch {}
                return [pscustomobject]@{
                    Image  = $img
                    Source = "embedded $ptype image #$n"
                }
            }
        }
        Write-EngineLog ("embedded album art present but none decoded; picture count=$($pictures.Count)")
    } catch {
        Write-EngineLog ("embedded album art read failed: " + $_.Exception.Message)
    }
    return $null
}

function Get-TrackMetadata {
    # Returns Title/Artist/Album/Duration/Art. Falls back to filename when
    # TagLib# isn't present. Art is a System.Drawing.Image (caller disposes).
    # Album art source order: embedded front cover -> any embedded image ->
    # sidecar cover image near the track (cover.jpg, Folder.jpg, one-image
    # album folder, Windows Media Player AlbumArt_*.jpg, etc.).
    param($Path)
    $meta = [ordered]@{
        Title     = [IO.Path]::GetFileNameWithoutExtension($Path)
        Artist    = ''
        Album     = ''
        Duration  = $null
        Art       = $null
        ArtSource = ''
    }

    $f = $null
    if ($script:Engine.TagLib) {
        try {
            $f = [TagLib.File]::Create($Path)
            if ($f.Tag.Title)          { $meta.Title  = $f.Tag.Title }
            if ($f.Tag.FirstPerformer) { $meta.Artist = $f.Tag.FirstPerformer }
            if ($f.Tag.Album)          { $meta.Album  = $f.Tag.Album }
            $meta.Duration = $f.Properties.Duration

            $embedded = Get-EmbeddedAlbumArt -TagFile $f
            if ($embedded -and $embedded.Image) {
                $meta.Art = $embedded.Image
                $meta.ArtSource = $embedded.Source
            }
        } catch {
            Write-EngineLog ("metadata read failed for '$Path': " + $_.Exception.Message)
        } finally {
            if ($f) { try { $f.Dispose() } catch {} }
        }
    }

    if (-not $meta.Art) {
        $sidecar = Find-SidecarAlbumArt -AudioPath $Path -Album ([string]$meta.Album)
        if ($sidecar) {
            $img = New-CadenceImageFromFile -ImagePath $sidecar
            if ($img) {
                $meta.Art = $img
                $meta.ArtSource = "sidecar " + [IO.Path]::GetFileName($sidecar)
            }
        }
    }

    if (-not $meta.Art) {
        $online = Find-OnlineAlbumArt -Artist ([string]$meta.Artist) -Album ([string]$meta.Album)
        if ($online -and $online.Path) {
            $img = New-CadenceImageFromFile -ImagePath ([string]$online.Path)
            if ($img) {
                $meta.Art = $img
                $meta.ArtSource = [string]$online.Source
            }
        }
    }

    if ($meta.ArtSource) {
        Write-EngineLog ("album art loaded for '$Path': $($meta.ArtSource)")
    } else {
        Write-EngineLog ("album art not found for '$Path' (no decodable embedded art or sidecar image)")
    }

    [pscustomobject]$meta
}
