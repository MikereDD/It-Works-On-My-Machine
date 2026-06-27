# ============================================================================
#  player.ui.ps1  -  Cadence look & feel: palette, owner-drawn controls
# ----------------------------------------------------------------------------
#  Monochrome + depth. Surfaces are raised (bevel) or recessed (wells); buttons
#  are M3-style pills/FAB with soft contour + hover state layers. No
#  WinForms/Drawing types in parameter signatures (parse-order safe).
# ============================================================================

# --- Palette (monochrome, depth tokens) -------------------------------------
$script:Theme = @{
    Bg        = [System.Drawing.ColorTranslator]::FromHtml('#101116')   # window ground
    Surface   = [System.Drawing.ColorTranslator]::FromHtml('#20222A')   # raised cards/pills
    SurfaceHi = [System.Drawing.ColorTranslator]::FromHtml('#2A2D36')   # bevel highlight
    Panel     = [System.Drawing.ColorTranslator]::FromHtml('#20222A')   # alias of Surface (compat)
    Well      = [System.Drawing.ColorTranslator]::FromHtml('#0C0D11')   # recessed (lists, vis)
    Track     = [System.Drawing.ColorTranslator]::FromHtml('#0C0D11')   # slider groove
    Fill      = [System.Drawing.ColorTranslator]::FromHtml('#54585F')   # slider filled
    Hover     = [System.Drawing.ColorTranslator]::FromHtml('#2A2D34')
    Text      = [System.Drawing.ColorTranslator]::FromHtml('#E6E8EE')
    Muted     = [System.Drawing.ColorTranslator]::FromHtml('#888C97')
    Accent    = [System.Drawing.ColorTranslator]::FromHtml('#3A3D44')   # dark grey (fills/sel)
    AccentHi  = [System.Drawing.ColorTranslator]::FromHtml('#9CA0AB')   # light grey (knob/edge)
    Contour   = [System.Drawing.ColorTranslator]::FromHtml('#3A3E47')   # soft outline
    VisBorder = [System.Drawing.ColorTranslator]::FromHtml('#5A5E68')   # visualizer light edge
    GlyphOn   = [System.Drawing.ColorTranslator]::FromHtml('#EEF1F6')   # glyph on FAB
}

function Set-DoubleBuffered {
    param($Control)
    $prop = [System.Windows.Forms.Control].GetProperty(
        'DoubleBuffered',
        [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic)
    $prop.SetValue($Control, $true, $null)
}

function New-RoundedRect {
    param($X, $Y, $W, $H, $R)
    $gp = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $d = [single]($R * 2)
    if ($d -gt $W) { $d = $W }
    if ($d -gt $H) { $d = $H }
    if ($d -le 0) {
        $gp.AddRectangle([System.Drawing.RectangleF]::new($X, $Y, $W, $H))
        return $gp
    }
    $gp.AddArc($X, $Y, $d, $d, 180, 90)
    $gp.AddArc($X + $W - $d, $Y, $d, $d, 270, 90)
    $gp.AddArc($X + $W - $d, $Y + $H - $d, $d, $d, 0, 90)
    $gp.AddArc($X, $Y + $H - $d, $d, $d, 90, 90)
    $gp.CloseFigure()
    $gp
}

function Blend-Color {
    param($C1, $C2, $T)
    $t = [Math]::Max(0.0, [Math]::Min(1.0, [double]$T))
    [System.Drawing.Color]::FromArgb(
        [int]($C1.R + ($C2.R - $C1.R) * $t),
        [int]($C1.G + ($C2.G - $C1.G) * $t),
        [int]($C1.B + ($C2.B - $C1.B) * $t))
}

# --- Generic horizontal slider (seek + volume) ------------------------------
function New-Slider {
    param($Width, $Height = 20)
    $bar = [System.Windows.Forms.Panel]::new()
    $bar.Width = $Width; $bar.Height = $Height
    $bar.BackColor = $script:Theme.Bg
    Set-DoubleBuffered $bar
    $bar | Add-Member -NotePropertyName Fraction -NotePropertyValue 0.0 -Force
    $bar | Add-Member -NotePropertyName Dragging -NotePropertyValue $false -Force
    $bar | Add-Member -NotePropertyName OnSeek   -NotePropertyValue ([scriptblock]{}) -Force

    $bar.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $w = $s.ClientSize.Width; $h = $s.ClientSize.Height
        $th = 5; $ty = [single]([int]($h / 2) - [int]($th / 2)); $rad = 7

        # recessed groove
        $gr = New-RoundedRect 0 $ty $w $th 2.5
        $gb = [System.Drawing.SolidBrush]::new($script:Theme.Track); $g.FillPath($gb, $gr); $gb.Dispose()
        $sp = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(120, 0, 0, 0), 1); $g.DrawPath($sp, $gr); $sp.Dispose()
        $gr.Dispose()

        $px = [int][Math]::Round($w * [double]$s.Fraction)
        if ($px -gt 0) {
            $fr = New-RoundedRect 0 $ty $px $th 2.5
            $fb = [System.Drawing.SolidBrush]::new($script:Theme.Fill); $g.FillPath($fb, $fr); $fb.Dispose(); $fr.Dispose()
            # knob: light grey with soft ring
            $tx = [Math]::Max(0, [Math]::Min($w - ($rad * 2), $px - $rad))
            $halo = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(60, 0, 0, 0))
            $g.FillEllipse($halo, [single]($tx - 1), [single]([int]($h / 2) - $rad), [single]($rad * 2 + 2), [single]($rad * 2 + 2)); $halo.Dispose()
            $kb = [System.Drawing.SolidBrush]::new($script:Theme.AccentHi)
            $g.FillEllipse($kb, $tx, [int]($h / 2) - $rad, $rad * 2, $rad * 2); $kb.Dispose()
            $kp = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(150, 230, 232, 238), 1)
            $g.DrawEllipse($kp, [single]$tx, [single]([int]($h / 2) - $rad), [single]($rad * 2), [single]($rad * 2)); $kp.Dispose()
        }
    })

    $apply = {
        param($s, $x)
        $f = [double]$x / [double][Math]::Max(1, $s.ClientSize.Width)
        $f = [Math]::Max(0.0, [Math]::Min(1.0, $f))
        $s.Fraction = $f; $s.Invalidate(); & $s.OnSeek $f
    }
    $bar.Add_MouseDown({ param($s, $e) $s.Dragging = $true;  & $apply $s $e.X }.GetNewClosure())
    $bar.Add_MouseMove({ param($s, $e) if ($s.Dragging) { & $apply $s $e.X } }.GetNewClosure())
    $bar.Add_MouseUp(  { param($s, $e) $s.Dragging = $false; & $apply $s $e.X }.GetNewClosure())
    return $bar
}

# --- M3 tonal pill button (action buttons) ----------------------------------
function New-FlatButton {
    param($Text, $W, $H = 38)
    $b = [System.Windows.Forms.Button]::new()
    $b.Width = $W; $b.Height = $H
    $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderSize = 0
    $b.FlatAppearance.MouseOverBackColor = $script:Theme.Bg
    $b.FlatAppearance.MouseDownBackColor = $script:Theme.Bg
    $b.BackColor = $script:Theme.Bg; $b.ForeColor = $script:Theme.Text
    $b.Font = [System.Drawing.Font]::new('Segoe UI', 9.5)
    $b.TabStop = $false; $b.Text = ''
    Set-DoubleBuffered $b
    $b | Add-Member -NotePropertyName Label -NotePropertyValue $Text -Force
    $b | Add-Member -NotePropertyName Hover -NotePropertyValue $false -Force
    $b | Add-Member -NotePropertyName Press -NotePropertyValue $false -Force
    $r = [int]($H / 2); $gp = New-RoundedRect 0 0 $W $H $r; $b.Region = [System.Drawing.Region]::new($gp); $gp.Dispose()
    $b.Add_Resize({ $r = [int]($this.Height / 2); $gp = New-RoundedRect 0 0 $this.Width $this.Height $r; $this.Region = [System.Drawing.Region]::new($gp); $gp.Dispose() })
    $b.Add_MouseEnter({ $this.Hover = $true;  $this.Invalidate() })
    $b.Add_MouseLeave({ $this.Hover = $false; $this.Press = $false; $this.Invalidate() })
    $b.Add_MouseDown({ $this.Press = $true;  $this.Invalidate() })
    $b.Add_MouseUp({ $this.Press = $false; $this.Invalidate() })
    $b.Add_Paint({ param($s, $e) Draw-PillButton $s $e })
    return $b
}

function Draw-PillButton {
    param($s, $e)
    $g = $e.Graphics; $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $w = $s.ClientSize.Width; $h = $s.ClientSize.Height
    $r = [single]($h / 2.0)
    $rect = New-RoundedRect 0.7 0.7 ($w - 1.4) ($h - 1.4) ($r - 0.7)
    $lg = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
        [System.Drawing.Rectangle]::new(0, 0, $w, $h), $script:Theme.SurfaceHi, $script:Theme.Surface, 90.0)
    $g.FillPath($lg, $rect); $lg.Dispose()
    if ($s.Press -or $s.Hover) {
        $a = if ($s.Press) { 26 } else { 15 }
        $sl = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb($a, 255, 255, 255))
        $g.FillPath($sl, $rect); $sl.Dispose()
    }
    $pen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(110, $script:Theme.AccentHi.R, $script:Theme.AccentHi.G, $script:Theme.AccentHi.B), 1.0)
    $g.DrawPath($pen, $rect); $pen.Dispose()
    $sf = [System.Drawing.StringFormat]::new(); $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
    $tb = [System.Drawing.SolidBrush]::new($script:Theme.Text)
    $g.DrawString($s.Label, $s.Font, $tb, [System.Drawing.RectangleF]::new(0, 0, $w, $h), $sf)
    $tb.Dispose(); $sf.Dispose(); $rect.Dispose()
}

# --- Transport: M3 icon buttons + FAB ---------------------------------------
function New-TransportButton {
    param($Glyph, $Size = 44, $Primary = $false)
    $b = [System.Windows.Forms.Button]::new()
    $b.Width = $Size; $b.Height = $Size
    $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderSize = 0
    $b.FlatAppearance.MouseOverBackColor = $script:Theme.Bg
    $b.FlatAppearance.MouseDownBackColor = $script:Theme.Bg
    $b.BackColor = $script:Theme.Bg; $b.ForeColor = $script:Theme.Text
    $b.TabStop = $false; $b.Text = ''
    Set-DoubleBuffered $b
    $b | Add-Member -NotePropertyName Glyph   -NotePropertyValue $Glyph -Force
    $b | Add-Member -NotePropertyName Primary -NotePropertyValue ([bool]$Primary) -Force
    $b | Add-Member -NotePropertyName Hover   -NotePropertyValue $false -Force
    $b | Add-Member -NotePropertyName Press   -NotePropertyValue $false -Force
    $gp = [System.Drawing.Drawing2D.GraphicsPath]::new(); $gp.AddEllipse(0, 0, $Size, $Size)
    $b.Region = [System.Drawing.Region]::new($gp); $gp.Dispose()
    $b.Add_MouseEnter({ $this.Hover = $true;  $this.Invalidate() })
    $b.Add_MouseLeave({ $this.Hover = $false; $this.Press = $false; $this.Invalidate() })
    $b.Add_MouseDown({ $this.Press = $true;  $this.Invalidate() })
    $b.Add_MouseUp({ $this.Press = $false; $this.Invalidate() })
    $b.Add_Paint({ param($s, $e) Invoke-DrawGlyph $s $e })
    return $b
}

function Invoke-DrawGlyph {
    param($s, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $w = $s.ClientSize.Width; $h = $s.ClientSize.Height
    $cx = $w / 2.0; $cy = $h / 2.0
    $u = [Math]::Min($w, $h) * 0.30

    if ($s.Primary) {
        $fb = [System.Drawing.SolidBrush]::new($script:Theme.Accent)
        $g.FillEllipse($fb, 0, 0, $w, $h); $fb.Dispose()
        $sheen = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(34, 255, 255, 255))
        $g.FillEllipse($sheen, [single]($w * 0.12), [single](-$h * 0.28), [single]($w * 0.76), [single]($h * 0.72)); $sheen.Dispose()
        if ($s.Press -or $s.Hover) {
            $a = if ($s.Press) { 30 } else { 18 }
            $sl = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb($a, 255, 255, 255))
            $g.FillEllipse($sl, 0, 0, $w, $h); $sl.Dispose()
        }
        $rp = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(120, $script:Theme.AccentHi.R, $script:Theme.AccentHi.G, $script:Theme.AccentHi.B), 1.4)
        $g.DrawEllipse($rp, 0.8, 0.8, [single]($w - 1.6), [single]($h - 1.6)); $rp.Dispose()
        $col = $script:Theme.GlyphOn
    } else {
        # Paint the exact gradient slice behind this button so the circular
        # region melts into the form ground (no visible disc).
        $p = $s.Parent
        if ($p) {
            $H = [double]$p.ClientSize.Height; if ($H -lt 1) { $H = 1 }
            $T = [System.Drawing.Color]::FromArgb(0x16, 0x17, 0x1E)
            $B = [System.Drawing.Color]::FromArgb(0x0B, 0x0C, 0x10)
            $c0 = Blend-Color $T $B ([Math]::Max(0.0, [Math]::Min(1.0, $s.Top / $H)))
            $c1 = Blend-Color $T $B ([Math]::Max(0.0, [Math]::Min(1.0, ($s.Top + $s.Height) / $H)))
            $bgrad = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
                [System.Drawing.Rectangle]::new(0, 0, $w, [Math]::Max(1, $h)), $c0, $c1, 90.0)
            $g.FillRectangle($bgrad, 0, 0, $w, $h); $bgrad.Dispose()
        }
        if ($s.Press -or $s.Hover) {
            $a = if ($s.Press) { 26 } else { 14 }
            $sl = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb($a, 255, 255, 255))
            $g.FillEllipse($sl, 0, 0, $w, $h); $sl.Dispose()
        }
        $col = $script:Theme.Text
    }

    $brush = [System.Drawing.SolidBrush]::new($col)
    switch ($s.Glyph) {
        'play' {
            $pts = @(
                [System.Drawing.PointF]::new($cx - $u * 0.7, $cy - $u),
                [System.Drawing.PointF]::new($cx - $u * 0.7, $cy + $u),
                [System.Drawing.PointF]::new($cx + $u,        $cy))
            $g.FillPolygon($brush, $pts)
        }
        'pause' {
            $bw = $u * 0.62
            $g.FillRectangle($brush, [single]($cx - $u),       [single]($cy - $u), [single]$bw, [single]($u * 2))
            $g.FillRectangle($brush, [single]($cx + $u - $bw), [single]($cy - $u), [single]$bw, [single]($u * 2))
        }
        'stop' {
            $rr = New-RoundedRect ($cx - $u) ($cy - $u) ($u * 2) ($u * 2) ($u * 0.28)
            $g.FillPath($brush, $rr); $rr.Dispose()
        }
        'next' {
            $pts = @(
                [System.Drawing.PointF]::new($cx - $u,       $cy - $u),
                [System.Drawing.PointF]::new($cx - $u,       $cy + $u),
                [System.Drawing.PointF]::new($cx + $u * 0.3, $cy))
            $g.FillPolygon($brush, $pts)
            $g.FillRectangle($brush, [single]($cx + $u * 0.45), [single]($cy - $u), [single]($u * 0.5), [single]($u * 2))
        }
        'prev' {
            $pts = @(
                [System.Drawing.PointF]::new($cx + $u,        $cy - $u),
                [System.Drawing.PointF]::new($cx + $u,        $cy + $u),
                [System.Drawing.PointF]::new($cx - $u * 0.3,  $cy))
            $g.FillPolygon($brush, $pts)
            $g.FillRectangle($brush, [single]($cx - $u * 0.95), [single]($cy - $u), [single]($u * 0.5), [single]($u * 2))
        }
    }
    $brush.Dispose()
}

# --- M3 toggle chip (shuffle / repeat) --------------------------------------
function New-TogglePill {
    param($Text, $Width = 82, $Height = 30)
    $b = [System.Windows.Forms.Button]::new()
    $b.Width = $Width; $b.Height = $Height
    $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderSize = 0
    $b.FlatAppearance.MouseOverBackColor = $script:Theme.Bg
    $b.FlatAppearance.MouseDownBackColor = $script:Theme.Bg
    $b.BackColor = $script:Theme.Bg
    $b.Font = [System.Drawing.Font]::new('Segoe UI Semibold', 8.0)
    $b.TabStop = $false; $b.Text = ''
    Set-DoubleBuffered $b
    $b | Add-Member -NotePropertyName Label  -NotePropertyValue $Text  -Force
    $b | Add-Member -NotePropertyName Active -NotePropertyValue $false -Force
    $b | Add-Member -NotePropertyName Hover  -NotePropertyValue $false -Force
    $r = [int]($Height / 2); $gp = New-RoundedRect 0 0 $Width $Height $r; $b.Region = [System.Drawing.Region]::new($gp); $gp.Dispose()
    $b.Add_MouseEnter({ $this.Hover = $true;  $this.Invalidate() })
    $b.Add_MouseLeave({ $this.Hover = $false; $this.Invalidate() })
    $b.Add_Paint({ param($s, $e) Draw-TogglePill $s $e })
    return $b
}

function Draw-TogglePill {
    param($s, $e)
    $g = $e.Graphics; $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $w = $s.ClientSize.Width; $h = $s.ClientSize.Height
    $r = [single]($h / 2.0)
    $rect = New-RoundedRect 0.7 0.7 ($w - 1.4) ($h - 1.4) ($r - 0.7)
    if ($s.Active) {
        $fb = [System.Drawing.SolidBrush]::new($script:Theme.Accent); $g.FillPath($fb, $rect); $fb.Dispose()
        if ($s.Hover) { $sl = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(16, 255, 255, 255)); $g.FillPath($sl, $rect); $sl.Dispose() }
        $tc = $script:Theme.GlyphOn
    } else {
        if ($s.Hover) { $sl = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(10, 255, 255, 255)); $g.FillPath($sl, $rect); $sl.Dispose() }
        $pen = [System.Drawing.Pen]::new($script:Theme.Contour, 1.2); $g.DrawPath($pen, $rect); $pen.Dispose()
        $tc = $script:Theme.Muted
    }
    $sf = [System.Drawing.StringFormat]::new(); $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
    $tb = [System.Drawing.SolidBrush]::new($tc)
    $g.DrawString($s.Label, $s.Font, $tb, [System.Drawing.RectangleF]::new(0, 0, $w, $h), $sf)
    $tb.Dispose(); $sf.Dispose(); $rect.Dispose()
}

function Update-PillVisual { param($b) $b.Invalidate() }

# --- Visualizer -------------------------------------------------------------
#  Dark recessed well, light-grey hairline border, grey spikes (dark->white by
#  frequency), with a dim mirrored reflection.
function Hsv-Color {
    param($H, $S, $V)
    $h = ((([double]$H) % 360) + 360) % 360
    $c = $V * $S
    $x = $c * (1 - [Math]::Abs((($h / 60.0) % 2) - 1))
    $m = $V - $c
    switch ([int][Math]::Floor($h / 60)) {
        0 { $r = $c; $g = $x; $b = 0 }
        1 { $r = $x; $g = $c; $b = 0 }
        2 { $r = 0; $g = $c; $b = $x }
        3 { $r = 0; $g = $x; $b = $c }
        4 { $r = $x; $g = 0; $b = $c }
        default { $r = $c; $g = 0; $b = $x }
    }
    [System.Drawing.Color]::FromArgb(
        [int]([Math]::Max(0.0, [Math]::Min(1.0, $r + $m)) * 255),
        [int]([Math]::Max(0.0, [Math]::Min(1.0, $g + $m)) * 255),
        [int]([Math]::Max(0.0, [Math]::Min(1.0, $b + $m)) * 255))
}

function Vis-BandColor {
    param($F, $Mag)
    $m = [Math]::Min(1.0, [double]$Mag)
    $pal = 'mono'
    try { if ($script:State -and $script:State.VisPalette) { $pal = $script:State.VisPalette } } catch {}
    switch ($pal) {
        'spectrum' {
            # blue (bass) -> red (treble), brighter with magnitude
            return (Hsv-Color (240.0 - ($F * 240.0)) 0.72 (0.55 + 0.45 * $m))
        }
        'indigo' {
            $low  = [System.Drawing.Color]::FromArgb(0x3B, 0x33, 0x8A)
            $mid  = [System.Drawing.Color]::FromArgb(0x6A, 0x5A, 0xE0)
            $high = [System.Drawing.Color]::FromArgb(0xB9, 0xB0, 0xFF)
            $base = if ($F -lt 0.5) { Blend-Color $low $mid ($F * 2) } else { Blend-Color $mid $high (($F - 0.5) * 2) }
            return (Blend-Color $base ([System.Drawing.Color]::FromArgb(0xEC, 0xEA, 0xFF)) ($m * 0.4))
        }
        default {
            $low  = [System.Drawing.Color]::FromArgb(0x5E, 0x62, 0x6B)   # bass: mid grey
            $mid  = [System.Drawing.Color]::FromArgb(0x9A, 0x9E, 0xA8)
            $high = [System.Drawing.Color]::FromArgb(0xDE, 0xE1, 0xE8)   # treble: near-white
            $base = if ($F -lt 0.5) { Blend-Color $low $mid ($F * 2) } else { Blend-Color $mid $high (($F - 0.5) * 2) }
            return (Blend-Color $base ([System.Drawing.Color]::FromArgb(0xF2, 0xF4, 0xF8)) ($m * 0.4))
        }
    }
}

function New-Visualizer {
    param($Width, $Height = 64, $BandCount = 56)
    $vis = [System.Windows.Forms.Panel]::new()
    $vis.Width = $Width; $vis.Height = $Height
    $vis.BackColor = $script:Theme.Bg
    Set-DoubleBuffered $vis
    $vis | Add-Member -NotePropertyName Bars  -NotePropertyValue (New-Object 'double[]' $BandCount) -Force
    $vis | Add-Member -NotePropertyName Peaks -NotePropertyValue (New-Object 'double[]' $BandCount) -Force

    $vis.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $w = $s.ClientSize.Width; $h = $s.ClientSize.Height
        if ($w -le 2 -or $h -le 2) { return }

        # recessed well
        $well = New-RoundedRect 1 1 ($w - 2) ($h - 2) 10
        $wb = [System.Drawing.SolidBrush]::new($script:Theme.Well); $g.FillPath($wb, $well); $wb.Dispose()
        $g.SetClip($well)

        $n = $s.Bars.Length
        if ($n -gt 0) {
            $pad    = 10.0
            $iw     = $w - $pad * 2
            $cell   = [double]$iw / $n
            $bw     = [single]([Math]::Max(2.0, $cell * 0.62))   # wider bars + gaps
            $base   = [double]$h * 0.72                           # bars rise to here
            $topPad = 6.0
            $usable = $base - $topPad
            $baseCol  = [System.Drawing.Color]::FromArgb(0x2C, 0x30, 0x38)   # dark bar foot
            $capWhite = [System.Drawing.Color]::FromArgb(0xF4, 0xF6, 0xFA)
            $hasPeaks = ($s.PSObject.Properties['Peaks'] -and $s.Peaks.Length -eq $n)

            for ($i = 0; $i -lt $n; $i++) {
                $mag = [double]$s.Bars[$i]
                if ($mag -lt 0) { $mag = 0 } elseif ($mag -gt 1) { $mag = 1 }
                $f   = if ($n -gt 1) { [double]$i / ($n - 1) } else { 0 }
                $cx  = [single]($pad + $i * $cell + $cell / 2)
                $x   = [single]($cx - $bw / 2)
                $tip = Vis-BandColor $f $mag
                $barH = [single]($mag * $usable)

                if ($barH -ge 1.2) {
                    $topY = [single]($base - $barH)
                    $rad  = [single]([Math]::Min([double]($bw / 2), 3.0))
                    # bar body: bright freq-tinted tip fading down to a dark foot
                    $barRect = New-RoundedRect $x $topY $bw $barH $rad
                    $grad = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
                        [System.Drawing.RectangleF]::new($x, $topY, $bw, [single]([Math]::Max(1.0, $barH))),
                        $tip, $baseCol, 90.0)
                    $g.FillPath($grad, $barRect); $grad.Dispose(); $barRect.Dispose()

                    # subtle mirrored reflection below the baseline
                    $reflH = [single]($mag * ($h - $base) * 0.5)
                    if ($reflH -ge 1) {
                        $rb = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(42, $tip.R, $tip.G, $tip.B))
                        $g.FillRectangle($rb, $x, [single]($base + 1), $bw, $reflH); $rb.Dispose()
                    }
                }

                # floating peak-hold cap
                if ($hasPeaks) {
                    $pk = [double]$s.Peaks[$i]
                    if ($pk -lt 0) { $pk = 0 } elseif ($pk -gt 1) { $pk = 1 }
                    $pkH = [single]($pk * $usable)
                    if ($pkH -ge 1) {
                        $py = [single]($base - $pkH - 2.5)
                        $capCol = Blend-Color $tip $capWhite 0.55
                        $cb = [System.Drawing.SolidBrush]::new($capCol)
                        $cap = New-RoundedRect $x $py $bw 2.5 1.2
                        $g.FillPath($cb, $cap); $cb.Dispose(); $cap.Dispose()
                    }
                }
            }
        }
        $g.ResetClip()

        # light-grey hairline border on top
        $bp = [System.Drawing.Pen]::new($script:Theme.VisBorder, 1.2); $g.DrawPath($bp, $well); $bp.Dispose()
        $well.Dispose()
    })
    return $vis
}

function Format-Time {
    param($TimeSpan)
    if (-not $TimeSpan) { return '0:00' }
    if ($TimeSpan.TotalHours -ge 1) { return ('{0}:{1:mm\:ss}' -f [int]$TimeSpan.TotalHours, $TimeSpan) }
    '{0}:{1:00}' -f [int]$TimeSpan.Minutes, $TimeSpan.Seconds
}
