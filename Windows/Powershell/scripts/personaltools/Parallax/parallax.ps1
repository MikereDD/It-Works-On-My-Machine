# file:    parallax.ps1
# author:  typezero
# version: 0.8.5
# created: 2026-06-24
# updated: 2026-06-26
# desc:    libmpv-backed WinForms video player (VLC-style), HWND embedding.
#          Monochrome Material 3 UI: tracks, fullscreen, resume, disc playback.

# --- STA / Desktop-edition relaunch guard -----------------------------------
$apartment = [System.Threading.Thread]::CurrentThread.GetApartmentState()
if ($PSVersionTable.PSEdition -eq 'Core' -or $apartment -ne 'STA') {
    $psExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    Start-Process -FilePath $psExe -ArgumentList @(
        '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath
    )
    exit
}

# --- Config -----------------------------------------------------------------
$MpvDir = $PSScriptRoot
if ([string]::IsNullOrEmpty($MpvDir)) { $MpvDir = (Get-Location).Path }
$MpvDllName = 'libmpv-2.dll'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- Native interop: libmpv + DWM dark title bar + owner-drawn controls ------
$cs = @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

namespace Mpv {
  public static class Native {
    [DllImport("kernel32", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr LoadLibrary(string path);

    [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr mpv_create();
    [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern int mpv_initialize(IntPtr ctx);
    [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern void mpv_terminate_destroy(IntPtr ctx);
    [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern void mpv_free(IntPtr data);
    [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern int mpv_set_option(IntPtr ctx, byte[] name, int format, ref long data);
    [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern int mpv_set_option_string(IntPtr ctx, byte[] name, byte[] data);
    [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern int mpv_set_property_string(IntPtr ctx, byte[] name, byte[] data);
    [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern int mpv_get_property(IntPtr ctx, byte[] name, int format, out double data);
    [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern int mpv_get_property(IntPtr ctx, byte[] name, int format, out long data);
    [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern int mpv_get_property(IntPtr ctx, byte[] name, int format, out IntPtr data);
    [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern int mpv_command(IntPtr ctx, IntPtr args);

    private const int MPV_FORMAT_STRING = 1;
    private const int MPV_FORMAT_INT64  = 4;
    private const int MPV_FORMAT_DOUBLE = 5;
    private static byte[] U(string s) { return Encoding.UTF8.GetBytes(s + "\0"); }
    private static string ReadUtf8(IntPtr p) {
      int len = 0;
      while (Marshal.ReadByte(p, len) != 0) len++;
      byte[] b = new byte[len];
      Marshal.Copy(p, b, 0, len);
      return Encoding.UTF8.GetString(b);
    }

    public static IntPtr Create() { return mpv_create(); }
    public static bool Initialize(IntPtr ctx) { return mpv_initialize(ctx) >= 0; }
    public static void Destroy(IntPtr ctx) { if (ctx != IntPtr.Zero) mpv_terminate_destroy(ctx); }
    public static bool SetOptionString(IntPtr ctx, string name, string val) {
      return mpv_set_option_string(ctx, U(name), U(val)) >= 0;
    }
    public static bool SetOptionInt64(IntPtr ctx, string name, long val) {
      long v = val; return mpv_set_option(ctx, U(name), MPV_FORMAT_INT64, ref v) >= 0;
    }
    public static bool SetPropertyString(IntPtr ctx, string name, string val) {
      return mpv_set_property_string(ctx, U(name), U(val)) >= 0;
    }
    public static bool TryGetDouble(IntPtr ctx, string name, out double val) {
      double d = 0; int rc = mpv_get_property(ctx, U(name), MPV_FORMAT_DOUBLE, out d);
      val = d; return rc >= 0;
    }
    public static bool TryGetInt(IntPtr ctx, string name, out long val) {
      long d = 0; int rc = mpv_get_property(ctx, U(name), MPV_FORMAT_INT64, out d);
      val = d; return rc >= 0;
    }
    public static string GetString(IntPtr ctx, string name) {
      IntPtr p; int rc = mpv_get_property(ctx, U(name), MPV_FORMAT_STRING, out p);
      if (rc < 0 || p == IntPtr.Zero) return null;
      string s = ReadUtf8(p);
      mpv_free(p);
      return s;
    }
    public static bool Command(IntPtr ctx, string[] args) {
      IntPtr[] ptrs = new IntPtr[args.Length + 1];
      for (int i = 0; i < args.Length; i++) {
        byte[] b = U(args[i]);
        IntPtr p = Marshal.AllocHGlobal(b.Length);
        Marshal.Copy(b, 0, p, b.Length); ptrs[i] = p;
      }
      ptrs[args.Length] = IntPtr.Zero;
      GCHandle gch = GCHandle.Alloc(ptrs, GCHandleType.Pinned);
      int rc;
      try { rc = mpv_command(ctx, gch.AddrOfPinnedObject()); }
      finally {
        gch.Free();
        for (int i = 0; i < args.Length; i++) Marshal.FreeHGlobal(ptrs[i]);
      }
      return rc >= 0;
    }
  }
}

namespace VP {
  public static class Theme {
    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int val, int size);
    public static void DarkTitleBar(IntPtr hwnd) {
      int on = 1;
      if (DwmSetWindowAttribute(hwnd, 20, ref on, 4) != 0) {
        DwmSetWindowAttribute(hwnd, 19, ref on, 4);
      }
    }
  }

  // Focus-independent input: poll key state and the active top-level window
  // (mpv's embedded child window steals focus, so WinForms key events miss).
  public static class Win {
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  }

  // Dark color table for the Tracks popup menu.
  public class DarkMenuColors : ProfessionalColorTable {
    private Color bg = Color.FromArgb(28, 28, 28);
    private Color hi = Color.FromArgb(56, 56, 56);
    private Color bd = Color.FromArgb(70, 70, 70);
    public override Color ToolStripDropDownBackground { get { return bg; } }
    public override Color MenuItemSelected { get { return hi; } }
    public override Color MenuItemSelectedGradientBegin { get { return hi; } }
    public override Color MenuItemSelectedGradientEnd { get { return hi; } }
    public override Color MenuItemBorder { get { return hi; } }
    public override Color MenuBorder { get { return bd; } }
    public override Color ImageMarginGradientBegin { get { return bg; } }
    public override Color ImageMarginGradientMiddle { get { return bg; } }
    public override Color ImageMarginGradientEnd { get { return bg; } }
    public override Color SeparatorDark { get { return bd; } }
    public override Color SeparatorLight { get { return bd; } }
  }

  // Owner-drawn monochrome slider. Replaces the unthemable WinForms TrackBar.
  public class Slider : Control {
    private int _min = 0, _max = 1000, _val = 0;
    private bool _dragging = false;
    public Color TrackColor = Color.FromArgb(60, 60, 60);
    public Color FillColor  = Color.FromArgb(224, 224, 224);
    public Color ThumbColor = Color.FromArgb(240, 240, 240);

    public int Minimum { get { return _min; } set { _min = value; Invalidate(); } }
    public int Maximum { get { return _max; } set { _max = value; Invalidate(); } }
    public int Value {
      get { return _val; }
      set {
        int v = value;
        if (v < _min) v = _min;
        if (v > _max) v = _max;
        if (v != _val) { _val = v; Invalidate(); }
      }
    }
    public bool IsDragging { get { return _dragging; } }
    public event EventHandler UserSeek;
    public event EventHandler UserScrubbing;

    public Slider() {
      SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint
        | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
      Height = 24;
    }

    private int ValueFromX(int x) {
      int pad = 8; int w = Width - pad * 2;
      if (w <= 0) return _min;
      double frac = (double)(x - pad) / (double)w;
      if (frac < 0) frac = 0;
      if (frac > 1) frac = 1;
      return _min + (int)Math.Round(frac * (_max - _min));
    }

    protected override void OnMouseDown(MouseEventArgs e) {
      base.OnMouseDown(e);
      if (e.Button == MouseButtons.Left) {
        _dragging = true; Value = ValueFromX(e.X);
        if (UserScrubbing != null) UserScrubbing(this, EventArgs.Empty);
      }
    }
    protected override void OnMouseMove(MouseEventArgs e) {
      base.OnMouseMove(e);
      if (_dragging) {
        Value = ValueFromX(e.X);
        if (UserScrubbing != null) UserScrubbing(this, EventArgs.Empty);
      }
    }
    protected override void OnMouseUp(MouseEventArgs e) {
      base.OnMouseUp(e);
      if (_dragging && e.Button == MouseButtons.Left) {
        _dragging = false; Value = ValueFromX(e.X);
        if (UserSeek != null) UserSeek(this, EventArgs.Empty);
      }
    }

    protected override void OnPaint(PaintEventArgs e) {
      Graphics g = e.Graphics;
      g.SmoothingMode = SmoothingMode.AntiAlias;
      int pad = 8; int cy = Height / 2; int trackH = 4;
      int x0 = pad; int wTrack = Width - pad * 2;
      if (wTrack < 1) return;
      double frac = 0;
      if (_max > _min) frac = (double)(_val - _min) / (double)(_max - _min);
      int fillW = (int)(frac * wTrack);
      using (SolidBrush tb = new SolidBrush(TrackColor))
        g.FillRectangle(tb, x0, cy - trackH / 2, wTrack, trackH);
      using (SolidBrush fb = new SolidBrush(FillColor))
        g.FillRectangle(fb, x0, cy - trackH / 2, fillW, trackH);
      int r = 6; int tx = x0 + fillW;
      using (SolidBrush thb = new SolidBrush(ThumbColor))
        g.FillEllipse(thb, tx - r, cy - r, r * 2, r * 2);
    }
  }
}
'@
Add-Type -TypeDefinition $cs -Language CSharp -ReferencedAssemblies 'System.Windows.Forms', 'System.Drawing'

# --- Preload native DLL -----------------------------------------------------
if (-not [Environment]::Is64BitProcess) {
    [System.Windows.Forms.MessageBox]::Show(
        'Run under 64-bit PowerShell with a 64-bit libmpv-2.dll.', 'Bitness') | Out-Null
    exit
}
$dllPath = Join-Path $MpvDir $MpvDllName
if (-not (Test-Path -LiteralPath $dllPath)) {
    [System.Windows.Forms.MessageBox]::Show(
        ('libmpv not found at: ' + $dllPath + "`n`nDrop libmpv-2.dll next to this script."),
        'Missing libmpv') | Out-Null
    exit
}
if ([Mpv.Native]::LoadLibrary($dllPath) -eq [IntPtr]::Zero) {
    [System.Windows.Forms.MessageBox]::Show(('LoadLibrary failed: ' + $dllPath), 'Load failed') | Out-Null
    exit
}

# --- Palette (monochrome Material 3) ----------------------------------------
$script:colBg       = [System.Drawing.Color]::FromArgb(18, 18, 18)
$script:colBar      = [System.Drawing.Color]::FromArgb(28, 28, 28)
$script:colBtn      = [System.Drawing.Color]::FromArgb(40, 40, 40)
$script:colBtnHover = [System.Drawing.Color]::FromArgb(56, 56, 56)
$script:colText     = [System.Drawing.Color]::FromArgb(222, 222, 222)
$script:colMuted    = [System.Drawing.Color]::FromArgb(150, 150, 150)
$script:menuColors  = New-Object VP.DarkMenuColors

# --- Helpers ----------------------------------------------------------------
function Format-Time {
    param([double]$Seconds)
    if ($Seconds -lt 0 -or [double]::IsNaN($Seconds)) { $Seconds = 0 }
    $ts = [TimeSpan]::FromSeconds($Seconds)
    if ($ts.TotalHours -ge 1) {
        $h = [int][System.Math]::Floor($ts.TotalHours)
        return ('{0:0}:{1:00}:{2:00}' -f $h, $ts.Minutes, $ts.Seconds)
    }
    return ('{0:0}:{1:00}' -f $ts.Minutes, $ts.Seconds)
}

function Get-TrackLabel {
    param($id, $lang, $title)
    $label = 'Track ' + [string]$id
    if (-not [string]::IsNullOrEmpty($lang))  { $label = $label + ' (' + $lang + ')' }
    if (-not [string]::IsNullOrEmpty($title)) { $label = $label + ' - ' + $title }
    return $label
}

function Style-Button {
    param($btn)
    $btn.FlatStyle = 'Flat'
    $btn.FlatAppearance.BorderSize = 0
    $btn.BackColor = $script:colBtn
    $btn.ForeColor = $script:colText
    $btn.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $btn.Cursor = 'Hand'
    $btn.Add_MouseEnter({ $this.BackColor = $script:colBtnHover })
    $btn.Add_MouseLeave({ $this.BackColor = $script:colBtn })
}

function Toggle-Pause {
    if ($script:ctx -eq [IntPtr]::Zero) { return }
    if ($script:paused) {
        [void][Mpv.Native]::SetPropertyString($script:ctx, 'pause', 'no')
        $script:paused = $false; $btnPlay.Text = 'Pause'
    } else {
        [void][Mpv.Native]::SetPropertyString($script:ctx, 'pause', 'yes')
        $script:paused = $true; $btnPlay.Text = 'Play'
    }
}

# Shared handler for every track item; reads its target from .Tag (no closures).
$script:onSelectTrack = {
    $t = $this.Tag
    if ($null -ne $t -and $script:ctx -ne [IntPtr]::Zero) {
        [void][Mpv.Native]::SetPropertyString($script:ctx, $t.Kind, $t.Id)
    }
}

# Shared handler for disc items; .Tag carries the protocol + device path.
$script:onSelectDisc = {
    $t = $this.Tag
    if ($null -eq $t -or $script:ctx -eq [IntPtr]::Zero) { return }
    $script:discProto = $t.Kind
    if ($null -ne $t.Label) { $script:discLabel = $t.Label } else { $script:discLabel = '' }
    [void][Mpv.Native]::Command($script:ctx, @('write-watch-later-config'))
    if ($t.Kind -eq 'bd') {
        [void][Mpv.Native]::SetPropertyString($script:ctx, 'bluray-device', $t.Device)
        [void][Mpv.Native]::Command($script:ctx, @('loadfile', 'bd://'))
    } else {
        [void][Mpv.Native]::SetPropertyString($script:ctx, 'dvd-device', $t.Device.TrimEnd('\'))
        [void][Mpv.Native]::Command($script:ctx, @('loadfile', 'dvd://'))
    }
    $script:paused = $false
    $btnPlay.Text = 'Pause'
    Set-SubPos
}

# Shared handler for disc titles; .Tag carries the dvd://N or bd://N URL.
$script:onSelectTitle = {
    $t = $this.Tag
    if ($null -eq $t -or $script:ctx -eq [IntPtr]::Zero) { return }
    [void][Mpv.Native]::Command($script:ctx, @('loadfile', $t.Url))
    $script:paused = $false
    $btnPlay.Text = 'Pause'
    Set-SubPos
}

# Shared handler for chapters; .Tag carries the 0-based chapter index.
$script:onSelectChapter = {
    $t = $this.Tag
    if ($null -eq $t -or $script:ctx -eq [IntPtr]::Zero) { return }
    [void][Mpv.Native]::SetPropertyString($script:ctx, 'chapter', $t.Chapter)
}

# Shared handler for absolute-time jumps (equal-split episodes).
$script:onSelectTime = {
    $t = $this.Tag
    if ($null -eq $t -or $script:ctx -eq [IntPtr]::Zero) { return }
    [void][Mpv.Native]::Command($script:ctx, @('seek', $t.Seek, 'absolute'))
}

# Sets how many even episodes to split a title into (0 = auto gap-detect).
$script:onSetEpisodeCount = {
    $t = $this.Tag
    if ($null -ne $t) { $script:episodeCount = [int]$t.Count }
}

function Add-TrackItems {
    param($menu, $wantType, $kind)
    $added = 0
    $anySelected = $false
    $count = 0L
    [void][Mpv.Native]::TryGetInt($script:ctx, 'track-list/count', [ref]$count)
    for ($i = 0; $i -lt $count; $i++) {
        $type = [Mpv.Native]::GetString($script:ctx, ('track-list/' + $i + '/type'))
        if ($type -ne $wantType) { continue }
        $id = 0L
        [void][Mpv.Native]::TryGetInt($script:ctx, ('track-list/' + $i + '/id'), [ref]$id)
        $lang  = [Mpv.Native]::GetString($script:ctx, ('track-list/' + $i + '/lang'))
        $title = [Mpv.Native]::GetString($script:ctx, ('track-list/' + $i + '/title'))
        $sel   = [Mpv.Native]::GetString($script:ctx, ('track-list/' + $i + '/selected'))
        $item = New-Object System.Windows.Forms.ToolStripMenuItem (Get-TrackLabel $id $lang $title)
        $item.ForeColor = $script:colText
        $item.Tag = @{ Kind = $kind; Id = [string]$id }
        if ($sel -eq 'yes') { $item.Checked = $true; $anySelected = $true }
        $item.Add_Click($script:onSelectTrack)
        [void]$menu.Items.Add($item)
        $added++
    }
    return @{ Added = $added; AnySelected = $anySelected }
}

function Build-TracksMenu {
    if ($script:ctx -eq [IntPtr]::Zero) { return $null }
    $count = 0L
    if (-not [Mpv.Native]::TryGetInt($script:ctx, 'track-list/count', [ref]$count)) { return $null }

    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $menu.BackColor = $script:colBar
    $menu.ForeColor = $script:colText
    $menu.Renderer = New-Object System.Windows.Forms.ToolStripProfessionalRenderer ($script:menuColors)

    $np = Get-MediaTitle
    if (-not [string]::IsNullOrEmpty($np)) {
        $npItem = New-Object System.Windows.Forms.ToolStripMenuItem ('Now Playing: ' + $np)
        $npItem.Enabled = $false
        [void]$menu.Items.Add($npItem)
        [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    }

    $hAudio = New-Object System.Windows.Forms.ToolStripMenuItem 'Audio'
    $hAudio.Enabled = $false
    [void]$menu.Items.Add($hAudio)
    $a = Add-TrackItems $menu 'audio' 'aid'
    if ($a.Added -eq 0) {
        $none = New-Object System.Windows.Forms.ToolStripMenuItem '(none)'
        $none.Enabled = $false
        [void]$menu.Items.Add($none)
    }

    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

    $hSub = New-Object System.Windows.Forms.ToolStripMenuItem 'Subtitles'
    $hSub.Enabled = $false
    [void]$menu.Items.Add($hSub)
    $s = Add-TrackItems $menu 'sub' 'sid'
    $off = New-Object System.Windows.Forms.ToolStripMenuItem 'Off'
    $off.ForeColor = $script:colText
    $off.Tag = @{ Kind = 'sid'; Id = 'no' }
    if (-not $s.AnySelected) { $off.Checked = $true }
    $off.Add_Click($script:onSelectTrack)
    [void]$menu.Items.Add($off)

    Add-DiscTitles $menu
    Add-Episodes $menu
    Add-Chapters $menu

    return $menu
}

function Add-DiscTitles {
    param($menu)
    if ($script:discProto -eq '') { return }
    $tcount = 0L
    if (-not [Mpv.Native]::TryGetInt($script:ctx, 'disc-titles', [ref]$tcount)) { return }
    if ($tcount -le 1) { return }

    $cur = -1L
    if (-not [Mpv.Native]::TryGetInt($script:ctx, 'disc-title', [ref]$cur)) { $cur = -1 }

    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    $hdr = New-Object System.Windows.Forms.ToolStripMenuItem 'Titles'
    $hdr.Enabled = $false
    [void]$menu.Items.Add($hdr)

    for ($i = 1; $i -le $tcount; $i++) {
        $item = New-Object System.Windows.Forms.ToolStripMenuItem ('Title ' + [string]$i)
        $item.ForeColor = $script:colText
        $item.Tag = @{ Url = $script:discProto + '://' + [string]$i }
        if ($i -eq $cur) { $item.Checked = $true }
        $item.Add_Click($script:onSelectTitle)
        [void]$menu.Items.Add($item)
    }
}

function Add-Episodes {
    param($menu)
    if ($script:discProto -eq '') { return }

    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    $hdr = New-Object System.Windows.Forms.ToolStripMenuItem 'Episodes'
    $hdr.Enabled = $false
    [void]$menu.Items.Add($hdr)

    $dur = 0.0
    [void][Mpv.Native]::TryGetDouble($script:ctx, 'duration', [ref]$dur)
    $pos = 0.0
    [void][Mpv.Native]::TryGetDouble($script:ctx, 'time-pos', [ref]$pos)

    if ($script:episodeCount -gt 1 -and $dur -gt 0) {
        # Even split into the chosen number of episodes (absolute-time seeks).
        $seg = $dur / $script:episodeCount
        for ($k = 0; $k -lt $script:episodeCount; $k++) {
            $start = $seg * $k
            $end = $seg * ($k + 1)
            $item = New-Object System.Windows.Forms.ToolStripMenuItem ('Episode ' + [string]($k + 1) + '  -  ' + (Format-Time $start))
            $item.ForeColor = $script:colText
            $item.Tag = @{ Seek = [string]$start }
            if ($pos -ge $start -and $pos -lt $end) { $item.Checked = $true }
            $item.Add_Click($script:onSelectTime)
            [void]$menu.Items.Add($item)
        }
    } else {
        # Auto: infer boundaries from large gaps between chapter timestamps.
        $shown = $false
        $ccount = 0L
        if ([Mpv.Native]::TryGetInt($script:ctx, 'chapter-list/count', [ref]$ccount) -and $ccount -gt 1) {
            $times = @()
            for ($i = 0; $i -lt $ccount; $i++) {
                $tt = 0.0
                [void][Mpv.Native]::TryGetDouble($script:ctx, ('chapter-list/' + $i + '/time'), [ref]$tt)
                $times += $tt
            }
            $starts = @(0)
            for ($i = 1; $i -lt $ccount; $i++) {
                if (($times[$i] - $times[$i - 1]) -gt $script:episodeGapSec) { $starts += $i }
            }
            if ($starts.Count -gt 1) {
                $cur = -1L
                if (-not [Mpv.Native]::TryGetInt($script:ctx, 'chapter', [ref]$cur)) { $cur = -1 }
                for ($k = 0; $k -lt $starts.Count; $k++) {
                    $s = $starts[$k]
                    if ($k -lt $starts.Count - 1) { $next = $starts[$k + 1] } else { $next = $ccount }
                    $item = New-Object System.Windows.Forms.ToolStripMenuItem ('Episode ' + [string]($k + 1) + '  -  ' + (Format-Time $times[$s]))
                    $item.ForeColor = $script:colText
                    $item.Tag = @{ Chapter = [string]$s }
                    if ($cur -ge $s -and $cur -lt $next) { $item.Checked = $true }
                    $item.Add_Click($script:onSelectChapter)
                    [void]$menu.Items.Add($item)
                }
                $shown = $true
            }
        }
        if (-not $shown) {
            $hint = New-Object System.Windows.Forms.ToolStripMenuItem 'Auto-detect found none - use Split evenly'
            $hint.Enabled = $false
            [void]$menu.Items.Add($hint)
        }
    }

    # Split-evenly submenu: choose the episode count straight from the UI.
    $split = New-Object System.Windows.Forms.ToolStripMenuItem 'Split evenly'
    $split.ForeColor = $script:colText
    $split.DropDown.BackColor = $script:colBar
    $split.DropDown.ForeColor = $script:colText
    $split.DropDown.Renderer = New-Object System.Windows.Forms.ToolStripProfessionalRenderer ($script:menuColors)
    foreach ($n in @(0, 2, 3, 4, 5, 6, 7, 8, 9, 10)) {
        if ($n -eq 0) { $lbl = 'Auto (detect)' } else { $lbl = [string]$n + ' episodes' }
        $si = New-Object System.Windows.Forms.ToolStripMenuItem $lbl
        $si.ForeColor = $script:colText
        $si.Tag = @{ Count = $n }
        if ($n -eq $script:episodeCount) { $si.Checked = $true }
        $si.Add_Click($script:onSetEpisodeCount)
        [void]$split.DropDownItems.Add($si)
    }
    [void]$menu.Items.Add($split)
}

function Add-Chapters {
    param($menu)
    $ccount = 0L
    if (-not [Mpv.Native]::TryGetInt($script:ctx, 'chapter-list/count', [ref]$ccount)) { return }
    if ($ccount -le 1) { return }

    $cur = -1L
    if (-not [Mpv.Native]::TryGetInt($script:ctx, 'chapter', [ref]$cur)) { $cur = -1 }

    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    $parent = New-Object System.Windows.Forms.ToolStripMenuItem 'Chapters'
    $parent.ForeColor = $script:colText
    $parent.DropDown.BackColor = $script:colBar
    $parent.DropDown.ForeColor = $script:colText
    $parent.DropDown.Renderer = New-Object System.Windows.Forms.ToolStripProfessionalRenderer ($script:menuColors)
    $parent.DropDown.MaximumSize = New-Object System.Drawing.Size(440, 760)

    for ($i = 0; $i -lt $ccount; $i++) {
        $name = [Mpv.Native]::GetString($script:ctx, ('chapter-list/' + $i + '/title'))
        $time = 0.0
        [void][Mpv.Native]::TryGetDouble($script:ctx, ('chapter-list/' + $i + '/time'), [ref]$time)
        if ([string]::IsNullOrEmpty($name)) { $label = 'Chapter ' + [string]($i + 1) } else { $label = $name }
        $label = $label + '  -  ' + (Format-Time $time)
        $item = New-Object System.Windows.Forms.ToolStripMenuItem $label
        $item.ForeColor = $script:colText
        $item.Tag = @{ Chapter = [string]$i }
        if ($i -eq $cur) { $item.Checked = $true }
        $item.Add_Click($script:onSelectChapter)
        [void]$parent.DropDownItems.Add($item)
    }
    [void]$menu.Items.Add($parent)
}

function Get-OpticalDiscs {
    $list = @()
    foreach ($d in [System.IO.DriveInfo]::GetDrives()) {
        if ($d.DriveType -ne [System.IO.DriveType]::CDRom) { continue }
        $info = @{ Letter = $d.Name; Ready = $d.IsReady; Label = ''; Type = 'unknown' }
        if ($d.IsReady) {
            try { $info.Label = $d.VolumeLabel } catch { $info.Label = '' }
            $root = $d.RootDirectory.FullName
            if (Test-Path -LiteralPath (Join-Path $root 'BDMV')) {
                $info.Type = 'bd'
            } elseif (Test-Path -LiteralPath (Join-Path $root 'VIDEO_TS')) {
                $info.Type = 'dvd'
            }
        }
        $list += $info
    }
    return $list
}

function Add-DiscItem {
    param($menu, $text, $kind, $device, $label)
    $item = New-Object System.Windows.Forms.ToolStripMenuItem $text
    $item.ForeColor = $script:colText
    $item.Tag = @{ Kind = $kind; Device = $device; Label = $label }
    $item.Add_Click($script:onSelectDisc)
    [void]$menu.Items.Add($item)
}

function Build-DiscMenu {
    if ($script:ctx -eq [IntPtr]::Zero) { return $null }
    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $menu.BackColor = $script:colBar
    $menu.ForeColor = $script:colText
    $menu.Renderer = New-Object System.Windows.Forms.ToolStripProfessionalRenderer ($script:menuColors)

    $discs = Get-OpticalDiscs
    if ($discs.Count -eq 0) {
        $none = New-Object System.Windows.Forms.ToolStripMenuItem 'No optical drives'
        $none.Enabled = $false
        [void]$menu.Items.Add($none)
        return $menu
    }

    foreach ($disc in $discs) {
        $letter = $disc.Letter.TrimEnd('\')
        if (-not $disc.Ready) {
            $empty = New-Object System.Windows.Forms.ToolStripMenuItem ($letter + '  (no disc)')
            $empty.Enabled = $false
            [void]$menu.Items.Add($empty)
            continue
        }
        $base = $letter
        if (-not [string]::IsNullOrEmpty($disc.Label)) { $base = $letter + '  ' + $disc.Label }

        if ($disc.Type -eq 'bd') {
            Add-DiscItem $menu ('Play Blu-ray  -  ' + $base) 'bd' $disc.Letter $disc.Label
        } elseif ($disc.Type -eq 'dvd') {
            Add-DiscItem $menu ('Play DVD  -  ' + $base) 'dvd' $disc.Letter $disc.Label
        } else {
            Add-DiscItem $menu ('Play Blu-ray  -  ' + $base) 'bd' $disc.Letter $disc.Label
            Add-DiscItem $menu ('Play DVD  -  ' + $base) 'dvd' $disc.Letter $disc.Label
        }
    }
    return $menu
}

# --- Fullscreen + control auto-hide -----------------------------------------
$script:fullscreen     = $false
$script:prevState      = 'Normal'
$script:prevBorder     = 'Sizable'
$script:controlsHidden = $false
$script:idleCount      = 0
$script:lastX          = [System.Windows.Forms.Cursor]::Position.X
$script:lastY          = [System.Windows.Forms.Cursor]::Position.Y
$script:keyPrev        = @{}

function Poll-Key {
    param($vk)
    $down = ([VP.Win]::GetAsyncKeyState($vk) -band 0x8000) -ne 0
    $was = $false
    if ($script:keyPrev.ContainsKey($vk)) { $was = $script:keyPrev[$vk] }
    $script:keyPrev[$vk] = $down
    return ($down -and -not $was)
}

function Show-Controls {
    if ($script:controlsHidden) {
        $bar.Visible = $true
        [System.Windows.Forms.Cursor]::Show()
        $script:controlsHidden = $false
    }
}

function Hide-Controls {
    if (-not $script:controlsHidden) {
        $bar.Visible = $false
        [System.Windows.Forms.Cursor]::Hide()
        $script:controlsHidden = $true
    }
}

function Enter-Fullscreen {
    if ($script:fullscreen) { return }
    $script:prevState  = $form.WindowState
    $script:prevBorder = $form.FormBorderStyle
    $form.WindowState = 'Normal'
    $form.FormBorderStyle = 'None'
    $form.WindowState = 'Maximized'
    $form.TopMost = $true
    $script:fullscreen = $true
    $script:idleCount = 0
    $btnFull.Text = 'Windowed'
    Set-SubPos
}

function Exit-Fullscreen {
    if (-not $script:fullscreen) { return }
    $form.TopMost = $false
    $form.FormBorderStyle = $script:prevBorder
    $form.WindowState = $script:prevState
    $script:fullscreen = $false
    $btnFull.Text = 'Full'
    Set-SubPos
    Show-Controls
}

function Toggle-Fullscreen {
    if ($script:fullscreen) { Exit-Fullscreen } else { Enter-Fullscreen }
}

function Set-SubPos {
    # Bottom edge in fullscreen (bar hidden); lift up in windowed so subtitles
    # clear the control bar. sub-pos: 100 = bottom, lower = higher on screen.
    if ($script:ctx -eq [IntPtr]::Zero) { return }
    if ($script:fullscreen) {
        [void][Mpv.Native]::SetPropertyString($script:ctx, 'sub-pos', '100')
    } else {
        [void][Mpv.Native]::SetPropertyString($script:ctx, 'sub-pos', '90')
    }
}

function Get-MediaTitle {
    # Best-available name for what is playing: mpv media-title (metadata/volume
    # label), then the disc volume label, then the filename. A bare dvd:// /
    # bd:// URL is not useful, so fall through to the disc label in that case.
    if ($script:ctx -eq [IntPtr]::Zero) { return '' }
    $mt = [Mpv.Native]::GetString($script:ctx, 'media-title')
    if (-not [string]::IsNullOrEmpty($mt)) {
        if (-not $mt.StartsWith('dvd://') -and -not $mt.StartsWith('bd://')) { return $mt }
    }
    if (-not [string]::IsNullOrEmpty($script:discLabel)) { return $script:discLabel }
    if (-not [string]::IsNullOrEmpty($mt)) { return $mt }
    $fn = [Mpv.Native]::GetString($script:ctx, 'filename')
    if (-not [string]::IsNullOrEmpty($fn)) { return $fn }
    return ''
}

# --- State ------------------------------------------------------------------
$script:ctx       = [IntPtr]::Zero
$script:duration  = 0.0
$script:paused    = $false
$script:discProto = ''
$script:discLabel      = ''
$script:lastTitleShown = ''
$script:episodeGapSec  = 600
$script:episodeCount   = 0

# --- Form -------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Parallax'
$form.Size = New-Object System.Drawing.Size(960, 600)
$form.MinimumSize = New-Object System.Drawing.Size(720, 360)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $script:colBg
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

$bar = New-Object System.Windows.Forms.Panel
$bar.Dock = 'Bottom'
$bar.Height = 96
$bar.BackColor = $script:colBar
$form.Controls.Add($bar)

$videoPanel = New-Object System.Windows.Forms.Panel
$videoPanel.Dock = 'Fill'
$videoPanel.BackColor = [System.Drawing.Color]::Black
$form.Controls.Add($videoPanel)

# Seek slider (row 1, full width)
$seek = New-Object VP.Slider
$seek.Minimum = 0
$seek.Maximum = 1000
$seek.Location = New-Object System.Drawing.Point(16, 14)
$seek.Size = New-Object System.Drawing.Size(($bar.Width - 32), 24)
$seek.Anchor = 'Top, Left, Right'
$seek.BackColor = $script:colBar
$bar.Controls.Add($seek)

# Row 2: transport + tracks + time (left), volume (right)
$btnOpen = New-Object System.Windows.Forms.Button
$btnOpen.Text = 'Open'
$btnOpen.Location = New-Object System.Drawing.Point(16, 52)
$btnOpen.Size = New-Object System.Drawing.Size(70, 32)
Style-Button $btnOpen
$bar.Controls.Add($btnOpen)

$btnDisc = New-Object System.Windows.Forms.Button
$btnDisc.Text = 'Disc'
$btnDisc.Location = New-Object System.Drawing.Point(94, 52)
$btnDisc.Size = New-Object System.Drawing.Size(70, 32)
Style-Button $btnDisc
$bar.Controls.Add($btnDisc)

$btnPlay = New-Object System.Windows.Forms.Button
$btnPlay.Text = 'Play'
$btnPlay.Location = New-Object System.Drawing.Point(172, 52)
$btnPlay.Size = New-Object System.Drawing.Size(82, 32)
Style-Button $btnPlay
$bar.Controls.Add($btnPlay)

$btnTracks = New-Object System.Windows.Forms.Button
$btnTracks.Text = 'Tracks'
$btnTracks.Location = New-Object System.Drawing.Point(262, 52)
$btnTracks.Size = New-Object System.Drawing.Size(82, 32)
Style-Button $btnTracks
$bar.Controls.Add($btnTracks)

$btnFull = New-Object System.Windows.Forms.Button
$btnFull.Text = 'Full'
$btnFull.Location = New-Object System.Drawing.Point(352, 52)
$btnFull.Size = New-Object System.Drawing.Size(72, 32)
Style-Button $btnFull
$bar.Controls.Add($btnFull)

$lblTime = New-Object System.Windows.Forms.Label
$lblTime.Text = '0:00 / 0:00'
$lblTime.ForeColor = $script:colText
$lblTime.AutoSize = $true
$lblTime.Location = New-Object System.Drawing.Point(436, 60)
$bar.Controls.Add($lblTime)

$vol = New-Object VP.Slider
$vol.Minimum = 0
$vol.Maximum = 130
$vol.Value = 100
$vol.Size = New-Object System.Drawing.Size(130, 24)
$vol.Location = New-Object System.Drawing.Point(($bar.Width - 146), 56)
$vol.Anchor = 'Top, Right'
$vol.BackColor = $script:colBar
$bar.Controls.Add($vol)

$lblVol = New-Object System.Windows.Forms.Label
$lblVol.Text = 'VOL'
$lblVol.ForeColor = $script:colMuted
$lblVol.AutoSize = $true
$lblVol.Location = New-Object System.Drawing.Point(($bar.Width - 182), 60)
$lblVol.Anchor = 'Top, Right'
$bar.Controls.Add($lblVol)

# --- Engine init (handles must exist) ---------------------------------------
$form.Add_Shown({
    [VP.Theme]::DarkTitleBar($form.Handle)
    $c = [Mpv.Native]::Create()
    if ($c -eq [IntPtr]::Zero) {
        [System.Windows.Forms.MessageBox]::Show('mpv_create failed.', 'mpv') | Out-Null
        return
    }
    $watchDir = Join-Path $env:APPDATA 'Parallax\watch_later'
    if (-not (Test-Path -LiteralPath $watchDir)) {
        New-Item -ItemType Directory -Path $watchDir -Force | Out-Null
    }
    [void][Mpv.Native]::SetOptionInt64($c, 'wid', $videoPanel.Handle.ToInt64())
    [void][Mpv.Native]::SetOptionString($c, 'keep-open', 'yes')
    [void][Mpv.Native]::SetOptionString($c, 'idle', 'yes')
    [void][Mpv.Native]::SetOptionString($c, 'input-default-bindings', 'no')
    [void][Mpv.Native]::SetOptionString($c, 'input-vo-keyboard', 'no')
    [void][Mpv.Native]::SetOptionString($c, 'sub-use-margins', 'yes')
    [void][Mpv.Native]::SetOptionString($c, 'sub-ass-force-margins', 'yes')
    [void][Mpv.Native]::SetOptionString($c, 'watch-later-directory', $watchDir)
    [void][Mpv.Native]::SetOptionString($c, 'save-position-on-quit', 'yes')
    [void][Mpv.Native]::SetOptionString($c, 'watch-later-options', 'start')
    if (-not [Mpv.Native]::Initialize($c)) {
        [System.Windows.Forms.MessageBox]::Show('mpv_initialize failed.', 'mpv') | Out-Null
        return
    }
    $script:ctx = $c
    Set-SubPos
    $timer.Start()
})

# --- Handlers ---------------------------------------------------------------
$btnOpen.Add_Click({
    if ($script:ctx -eq [IntPtr]::Zero) { return }
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = 'Media files|*.mkv;*.mp4;*.avi;*.mov;*.m2ts;*.ts;*.webm;*.flv;*.wmv;*.mpg;*.mpeg|All files|*.*'
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        [void][Mpv.Native]::Command($script:ctx, @('write-watch-later-config'))
        [void][Mpv.Native]::Command($script:ctx, @('loadfile', $dlg.FileName))
        $script:paused = $false
        $btnPlay.Text = 'Pause'
        $script:discProto = ''
        $script:discLabel = ''
        Set-SubPos
    }
})

$btnPlay.Add_Click({ Toggle-Pause })

$btnFull.Add_Click({ Toggle-Fullscreen })
$videoPanel.Add_DoubleClick({ Toggle-Fullscreen })

$btnTracks.Add_Click({
    $m = Build-TracksMenu
    if ($null -ne $m) {
        $m.Show($btnTracks, (New-Object System.Drawing.Point(0, -$m.Height)))
    }
})

$btnDisc.Add_Click({
    $m = Build-DiscMenu
    if ($null -ne $m) {
        $m.Show($btnDisc, (New-Object System.Drawing.Point(0, -$m.Height)))
    }
})

$seek.add_UserScrubbing({
    if ($script:duration -gt 0) {
        $preview = ($this.Value / 1000.0) * $script:duration
        $lblTime.Text = (Format-Time $preview) + ' / ' + (Format-Time $script:duration)
    }
})
$seek.add_UserSeek({
    if ($script:ctx -ne [IntPtr]::Zero -and $script:duration -gt 0) {
        $target = ($this.Value / 1000.0) * $script:duration
        [void][Mpv.Native]::Command($script:ctx, @('seek', ([string]$target), 'absolute'))
    }
})

$vol.add_UserScrubbing({
    if ($script:ctx -ne [IntPtr]::Zero) {
        [void][Mpv.Native]::SetPropertyString($script:ctx, 'volume', ([string]$this.Value))
    }
})
$vol.add_UserSeek({
    if ($script:ctx -ne [IntPtr]::Zero) {
        [void][Mpv.Native]::SetPropertyString($script:ctx, 'volume', ([string]$this.Value))
    }
})

# --- Poll loop --------------------------------------------------------------
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 100
$timer.Add_Tick({
    # focus-independent input + activity tracking (mouse move OR key press reveals)
    $active = $false
    if ([VP.Win]::GetForegroundWindow().ToInt64() -eq $form.Handle.ToInt64()) {
        if (Poll-Key 0x46) { Toggle-Fullscreen; $active = $true }                          # F
        if ((Poll-Key 0x1B) -and $script:fullscreen) { Exit-Fullscreen; $active = $true }  # Esc
        if ($script:ctx -ne [IntPtr]::Zero) {
            if (Poll-Key 0x20) { Toggle-Pause; $active = $true }                                                       # Space
            if (Poll-Key 0x25) { [void][Mpv.Native]::Command($script:ctx, @('seek', '-5', 'relative')); $active = $true }  # Left
            if (Poll-Key 0x27) { [void][Mpv.Native]::Command($script:ctx, @('seek', '5', 'relative'));  $active = $true }  # Right
            if (Poll-Key 0x26) { [void][Mpv.Native]::Command($script:ctx, @('add', 'volume', '5'));      $active = $true }  # Up
            if (Poll-Key 0x28) { [void][Mpv.Native]::Command($script:ctx, @('add', 'volume', '-5'));     $active = $true }  # Down
        }
    } else {
        $script:keyPrev.Clear()
    }

    # mouse movement = activity (integer compare; Point -ne is unreliable in PS)
    $mx = [System.Windows.Forms.Cursor]::Position.X
    $my = [System.Windows.Forms.Cursor]::Position.Y
    if ($mx -ne $script:lastX -or $my -ne $script:lastY) {
        $script:lastX = $mx
        $script:lastY = $my
        $active = $true
    }

    # reveal on activity; otherwise count toward auto-hide (fullscreen only)
    if ($active) {
        $script:idleCount = 0
        Show-Controls
    } elseif ($script:fullscreen) {
        $script:idleCount++
        if ($script:idleCount -ge 20) { Hide-Controls }
    }

    if ($script:ctx -eq [IntPtr]::Zero) { return }
    $dur = 0.0
    if ([Mpv.Native]::TryGetDouble($script:ctx, 'duration', [ref]$dur)) { $script:duration = $dur }
    $pos = 0.0
    if (-not [Mpv.Native]::TryGetDouble($script:ctx, 'time-pos', [ref]$pos)) { $pos = 0.0 }
    if (-not $seek.IsDragging -and $script:duration -gt 0) {
        $v = [int](($pos / $script:duration) * 1000)
        if ($v -lt 0) { $v = 0 }
        if ($v -gt 1000) { $v = 1000 }
        $seek.Value = $v
        $lblTime.Text = (Format-Time $pos) + ' / ' + (Format-Time $script:duration)
    }

    $mt = Get-MediaTitle
    if ($mt -ne $script:lastTitleShown) {
        $script:lastTitleShown = $mt
        if ([string]::IsNullOrEmpty($mt)) { $form.Text = 'Parallax' } else { $form.Text = 'Parallax  -  ' + $mt }
    }
})

$form.Add_FormClosing({
    $timer.Stop()
    if ($script:controlsHidden) { [System.Windows.Forms.Cursor]::Show() }
    if ($script:ctx -ne [IntPtr]::Zero) {
        [void][Mpv.Native]::Command($script:ctx, @('write-watch-later-config'))
        [Mpv.Native]::Destroy($script:ctx)
        $script:ctx = [IntPtr]::Zero
    }
})

[void]$form.ShowDialog()
