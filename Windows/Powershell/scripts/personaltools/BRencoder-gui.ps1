<#
================================================================
  BRencoder GUI  -  thin WinForms front end for BRencoder.ps1
  version:  0.8  by Mike Redd
----------------------------------------------------------------
  Reuses BRencoder.ps1's own functions (config, Get-M2tsFiles,
  Read-ClpiSubtitleLanguages, Encode-File) by dot-sourcing it.
  It does NOT reimplement the encode pipeline, so the .clpi
  subtitle fix and everything else stay in one place.

  REQUIRED one-time change in BRencoder.ps1 (two lines): wrap the
  bottom menu loop so dot-sourcing doesn't launch the CLI:

      if (-not $env:BRENCODER_NOMENU) {
          while ($true) { Show-Header; Show-Menu; ... }   # existing loop
      }

  Then run:  powershell -ExecutionPolicy Bypass -STA -File BRencoder-gui.ps1
  (-STA is required for WinForms.)
================================================================
#>

[CmdletBinding()]
param(
    # Path to BRencoder.ps1. If not given, try (in order): next to this GUI,
    # then the canonical deployed location used by tool-menu.ps1
    # (<PS>\scripts\personaltools\BRencoder.ps1), then a sibling
    # personaltools folder. dev/use can therefore live apart.
    [string]$BREncoderPath
)

if (-not $BREncoderPath) {
    $candidates = @(
        (Join-Path $PSScriptRoot 'BRencoder.ps1')
        (Join-Path $env:USERPROFILE 'PS\scripts\personaltools\BRencoder.ps1')
        (Join-Path (Split-Path $PSScriptRoot -Parent) 'personaltools\BRencoder.ps1')
    )
    $BREncoderPath = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    if (-not $BREncoderPath) { $BREncoderPath = $candidates[0] }
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ----------------------------------------------------------------
# Load BRencoder's functions without launching its menu.
# ----------------------------------------------------------------
$env:BRENCODER_NOMENU = '1'
if (-not (Test-Path -LiteralPath $BREncoderPath)) {
    [System.Windows.Forms.MessageBox]::Show("BRencoder.ps1 not found at:`n$BREncoderPath",
        'BRencoder GUI', 'OK', 'Error') | Out-Null
    return
}
try {
    . $BREncoderPath
}
catch {
    [System.Windows.Forms.MessageBox]::Show("Failed to load BRencoder.ps1:`n$($_.Exception.Message)",
        'BRencoder GUI', 'OK', 'Error') | Out-Null
    return
}

# ----------------------------------------------------------------
# Small helpers (independent of BRencoder so the grid works even
# if a probe fails). ffprobe path comes from BRencoder's config.
# ----------------------------------------------------------------
$script:FFprobe = if ($Script:FFprobePath) { $Script:FFprobePath } else { 'ffprobe' }
$script:InputRoot = if ($Script:InputRoot) { $Script:InputRoot } else { 'G:\Rip\bluray' }
$script:CancelRequested = $false
$script:Encoding = $false
$script:Ps      = $null
$script:Rs      = $null
$script:Async   = $null
$script:Timer   = $null
$script:InfoIdx = 0
$script:WarnIdx = 0
$script:ProbeSize  = if ($Script:M2tsProbeSize)  { $Script:M2tsProbeSize }  else { '100000000' }
$script:AnalyzeDur = if ($Script:M2tsAnalyzeDur) { $Script:M2tsAnalyzeDur } else { '300000000' }
$script:OutFile = $null
$script:OverFile = $null
# Async preview probe state (keeps ffprobe off the UI thread).
$script:PreviewPs    = $null
$script:PreviewRs    = $null
$script:PreviewAsync = $null
$script:PreviewTimer = $null

# Languages come from the BRTrackMeta sidecar (MakeMKV-sourced), resolved on the
# UI thread via Resolve-SidecarLanguages using BRencoder's own loader. The preview
# runspace only runs ffprobe, so a plain default session state is enough.
$script:PreviewIss = [initialsessionstate]::CreateDefault2()

$script:PreviewScript = {
    # ffprobe only: codecs, bitrate, disposition, commentary guess. Raw .m2ts has
    # no language tags, so languages are overlaid on the UI thread from the
    # BRTrackMeta sidecar (see Resolve-SidecarLanguages). Returns plain row objects.
    $raw = & $FFprobe -v error -probesize $ProbeSize -analyzeduration $AnalyzeDur `
        -show_entries 'stream=index,id,codec_type,codec_name,bit_rate,disposition:stream_tags=language,title' `
        -of json -- $Path 2>$null
    if (-not $raw) { return }
    $json = $raw | ConvertFrom-Json

    $audio = @(); $subs = @()
    foreach ($s in @($json.streams)) {
        if     ($s.codec_type -eq 'audio')    { $audio += $s }
        elseif ($s.codec_type -eq 'subtitle') { $subs  += $s }
    }
    $subs = @($subs | Sort-Object { try { [int]([string]$_.id) } catch { 0 } })

    # Commentary guess: a language with >=2 audio tracks -> the lowest-bitrate
    # one under ~512 kbps is probably the commentary. Just a guess to pre-tick.
    $byLang = @{}
    foreach ($s in $audio) {
        $l = if ($s.tags.language) { $s.tags.language } else { 'und' }
        $br = 0; if ($s.bit_rate -and $s.bit_rate -ne 'N/A') { try { $br = [int]$s.bit_rate } catch { $br = 0 } }
        if (-not $byLang.ContainsKey($l)) { $byLang[$l] = New-Object System.Collections.Generic.List[object] }
        $byLang[$l].Add([pscustomobject]@{ Idx = $s.index; Br = $br })
    }
    $commGuess = @{}
    foreach ($l in $byLang.Keys) {
        if ($byLang[$l].Count -ge 2) {
            $low = $byLang[$l] | Where-Object { $_.Br -gt 0 } | Sort-Object Br | Select-Object -First 1
            if ($low -and $low.Br -lt 512000) { $commGuess["$($low.Idx)"] = $true }
        }
    }

    $rows = New-Object System.Collections.Generic.List[object]
    $ai = 0
    foreach ($s in $audio) {
        $ai++
        $rows.Add([pscustomobject]@{
            Track = ('a{0}' -f $ai); Type = 'audio'; Codec = $s.codec_name
            Lang = $(if ($s.tags.language) { $s.tags.language } else { 'und' })
            Forced = [bool]($s.disposition.forced); Default = [bool]($s.disposition.'default')
            Commentary = [bool]$commGuess["$($s.index)"]; Title = $s.tags.title
        })
    }
    $si = 0
    foreach ($s in $subs) {
        $si++
        $rows.Add([pscustomobject]@{
            Track = ('s{0}' -f $si); Type = 'subtitle'; Codec = $s.codec_name
            Lang = $(if ($s.tags.language) { $s.tags.language } else { 'und' })
            Forced = [bool]($s.disposition.forced); Default = [bool]($s.disposition.'default')
            Commentary = $false; Title = $s.tags.title
        })
    }
    $rows
}

function Get-SourceM2tsList {
    # Reuse BRencoder's own discovery when available; fall back to a scan.
    if (Get-Command Get-M2tsFiles -ErrorAction SilentlyContinue) {
        try { return @(Get-M2tsFiles) } catch { }
    }
    if (Test-Path -LiteralPath $script:InputRoot) {
        return @(Get-ChildItem -Path $script:InputRoot -Recurse -Filter *.m2ts -File |
                 Sort-Object Length -Descending)
    }
    return @()
}

function Stop-PreviewProbe {
    if ($script:PreviewTimer) { try { $script:PreviewTimer.Stop() } catch { } }
    if ($script:PreviewPs) { try { $script:PreviewPs.Stop() } catch { }; try { $script:PreviewPs.Dispose() } catch { } }
    if ($script:PreviewRs) { try { $script:PreviewRs.Dispose() } catch { } }
    $script:PreviewPs = $null; $script:PreviewRs = $null
    $script:PreviewAsync = $null; $script:PreviewTimer = $null
}

# ----------------------------------------------------------------
# UI
# ----------------------------------------------------------------
function Get-DurationSeconds {
    param([string]$Path)
    try {
        $d = & $script:FFprobe -v error -show_entries format=duration -of csv=p=0 -- "$Path" 2>$null
        if ($d) { return [double]$d }
    } catch { }
    return 0
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "BRencoder GUI  v0.8"
$form.Size = New-Object System.Drawing.Size(1000, 700)
$form.StartPosition = 'CenterScreen'
$form.MinimumSize = New-Object System.Drawing.Size(860, 560)
$form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 34)
$form.ForeColor = [System.Drawing.Color]::Gainsboro
$mono = New-Object System.Drawing.Font('Consolas', 9)

# --- source file list ---
$lblFiles = New-Object System.Windows.Forms.Label
$lblFiles.Text = "Source .m2ts"
$lblFiles.Location = '12,10'; $lblFiles.AutoSize = $true
$form.Controls.Add($lblFiles)

$lstFiles = New-Object System.Windows.Forms.ListBox
$lstFiles.Location = '12,30'; $lstFiles.Size = '320,470'
$lstFiles.Font = $mono
$lstFiles.BackColor = [System.Drawing.Color]::FromArgb(22, 22, 26)
$lstFiles.ForeColor = [System.Drawing.Color]::Gainsboro
$form.Controls.Add($lstFiles)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = "Refresh"; $btnRefresh.Location = '12,506'; $btnRefresh.Size = '100,28'
$form.Controls.Add($btnRefresh)

# --- movie name ---
$lblName = New-Object System.Windows.Forms.Label
$lblName.Text = "Movie name"
$lblName.Location = '352,10'; $lblName.AutoSize = $true
$form.Controls.Add($lblName)

$txtName = New-Object System.Windows.Forms.TextBox
$txtName.Location = '352,30'; $txtName.Size = '618,24'
$txtName.Font = $mono
$txtName.BackColor = [System.Drawing.Color]::FromArgb(22, 22, 26)
$txtName.ForeColor = [System.Drawing.Color]::Gainsboro
$form.Controls.Add($txtName)

# --- track preview grid ---
$lblGrid = New-Object System.Windows.Forms.Label
$lblGrid.Text = "Tracks (audio + subtitle languages from BRTrackMeta sidecar)"
$lblGrid.Location = '352,62'; $lblGrid.AutoSize = $true
$form.Controls.Add($lblGrid)

$grid = New-Object System.Windows.Forms.DataGridView
$grid.Location = '352,84'; $grid.Size = '618,260'
$grid.AllowUserToAddRows = $false
$grid.ReadOnly = $false
$grid.RowHeadersVisible = $false
$grid.AutoSizeColumnsMode = 'Fill'
$grid.BackgroundColor = [System.Drawing.Color]::FromArgb(22, 22, 26)
$grid.ForeColor = [System.Drawing.Color]::Black
$grid.Font = $mono
$grid.EditMode = 'EditOnKeystrokeOrF2'
function Add-GridCol {
    param([string]$Name, [switch]$Check, [switch]$ReadOnlyCol, [int]$Weight = 60)
    $col = if ($Check) { New-Object System.Windows.Forms.DataGridViewCheckBoxColumn }
           else        { New-Object System.Windows.Forms.DataGridViewTextBoxColumn }
    $col.Name = $Name; $col.HeaderText = $Name; $col.ReadOnly = [bool]$ReadOnlyCol; $col.FillWeight = $Weight
    [void]$grid.Columns.Add($col)
}
Add-GridCol 'Track'   -ReadOnlyCol -Weight 38
Add-GridCol 'Type'    -ReadOnlyCol -Weight 55
Add-GridCol 'Codec'   -ReadOnlyCol -Weight 60
Add-GridCol 'Lang'    -Weight 42
Add-GridCol 'Forced'  -Check -Weight 50
Add-GridCol 'Default' -Check -Weight 52
Add-GridCol 'Comm'    -Check -Weight 50
Add-GridCol 'Title'   -Weight 150
$form.Controls.Add($grid)

# --- log + progress ---
$log = New-Object System.Windows.Forms.RichTextBox
$log.Location = '352,356'; $log.Size = '618,228'
$log.ReadOnly = $true
$log.Font = $mono
$log.BackColor = [System.Drawing.Color]::FromArgb(16, 16, 20)
$log.ForeColor = [System.Drawing.Color]::FromArgb(170, 220, 170)
$form.Controls.Add($log)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = '352,590'; $progress.Size = '460,22'
$progress.Style = 'Continuous'
$form.Controls.Add($progress)

$lblStat = New-Object System.Windows.Forms.Label
$lblStat.Location = '352,616'; $lblStat.Size = '460,18'
$lblStat.Font = $mono; $lblStat.Text = ''
$form.Controls.Add($lblStat)

$btnEncode = New-Object System.Windows.Forms.Button
$btnEncode.Text = "Encode"; $btnEncode.Location = '820,588'; $btnEncode.Size = '72,26'
$btnEncode.BackColor = [System.Drawing.Color]::FromArgb(40, 90, 50)
$form.Controls.Add($btnEncode)

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = "Cancel"; $btnCancel.Location = '898,588'; $btnCancel.Size = '72,26'
$btnCancel.Enabled = $false
$btnCancel.BackColor = [System.Drawing.Color]::FromArgb(110, 45, 45)
$form.Controls.Add($btnCancel)

# ----------------------------------------------------------------
# UI helpers (thread-safe)
# ----------------------------------------------------------------
function Add-Log {
    param([string]$Text)
    $sb = { $log.AppendText("$Text`r`n"); $log.ScrollToCaret() }.GetNewClosure()
    if ($log.IsHandleCreated -and $log.InvokeRequired) {
        [void]$log.BeginInvoke([System.Windows.Forms.MethodInvoker]$sb)
    } else {
        & $sb
    }
}
function Set-Progress {
    param([int]$Pct)
    if ($Pct -lt 0) { $Pct = 0 } elseif ($Pct -gt 100) { $Pct = 100 }
    $sb = { $progress.Value = $Pct }.GetNewClosure()
    if ($progress.IsHandleCreated -and $progress.InvokeRequired) {
        [void]$progress.BeginInvoke([System.Windows.Forms.MethodInvoker]$sb)
    } else {
        & $sb
    }
}

function Resolve-SidecarLanguages {
    # Overlay audio/subtitle languages (and forced/default/name) onto the probed
    # rows from the BRTrackMeta sidecar -- the same MakeMKV-sourced JSON the
    # encoder reads. Mutates $Rows in place; returns a one-line status for the log.
    param([object[]]$Rows, [System.IO.FileInfo]$File, [string]$Name)

    if (-not $Rows -or @($Rows).Count -eq 0) { return $null }
    if (-not $File) { return $null }
    if (-not (Get-Command Load-TrackMetadata -ErrorAction SilentlyContinue)) {
        return "    meta: BRencoder metadata loader unavailable"
    }
    if ([string]::IsNullOrWhiteSpace($Name)) {
        $Name = [System.IO.Path]::GetFileNameWithoutExtension($File.Name)
    }

    $mi = $null
    try { $mi = Load-TrackMetadata -SourceFile $File -MovieName $Name }
    catch { return "    meta: lookup error: $($_.Exception.Message)" }
    if (-not $mi) {
        return "    meta: no BRTrackMeta sidecar for '$Name' - run Blu-ray Track Dump, or type the movie name / edit Lang below"
    }

    $title = $null
    try { $title = Get-TrackMetaTitle -Meta $mi.Data } catch { }
    if (-not $title) { return "    meta: $([System.IO.Path]::GetFileName($mi.Path)) has no title data" }

    $aMeta = @(Resolve-TrackList -Title $title -Kind audio)
    $sMeta = @(Resolve-TrackList -Title $title -Kind subtitle)
    $ai = 0; $si = 0
    foreach ($r in $Rows) {
        if ($r.Type -eq 'audio') {
            if ($ai -lt $aMeta.Count) {
                $t = $aMeta[$ai]
                $lang = Get-MetaLanguage -Track $t
                if ($lang -and $lang -ne 'und') { $r.Lang = $lang }
                if ([bool]$t.Default) { $r.Default = $true }
                if ([string]::IsNullOrWhiteSpace([string]$r.Title)) {
                    $nm = Get-MetaTrackName -Track $t; if ($nm) { $r.Title = $nm }
                }
            }
            $ai++
        }
        elseif ($r.Type -eq 'subtitle') {
            if ($si -lt $sMeta.Count) {
                $t = $sMeta[$si]
                $lang = Get-MetaLanguage -Track $t
                if ($lang -and $lang -ne 'und') { $r.Lang = $lang }
                if ([bool]$t.Forced)  { $r.Forced  = $true }
                if ([bool]$t.Default) { $r.Default = $true }
                if ([string]::IsNullOrWhiteSpace([string]$r.Title)) {
                    $nm = Get-MetaTrackName -Track $t; if ($nm) { $r.Title = $nm }
                }
            }
            $si++
        }
    }

    $aProbe = @($Rows | Where-Object { $_.Type -eq 'audio' }).Count
    $sProbe = @($Rows | Where-Object { $_.Type -eq 'subtitle' }).Count
    $note = "    meta: $([System.IO.Path]::GetFileName($mi.Path)) -> $($aMeta.Count) audio / $($sMeta.Count) subtitle langs"
    if ($aMeta.Count -ne $aProbe -or $sMeta.Count -ne $sProbe) {
        $note += " (probe has $aProbe/$sProbe - mapped by order)"
    }
    return $note
}

function Load-Files {
    $lstFiles.Items.Clear()
    $script:Files = Get-SourceM2tsList
    foreach ($f in $script:Files) {
        $gb = [math]::Round($f.Length / 1GB, 2)
        [void]$lstFiles.Items.Add(("{0}  [{1} GB]" -f $f.Name, $gb))
    }
    if ($lstFiles.Items.Count -gt 0) { $lstFiles.SelectedIndex = 0 }
}

function Load-Preview {
    $i = $lstFiles.SelectedIndex
    $grid.Rows.Clear()
    if ($i -lt 0 -or $i -ge $script:Files.Count) { return }
    $file = $script:Files[$i]
    $script:PreviewFile = $file
    if (-not $txtName.Text) {
        $txtName.Text = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
    }
    [void]$grid.Rows.Add('...', 'probing', '', '', $false, $false, $false, $file.Name)

    # Supersede any in-flight probe, then run this one off the UI thread.
    Stop-PreviewProbe
    try {
        $rs = [runspacefactory]::CreateRunspace($script:PreviewIss)
        $rs.ApartmentState = 'MTA'; $rs.Open()
        $rs.SessionStateProxy.SetVariable('FFprobe',    $script:FFprobe)
        $rs.SessionStateProxy.SetVariable('Path',       $file.FullName)
        $rs.SessionStateProxy.SetVariable('ProbeSize',  $script:ProbeSize)
        $rs.SessionStateProxy.SetVariable('AnalyzeDur', $script:AnalyzeDur)
        $ps = [powershell]::Create(); $ps.Runspace = $rs
        [void]$ps.AddScript($script:PreviewScript)
        $script:PreviewPs = $ps; $script:PreviewRs = $rs
        $script:PreviewAsync = $ps.BeginInvoke()
    }
    catch {
        Add-Log ("    preview setup error: {0}: {1}" -f $_.Exception.GetType().Name, $_.Exception.Message)
        return
    }

    $t = New-Object System.Windows.Forms.Timer
    $t.Interval = 150
    $script:PreviewTimer = $t
    $t.Add_Tick({
        if (-not ($script:PreviewAsync -and $script:PreviewAsync.IsCompleted)) { return }
        $script:PreviewTimer.Stop()
        try {
            $rows = @()
            try { $rows = @($script:PreviewPs.EndInvoke($script:PreviewAsync)) }
            catch { Add-Log "    preview probe error: $($_.Exception.Message)" }
            try { $script:PreviewPs.Dispose() } catch { }
            try { $script:PreviewRs.Dispose() } catch { }
            $script:PreviewPs = $null; $script:PreviewRs = $null
            $script:PreviewAsync = $null; $script:PreviewTimer = $null

            $status = Resolve-SidecarLanguages -Rows $rows -File $script:PreviewFile -Name $txtName.Text
            if ($status) { Add-Log $status }

            $grid.Rows.Clear()
            foreach ($r in $rows) {
                [void]$grid.Rows.Add($r.Track, $r.Type, $r.Codec, $r.Lang,
                    [bool]$r.Forced, [bool]$r.Default, [bool]$r.Commentary, $r.Title)
            }
        }
        catch {
            Add-Log ("    preview render error: {0}: {1}" -f $_.Exception.GetType().Name, $_.Exception.Message)
        }
    })
    $t.Start()
}

# ----------------------------------------------------------------
# Encode on a background runspace, streaming progress to the UI.
# Reuses BRencoder's Encode-File. The runspace inherits the same
# session functions because we re-dot-source inside it.
# ----------------------------------------------------------------
function Get-OverridesJson {
    # Serialize the (possibly user-edited) grid into BRencoder's overrides
    # schema: per-type 1-based n; name only when the Title cell is non-empty.
    $grid.EndEdit() | Out-Null
    $list = New-Object System.Collections.Generic.List[object]
    $an = 0; $sn = 0
    foreach ($row in $grid.Rows) {
        if ($row.IsNewRow) { continue }
        $type = [string]$row.Cells['Type'].Value
        if ($type -ne 'audio' -and $type -ne 'subtitle') { continue }
        if ($type -eq 'audio') { $an++; $n = $an } else { $sn++; $n = $sn }
        $lang  = ([string]$row.Cells['Lang'].Value).Trim()
        $title = ([string]$row.Cells['Title'].Value).Trim()
        $o = [ordered]@{
            type       = $type
            n          = $n
            lang       = if ($lang) { $lang } else { 'und' }
            forced     = [bool]$row.Cells['Forced'].Value
            default    = [bool]$row.Cells['Default'].Value
            commentary = [bool]$row.Cells['Comm'].Value
        }
        if ($title) { $o['name'] = $title }
        $list.Add([pscustomobject]$o)
    }
    return (,$list | ConvertTo-Json -Depth 4)
}

function Start-Encode {
    if ($script:Encoding) { return }
    $i = $lstFiles.SelectedIndex
    if ($i -lt 0) { return }
    $file = $script:Files[$i]
    $name = $txtName.Text.Trim()
    if (-not $name) { $name = [System.IO.Path]::GetFileNameWithoutExtension($file.Name) }

    $script:OutFile = $null
    if (Get-Command Get-OutputPath -ErrorAction SilentlyContinue) {
        try { $script:OutFile = Get-OutputPath -MovieName $name } catch { }
    }

    # The grid must hold a finished probe (not the 'probing' placeholder).
    $probing = $false; $haveRows = $false
    foreach ($row in $grid.Rows) {
        if ($row.IsNewRow) { continue }
        $haveRows = $true
        if ([string]$row.Cells['Type'].Value -eq 'probing') { $probing = $true }
    }
    if (-not $haveRows -or $probing) {
        [System.Windows.Forms.MessageBox]::Show(
            'Track preview is still loading - wait a moment, then Encode.',
            'BRencoder GUI', 'OK', 'Information') | Out-Null
        return
    }
    $script:OverFile = Join-Path $env:TEMP ('brencoder-over-{0}.json' -f ([guid]::NewGuid().ToString('N')))
    try { (Get-OverridesJson) | Set-Content -LiteralPath $script:OverFile -Encoding UTF8 }
    catch { Add-Log "    (could not write overrides: $($_.Exception.Message))"; $script:OverFile = $null }

    $script:Encoding = $true
    $script:CancelRequested = $false
    $script:InfoIdx = 0; $script:WarnIdx = 0
    $btnEncode.Enabled = $false; $btnCancel.Enabled = $true
    $script:TotalSeconds = Get-DurationSeconds -Path $file.FullName
    $script:ProgFile = Join-Path $env:TEMP ('brencoder-progress-{0}.txt' -f ([guid]::NewGuid().ToString('N')))
    Remove-Item -LiteralPath $script:ProgFile -ErrorAction SilentlyContinue
    $progress.Style = 'Continuous'; Set-Progress 0
    $lblStat.Text = ''
    Add-Log "==> Encoding '$name'"
    Add-Log "    $($file.FullName)"
    if ($script:TotalSeconds -le 0) { Add-Log '    (duration unknown - bar stays at 0)' }

    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'MTA'
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('BREncoderPath', $BREncoderPath)
    $rs.SessionStateProxy.SetVariable('SourceFull',    $file.FullName)
    $rs.SessionStateProxy.SetVariable('MovieName',     $name)
    $rs.SessionStateProxy.SetVariable('ProgressFile',  $script:ProgFile)
    $rs.SessionStateProxy.SetVariable('OverridesFile', $script:OverFile)

    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript({
        $env:BRENCODER_NOMENU = '1'
        . $BREncoderPath
        $fi = Get-Item -LiteralPath $SourceFull
        $ovr = if ($OverridesFile) { @{ OverridesFile = $OverridesFile } } else { @{} }
        Encode-File -SourceFile $fi -MovieName $MovieName -AutoAccept -ProgressFile $ProgressFile @ovr
    })

    # Keep handles in script scope so the timer/cancel/close can reach them
    # reliably after this function returns (a closure over locals would not).
    $script:Ps = $ps; $script:Rs = $rs
    $script:Async = $ps.BeginInvoke()

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 750
    $script:Timer = $timer
    $timer.Add_Tick({
        # --- live output from the encode runspace (Write-Host -> Information) ---
        if ($script:Ps) {
            $inf = $script:Ps.Streams.Information
            while ($script:InfoIdx -lt $inf.Count) { Add-Log ('    ' + $inf[$script:InfoIdx].ToString()); $script:InfoIdx++ }
            $wrn = $script:Ps.Streams.Warning
            while ($script:WarnIdx -lt $wrn.Count) { Add-Log ('    WARN ' + $wrn[$script:WarnIdx].ToString()); $script:WarnIdx++ }
        }
        # --- progress from the ffmpeg -progress file ---
        if ($script:TotalSeconds -gt 0 -and (Test-Path -LiteralPath $script:ProgFile)) {
            try {
                $tail = Get-Content -LiteralPath $script:ProgFile -Tail 16 -ErrorAction SilentlyContinue
                $secs = $null
                $ln = $tail | Where-Object { $_ -like 'out_time_us=*' } | Select-Object -Last 1
                if ($ln) { $secs = [double]($ln -replace 'out_time_us=','') / 1e6 }
                if ($null -eq $secs) { $ln = $tail | Where-Object { $_ -like 'out_time_ms=*' } | Select-Object -Last 1; if ($ln) { $secs = [double]($ln -replace 'out_time_ms=','') / 1e6 } }
                if ($null -eq $secs) {
                    $ln = $tail | Where-Object { $_ -like 'out_time=*' } | Select-Object -Last 1
                    if ($ln -and (($ln -replace 'out_time=','').Trim() -match '^(\d+):(\d+):(\d+(?:\.\d+)?)$')) {
                        $secs = [double]$matches[1]*3600 + [double]$matches[2]*60 + [double]$matches[3]
                    }
                }
                if ($null -ne $secs) {
                    $pct = [int](($secs / $script:TotalSeconds) * 100); if ($pct -gt 100) { $pct = 100 }
                    Set-Progress $pct
                    $sp = $tail | Where-Object { $_ -like 'speed=*' } | Select-Object -Last 1
                    $fr = $tail | Where-Object { $_ -like 'frame=*' } | Select-Object -Last 1
                    $spd = if ($sp) { ($sp -replace 'speed=','').Trim() } else { '' }
                    $frm = if ($fr) { ($fr -replace 'frame=','').Trim() } else { '' }
                    $lblStat.Text = "  $pct%   speed $spd   frame $frm"
                }
            } catch { }
        }
        # --- completion ---
        if ($script:Async -and $script:Async.IsCompleted) {
            $script:Timer.Stop()
            $threw = $false
            try { $script:Ps.EndInvoke($script:Async) } catch { $threw = $true; Add-Log "    ERROR: $($_.Exception.Message)" }
            $inf = $script:Ps.Streams.Information
            while ($script:InfoIdx -lt $inf.Count) { Add-Log ('    ' + $inf[$script:InfoIdx].ToString()); $script:InfoIdx++ }
            if ($threw) {
                foreach ($er in (@($script:Ps.Streams.Error) | Select-Object -Last 10)) { Add-Log "    ERR  $er" }
            }
            try { $script:Ps.Dispose() } catch { }
            try { $script:Rs.Dispose() } catch { }
            Remove-Item -LiteralPath $script:ProgFile -ErrorAction SilentlyContinue
            if ($script:OverFile) { Remove-Item -LiteralPath $script:OverFile -ErrorAction SilentlyContinue; $script:OverFile = $null }
            $script:Ps = $null; $script:Rs = $null; $script:Async = $null; $script:Timer = $null
            $script:Encoding = $false
            if ($script:CancelRequested) {
                if ($script:OutFile -and (Test-Path -LiteralPath $script:OutFile)) {
                    Remove-Item -LiteralPath $script:OutFile -Force -ErrorAction SilentlyContinue
                    Add-Log "    removed partial output: $script:OutFile"
                }
                Add-Log '==> Cancelled.'; Set-Progress 0
            }
            elseif ($threw)              { Add-Log '==> Failed (see errors above).' }
            else                         { Set-Progress 100; Add-Log '==> Done.' }
            $lblStat.Text = ''
            $btnEncode.Enabled = $true; $btnCancel.Enabled = $false
            Load-Preview
        }
    })
    $timer.Start()
}

function Stop-Encode {
    if (-not $script:Encoding) { return }
    $script:CancelRequested = $true
    $btnCancel.Enabled = $false
    Add-Log '==> Cancelling - terminating ffmpeg...'
    # The encode runspace is in-process, so ffmpeg is a direct child of THIS
    # process. Kill ffmpeg children of $PID (leaves ffprobe and the GUI alone).
    try {
        Get-CimInstance Win32_Process -Filter "Name='ffmpeg.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.ParentProcessId -eq $PID } |
            ForEach-Object {
                Add-Log "    kill ffmpeg PID $($_.ProcessId)"
                Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
            }
    } catch { Add-Log "    (ffmpeg enumeration failed: $($_.Exception.Message))" }
    if ($script:Ps) { try { $script:Ps.Stop() } catch { } }
}

# ----------------------------------------------------------------
# Wire events
# ----------------------------------------------------------------
$btnRefresh.Add_Click({ Load-Files; Load-Preview })
$lstFiles.Add_SelectedIndexChanged({ $txtName.Clear(); Load-Preview })
$btnEncode.Add_Click({ Start-Encode })
$btnCancel.Add_Click({ Stop-Encode })

$form.Add_Shown({ Load-Files; Load-Preview; Add-Log "Loaded BRencoder from $BREncoderPath" })
$form.Add_FormClosing({
    param($s, $e)
    Stop-PreviewProbe
    if ($script:Encoding) {
        $r = [System.Windows.Forms.MessageBox]::Show(
            'An encode is still running. Stop ffmpeg and quit?',
            'BRencoder GUI', 'YesNo', 'Warning')
        if ($r -ne 'Yes') { $e.Cancel = $true; return }
        if ($script:Timer) { try { $script:Timer.Stop() } catch { } }
        Stop-Encode
        if ($script:Ps) { try { $script:Ps.Dispose() } catch { } }
        if ($script:Rs) { try { $script:Rs.Dispose() } catch { } }
        if ($script:ProgFile) { Remove-Item -LiteralPath $script:ProgFile -ErrorAction SilentlyContinue }
        if ($script:OverFile) { Remove-Item -LiteralPath $script:OverFile -ErrorAction SilentlyContinue }
        $script:Encoding = $false
    }
})

[void]$form.ShowDialog()
