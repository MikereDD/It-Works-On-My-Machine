# file:    video-player-gui.ps1
# author:  typezero
# version: 0.2.0
# created: 2026-06-24
# updated: 2026-06-25
# desc:    libmpv-backed WinForms video player (VLC-style), HWND embedding.
#          Monochrome Material 3 polish: dark title bar, owner-drawn sliders.

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

# --- Native interop: libmpv + DWM dark title bar + owner-drawn slider --------
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
    private static extern int mpv_set_option(IntPtr ctx, byte[] name, int format, ref long data);
    [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern int mpv_set_option_string(IntPtr ctx, byte[] name, byte[] data);
    [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern int mpv_set_property_string(IntPtr ctx, byte[] name, byte[] data);
    [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern int mpv_get_property(IntPtr ctx, byte[] name, int format, out double data);
    [DllImport("libmpv-2.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern int mpv_command(IntPtr ctx, IntPtr args);

    private const int MPV_FORMAT_INT64  = 4;
    private const int MPV_FORMAT_DOUBLE = 5;
    private static byte[] U(string s) { return Encoding.UTF8.GetBytes(s + "\0"); }

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

# --- Helpers ----------------------------------------------------------------
function Format-Time {
    param([double]$Seconds)
    if ($Seconds -lt 0 -or [double]::IsNaN($Seconds)) { $Seconds = 0 }
    $ts = [TimeSpan]::FromSeconds($Seconds)
    if ($ts.TotalHours -ge 1) {
        return ('{0:0}:{1:00}:{2:00}' -f [int]$ts.TotalHours, $ts.Minutes, $ts.Seconds)
    }
    return ('{0:0}:{1:00}' -f $ts.Minutes, $ts.Seconds)
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

# --- State ------------------------------------------------------------------
$script:ctx      = [IntPtr]::Zero
$script:duration = 0.0
$script:paused   = $false

# --- Form -------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Video Player'
$form.Size = New-Object System.Drawing.Size(960, 600)
$form.MinimumSize = New-Object System.Drawing.Size(560, 360)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $script:colBg
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$form.KeyPreview = $true

# Control bar (added before Fill panel so docking lays out correctly)
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

# Row 2: transport + time (left), volume (right)
$btnOpen = New-Object System.Windows.Forms.Button
$btnOpen.Text = 'Open'
$btnOpen.Location = New-Object System.Drawing.Point(16, 52)
$btnOpen.Size = New-Object System.Drawing.Size(84, 32)
Style-Button $btnOpen
$bar.Controls.Add($btnOpen)

$btnPlay = New-Object System.Windows.Forms.Button
$btnPlay.Text = 'Play'
$btnPlay.Location = New-Object System.Drawing.Point(108, 52)
$btnPlay.Size = New-Object System.Drawing.Size(92, 32)
Style-Button $btnPlay
$bar.Controls.Add($btnPlay)

$lblTime = New-Object System.Windows.Forms.Label
$lblTime.Text = '0:00 / 0:00'
$lblTime.ForeColor = $script:colText
$lblTime.AutoSize = $true
$lblTime.Location = New-Object System.Drawing.Point(214, 60)
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
    [void][Mpv.Native]::SetOptionInt64($c, 'wid', $videoPanel.Handle.ToInt64())
    [void][Mpv.Native]::SetOptionString($c, 'keep-open', 'yes')
    [void][Mpv.Native]::SetOptionString($c, 'idle', 'yes')
    if (-not [Mpv.Native]::Initialize($c)) {
        [System.Windows.Forms.MessageBox]::Show('mpv_initialize failed.', 'mpv') | Out-Null
        return
    }
    $script:ctx = $c
    $timer.Start()
})

# --- Handlers ---------------------------------------------------------------
$btnOpen.Add_Click({
    if ($script:ctx -eq [IntPtr]::Zero) { return }
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = 'Media files|*.mkv;*.mp4;*.avi;*.mov;*.m2ts;*.ts;*.webm;*.flv;*.wmv;*.mpg;*.mpeg|All files|*.*'
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        [void][Mpv.Native]::Command($script:ctx, @('loadfile', $dlg.FileName))
        $script:paused = $false
        $btnPlay.Text = 'Pause'
    }
})

$btnPlay.Add_Click({ Toggle-Pause })

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

$form.Add_KeyDown({
    param($s, $e)
    if ($script:ctx -eq [IntPtr]::Zero) { return }
    switch ($e.KeyCode) {
        'Space' { Toggle-Pause; $e.Handled = $true }
        'Left'  { [void][Mpv.Native]::Command($script:ctx, @('seek', '-5', 'relative')); $e.Handled = $true }
        'Right' { [void][Mpv.Native]::Command($script:ctx, @('seek', '5', 'relative'));  $e.Handled = $true }
        'Up'    { [void][Mpv.Native]::Command($script:ctx, @('add', 'volume', '5'));      $e.Handled = $true }
        'Down'  { [void][Mpv.Native]::Command($script:ctx, @('add', 'volume', '-5'));     $e.Handled = $true }
    }
})

# --- Poll loop --------------------------------------------------------------
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 250
$timer.Add_Tick({
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
})

$form.Add_FormClosing({
    $timer.Stop()
    if ($script:ctx -ne [IntPtr]::Zero) {
        [Mpv.Native]::Destroy($script:ctx)
        $script:ctx = [IntPtr]::Zero
    }
})

[void]$form.ShowDialog()
