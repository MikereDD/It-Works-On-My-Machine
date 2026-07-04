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
    $u = [Math]::Min($w, $h) * 0.28

    $shadow = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(56, 0, 0, 0))
    if ($s.Primary) {
        $g.FillEllipse($shadow, [single]4, [single]6, [single]($w - 8), [single]($h - 8))

        $outer = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
            [System.Drawing.Rectangle]::new(0, 0, $w, $h),
            [System.Drawing.Color]::FromArgb(0x63, 0x68, 0x73),
            [System.Drawing.Color]::FromArgb(0x1C, 0x1F, 0x27), 90.0)
        $g.FillEllipse($outer, [single]1.2, [single]1.2, [single]($w - 2.4), [single]($h - 2.4)); $outer.Dispose()

        $inner = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
            [System.Drawing.Rectangle]::new(0, 0, $w, $h),
            [System.Drawing.Color]::FromArgb(0x3E, 0x43, 0x4D),
            [System.Drawing.Color]::FromArgb(0x11, 0x14, 0x1B), 90.0)
        $g.FillEllipse($inner, [single]5.2, [single]5.2, [single]($w - 10.4), [single]($h - 10.4)); $inner.Dispose()

        $sheen = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
            [System.Drawing.Rectangle]::new(0, 0, $w, [Math]::Max(1, [int]($h * 0.46))),
            [System.Drawing.Color]::FromArgb(44, 255, 255, 255),
            [System.Drawing.Color]::FromArgb(0, 255, 255, 255), 90.0)
        $g.FillEllipse($sheen, [single]($w * 0.18), [single]($h * 0.10), [single]($w * 0.56), [single]($h * 0.30)); $sheen.Dispose()

        if ($s.Press -or $s.Hover) {
            $a = if ($s.Press) { 34 } else { 16 }
            $sl = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb($a, 255, 255, 255))
            $g.FillEllipse($sl, [single]5.2, [single]5.2, [single]($w - 10.4), [single]($h - 10.4)); $sl.Dispose()
        }

        $outerPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(210, $script:Theme.AccentHi.R, $script:Theme.AccentHi.G, $script:Theme.AccentHi.B), 1.8)
        $g.DrawEllipse($outerPen, [single]1.4, [single]1.4, [single]($w - 2.8), [single]($h - 2.8)); $outerPen.Dispose()
        $innerPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(78, 255, 255, 255), 1.0)
        $g.DrawEllipse($innerPen, [single]5.5, [single]5.5, [single]($w - 11.0), [single]($h - 11.0)); $innerPen.Dispose()
        $col = [System.Drawing.Color]::FromArgb(245, 247, 250)
    } else {
        $g.FillEllipse($shadow, [single]3, [single]5, [single]($w - 6), [single]($h - 6))

        $disc = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
            [System.Drawing.Rectangle]::new(0, 0, $w, $h),
            [System.Drawing.Color]::FromArgb(0x46, 0x4B, 0x56),
            [System.Drawing.Color]::FromArgb(0x15, 0x18, 0x20), 90.0)
        $g.FillEllipse($disc, [single]1.0, [single]1.0, [single]($w - 2.0), [single]($h - 2.0)); $disc.Dispose()

        $sheen = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
            [System.Drawing.Rectangle]::new(0, 0, $w, [Math]::Max(1, [int]($h * 0.42))),
            [System.Drawing.Color]::FromArgb(26, 255, 255, 255),
            [System.Drawing.Color]::FromArgb(0, 255, 255, 255), 90.0)
        $g.FillEllipse($sheen, [single]($w * 0.16), [single]($h * 0.10), [single]($w * 0.48), [single]($h * 0.24)); $sheen.Dispose()

        if ($s.Press -or $s.Hover) {
            $a = if ($s.Press) { 26 } else { 12 }
            $sl = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb($a, 255, 255, 255))
            $g.FillEllipse($sl, [single]1.0, [single]1.0, [single]($w - 2.0), [single]($h - 2.0)); $sl.Dispose()
        }

        $pen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(175, $script:Theme.AccentHi.R, $script:Theme.AccentHi.G, $script:Theme.AccentHi.B), 1.1)
        $g.DrawEllipse($pen, [single]1.0, [single]1.0, [single]($w - 2.0), [single]($h - 2.0)); $pen.Dispose()
        $innerPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(55, 255, 255, 255), 1.0)
        $g.DrawEllipse($innerPen, [single]4.0, [single]4.0, [single]($w - 8.0), [single]($h - 8.0)); $innerPen.Dispose()
        $col = [System.Drawing.Color]::FromArgb(241, 243, 247)
    }
    $shadow.Dispose()

    $brush = [System.Drawing.SolidBrush]::new($col)
    switch ($s.Glyph) {
        'play' {
            $triW = $u * 1.06; $triH = $u * 1.08
            $pts = @(
                [System.Drawing.PointF]::new($cx - $triW * 0.60, $cy - $triH),
                [System.Drawing.PointF]::new($cx - $triW * 0.60, $cy + $triH),
                [System.Drawing.PointF]::new($cx + $triW,        $cy))
            $g.FillPolygon($brush, $pts)
        }
        'pause' {
            $barH = $u * 1.82; $barW = [Math]::Max(3.0, $u * 0.44); $gap = $u * 0.42
            $g.FillRectangle($brush, [single]($cx - $gap - $barW), [single]($cy - $barH * 0.5), [single]$barW, [single]$barH)
            $g.FillRectangle($brush, [single]($cx + $gap),         [single]($cy - $barH * 0.5), [single]$barW, [single]$barH)
        }
        'stop' {
            $sq = $u * 1.40
            $rr = New-RoundedRect ($cx - $sq * 0.5) ($cy - $sq * 0.5) $sq $sq ($sq * 0.16)
            $g.FillPath($brush, $rr); $rr.Dispose()
        }
        'next' {
            $triW = $u * 0.70; $triH = $u * 0.84; $barW = [Math]::Max(3.0, $u * 0.18); $gap = $u * 0.12
            $pts = @(
                [System.Drawing.PointF]::new($cx - $triW * 0.82, $cy - $triH),
                [System.Drawing.PointF]::new($cx - $triW * 0.82, $cy + $triH),
                [System.Drawing.PointF]::new($cx + $triW * 0.35, $cy))
            $g.FillPolygon($brush, $pts)
            $g.FillRectangle($brush, [single]($cx + $triW * 0.52 + $gap), [single]($cy - $triH), [single]$barW, [single]($triH * 2))
        }
        'prev' {
            $triW = $u * 0.70; $triH = $u * 0.84; $barW = [Math]::Max(3.0, $u * 0.18); $gap = $u * 0.12
            $pts = @(
                [System.Drawing.PointF]::new($cx + $triW * 0.82, $cy - $triH),
                [System.Drawing.PointF]::new($cx + $triW * 0.82, $cy + $triH),
                [System.Drawing.PointF]::new($cx - $triW * 0.35, $cy))
            $g.FillPolygon($brush, $pts)
            $g.FillRectangle($brush, [single]($cx - $triW * 0.52 - $gap - $barW), [single]($cy - $triH), [single]$barW, [single]($triH * 2))
        }
    }
    $brush.Dispose()
}

function Draw-ToggleIcon {
    param($g, $Kind, $Rect, $Color)
    $pen = [System.Drawing.Pen]::new($Color, 2.0)
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
    $x = [single]$Rect.X; $y = [single]$Rect.Y; $w = [single]$Rect.Width; $h = [single]$Rect.Height
    switch ($Kind) {
        'shuffle' {
            $g.DrawLine($pen, $x + $w*0.06, $y + $h*0.28, $x + $w*0.34, $y + $h*0.28)
            $g.DrawLine($pen, $x + $w*0.34, $y + $h*0.28, $x + $w*0.76, $y + $h*0.72)
            $g.DrawLine($pen, $x + $w*0.50, $y + $h*0.72, $x + $w*0.76, $y + $h*0.72)
            $g.DrawLine($pen, $x + $w*0.76, $y + $h*0.72, $x + $w*0.66, $y + $h*0.62)
            $g.DrawLine($pen, $x + $w*0.76, $y + $h*0.72, $x + $w*0.66, $y + $h*0.82)
            $g.DrawLine($pen, $x + $w*0.06, $y + $h*0.72, $x + $w*0.22, $y + $h*0.72)
            $g.DrawLine($pen, $x + $w*0.22, $y + $h*0.72, $x + $w*0.40, $y + $h*0.54)
            $g.DrawLine($pen, $x + $w*0.58, $y + $h*0.28, $x + $w*0.76, $y + $h*0.28)
            $g.DrawLine($pen, $x + $w*0.76, $y + $h*0.28, $x + $w*0.66, $y + $h*0.18)
            $g.DrawLine($pen, $x + $w*0.76, $y + $h*0.28, $x + $w*0.66, $y + $h*0.38)
        }
        'repeat' {
            $g.DrawArc($pen, $x + $w*0.10, $y + $h*0.18, $w*0.46, $h*0.46, 190, 220)
            $g.DrawArc($pen, $x + $w*0.44, $y + $h*0.36, $w*0.46, $h*0.46, 10, 220)
            $g.DrawLine($pen, $x + $w*0.61, $y + $h*0.16, $x + $w*0.76, $y + $h*0.16)
            $g.DrawLine($pen, $x + $w*0.76, $y + $h*0.16, $x + $w*0.69, $y + $h*0.09)
            $g.DrawLine($pen, $x + $w*0.76, $y + $h*0.16, $x + $w*0.69, $y + $h*0.23)
            $g.DrawLine($pen, $x + $w*0.39, $y + $h*0.84, $x + $w*0.24, $y + $h*0.84)
            $g.DrawLine($pen, $x + $w*0.24, $y + $h*0.84, $x + $w*0.31, $y + $h*0.77)
            $g.DrawLine($pen, $x + $w*0.24, $y + $h*0.84, $x + $w*0.31, $y + $h*0.91)
        }
    }
    $pen.Dispose()
} {
    param($g, $Kind, $Rect, $Color)
    $pen = [System.Drawing.Pen]::new($Color, 1.8)
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
    $x = [single]$Rect.X; $y = [single]$Rect.Y; $w = [single]$Rect.Width; $h = [single]$Rect.Height
    switch ($Kind) {
        'shuffle' {
            $g.DrawLine($pen, $x, $y + $h * 0.28, $x + $w * 0.32, $y + $h * 0.28)
            $g.DrawLine($pen, $x + $w * 0.32, $y + $h * 0.28, $x + $w * 0.72, $y + $h * 0.72)
            $g.DrawLine($pen, $x + $w * 0.46, $y + $h * 0.72, $x + $w * 0.72, $y + $h * 0.72)
            $g.DrawLine($pen, $x, $y + $h * 0.72, $x + $w * 0.20, $y + $h * 0.72)
            $g.DrawLine($pen, $x + $w * 0.20, $y + $h * 0.72, $x + $w * 0.42, $y + $h * 0.50)
            $g.DrawLine($pen, $x + $w * 0.58, $y + $h * 0.28, $x + $w * 0.72, $y + $h * 0.28)
            $g.DrawLine($pen, $x + $w * 0.57, $y + $h * 0.28, $x + $w * 0.46, $y + $h * 0.17)
            $g.DrawLine($pen, $x + $w * 0.57, $y + $h * 0.28, $x + $w * 0.46, $y + $h * 0.39)
            $g.DrawLine($pen, $x + $w * 0.57, $y + $h * 0.72, $x + $w * 0.46, $y + $h * 0.61)
            $g.DrawLine($pen, $x + $w * 0.57, $y + $h * 0.72, $x + $w * 0.46, $y + $h * 0.83)
        }
        'repeat' {
            $g.DrawArc($pen, $x + $w * 0.10, $y + $h * 0.16, $w * 0.48, $h * 0.48, 200, 210)
            $g.DrawArc($pen, $x + $w * 0.42, $y + $h * 0.36, $w * 0.48, $h * 0.48, 20, 210)
            $g.DrawLine($pen, $x + $w * 0.62, $y + $h * 0.16, $x + $w * 0.76, $y + $h * 0.16)
            $g.DrawLine($pen, $x + $w * 0.76, $y + $h * 0.16, $x + $w * 0.68, $y + $h * 0.08)
            $g.DrawLine($pen, $x + $w * 0.76, $y + $h * 0.16, $x + $w * 0.68, $y + $h * 0.24)
            $g.DrawLine($pen, $x + $w * 0.38, $y + $h * 0.84, $x + $w * 0.24, $y + $h * 0.84)
            $g.DrawLine($pen, $x + $w * 0.24, $y + $h * 0.84, $x + $w * 0.32, $y + $h * 0.76)
            $g.DrawLine($pen, $x + $w * 0.24, $y + $h * 0.84, $x + $w * 0.32, $y + $h * 0.92)
        }
    }
    $pen.Dispose()
}

# --- M3 toggle chip (shuffle / repeat) --------------------------------------
function New-TogglePill {
    param($Text, $Width = 82, $Height = 30, $Icon = '')
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
    $b | Add-Member -NotePropertyName Icon   -NotePropertyValue $Icon  -Force
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

    $bgTop = if ($s.Active) { [System.Drawing.Color]::FromArgb(0x36, 0x3A, 0x43) } else { [System.Drawing.Color]::FromArgb(0x2E, 0x32, 0x3A) }
    $bgBot = if ($s.Active) { [System.Drawing.Color]::FromArgb(0x16, 0x19, 0x20) } else { [System.Drawing.Color]::FromArgb(0x14, 0x16, 0x1C) }
    $lg = [System.Drawing.Drawing2D.LinearGradientBrush]::new([System.Drawing.Rectangle]::new(0, 0, $w, $h), $bgTop, $bgBot, 90.0)
    $g.FillPath($lg, $rect); $lg.Dispose()

    $sheen = [System.Drawing.Drawing2D.LinearGradientBrush]::new([System.Drawing.Rectangle]::new(0, 0, $w, [Math]::Max(1, [int]($h * 0.48))), [System.Drawing.Color]::FromArgb(22, 255, 255, 255), [System.Drawing.Color]::FromArgb(0, 255, 255, 255), 90.0)
    $g.FillEllipse($sheen, [single]($w * 0.10), [single]($h * 0.06), [single]($w * 0.42), [single]($h * 0.34)); $sheen.Dispose()

    if ($s.Hover) {
        $hoverAlpha = if ($s.Active) { 16 } else { 10 }
        $sl = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb($hoverAlpha, 255, 255, 255))
        $g.FillPath($sl, $rect); $sl.Dispose()
    }

    $borderColor = if ($s.Active) { [System.Drawing.Color]::FromArgb(155, $script:Theme.AccentHi.R, $script:Theme.AccentHi.G, $script:Theme.AccentHi.B) } else { [System.Drawing.Color]::FromArgb(128, $script:Theme.Contour.R, $script:Theme.Contour.G, $script:Theme.Contour.B) }
    $pen = [System.Drawing.Pen]::new($borderColor, 1.1); $g.DrawPath($pen, $rect); $pen.Dispose()
    $inner = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(40, 255, 255, 255), 1.0); $g.DrawPath($inner, $rect); $inner.Dispose()

    $tc = if ($s.Active) { [System.Drawing.Color]::FromArgb(245, 247, 250) } else { [System.Drawing.Color]::FromArgb(232, 236, 242) }
    $tb = [System.Drawing.SolidBrush]::new($tc)
    $sf = [System.Drawing.StringFormat]::new(); $sf.Alignment = 'Near'; $sf.LineAlignment = 'Center'

    if ($s.Icon) {
        $iconSize = [single]15
        $gap = [single]10
        $textSize = $g.MeasureString($s.Label, $s.Font)
        $groupW = $iconSize + $gap + $textSize.Width
        $startX = [single](($w - $groupW) / 2.0)
        $iconRect = [System.Drawing.RectangleF]::new($startX, [single](($h - $iconSize) / 2.0), $iconSize, $iconSize)
        Draw-ToggleIcon $g $s.Icon $iconRect $tc
        $textRect = [System.Drawing.RectangleF]::new($startX + $iconSize + $gap, 0, [single]($w - ($startX + $iconSize + $gap) - 6), [single]$h)
        $g.DrawString($s.Label, $s.Font, $tb, $textRect, $sf)
    } else {
        $sf.Alignment = 'Center'
        $g.DrawString($s.Label, $s.Font, $tb, [System.Drawing.RectangleF]::new(0, 0, $w, $h), $sf)
    }

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
