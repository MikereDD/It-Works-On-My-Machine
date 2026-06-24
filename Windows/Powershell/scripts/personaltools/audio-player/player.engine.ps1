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
    HasSpectrum = $false   # whether the spectrum tap compiled
}

function Write-EngineLog {
    param($Message)
    try {
        Add-Content -Path (Join-Path $PSScriptRoot 'cadence-startup.log') `
            -Value ("[{0}] {1}" -f (Get-Date -Format s), $Message)
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

function Get-TrackMetadata {
    # Returns Title/Artist/Album/Duration/Art. Falls back to filename when
    # TagLib# isn't present. Art is a System.Drawing.Image (caller disposes).
    param($Path)
    $meta = [ordered]@{
        Title    = [IO.Path]::GetFileNameWithoutExtension($Path)
        Artist   = ''
        Album    = ''
        Duration = $null
        Art      = $null
    }
    if ($script:Engine.TagLib) {
        try {
            $f = [TagLib.File]::Create($Path)
            if ($f.Tag.Title)          { $meta.Title  = $f.Tag.Title }
            if ($f.Tag.FirstPerformer) { $meta.Artist = $f.Tag.FirstPerformer }
            if ($f.Tag.Album)          { $meta.Album  = $f.Tag.Album }
            $meta.Duration = $f.Properties.Duration
            if ($f.Tag.Pictures.Length -gt 0) {
                $bytes = $f.Tag.Pictures[0].Data.Data
                $ms = [IO.MemoryStream]::new([byte[]]$bytes)
                $meta.Art = [System.Drawing.Image]::FromStream($ms)
            }
            $f.Dispose()
        } catch {}
    }
    [pscustomobject]$meta
}
