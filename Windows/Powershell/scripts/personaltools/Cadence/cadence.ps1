# ============================================================================
#  cadence.ps1  -  Cadence  v0.3.0
#  A sleek local audio player (WinForms, owner-drawn, NAudio backend).
#  Part of personaltools/ - mirrors the media-encoder-gui.ps1 layout:
#    main GUI  +  dot-sourced engine/ui modules.
# ============================================================================

# --- STA relaunch guard -----------------------------------------------------
#  WinForms requires an STA thread. PowerShell 7 (pwsh) runs `-File` scripts in
#  an MTA -- only its interactive console is STA -- so the GUI can't host under
#  `pwsh -File`. The reliable STA host that still runs our PowerShell paint
#  handlers is Windows PowerShell (-STA). When we're not already STA, relaunch
#  HIDDEN into powershell.exe -STA so ONLY the player window shows (no stray
#  console). The -Relaunched sentinel prevents any loop; -NoProfile dodges the
#  profile-injected strict mode that otherwise crashes control construction.
param([switch]$Relaunched)

if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    $winps = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path $winps)) { $winps = (Get-Process -Id $PID).Path }
    Start-Process -FilePath $winps -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Relaunched'
    )
    return
}
Set-StrictMode -Off

# --- Never let a startup crash vanish ---------------------------------------
#  Catch-all: log any terminating error to cadence-startup.log AND surface it
#  in a message box, so a child-window crash can't disappear silently.
$script:StartupLog = Join-Path $PSScriptRoot 'cadence-startup.log'
trap {
    $msg = "[{0}] {1}`r`n{2}" -f (Get-Date -Format s), $_.Exception.Message, $_.ScriptStackTrace
    try { Add-Content -Path $script:StartupLog -Value $msg } catch {}
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message, 'Cadence - startup error', 'OK', 'Error') | Out-Null
    } catch {}
    break
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Native dark-mode scrollbars: the tree/list scrollbars are drawn by Windows,
# not our owner-draw code, so they ignore the theme and render light. This
# P/Invoke lets us apply the OS dark scrollbar style (dark track, light thumb).
if (-not ([System.Management.Automation.PSTypeName]'Cadence.Native').Type) {
    try {
        Add-Type -Namespace 'Cadence' -Name 'Native' -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("uxtheme.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern int SetWindowTheme(System.IntPtr hWnd, string pszSubAppName, string pszSubIdList);
'@
    } catch {}
}

[System.Windows.Forms.Application]::EnableVisualStyles()
# Only legal before the first window exists in the process; on a re-run in the
# same session it throws harmlessly, so ignore that case.
try { [System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false) } catch {}

# Contain benign NAudio device-disposal races (WaveOutEvent SafeWaitHandle)
# during track changes: log the stack, keep running, no crash dialog.
try {
    [System.Windows.Forms.Application]::SetUnhandledExceptionMode(
        [System.Windows.Forms.UnhandledExceptionMode]::CatchException)
} catch {}
[System.Windows.Forms.Application]::add_ThreadException({
    param($s, $e)
    try {
        Add-Content -Path (Join-Path $PSScriptRoot 'cadence-startup.log') -Value (
            "[{0}] ThreadException: {1}`r`n{2}" -f (Get-Date -Format s), $e.Exception.Message, $e.Exception.StackTrace)
    } catch {}
})
[System.AppDomain]::CurrentDomain.add_UnhandledException({
    param($s, $e)
    try {
        Add-Content -Path (Join-Path $PSScriptRoot 'cadence-startup.log') -Value (
            "[{0}] UnhandledException: {1}" -f (Get-Date -Format s), $e.ExceptionObject)
    } catch {}
})

$APP_NAME    = 'Cadence'
$APP_VERSION = '0.4.0'
$ROOT        = $PSScriptRoot
$LIB         = Join-Path $ROOT 'lib'
$AUDIO_EXT   = @('.mp3', '.flac', '.m4a', '.aac', '.wav', '.wma', '.ogg', '.opus')
$BROWSE_EXT  = $AUDIO_EXT + @('.m3u', '.m3u8')   # what the tree shows as files

# Strip mark-of-web from our own files. The execution-policy GPO blocks zoned
# (downloaded) files regardless of -ExecutionPolicy Bypass, which makes the
# spectrum tap's C# compile fail -- the visualizer then falls back to idle even
# though audio plays. Doing it here means every launch path works (including
# cadence.cmd / double-click) without a manual Unblock-File first.
try {
    Get-ChildItem -LiteralPath $ROOT -Recurse -Include *.ps1, *.dll -ErrorAction SilentlyContinue |
        Unblock-File -ErrorAction SilentlyContinue
} catch {}

. (Join-Path $ROOT 'player.engine.ps1')
. (Join-Path $ROOT 'player.ui.ps1')

try {
    Initialize-AudioBackend -LibDir $LIB
} catch {
    [System.Windows.Forms.MessageBox]::Show(
        "$($_.Exception.Message)`n`nRun setup-naudio.ps1 to fetch the NAudio DLLs.",
        $APP_NAME, 'OK', 'Error') | Out-Null
    return
}

# --- App state --------------------------------------------------------------
$script:State = @{
    Items   = New-Object System.Collections.Generic.List[string]   # full paths
    Seen    = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    ViewMap = New-Object System.Collections.Generic.List[int]       # list row -> Items index
    Filter  = ''          # active search text (filters the queue)
    Index   = -1
    Active  = $false      # true while a track is meant to be playing/paused
    Shuffle = $false
    Repeat  = $false      # repeat-all
    VisPalette = 'mono'   # visualizer palette: mono | spectrum | indigo
    Art     = $null       # current album art Image (disposed on swap)
}

# ============================================================================
#  Layout
# ============================================================================
$form = [System.Windows.Forms.Form]::new()
$form.Text = "$APP_NAME"
# Window/taskbar/alt-tab icon (optional; ignored if the .ico isn't present).
try {
    $icoPath = Join-Path $PSScriptRoot 'docs\cadence.ico'
    if (Test-Path $icoPath) { $form.Icon = [System.Drawing.Icon]::new($icoPath) }
} catch {}
$form.Size = [System.Drawing.Size]::new(540, 760)
$form.MinimumSize = [System.Drawing.Size]::new(460, 680)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $script:Theme.Bg
$form.ForeColor = $script:Theme.Text
$form.Font = [System.Drawing.Font]::new('Segoe UI', 9.0)
$form.KeyPreview = $true
Set-DoubleBuffered $form
# Subtle background depth: a vertical gradient ground (lighter top, darker base)
$form.Add_Paint({
    param($s, $e)
    $rect = $s.ClientRectangle
    if ($rect.Width -le 0 -or $rect.Height -le 0) { return }
    $top = [System.Drawing.Color]::FromArgb(0x16, 0x17, 0x1E)
    $bot = [System.Drawing.Color]::FromArgb(0x0B, 0x0C, 0x10)
    $lg = [System.Drawing.Drawing2D.LinearGradientBrush]::new($rect, $top, $bot, 90.0)
    $e.Graphics.FillRectangle($lg, $rect); $lg.Dispose()
})

$pad = 18

# Now-playing: art + title/artist/album
$artSize = 120
$art = [System.Windows.Forms.PictureBox]::new()
$art.SetBounds($pad, $pad, $artSize, $artSize)
$art.SizeMode = 'Zoom'
$art.BackColor = $script:Theme.Panel
$form.Controls.Add($art)

$textX = $pad + $artSize + 18
$textW = $form.ClientSize.Width - $textX - $pad

$lblTitle = [System.Windows.Forms.Label]::new()
$lblTitle.SetBounds($textX, $pad + 12, $textW, 36)
$lblTitle.Font = [System.Drawing.Font]::new('Segoe UI Semibold', 18.0)
$lblTitle.ForeColor = $script:Theme.Text
$lblTitle.AutoEllipsis = $true
$lblTitle.Anchor = 'Top,Left,Right'
$lblTitle.Text = 'Nothing playing'
$form.Controls.Add($lblTitle)

$lblArtist = [System.Windows.Forms.Label]::new()
$lblArtist.SetBounds($textX, $pad + 54, $textW, 26)
$lblArtist.Font = [System.Drawing.Font]::new('Segoe UI', 12.0)
$lblArtist.ForeColor = $script:Theme.Muted
$lblArtist.AutoEllipsis = $true
$lblArtist.Anchor = 'Top,Left,Right'
$form.Controls.Add($lblArtist)

$lblAlbum = [System.Windows.Forms.Label]::new()
$lblAlbum.SetBounds($textX, $pad + 82, $textW, 26)
$lblAlbum.Font = [System.Drawing.Font]::new('Segoe UI', 12.0)
$lblAlbum.ForeColor = $script:Theme.Muted
$lblAlbum.AutoEllipsis = $true
$lblAlbum.Anchor = 'Top,Left,Right'
$form.Controls.Add($lblAlbum)

# Visualizer
$visY = $pad + $artSize + 18
$vis = New-Visualizer -Width 0 -Height 60
$vis.SetBounds($pad, $visY, $form.ClientSize.Width - $pad * 2, 60)
$vis.Anchor = 'Top,Left,Right'
$form.Controls.Add($vis)

# Seek slider + time labels
$seekY = $visY + 60 + 16
$seek = New-Slider -Width 0 -Height 18
$seek.SetBounds($pad, $seekY, $form.ClientSize.Width - $pad * 2, 18)
$seek.Anchor = 'Top,Left,Right'
$form.Controls.Add($seek)

$timeY = $seekY + 22
$lblPos = [System.Windows.Forms.Label]::new()
$lblPos.SetBounds($pad, $timeY, 60, 16)
$lblPos.ForeColor = $script:Theme.Muted
$lblPos.Text = '0:00'
$form.Controls.Add($lblPos)

$lblDur = [System.Windows.Forms.Label]::new()
$lblDur.SetBounds($form.ClientSize.Width - $pad - 60, $timeY, 60, 16)
$lblDur.TextAlign = 'TopRight'
$lblDur.ForeColor = $script:Theme.Muted
$lblDur.Anchor = 'Top,Right'
$lblDur.Text = '0:00'
$form.Controls.Add($lblDur)

# Transport row
$rowY = $timeY + 28
$btnPrev  = New-TransportButton -Glyph 'prev'  -Size 44
$btnPlay  = New-TransportButton -Glyph 'play'  -Size 60 -Primary $true
$btnNext  = New-TransportButton -Glyph 'next'  -Size 44
$btnStop  = New-TransportButton -Glyph 'stop'  -Size 44

$cx = [int]($form.ClientSize.Width / 2)
$btnPlay.Location = [System.Drawing.Point]::new($cx - 30, $rowY)
$btnPrev.Location = [System.Drawing.Point]::new($cx - 30 - 12 - 44, $rowY + 8)
$btnNext.Location = [System.Drawing.Point]::new($cx + 30 + 12,       $rowY + 8)
$btnStop.Location = [System.Drawing.Point]::new($cx + 30 + 12 + 44 + 12, $rowY + 8)
foreach ($b in @($btnPrev, $btnPlay, $btnNext, $btnStop)) {
    $b.Anchor = 'Top'; $form.Controls.Add($b)
}

# Shuffle / repeat + volume
$rowY2 = $rowY + 76
$pillShuffle = New-TogglePill -Text 'SHUFFLE'
$pillShuffle.Location = [System.Drawing.Point]::new($pad, $rowY2)
$pillShuffle.Anchor = 'Top,Left'
$form.Controls.Add($pillShuffle)

$pillRepeat = New-TogglePill -Text 'REPEAT'
$pillRepeat.Location = [System.Drawing.Point]::new($pad + 90, $rowY2)
$pillRepeat.Anchor = 'Top,Left'
$form.Controls.Add($pillRepeat)

$vol = New-Slider -Width 120 -Height 18
$vol.Location = [System.Drawing.Point]::new($form.ClientSize.Width - $pad - 120, $rowY2 + 4)
$vol.Anchor = 'Top,Right'
$vol.Fraction = $script:Engine.Volume
$form.Controls.Add($vol)

# --- Library browser (lazy tree) + play queue, split vertically -------------
$splitY = $rowY2 + 40
$splitH = $form.ClientSize.Height - $splitY - 56
$split = [System.Windows.Forms.SplitContainer]::new()
$split.Orientation = 'Horizontal'
$split.SetBounds($pad, $splitY, $form.ClientSize.Width - $pad * 2, $splitH)
$split.Anchor = 'Top,Bottom,Left,Right'
$split.BackColor = $script:Theme.Bg
$split.SplitterWidth = 6
$split.Panel1.BackColor = $script:Theme.Well
$split.Panel2.BackColor = $script:Theme.Well
$form.Controls.Add($split)
try { $split.SplitterDistance = [int]($splitH * 0.55) } catch {}

# Folder tree: browse the library without flattening it. Lazy-loaded, so a
# huge tree opens instantly (a folder is only read when you expand it).
$tree = [System.Windows.Forms.TreeView]::new()
$tree.Dock = 'Fill'
$tree.BackColor = $script:Theme.Well
$tree.ForeColor = $script:Theme.Text
$tree.BorderStyle = 'None'
$tree.HideSelection = $false
$tree.DrawMode = 'OwnerDrawText'
$tree.ItemHeight = 22
$split.Panel1.Controls.Add($tree)

$tree.Add_DrawNode({
    param($s, $e)
    $sel = ($e.State -band [System.Windows.Forms.TreeNodeStates]::Selected) -ne 0
    $bg  = if ($sel) { $script:Theme.Accent } else { $script:Theme.Well }
    $fg  = if ($sel) { [System.Drawing.Color]::White } else { $script:Theme.Text }
    $bb  = [System.Drawing.SolidBrush]::new($bg)
    $e.Graphics.FillRectangle($bb, $e.Bounds); $bb.Dispose()
    $tb  = [System.Drawing.SolidBrush]::new($fg)
    $e.Graphics.DrawString($e.Node.Text, $tree.Font, $tb, $e.Bounds.X + 1, $e.Bounds.Y + 2)
    $tb.Dispose()
})

# Right-click a folder -> bulk-add it (recursively) to the queue
$treeMenu = [System.Windows.Forms.ContextMenuStrip]::new()
$treeMenu.BackColor = $script:Theme.Panel
$treeMenu.ForeColor = $script:Theme.Text
$miAddFolder = $treeMenu.Items.Add('Add folder to queue (recursive)')
$tree.ContextMenuStrip = $treeMenu

# Play queue
$list = [System.Windows.Forms.ListBox]::new()
$list.Dock = 'Fill'
$list.BackColor = $script:Theme.Well
$list.ForeColor = $script:Theme.Text
$list.BorderStyle = 'None'
$list.IntegralHeight = $false
$list.DrawMode = 'OwnerDrawFixed'
$list.ItemHeight = 30
$split.Panel2.Controls.Add($list)

# Search box: live-filters the queue (docks above the list; added after the
# Fill list so it claims the top edge).
$search = [System.Windows.Forms.TextBox]::new()
$search.Dock        = 'Top'
$search.BorderStyle = 'FixedSingle'
$search.BackColor   = $script:Theme.SurfaceHi
$search.ForeColor   = $script:Theme.Text
$search.Font        = [System.Drawing.Font]::new('Segoe UI', 10)
try { $search.PlaceholderText = 'Search queue...' } catch {}
$search.Add_TextChanged({ $script:State.Filter = $search.Text; Sync-List })
$search.Add_KeyDown({
    param($s, $e)
    if ($e.KeyCode -eq 'Escape') { $search.Text = ''; $e.Handled = $true; $e.SuppressKeyPress = $true }
})
$split.Panel2.Controls.Add($search)
$script:SearchBox = $search

$list.Add_DrawItem({
    param($s, $e)
    $e.DrawBackground()
    if ($e.Index -lt 0) { return }
    $sel = ($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0
    $bg  = if ($sel) { $script:Theme.Accent } else { $script:Theme.Well }
    $fg  = if ($sel) { [System.Drawing.Color]::White } else { $script:Theme.Text }
    $bb  = [System.Drawing.SolidBrush]::new($bg)
    $e.Graphics.FillRectangle($bb, $e.Bounds); $bb.Dispose()
    $sf = [System.Drawing.StringFormat]::new()
    $sf.LineAlignment = 'Center'; $sf.Trimming = 'EllipsisCharacter'
    $sf.FormatFlags = [System.Drawing.StringFormatFlags]::NoWrap
    $tb = [System.Drawing.SolidBrush]::new($fg)
    $r  = [System.Drawing.RectangleF]::new($e.Bounds.X + 12, $e.Bounds.Y, $e.Bounds.Width - 24, $e.Bounds.Height)
    $e.Graphics.DrawString([string]$s.Items[$e.Index], $s.Font, $tb, $r, $sf)
    $tb.Dispose(); $sf.Dispose()
})

# Bottom buttons (M3 pills via New-FlatButton in the UI module)
$btnAddFiles = New-FlatButton 'Add Files'   100
$btnSetLib   = New-FlatButton 'Library'     100
$btnClear    = New-FlatButton 'Clear'       70
$byY = $form.ClientSize.Height - 44
$btnAddFiles.Location = [System.Drawing.Point]::new($pad, $byY)
$btnSetLib.Location   = [System.Drawing.Point]::new($pad + 108, $byY)
$btnClear.Location    = [System.Drawing.Point]::new($form.ClientSize.Width - $pad - 70, $byY)
$btnAddFiles.Anchor = 'Bottom,Left'
$btnSetLib.Anchor   = 'Bottom,Left'
$btnClear.Anchor    = 'Bottom,Right'
$form.Controls.AddRange(@($btnAddFiles, $btnSetLib, $btnClear))

# Library button menu: add / remove / clear saved roots (persisted to config)
$libMenu = [System.Windows.Forms.ContextMenuStrip]::new()
$libMenu.BackColor = $script:Theme.Panel
$libMenu.ForeColor = $script:Theme.Text
$miAddRoot    = $libMenu.Items.Add('Add root folder...')
$miRemoveRoot = $libMenu.Items.Add('Remove selected root')
$miClearRoots = $libMenu.Items.Add('Clear all roots')

# ============================================================================
#  Behaviour
# ============================================================================
function Sync-PlayGlyph {
    $st = Get-PlaybackState
    $btnPlay.Glyph = if ($st -eq 'Playing') { 'pause' } else { 'play' }
    $btnPlay.Invalidate()
}

function Update-NowPlaying {
    param($Path)
    $meta = Get-TrackMetadata -Path $Path
    $lblTitle.Text  = $meta.Title
    $lblArtist.Text = $meta.Artist
    $lblAlbum.Text  = $meta.Album
    if ($script:State.Art) { try { $script:State.Art.Dispose() } catch {} ; $script:State.Art = $null }
    if ($meta.Art) { $script:State.Art = $meta.Art; $art.Image = $meta.Art }
    else { $art.Image = $null }
    $form.Text = "$APP_NAME  -  $($meta.Title)"
}

function Invoke-PlayIndex {
    param($i)
    if ($i -lt 0 -or $i -ge $script:State.Items.Count) { return }
    $script:State.Index = $i
    # Highlight in the (possibly filtered) list via the view->model map.
    $vr = $script:State.ViewMap.IndexOf($i)
    if ($list.SelectedIndex -ne $vr) { $list.SelectedIndex = $vr }
    $path = $script:State.Items[$i]
    try {
        Open-Track -Path $path
        Start-Playback
        $script:State.Active = $true
        Update-NowPlaying -Path $path
        $lblDur.Text = Format-Time (Get-Duration)
    } catch {
        $lblTitle.Text = "Can't play: $([IO.Path]::GetFileName($path))"
    }
    Sync-PlayGlyph
}

function Invoke-Next {
    $n = $script:State.Items.Count
    if ($n -eq 0) { return }
    if ($script:State.Shuffle -and $n -gt 1) {
        do { $j = Get-Random -Maximum $n } while ($j -eq $script:State.Index)
        Invoke-PlayIndex $j
    } elseif ($script:State.Index -lt $n - 1) {
        Invoke-PlayIndex ($script:State.Index + 1)
    } elseif ($script:State.Repeat) {
        Invoke-PlayIndex 0
    } else {
        $script:State.Active = $false; Sync-PlayGlyph
    }
}

function Invoke-Prev {
    if ($script:State.Items.Count -eq 0) { return }
    # Restart current if >3s in, else go back one.
    if ((Get-Position).TotalSeconds -gt 3) { Seek-To 0.0; return }
    if ($script:State.Index -gt 0) { Invoke-PlayIndex ($script:State.Index - 1) }
    else { Invoke-PlayIndex 0 }
}

function Toggle-PlayPause {
    if ($script:State.Items.Count -eq 0) { return }
    $st = Get-PlaybackState
    if ($st -eq 'Playing') {
        Suspend-Playback
    } elseif ($st -eq 'Paused') {
        Start-Playback; $script:State.Active = $true
    } else {
        $i = if ($script:State.Index -ge 0) { $script:State.Index } else { 0 }
        Invoke-PlayIndex $i
    }
    Sync-PlayGlyph
}

function Import-M3U {
    # Parses .m3u/.m3u8 into existing local audio paths. Relative entries
    # resolve against the playlist's folder; file:// URIs are converted;
    # http/ftp/rtsp/mms streams are skipped (local player). .m3u8 = UTF-8.
    param($Path)
    $base = Split-Path -Parent $Path
    $out  = New-Object System.Collections.Generic.List[string]
    $enc  = if ($Path -match '\.m3u8$') { 'UTF8' } else { 'Default' }
    try { $lines = Get-Content -LiteralPath $Path -Encoding $enc -ErrorAction Stop }
    catch { return ,$out }
    foreach ($raw in $lines) {
        $line = "$raw".TrimStart([char]0xFEFF).Trim().Trim('"')   # BOM + quotes
        if ($line -eq '' -or $line.StartsWith('#')) { continue }      # blank / #EXTINF
        if ($line -match '^(https?|ftp|rtsp|mms)://') { continue }    # remote streams
        if ($line -match '^file:') { try { $line = ([Uri]$line).LocalPath } catch {} }
        $full = if ([IO.Path]::IsPathRooted($line)) { $line } else { Join-Path $base $line }
        try { $full = [IO.Path]::GetFullPath($full) } catch {}
        if (Test-Path -LiteralPath $full -PathType Leaf) { $out.Add($full) }
    }
    return ,$out
}

# Does a display name pass the active search filter?
function Test-FilterMatch {
    param($Name)
    $f = $script:State.Filter
    if ([string]::IsNullOrEmpty($f)) { return $true }
    return ($Name.IndexOf($f, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
}

# Rebuild the visible queue from Items applying the current filter, and rebuild
# the view->model map. Used when the search text changes.
function Sync-List {
    $list.BeginUpdate()
    try {
        $list.Items.Clear()
        $script:State.ViewMap.Clear()
        for ($i = 0; $i -lt $script:State.Items.Count; $i++) {
            $name = [IO.Path]::GetFileNameWithoutExtension($script:State.Items[$i])
            if (Test-FilterMatch $name) {
                $list.Items.Add($name) | Out-Null
                $script:State.ViewMap.Add($i)
            }
        }
    } finally { $list.EndUpdate() }
    if ($script:State.Index -ge 0) {
        $vr = $script:State.ViewMap.IndexOf($script:State.Index)
        if ($vr -ge 0) { $list.SelectedIndex = $vr }
    }
}

function Add-One {
    param($p)
    if ($AUDIO_EXT -notcontains [IO.Path]::GetExtension($p).ToLower()) { return }
    if (-not $script:State.Seen.Add($p)) { return }   # already in list
    $idx = $script:State.Items.Count
    $script:State.Items.Add($p)
    $name = [IO.Path]::GetFileNameWithoutExtension($p)
    if (Test-FilterMatch $name) {                     # respect an active search
        $list.Items.Add($name) | Out-Null
        $script:State.ViewMap.Add($idx)
    }
}

function Add-Paths {
    param($Paths)
    $list.BeginUpdate()
    try {
        foreach ($p in $Paths) {
            $ext = [IO.Path]::GetExtension($p).ToLower()
            if ($ext -eq '.m3u' -or $ext -eq '.m3u8') {
                foreach ($t in (Import-M3U $p)) { Add-One $t }   # expand playlist
            } else {
                Add-One $p
            }
        }
    } finally {
        $list.EndUpdate()
    }
}

# --- Library tree (lazy) ----------------------------------------------------
function Get-NaturalKey {
    # Pads runs of digits so lexicographic sort == numeric sort (2 before 10).
    param($s)
    [regex]::Replace([string]$s, '\d+', { param($m) $m.Value.PadLeft(12, '0') })
}

function New-DummyNode {
    $d = [System.Windows.Forms.TreeNode]::new('  ...')
    $d.Tag = @{ Kind = 'dummy' }
    $d
}

function Add-FolderNode {
    param($Parent, $Path, $Label)
    $node = [System.Windows.Forms.TreeNode]::new($Label)
    $node.Tag = @{ Path = $Path; Kind = 'dir'; Loaded = $false }
    $node.Nodes.Add((New-DummyNode)) | Out-Null   # placeholder = shows expander
    if ($Parent) { $Parent.Nodes.Add($node) | Out-Null } else { $tree.Nodes.Add($node) | Out-Null }
    $node
}

function Expand-Node {
    param($Node)
    if (-not $Node.Tag -or $Node.Tag.Kind -ne 'dir' -or $Node.Tag.Loaded) { return }
    $Node.Tag.Loaded = $true
    $tree.BeginUpdate()
    try {
        $Node.Nodes.Clear()   # drop the dummy
        $p = $Node.Tag.Path
        try {
            Get-ChildItem -LiteralPath $p -Directory -ErrorAction SilentlyContinue |
                Sort-Object { Get-NaturalKey $_.Name } |
                ForEach-Object { [void](Add-FolderNode -Parent $Node -Path $_.FullName -Label $_.Name) }
        } catch {}
        try {
            Get-ChildItem -LiteralPath $p -File -ErrorAction SilentlyContinue |
                Where-Object { $BROWSE_EXT -contains $_.Extension.ToLower() } |
                Sort-Object { Get-NaturalKey $_.Name } |
                ForEach-Object {
                    $ext = $_.Extension.ToLower()
                    $label = if ($ext -eq '.m3u' -or $ext -eq '.m3u8') { "[M3U] " + $_.Name } else { $_.Name }
                    $fn = [System.Windows.Forms.TreeNode]::new($label)
                    $fn.Tag = @{ Path = $_.FullName; Kind = 'file' }
                    $Node.Nodes.Add($fn) | Out-Null
                }
        } catch {}
    } finally { $tree.EndUpdate() }
}

$script:ConfigPath = Join-Path $ROOT 'cadence.config.json'
$script:Config     = @{ roots = @(); volume = 0.8; shuffle = $false; repeat = $false; palette = 'mono' }

function Load-Config {
    if (-not (Test-Path -LiteralPath $script:ConfigPath)) { return }
    try {
        $json = Get-Content -LiteralPath $script:ConfigPath -Raw -ErrorAction Stop | ConvertFrom-Json
        $script:Config = @{
            roots   = @($json.roots | Where-Object { $_ })
            volume  = if ($null -ne $json.volume) { [double]$json.volume } else { 0.8 }
            shuffle = [bool]$json.shuffle
            repeat  = [bool]$json.repeat
            palette = if ($json.palette) { [string]$json.palette } else { 'mono' }
        }
    } catch { $script:Config = @{ roots = @(); volume = 0.8; shuffle = $false; repeat = $false; palette = 'mono' } }
}

function Save-Config {
    try {
        [pscustomobject]@{
            roots   = @($script:Config.roots)
            volume  = [double]$script:Engine.Volume
            shuffle = [bool]$script:State.Shuffle
            repeat  = [bool]$script:State.Repeat
            palette = [string]$script:State.VisPalette
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:ConfigPath -Encoding UTF8
    } catch {}
}

function Build-Tree {
    # Top-level nodes = saved roots (local/external/cloud). None saved -> drives.
    $tree.BeginUpdate()
    try {
        $tree.Nodes.Clear()
        $roots = @($script:Config.roots | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
        if ($roots.Count -gt 0) {
            foreach ($r in $roots) { [void](Add-FolderNode -Parent $null -Path $r -Label $r) }
        } else {
            foreach ($d in [System.IO.DriveInfo]::GetDrives()) {
                try {
                    if ($d.IsReady) {
                        [void](Add-FolderNode -Parent $null -Path $d.RootDirectory.FullName -Label $d.Name)
                    }
                } catch {}
            }
        }
    } finally { $tree.EndUpdate() }
    if ($tree.Nodes.Count -eq 1) { $tree.Nodes[0].Expand() }
}

function Test-RootSaved {
    param($Path)
    foreach ($r in $script:Config.roots) {
        if ([string]::Equals($r, $Path, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    $false
}

function Add-LibraryRoot {
    param($Path)
    if (-not $Path) { return }
    if (-not (Test-RootSaved $Path)) {
        $script:Config.roots = @($script:Config.roots) + $Path
        Save-Config
    }
    Build-Tree
    foreach ($n in $tree.Nodes) {
        if ($n.Tag -and [string]::Equals("$($n.Tag.Path)", $Path, [System.StringComparison]::OrdinalIgnoreCase)) {
            $tree.SelectedNode = $n; $n.Expand(); break
        }
    }
}

function Remove-LibraryRoot {
    param($Path)
    if (-not $Path) { return }
    $script:Config.roots = @($script:Config.roots | Where-Object {
        -not [string]::Equals($_, $Path, [System.StringComparison]::OrdinalIgnoreCase) })
    Save-Config
    Build-Tree
}

function Clear-LibraryRoots {
    $script:Config.roots = @()
    Save-Config
    Build-Tree
}

function Get-PathIndex {
    param($p)
    for ($i = 0; $i -lt $script:State.Items.Count; $i++) {
        if ([string]::Equals($script:State.Items[$i], $p, [System.StringComparison]::OrdinalIgnoreCase)) { return $i }
    }
    -1
}

function Add-FolderToQueue {
    param($FolderPath)
    if (-not $FolderPath) { return }
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $form.Text = "$APP_NAME  -  scanning..."
    [System.Windows.Forms.Application]::DoEvents()
    try {
        $before = $script:State.Items.Count
        $files = Get-ChildItem -LiteralPath $FolderPath -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $AUDIO_EXT -contains $_.Extension.ToLower() } |
            Sort-Object { Get-NaturalKey $_.FullName } | Select-Object -ExpandProperty FullName
        Add-Paths $files
        $n = $script:State.Items.Count - $before
        $form.Text = "$APP_NAME  -  added $n track(s)"
    } finally {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
}

# Drag-and-drop: accept dropped files/folders/playlists onto the window.
function Add-Dropped {
    param($Paths)
    if (-not $Paths) { return }
    $loose = New-Object System.Collections.Generic.List[string]
    foreach ($p in $Paths) {
        try {
            if (Test-Path -LiteralPath $p -PathType Container) { Add-FolderToQueue $p }
            else { $loose.Add($p) }   # files + .m3u handled by Add-Paths
        } catch {}
    }
    if ($loose.Count -gt 0) { Add-Paths $loose }
}

# Export the current queue as an M3U playlist.
function Export-QueueM3U {
    if ($script:State.Items.Count -eq 0) {
        $form.Text = "$APP_NAME  -  nothing to export"
        return
    }
    $dlg = [System.Windows.Forms.SaveFileDialog]::new()
    $dlg.Title    = 'Export queue'
    $dlg.Filter   = 'M3U8 playlist (*.m3u8)|*.m3u8|M3U playlist (*.m3u)|*.m3u'
    $dlg.FileName = 'cadence-queue.m3u8'
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            $sb = [System.Text.StringBuilder]::new()
            [void]$sb.AppendLine('#EXTM3U')
            foreach ($p in $script:State.Items) { [void]$sb.AppendLine($p) }
            [System.IO.File]::WriteAllText($dlg.FileName, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))
            $form.Text = "$APP_NAME  -  exported $($script:State.Items.Count) track(s)"
        } catch {
            $form.Text = "$APP_NAME  -  export failed"
        }
    }
}

# Switch the visualizer palette and persist it.
function Set-VisPalette {
    param($Name)
    $script:State.VisPalette = $Name
    $script:Config.palette   = $Name
    Save-Config
    if ($script:miPalMono)     { $script:miPalMono.Checked     = ($Name -eq 'mono') }
    if ($script:miPalSpectrum) { $script:miPalSpectrum.Checked = ($Name -eq 'spectrum') }
    if ($script:miPalIndigo)   { $script:miPalIndigo.Checked   = ($Name -eq 'indigo') }
    $vis.Invalidate()
}

# --- Wiring -----------------------------------------------------------------
$seek.OnSeek = { param($f) Seek-To $f }.GetNewClosure()
$vol.OnSeek  = { param($f) Set-Volume $f }.GetNewClosure()

$btnPlay.Add_Click({ Toggle-PlayPause })
$btnNext.Add_Click({ Invoke-Next })
$btnPrev.Add_Click({ Invoke-Prev })
$btnStop.Add_Click({ Stop-Playback; $script:State.Active = $false; Sync-PlayGlyph })

$pillShuffle.Add_Click({
    $script:State.Shuffle = -not $script:State.Shuffle
    $pillShuffle.Active = $script:State.Shuffle; Update-PillVisual $pillShuffle
    Save-Config
})
$pillRepeat.Add_Click({
    $script:State.Repeat = -not $script:State.Repeat
    $pillRepeat.Active = $script:State.Repeat; Update-PillVisual $pillRepeat
    Save-Config
})

# Drag-and-drop files / folders / playlists onto the window.
$form.AllowDrop = $true
$form.Add_DragEnter({
    param($s, $e)
    if ($e.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) {
        $e.Effect = [System.Windows.Forms.DragDropEffects]::Copy
    }
})
$form.Add_DragDrop({
    param($s, $e)
    try { Add-Dropped ($e.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop)) } catch {}
})

# Queue context menu: export as M3U.
$listMenu = [System.Windows.Forms.ContextMenuStrip]::new()
$listMenu.BackColor = $script:Theme.Panel
$listMenu.ForeColor = $script:Theme.Text
$miExport = $listMenu.Items.Add('Export queue as M3U...')
$miExport.Add_Click({ Export-QueueM3U })
$list.ContextMenuStrip = $listMenu

# Visualizer context menu: palette picker.
$visMenu = [System.Windows.Forms.ContextMenuStrip]::new()
$visMenu.BackColor = $script:Theme.Panel
$visMenu.ForeColor = $script:Theme.Text
$script:miPalMono     = $visMenu.Items.Add('Monochrome')
$script:miPalSpectrum = $visMenu.Items.Add('Full spectrum')
$script:miPalIndigo   = $visMenu.Items.Add('Indigo')
$script:miPalMono.Add_Click({ Set-VisPalette 'mono' })
$script:miPalSpectrum.Add_Click({ Set-VisPalette 'spectrum' })
$script:miPalIndigo.Add_Click({ Set-VisPalette 'indigo' })
$vis.ContextMenuStrip = $visMenu

$list.Add_DoubleClick({
    $vr = $list.SelectedIndex
    if ($vr -ge 0 -and $vr -lt $script:State.ViewMap.Count) { Invoke-PlayIndex $script:State.ViewMap[$vr] }
})

$btnAddFiles.Add_Click({
    $dlg = [System.Windows.Forms.OpenFileDialog]::new()
    $dlg.Multiselect = $true
    $dlg.Filter = "Audio + playlists|*.mp3;*.flac;*.m4a;*.aac;*.wav;*.wma;*.ogg;*.opus;*.m3u;*.m3u8|Playlists|*.m3u;*.m3u8|All files|*.*"
    if ($dlg.ShowDialog() -eq 'OK') { Add-Paths $dlg.FileNames }
})

$btnSetLib.Add_Click({
    $libMenu.Show($btnSetLib, [System.Drawing.Point]::new(0, 0),
        [System.Windows.Forms.ToolStripDropDownDirection]::AboveRight)
})

$miAddRoot.Add_Click({
    $dlg = [System.Windows.Forms.FolderBrowserDialog]::new()
    if ($dlg.ShowDialog() -eq 'OK') { Add-LibraryRoot $dlg.SelectedPath }
})

$miRemoveRoot.Add_Click({
    $n = $tree.SelectedNode
    while ($n -and $n.Parent) { $n = $n.Parent }   # climb to the top-level root
    if ($n -and $n.Tag -and $n.Tag.Path -and (Test-RootSaved $n.Tag.Path)) {
        Remove-LibraryRoot $n.Tag.Path
    }
})

$miClearRoots.Add_Click({
    $ans = [System.Windows.Forms.MessageBox]::Show(
        'Remove all saved library roots? The tree falls back to drives.',
        $APP_NAME, 'YesNo', 'Question')
    if ($ans -eq 'Yes') { Clear-LibraryRoots }
})

# Tree: lazy-expand, right-click selects for the context menu, double-click
# plays a file/m3u; folders just expand (bulk-add is the right-click menu).
$tree.Add_BeforeExpand({ param($s, $e) Expand-Node $e.Node })

$tree.Add_NodeMouseClick({
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) { $tree.SelectedNode = $e.Node }
})

$tree.Add_NodeMouseDoubleClick({
    param($s, $e)
    $tag = $e.Node.Tag
    if (-not $tag -or $tag.Kind -ne 'file') { return }
    $ext = [IO.Path]::GetExtension($tag.Path).ToLower()
    if ($ext -eq '.m3u' -or $ext -eq '.m3u8') {
        $tracks = Import-M3U $tag.Path
        if ($tracks.Count -eq 0) {
            $form.Text = "$APP_NAME  -  playlist: no playable tracks found on this PC"
            return
        }
        $before = $script:State.Items.Count
        Add-Paths $tracks
        if ($script:State.Items.Count -gt $before) {
            Invoke-PlayIndex $before          # play first newly-added track
        } else {
            $i = Get-PathIndex $tracks[0]      # all already queued; play from its start
            if ($i -ge 0) { Invoke-PlayIndex $i }
        }
    } else {
        Add-Paths @($tag.Path)
        $i = Get-PathIndex $tag.Path
        if ($i -ge 0) { Invoke-PlayIndex $i }
    }
})

$miAddFolder.Add_Click({
    $n = $tree.SelectedNode
    if ($n -and $n.Tag -and $n.Tag.Kind -eq 'dir') { Add-FolderToQueue $n.Tag.Path }
})

$btnClear.Add_Click({
    Stop-Playback; Close-Track
    $script:State.Items.Clear(); $script:State.Seen.Clear(); $list.Items.Clear()
    $script:State.ViewMap.Clear(); $script:State.Filter = ''
    if ($script:SearchBox) { $script:SearchBox.Text = '' }
    $script:State.Index = -1; $script:State.Active = $false
    $lblTitle.Text = 'Nothing playing'; $lblArtist.Text = ''; $lblAlbum.Text = ''
    $art.Image = $null; $lblPos.Text = '0:00'; $lblDur.Text = '0:00'
    $seek.Fraction = 0; $seek.Invalidate(); $form.Text = $APP_NAME
    Sync-PlayGlyph
})

# Keyboard: Space = play/pause, arrows = prev/next, M = mute toggle
$script:lastVol = $script:Engine.Volume
$form.Add_KeyDown({
    param($s, $e)
    # Don't hijack typing while the search box has focus.
    if ($script:SearchBox -and $script:SearchBox.Focused) { return }
    switch ($e.KeyCode) {
        'Space'      { Toggle-PlayPause; $e.Handled = $true }
        'MediaPlayPause' { Toggle-PlayPause; $e.Handled = $true }
        'Right'      { if ($e.Control) { Invoke-Next } }
        'Left'       { if ($e.Control) { Invoke-Prev } }
        'M' {
            if ($script:Engine.Volume -gt 0) { $script:lastVol = $script:Engine.Volume; Set-Volume 0 }
            else { Set-Volume $script:lastVol }
            $vol.Fraction = $script:Engine.Volume; $vol.Invalidate()
        }
    }
})

# --- Position timer (also drives auto-advance) ------------------------------
$timer = [System.Windows.Forms.Timer]::new()
$timer.Interval = 250
$timer.Add_Tick({
  try {
    if (-not $script:State.Active) { return }
    $st = Get-PlaybackState
    if ($st -eq 'Stopped') {
        # Reached natural end -> advance.
        $script:State.Active = $false
        Invoke-Next
        return
    }
    if (-not $seek.Dragging) {
        $seek.Fraction = Get-PositionFraction
        $seek.Invalidate()
    }
    $lblPos.Text = Format-Time (Get-Position)
  } catch {}
})
$timer.Start()

# Resolution-aware bar count: chunkier bars with gaps (~14px pitch).
function Set-VisResolution {
    $w = $vis.ClientSize.Width
    if ($w -lt 1) { return }
    $bands = [Math]::Max(20, [Math]::Min(64, [int]($w / 14)))
    if ($vis.Bars.Length -ne $bands) {
        $vis.Bars  = New-Object 'double[]' $bands
        $vis.Peaks = New-Object 'double[]' $bands
        $vis.Invalidate()
    }
}
$vis.Add_Resize({ try { Set-VisResolution } catch {} })
Set-VisResolution

# Visualizer: ~25fps. Pull FFT bars while playing; smooth with fast attack /
# slow decay so it feels musical, and decay to flat when paused/stopped.
$visTimer = [System.Windows.Forms.Timer]::new()
$visTimer.Interval = 40
$visTimer.Add_Tick({
  try {
    $playing = ($script:State.Active -and (Get-PlaybackState) -eq 'Playing')
    $raw = if ($playing) { Get-SpectrumBars $vis.Bars.Length } else { $null }
    $n = $vis.Bars.Length
    if ($vis.Peaks.Length -ne $n) { $vis.Peaks = New-Object 'double[]' $n }
    $changed = $false
    for ($i = 0; $i -lt $n; $i++) {
        $cur = [double]$vis.Bars[$i]
        $t = if ($raw) { [double]$raw[$i] } else { 0.0 }
        if ($t -lt 0) { $t = 0 } elseif ($t -gt 1) { $t = 1 }
        # Expand dynamic range: gamma pushes the mid-band wash down so loud
        # bands tower and quiet ones drop -- the silhouette actually moves.
        $target = [Math]::Pow($t, 1.7)
        # Snappy attack, slow decay -> musical motion.
        $new = if ($target -gt $cur) { $cur * 0.35 + $target * 0.65 } else { $cur * 0.82 + $target * 0.18 }
        $vis.Bars[$i] = $new
        # Peak-hold cap: jumps up instantly, then falls under gravity.
        $pk = [double]$vis.Peaks[$i]
        if ($new -ge $pk) { $vis.Peaks[$i] = $new }
        else { $np = $pk - 0.028; $vis.Peaks[$i] = if ($np -gt $new) { $np } else { $new } }
        if ([Math]::Abs($new - $cur) -gt 0.002 -or $vis.Peaks[$i] -ne $pk) { $changed = $true }
    }
    if ($changed) { $vis.Invalidate() }
  } catch {}
})
$visTimer.Start()

$form.Add_FormClosed({
    try { $timer.Stop(); $timer.Dispose() } catch {}
    try { $visTimer.Stop(); $visTimer.Dispose() } catch {}
    Close-Track
    if ($script:State.Art) { try { $script:State.Art.Dispose() } catch {} }
})

# Center the transport row on resize (Anchor=Top keeps Y, we fix X).
$form.Add_Resize({
    $cx = [int]($form.ClientSize.Width / 2)
    $btnPlay.Left = $cx - 30
    $btnPrev.Left = $cx - 30 - 12 - 44
    $btnNext.Left = $cx + 30 + 12
    $btnStop.Left = $cx + 30 + 12 + 44 + 12
    $form.Invalidate()   # full repaint of the gradient ground -> clears ghosts
})

# Load saved library roots and build the tree (falls back to drives if none).
Load-Config
Build-Tree

# Apply persisted settings (volume / shuffle / repeat / visualizer palette).
try {
    Set-Volume ([double]$script:Config.volume)
    $vol.Fraction = $script:Engine.Volume; $vol.Invalidate()
    $script:lastVol = $script:Engine.Volume
    $script:State.Shuffle = [bool]$script:Config.shuffle
    $pillShuffle.Active = $script:State.Shuffle; Update-PillVisual $pillShuffle
    $script:State.Repeat = [bool]$script:Config.repeat
    $pillRepeat.Active = $script:State.Repeat; Update-PillVisual $pillRepeat
    Set-VisPalette ([string]$script:Config.palette)
} catch {}

# Persist settings (incl. final volume) when the window closes.
$form.Add_FormClosing({ try { Save-Config } catch {} })

# Apply Windows dark-mode scrollbars to the native tree + list once handles exist.
$form.Add_Shown({
    foreach ($c in @($tree, $list)) {
        try {
            [Cadence.Native]::SetWindowTheme($c.Handle, 'DarkMode_Explorer', $null) | Out-Null
            $c.Invalidate()
        } catch {}
    }
})

[System.Windows.Forms.Application]::Run($form)
