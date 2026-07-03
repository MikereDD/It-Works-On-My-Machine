<#
================================================================
  DVD Ripper Encoder GUI  -  thin WinForms front end
  version:  1.1.0  by Mike Redd
----------------------------------------------------------------
  Reuses dvd-ripper-encoder.ps1's own functions (config,
  Encode-DvdTitle, sidecar I/O, language resolution, tool
  discovery) by dot-sourcing it. It does NOT reimplement the
  encode pipeline, so the mkvpropedit language remux, source
  archiving and NFO writing all stay in one place.

  REQUIRED one-time change in dvd-ripper-encoder.ps1 (already
  applied): the bottom startup/menu block is wrapped so
  dot-sourcing doesn't launch the CLI:

      if (-not $env:DVDENCODER_NOMENU) {
          try { Ensure-Dependencies; Ensure-Directories } ...
          while ($true) { Show-Header; Show-Menu; ... }
      }

  Then run:  powershell -ExecutionPolicy Bypass -STA -File dvd-ripper-encoder-gui.ps1
  (-STA is required for WinForms.)
================================================================
#>

[CmdletBinding()]
param(
    # Path to dvd-ripper-encoder.ps1. If not given, try (in order):
    # next to this GUI, then the canonical deployed location, then a
    # sibling personaltools folder.
    [string]$DvdEncoderPath
)

if (-not $DvdEncoderPath) {
    $candidates = @(
        (Join-Path $PSScriptRoot 'dvd-ripper-encoder.ps1')
        (Join-Path $HOME 'PS\scripts\personaltools\dvd-ripper-encoder.ps1')
        (Join-Path (Split-Path $PSScriptRoot -Parent) 'personaltools\dvd-ripper-encoder.ps1')
    )
    $DvdEncoderPath = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    if (-not $DvdEncoderPath) { $DvdEncoderPath = $candidates[0] }
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ----------------------------------------------------------------
# Load the DVD encoder's functions without launching its menu.
# ----------------------------------------------------------------
$env:DVDENCODER_NOMENU = '1'
if (-not (Test-Path -LiteralPath $DvdEncoderPath)) {
    [System.Windows.Forms.MessageBox]::Show("dvd-ripper-encoder.ps1 not found at:`n$DvdEncoderPath",
        'DVD Encoder GUI', 'OK', 'Error') | Out-Null
    return
}
try {
    . $DvdEncoderPath
}
catch {
    [System.Windows.Forms.MessageBox]::Show("Failed to load dvd-ripper-encoder.ps1:`n$($_.Exception.Message)",
        'DVD Encoder GUI', 'OK', 'Error') | Out-Null
    return
}

# The CLI sets $ErrorActionPreference='Stop' at its top; keep the UI thread
# forgiving so a stray non-terminating error can't tear down the form. The
# encode runspace re-dot-sources the CLI, so it keeps Stop where it matters.
$ErrorActionPreference = 'Continue'

# ----------------------------------------------------------------
# Pull config + tools from the CLI (resolved via its own helpers).
# Run dependency setup once so GUI scans get the same libdvdcss self-healing
# as the CLI menu path.
# ----------------------------------------------------------------
try { Ensure-Dependencies; Ensure-Directories } catch { }
$script:HandBrakeCLI = $null
$script:MkvPropEdit  = $null
$script:MkvMerge     = $null
try { $script:HandBrakeCLI = Get-HandBrakeCLIPath } catch { }
try { $script:MkvPropEdit  = Get-MkvPropEditPath }  catch { }
try { $script:MkvMerge     = Get-MkvMergePath }     catch { }

$script:OutputRoot   = if ($Script:OutputRoot)      { $Script:OutputRoot }      else { 'G:\Rip\dvdarchive' }
$script:MetaRoot     = if ($Script:MetaRoot)        { $Script:MetaRoot }        else { 'G:\Rip\meta' }
$script:SourceRoot   = if ($Script:SourceRoot)      { $Script:SourceRoot }      else { 'G:\Rip\dvdsource' }
$script:DefaultEnc   = if ($Script:DefaultEncoder)  { $Script:DefaultEncoder }  else { 'x265_10bit' }
$script:MinTitleSecs = if ($Script:MinTitleSeconds) { $Script:MinTitleSeconds } else { 900 }

# runspace / async state (script scope so timers + cancel can reach it)
$script:Titles      = @()
$script:CurrentTitle = $null
$script:Encoding    = $false
$script:CancelRequested = $false
$script:Ps = $null; $script:Rs = $null; $script:Async = $null; $script:Timer = $null
$script:InfoIdx = 0; $script:WarnIdx = 0
$script:ScanPs = $null; $script:ScanRs = $null; $script:ScanAsync = $null; $script:ScanTimer = $null

# ----------------------------------------------------------------
# Small GUI-side helpers
# ----------------------------------------------------------------
function Strip-Ansi { param([string]$s); if (-not $s) { return '' }; return [regex]::Replace($s, "\x1b\[[0-9;]*[A-Za-z]", '') }

function Get-OpticalDrives {
    $d = @()
    try { $d = @(Get-CimInstance Win32_CDROMDrive -ErrorAction Stop | Where-Object { $_.Drive } | ForEach-Object { $_.Drive }) } catch { }
    if (-not $d -or $d.Count -eq 0) { $d = @('D:') }
    return $d
}

function Get-CodecFromDesc {
    param([string]$Kind, [string]$Desc)
    if ($Kind -eq 'audio') {
        if ($Desc -match '\b(TrueHD|E?AC-?3|DTS(?:-HD)?|AAC|MP2|MP3|LPCM|PCM|FLAC|Vorbis)\b') { return $matches[1] }
    } else {
        if ($Desc -match '\b(VOBSUB|PGS|Bitmap|Text|CC|SRT)\b') { return $matches[1] }
    }
    return ''
}

# Pure scan parser (mirrors Invoke-HandBrakeScan's parsing, minus console output)
function ConvertFrom-HandBrakeScan {
    param([string]$ScanText)
    $titles = @(); $cur = $null; $section = $null
    foreach ($line in ($ScanText -split "`r?`n")) {
        if ($line -match '^\+\s+title\s+(\d+):') {
            if ($null -ne $cur) { $titles += [pscustomobject]$cur }
            $cur = @{ Title = [int]$matches[1]; Duration = ''; AudioList = @(); SubtitleList = @() }
            $section = $null
        }
        if ($null -ne $cur) {
            if     ($line -match '^\s*\+\s+duration:\s+(.+)$')    { $cur.Duration = $matches[1].Trim() }
            elseif ($line -match '^\s*\+\s+audio tracks:\s*$')    { $section = 'audio' }
            elseif ($line -match '^\s*\+\s+subtitle tracks:\s*$') { $section = 'subtitle' }
            elseif ($line -match '^\s*\+\s+\w[\w ]*:\s*$')        { $section = $null }
            elseif ($line -match '^\s*\+\s+(\d+),\s*(.+)$') {
                $num = [int]$matches[1]; $desc = $matches[2].Trim()
                $lang = Get-TrackLangFromDesc -Desc $desc   # reused from the CLI
                $obj = [pscustomobject]@{ Num = $num; Lang = $lang.Label; Code = $lang.Code; Desc = $desc }
                if     ($section -eq 'audio')    { $cur.AudioList    += $obj }
                elseif ($section -eq 'subtitle') { $cur.SubtitleList += $obj }
            }
        }
    }
    if ($null -ne $cur) { $titles += [pscustomobject]$cur }
    return ,$titles
}

function Get-DurationSeconds2 {
    param([string]$Duration)
    if ($Duration -match '^\d{2}:\d{2}:\d{2}$') { return [int][TimeSpan]::Parse($Duration).TotalSeconds }
    return 0
}

function Get-CurrentSource {
    if ($rbDrive.Checked) {
        $d = [string]$cmbDrive.SelectedItem
        if ([string]::IsNullOrWhiteSpace($d)) { return $null }
        if ($d -notmatch ':$') { $d += ':' }
        if (-not (Test-Path -LiteralPath (Join-Path $d 'VIDEO_TS'))) { Add-Log "    No VIDEO_TS on $d"; return $null }
        return $d
    }
    $f = $txtFolder.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($f) -or -not (Test-Path -LiteralPath $f)) { Add-Log '    Folder not found.'; return $null }
    $vt = Join-Path $f 'VIDEO_TS'
    if (Test-Path -LiteralPath $vt) { return $vt }
    return $f
}

function Get-MovieName {
    $n = $txtName.Text.Trim()
    if (-not $n) { $n = "dvd_encode_$(Get-Date -Format 'yyyyMMdd_HHmmss')" }
    $y = $txtYear.Text.Trim()
    if ($y -match '^\d{4}$') { $n = "$n [$y]" }
    return $n
}

# ════════════════════════════════════════════════════════════════
#  FORM (dark theme, matching BRencoder GUI)
# ════════════════════════════════════════════════════════════════
$form = New-Object System.Windows.Forms.Form
$form.Text = 'DVD Ripper Encoder GUI  v1.1.0'
$form.Size = New-Object System.Drawing.Size(1240, 920)
$form.MinimumSize = New-Object System.Drawing.Size(1040, 840)
$form.StartPosition = 'CenterScreen'
$form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 34)
$form.ForeColor = [System.Drawing.Color]::Gainsboro
$mono = New-Object System.Drawing.Font('Consolas', 9)

$dark = [System.Drawing.Color]::FromArgb(22, 22, 26)

# --- source ---
$lblSource = New-Object System.Windows.Forms.Label
$lblSource.Text = 'Source'; $lblSource.Location = '12,10'; $lblSource.AutoSize = $true
$form.Controls.Add($lblSource)

$rbDrive = New-Object System.Windows.Forms.RadioButton
$rbDrive.Text = 'DVD'; $rbDrive.Location = '12,30'; $rbDrive.Size = '54,24'; $rbDrive.Checked = $true
$form.Controls.Add($rbDrive)
$cmbDrive = New-Object System.Windows.Forms.ComboBox
$cmbDrive.Location = '70,30'; $cmbDrive.Size = '80,24'; $cmbDrive.DropDownStyle = 'DropDownList'
$cmbDrive.BackColor = $dark; $cmbDrive.ForeColor = [System.Drawing.Color]::Gainsboro
$form.Controls.Add($cmbDrive)

$btnScan = New-Object System.Windows.Forms.Button
$btnScan.Text = 'Scan'; $btnScan.Location = '160,29'; $btnScan.Size = '172,26'
$btnScan.BackColor = [System.Drawing.Color]::FromArgb(40, 70, 110)
$form.Controls.Add($btnScan)

$rbFolder = New-Object System.Windows.Forms.RadioButton
$rbFolder.Text = 'Folder'; $rbFolder.Location = '12,58'; $rbFolder.Size = '66,24'
$form.Controls.Add($rbFolder)
$txtFolder = New-Object System.Windows.Forms.TextBox
$txtFolder.Location = '78,58'; $txtFolder.Size = '170,24'; $txtFolder.Enabled = $false
$txtFolder.BackColor = $dark; $txtFolder.ForeColor = [System.Drawing.Color]::Gainsboro; $txtFolder.Font = $mono
$form.Controls.Add($txtFolder)
$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = '…'; $btnBrowse.Location = '252,57'; $btnBrowse.Size = '80,26'; $btnBrowse.Enabled = $false
$form.Controls.Add($btnBrowse)

# --- titles list ---
$lblTitles = New-Object System.Windows.Forms.Label
$lblTitles.Text = 'Titles'; $lblTitles.Location = '12,92'; $lblTitles.AutoSize = $true
$form.Controls.Add($lblTitles)
$lstTitles = New-Object System.Windows.Forms.ListBox
$lstTitles.Location = '12,112'; $lstTitles.Size = '320,360'; $lstTitles.Anchor = 'Top, Left'
$lstTitles.Font = $mono; $lstTitles.BackColor = $dark; $lstTitles.ForeColor = [System.Drawing.Color]::Gainsboro
$form.Controls.Add($lstTitles)

# --- settings ---
$grpSet = New-Object System.Windows.Forms.GroupBox
$grpSet.Text = 'Encode settings'; $grpSet.Location = '12,480'; $grpSet.Size = '320,300'
$grpSet.ForeColor = [System.Drawing.Color]::Gainsboro; $grpSet.Anchor = 'Top, Left'
$form.Controls.Add($grpSet)

$lblRF = New-Object System.Windows.Forms.Label
$lblRF.Text = 'RF'; $lblRF.Location = '14,28'; $lblRF.AutoSize = $true; $grpSet.Controls.Add($lblRF)
$numRF = New-Object System.Windows.Forms.NumericUpDown
$numRF.Location = '110,26'; $numRF.Size = '60,24'; $numRF.Minimum = 16; $numRF.Maximum = 28; $numRF.Value = 20
$numRF.BackColor = $dark; $numRF.ForeColor = [System.Drawing.Color]::Gainsboro
$grpSet.Controls.Add($numRF)

$lblPreset = New-Object System.Windows.Forms.Label
$lblPreset.Text = 'Preset'; $lblPreset.Location = '14,60'; $lblPreset.AutoSize = $true; $grpSet.Controls.Add($lblPreset)
$cmbPreset = New-Object System.Windows.Forms.ComboBox
$cmbPreset.Location = '110,58'; $cmbPreset.Size = '120,24'; $cmbPreset.DropDownStyle = 'DropDownList'
[void]$cmbPreset.Items.AddRange(@('slow','slower','veryslow')); $cmbPreset.SelectedItem = 'slower'
$cmbPreset.BackColor = $dark; $cmbPreset.ForeColor = [System.Drawing.Color]::Gainsboro
$grpSet.Controls.Add($cmbPreset)

$lblCont = New-Object System.Windows.Forms.Label
$lblCont.Text = 'Container'; $lblCont.Location = '14,92'; $lblCont.AutoSize = $true; $grpSet.Controls.Add($lblCont)
$cmbCont = New-Object System.Windows.Forms.ComboBox
$cmbCont.Location = '110,90'; $cmbCont.Size = '120,24'; $cmbCont.DropDownStyle = 'DropDownList'
[void]$cmbCont.Items.AddRange(@('mkv','mp4')); $cmbCont.SelectedItem = 'mkv'
$cmbCont.BackColor = $dark; $cmbCont.ForeColor = [System.Drawing.Color]::Gainsboro
$grpSet.Controls.Add($cmbCont)

$lblTune = New-Object System.Windows.Forms.Label
$lblTune.Text = 'Tune'; $lblTune.Location = '14,124'; $lblTune.AutoSize = $true; $grpSet.Controls.Add($lblTune)
$cmbTune = New-Object System.Windows.Forms.ComboBox
$cmbTune.Location = '110,122'; $cmbTune.Size = '120,24'; $cmbTune.DropDownStyle = 'DropDownList'
[void]$cmbTune.Items.AddRange(@('auto','none','animation','grain')); $cmbTune.SelectedItem = 'auto'
$cmbTune.BackColor = $dark; $cmbTune.ForeColor = [System.Drawing.Color]::Gainsboro
$grpSet.Controls.Add($cmbTune)

$lblEnc = New-Object System.Windows.Forms.Label
$lblEnc.Text = "Encoder: $script:DefaultEnc"; $lblEnc.ForeColor = [System.Drawing.Color]::Gray
$lblEnc.Location = '14,156'; $lblEnc.AutoSize = $true; $grpSet.Controls.Add($lblEnc)

$chkArchive = New-Object System.Windows.Forms.CheckBox
$chkArchive.Text = 'Archive source VIDEO_TS'; $chkArchive.Location = '14,184'; $chkArchive.Size = '260,24'; $chkArchive.Checked = $true
$grpSet.Controls.Add($chkArchive)
$chkRemux = New-Object System.Windows.Forms.CheckBox
$chkRemux.Text = 'Tag languages (mkvpropedit)'; $chkRemux.Location = '14,210'; $chkRemux.Size = '260,24'; $chkRemux.Checked = $true
$grpSet.Controls.Add($chkRemux)
$chkDry = New-Object System.Windows.Forms.CheckBox
$chkDry.Text = 'Dry run'; $chkDry.Location = '14,236'; $chkDry.Size = '120,24'
$grpSet.Controls.Add($chkDry)

# --- movie name + year ---
$lblName = New-Object System.Windows.Forms.Label
$lblName.Text = 'Movie name'; $lblName.Location = '352,10'; $lblName.AutoSize = $true
$form.Controls.Add($lblName)
$txtName = New-Object System.Windows.Forms.TextBox
$txtName.Location = '352,30'; $txtName.Size = '740,24'; $txtName.Anchor = 'Top, Left, Right'
$txtName.Font = $mono; $txtName.BackColor = $dark; $txtName.ForeColor = [System.Drawing.Color]::Gainsboro
$form.Controls.Add($txtName)
$lblYear = New-Object System.Windows.Forms.Label
$lblYear.Text = 'Year'; $lblYear.Location = '1100,12'; $lblYear.AutoSize = $true; $lblYear.Anchor = 'Top, Right'
$form.Controls.Add($lblYear)
$txtYear = New-Object System.Windows.Forms.TextBox
$txtYear.Location = '1138,30'; $txtYear.Size = '70,24'; $txtYear.Anchor = 'Top, Right'
$txtYear.Font = $mono; $txtYear.BackColor = $dark; $txtYear.ForeColor = [System.Drawing.Color]::Gainsboro
$form.Controls.Add($txtYear)

# --- track grid ---
$lblGrid = New-Object System.Windows.Forms.Label
$lblGrid.Text = 'Tracks  (tick Incl to keep; edit Lang to fix undefined codes)'
$lblGrid.Location = '352,62'; $lblGrid.AutoSize = $true
$form.Controls.Add($lblGrid)

$grid = New-Object System.Windows.Forms.DataGridView
$grid.Location = '352,84'; $grid.Size = '856,440'; $grid.Anchor = 'Top, Bottom, Left, Right'
$grid.AllowUserToAddRows = $false
$grid.RowHeadersVisible = $false
$grid.AutoSizeColumnsMode = 'Fill'
$grid.BackgroundColor = $dark
$grid.ForeColor = [System.Drawing.Color]::Black
$grid.Font = $mono
$grid.EditMode = 'EditOnKeystrokeOrF2'
function Add-GridCol {
    param([string]$Name, [string]$Header, [switch]$Check, [switch]$ReadOnlyCol, [int]$Weight = 60)
    $col = if ($Check) { New-Object System.Windows.Forms.DataGridViewCheckBoxColumn } else { New-Object System.Windows.Forms.DataGridViewTextBoxColumn }
    $col.Name = $Name; $col.HeaderText = $Header; $col.ReadOnly = [bool]$ReadOnlyCol; $col.FillWeight = $Weight
    [void]$grid.Columns.Add($col)
}
Add-GridCol 'Track' 'Track' -ReadOnlyCol -Weight 38
Add-GridCol 'Type'  'Type'  -ReadOnlyCol -Weight 55
Add-GridCol 'Codec' 'Codec' -ReadOnlyCol -Weight 55
Add-GridCol 'Lang'  'Lang'  -Weight 45
Add-GridCol 'Incl'  'Incl'  -Check -Weight 40
Add-GridCol 'Desc'  'Description' -ReadOnlyCol -Weight 180
$form.Controls.Add($grid)

# --- log + progress ---
$log = New-Object System.Windows.Forms.RichTextBox
$log.Location = '352,536'; $log.Size = '856,250'; $log.Anchor = 'Bottom, Left, Right'
$log.ReadOnly = $true; $log.Font = $mono
$log.BackColor = [System.Drawing.Color]::FromArgb(16, 16, 20)
$log.ForeColor = [System.Drawing.Color]::FromArgb(170, 220, 170)
$form.Controls.Add($log)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = '352,798'; $progress.Size = '660,22'; $progress.Anchor = 'Bottom, Left'; $progress.Style = 'Continuous'
$form.Controls.Add($progress)
$lblStat = New-Object System.Windows.Forms.Label
$lblStat.Location = '352,824'; $lblStat.Size = '660,18'; $lblStat.Anchor = 'Bottom, Left'; $lblStat.Font = $mono; $lblStat.Text = ''
$form.Controls.Add($lblStat)

$btnEncode = New-Object System.Windows.Forms.Button
$btnEncode.Text = 'Encode'; $btnEncode.Location = '1058,797'; $btnEncode.Size = '72,26'; $btnEncode.Anchor = 'Bottom, Right'
$btnEncode.BackColor = [System.Drawing.Color]::FromArgb(40, 90, 50)
$form.Controls.Add($btnEncode)
$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = 'Cancel'; $btnCancel.Location = '1136,797'; $btnCancel.Size = '72,26'; $btnCancel.Anchor = 'Bottom, Right'; $btnCancel.Enabled = $false
$btnCancel.BackColor = [System.Drawing.Color]::FromArgb(110, 45, 45)
$form.Controls.Add($btnCancel)

# ----------------------------------------------------------------
# Thread-safe UI helpers
# ----------------------------------------------------------------
function Add-Log {
    param([string]$Text)
    $sb = { $log.AppendText("$Text`r`n"); $log.ScrollToCaret() }.GetNewClosure()
    if ($log.IsHandleCreated -and $log.InvokeRequired) { [void]$log.BeginInvoke([System.Windows.Forms.MethodInvoker]$sb) }
    else { & $sb }
}
function Set-Progress {
    param([int]$Pct)
    if ($Pct -lt 0) { $Pct = 0 } elseif ($Pct -gt 100) { $Pct = 100 }
    $sb = { $progress.Style = 'Continuous'; $progress.Value = $Pct }.GetNewClosure()
    if ($progress.IsHandleCreated -and $progress.InvokeRequired) { [void]$progress.BeginInvoke([System.Windows.Forms.MethodInvoker]$sb) }
    else { & $sb }
}

# ----------------------------------------------------------------
# Populate the grid from the selected title (+ sidecar overlay)
# ----------------------------------------------------------------
function Update-Grid {
    param($TitleObj)
    $grid.Rows.Clear()
    $script:CurrentTitle = $TitleObj
    if (-not $TitleObj) { return }

    $movie   = Get-MovieName
    $sidecar = $null
    try { $sidecar = Read-DvdTrackMeta -MovieName $movie } catch { }

    $ai = 0
    foreach ($a in $TitleObj.AudioList) {
        $ai++
        $code = Normalize-LanguageCode $a.Code
        if ((-not $code -or $code -eq 'und') -and $sidecar -and $sidecar.Audio.ContainsKey([int]$a.Num)) { $code = Normalize-LanguageCode ($sidecar.Audio[[int]$a.Num]) }
        if (-not $code) { $code = 'und' }
        $idx = $grid.Rows.Add(("a{0}" -f $ai), 'audio', (Get-CodecFromDesc 'audio' $a.Desc), $code, $true, $a.Desc)
        $grid.Rows[$idx].Tag = [pscustomobject]@{ Num = $a.Num; Kind = 'audio' }
    }
    $si = 0
    foreach ($s in $TitleObj.SubtitleList) {
        $si++
        $code = Normalize-LanguageCode $s.Code
        if ((-not $code -or $code -eq 'und') -and $sidecar -and $sidecar.Subtitle.ContainsKey([int]$s.Num)) { $code = Normalize-LanguageCode ($sidecar.Subtitle[[int]$s.Num]) }
        if (-not $code) { $code = 'und' }
        $idx = $grid.Rows.Add(("s{0}" -f $si), 'subtitle', (Get-CodecFromDesc 'subtitle' $s.Desc), $code, $true, $s.Desc)
        $grid.Rows[$idx].Tag = [pscustomobject]@{ Num = $s.Num; Kind = 'subtitle' }
    }
    if ($sidecar) { Add-Log "    meta: applied sidecar languages for '$movie' where undefined" }
}

# Read selections + resolved codes out of the (possibly edited) grid
function Get-GridSelections {
    $grid.EndEdit() | Out-Null
    $aNums = @(); $aCodes = @(); $aTotal = 0
    $sNums = @(); $sCodes = @(); $sTotal = 0
    foreach ($row in $grid.Rows) {
        if ($row.IsNewRow) { continue }
        $tag = $row.Tag; if (-not $tag) { continue }
        $lang = Normalize-LanguageCode ([string]$row.Cells['Lang'].Value); if (-not $lang) { $lang = 'und' }
        $incl = [bool]$row.Cells['Incl'].Value
        if ($tag.Kind -eq 'audio') { $aTotal++; if ($incl) { $aNums += [int]$tag.Num; $aCodes += $lang } }
        elseif ($tag.Kind -eq 'subtitle') { $sTotal++; if ($incl) { $sNums += [int]$tag.Num; $sCodes += $lang } }
    }
    $aSel = if ($aTotal -eq 0) { 'all' } elseif ($aNums.Count -eq 0) { 'none' } elseif ($aNums.Count -eq $aTotal) { 'all' } else { ($aNums -join ',') }
    $sSel = if ($sTotal -eq 0) { 'all' } elseif ($sNums.Count -eq 0) { 'none' } elseif ($sNums.Count -eq $sTotal) { 'all' } else { ($sNums -join ',') }
    return @{ AudioSel = $aSel; SubSel = $sSel; AudioCodes = $aCodes; SubCodes = $sCodes }
}

# ════════════════════════════════════════════════════════════════
#  Scan (background runspace, like BRencoder's preview probe)
# ════════════════════════════════════════════════════════════════

function Stop-HandBrakeChildren {
    param([string]$Reason = 'stopping')
    try {
        Get-CimInstance Win32_Process -Filter "Name='HandBrakeCLI.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.ParentProcessId -eq $PID } |
            ForEach-Object {
                Add-Log ("    {0} HandBrakeCLI PID {1}" -f $Reason, $_.ProcessId)
                Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
            }
    }
    catch { Add-Log "    (HandBrakeCLI enumeration failed: $($_.Exception.Message))" }
}

function Stop-Scan {
    if ($script:ScanTimer) { try { $script:ScanTimer.Stop() } catch { } }
    if (-not $script:Encoding) { Stop-HandBrakeChildren -Reason 'stop scan' }
    if ($script:ScanPs) { try { $script:ScanPs.Stop() } catch { }; try { $script:ScanPs.Dispose() } catch { } }
    if ($script:ScanRs) { try { $script:ScanRs.Dispose() } catch { } }
    $script:ScanPs = $null; $script:ScanRs = $null; $script:ScanAsync = $null; $script:ScanTimer = $null
}

function Start-Scan {
    if (-not $script:HandBrakeCLI) { [System.Windows.Forms.MessageBox]::Show('HandBrakeCLI not found.', 'DVD Encoder GUI') | Out-Null; return }
    if ($script:Encoding) { return }
    $src = Get-CurrentSource
    if (-not $src) { return }

    if ($rbDrive.Checked -and [string]::IsNullOrWhiteSpace($txtName.Text)) {
        $label = ''
        try { $label = Get-DvdVolumeLabel -DriveLetter ([string]$cmbDrive.SelectedItem) } catch { }
        if ($label) { $txtName.Text = $label }
    }

    $log.Clear()
    Add-Log "==> Scanning $src"
    $lstTitles.Items.Clear(); $grid.Rows.Clear()
    $btnScan.Enabled = $false; $btnEncode.Enabled = $false
    $progress.Style = 'Marquee'; $lblStat.Text = '  scanning titles...'

    Stop-Scan
    $rs = [runspacefactory]::CreateRunspace(); $rs.ApartmentState = 'MTA'; $rs.Open()
    $rs.SessionStateProxy.SetVariable('Cli', $script:HandBrakeCLI)
    $rs.SessionStateProxy.SetVariable('Input', $src)
    $rs.SessionStateProxy.SetVariable('MinDur', $script:MinTitleSecs)
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    [void]$ps.AddScript({
        $out = & $Cli --input $Input --title 0 --scan --min-duration $MinDur 2>&1
        ($out | Out-String)
    })
    $script:ScanPs = $ps; $script:ScanRs = $rs; $script:ScanAsync = $ps.BeginInvoke()

    $t = New-Object System.Windows.Forms.Timer; $t.Interval = 200; $script:ScanTimer = $t
    $t.Add_Tick({
        if (-not ($script:ScanAsync -and $script:ScanAsync.IsCompleted)) { return }
        $script:ScanTimer.Stop()
        $text = ''
        try { $text = [string]($script:ScanPs.EndInvoke($script:ScanAsync) | Out-String) } catch { Add-Log "    scan error: $($_.Exception.Message)" }
        try { $script:ScanPs.Dispose() } catch { }
        try { $script:ScanRs.Dispose() } catch { }
        $script:ScanPs = $null; $script:ScanRs = $null; $script:ScanAsync = $null; $script:ScanTimer = $null

        $script:Titles = @(ConvertFrom-HandBrakeScan -ScanText $text)
        $progress.Style = 'Continuous'; Set-Progress 0; $lblStat.Text = ''
        $btnScan.Enabled = $true; $btnEncode.Enabled = $true

        if (-not $script:Titles -or $script:Titles.Count -eq 0) { Add-Log '    No titles detected.'; return }
        $main = $script:Titles | Sort-Object { Get-DurationSeconds2 $_.Duration } -Descending | Select-Object -First 1
        foreach ($ti in ($script:Titles | Sort-Object Title)) {
            [void]$lstTitles.Items.Add(("Title {0}   {1}   (a:{2} s:{3})" -f $ti.Title, $ti.Duration, $ti.AudioList.Count, $ti.SubtitleList.Count))
        }
        for ($i = 0; $i -lt $lstTitles.Items.Count; $i++) {
            if ($lstTitles.Items[$i] -match ("^Title {0}\b" -f $main.Title)) { $lstTitles.SelectedIndex = $i; break }
        }
        Add-Log ("==> Found {0} title(s). Main: title {1} ({2})." -f $script:Titles.Count, $main.Title, $main.Duration)
    })
    $t.Start()
}

# ════════════════════════════════════════════════════════════════
#  Encode (background runspace, reusing the CLI's Encode-DvdTitle)
# ════════════════════════════════════════════════════════════════
function Start-Encode {
    if ($script:Encoding) { return }
    if (-not $script:HandBrakeCLI) { [System.Windows.Forms.MessageBox]::Show('HandBrakeCLI not found.', 'DVD Encoder GUI') | Out-Null; return }
    if (-not $script:CurrentTitle) { [System.Windows.Forms.MessageBox]::Show('Scan and pick a title first.', 'DVD Encoder GUI') | Out-Null; return }

    $src = Get-CurrentSource
    if (-not $src) { return }
    $movie = Get-MovieName
    $sel   = Get-GridSelections

    $tune = [string]$cmbTune.SelectedItem
    if ($tune -eq 'auto') { try { $tune = [string](Get-AutoTune -MovieName $movie).Tune } catch { $tune = '' } }
    if ($tune -eq 'none') { $tune = '' }

    # Refresh the sidecar (reuse the CLI's writer) so it documents the disc.
    try {
        $existing = Read-DvdTrackMeta -MovieName $movie
        [void](Write-DvdTrackMeta -MovieName $movie -Title $script:CurrentTitle.Title `
            -AudioList $script:CurrentTitle.AudioList -SubtitleList $script:CurrentTitle.SubtitleList -Existing $existing)
    } catch { Add-Log "    (sidecar write skipped: $($_.Exception.Message))" }

    $script:Encoding = $true; $script:CancelRequested = $false; $script:InfoIdx = 0; $script:WarnIdx = 0
    $btnEncode.Enabled = $false; $btnCancel.Enabled = $true; $btnScan.Enabled = $false
    $progress.Style = 'Marquee'; $lblStat.Text = '  encoding...'
    $log.Clear()
    Add-Log "==> Encoding '$movie'  (title $($script:CurrentTitle.Title))"
    if ($chkDry.Checked) { Add-Log '    DRY RUN' }

    $rs = [runspacefactory]::CreateRunspace(); $rs.ApartmentState = 'MTA'; $rs.Open()
    $rs.SessionStateProxy.SetVariable('CliPath',    $DvdEncoderPath)
    $rs.SessionStateProxy.SetVariable('InputPath',  $src)
    $rs.SessionStateProxy.SetVariable('TitleNum',   [int]$script:CurrentTitle.Title)
    $rs.SessionStateProxy.SetVariable('Movie',      $movie)
    $rs.SessionStateProxy.SetVariable('Tune',       [string]$tune)
    $rs.SessionStateProxy.SetVariable('Container',  [string]$cmbCont.SelectedItem)
    $rs.SessionStateProxy.SetVariable('RF',         [int]$numRF.Value)
    $rs.SessionStateProxy.SetVariable('Preset',     [string]$cmbPreset.SelectedItem)
    $rs.SessionStateProxy.SetVariable('AudioSel',   [string]$sel.AudioSel)
    $rs.SessionStateProxy.SetVariable('SubSel',     [string]$sel.SubSel)
    $rs.SessionStateProxy.SetVariable('AudioCodes', [string[]]$sel.AudioCodes)
    $rs.SessionStateProxy.SetVariable('SubCodes',   [string[]]$sel.SubCodes)
    $rs.SessionStateProxy.SetVariable('DoArchive',  [bool]$chkArchive.Checked)
    $rs.SessionStateProxy.SetVariable('DoRemux',    [bool]$chkRemux.Checked)
    $rs.SessionStateProxy.SetVariable('DoDry',      [bool]$chkDry.Checked)

    $ps = [powershell]::Create(); $ps.Runspace = $rs
    [void]$ps.AddScript({
        $env:DVDENCODER_NOMENU = '1'
        . $CliPath
        try { Ensure-Dependencies } catch { Write-Host "ERROR: $($_.Exception.Message)"; return }
        Ensure-Directories
        # Drive the CLI's encode flow non-interactively.
        $AutoAccept = $true
        $DryRun = [bool]$DoDry
        $Script:ArchiveSource = [bool]$DoArchive
        if (-not $DoRemux) { $Script:MkvPropEdit = $null }
        Encode-DvdTitle -InputPath $InputPath -TitleNumber $TitleNum -MovieName $Movie `
            -Tune $Tune -Container $Container -RF $RF -Preset $Preset `
            -AudioSelection $AudioSel -SubtitleSelection $SubSel `
            -AudioCodes $AudioCodes -SubtitleCodes $SubCodes
    })
    $script:Ps = $ps; $script:Rs = $rs; $script:Async = $ps.BeginInvoke()

    $timer = New-Object System.Windows.Forms.Timer; $timer.Interval = 500; $script:Timer = $timer
    $timer.Add_Tick({
        if ($script:Ps) {
            $inf = $script:Ps.Streams.Information
            while ($script:InfoIdx -lt $inf.Count) { Add-Log ('    ' + (Strip-Ansi $inf[$script:InfoIdx].ToString())); $script:InfoIdx++ }
            $wrn = $script:Ps.Streams.Warning
            while ($script:WarnIdx -lt $wrn.Count) { Add-Log ('    WARN ' + (Strip-Ansi $wrn[$script:WarnIdx].ToString())); $script:WarnIdx++ }
        }
        if ($script:Async -and $script:Async.IsCompleted) {
            $script:Timer.Stop()
            $threw = $false
            try { $script:Ps.EndInvoke($script:Async) } catch { $threw = $true; Add-Log "    ERROR: $($_.Exception.Message)" }
            $inf = $script:Ps.Streams.Information
            while ($script:InfoIdx -lt $inf.Count) { Add-Log ('    ' + (Strip-Ansi $inf[$script:InfoIdx].ToString())); $script:InfoIdx++ }
            if ($threw) { foreach ($er in (@($script:Ps.Streams.Error) | Select-Object -Last 8)) { Add-Log "    ERR  $er" } }
            try { $script:Ps.Dispose() } catch { }
            try { $script:Rs.Dispose() } catch { }
            $script:Ps = $null; $script:Rs = $null; $script:Async = $null; $script:Timer = $null
            $script:Encoding = $false
            $progress.Style = 'Continuous'
            if ($script:CancelRequested) { Add-Log '==> Cancelled.'; Set-Progress 0 }
            elseif ($threw)              { Add-Log '==> Failed (see errors above).'; Set-Progress 0 }
            else                         { Set-Progress 100; Add-Log '==> Done.' }
            $lblStat.Text = ''
            $btnEncode.Enabled = $true; $btnCancel.Enabled = $false; $btnScan.Enabled = $true
        }
    })
    $timer.Start()
}

function Stop-Encode {
    if (-not $script:Encoding) { return }
    $script:CancelRequested = $true
    $btnCancel.Enabled = $false
    Add-Log '==> Cancelling - terminating HandBrakeCLI...'
    Stop-HandBrakeChildren -Reason 'kill'
    if ($script:Ps) { try { $script:Ps.Stop() } catch { } }
}

# ----------------------------------------------------------------
# Wire events
# ----------------------------------------------------------------
$rbDrive.Add_CheckedChanged({ $cmbDrive.Enabled = $rbDrive.Checked; $txtFolder.Enabled = $rbFolder.Checked; $btnBrowse.Enabled = $rbFolder.Checked })
$btnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Select VIDEO_TS folder or its parent'
    if ($dlg.ShowDialog() -eq 'OK') { $txtFolder.Text = $dlg.SelectedPath }
})
$btnScan.Add_Click({ Start-Scan })
$lstTitles.Add_SelectedIndexChanged({
    $i = $lstTitles.SelectedIndex
    if ($i -lt 0) { return }
    $tnum = [int]([string]$lstTitles.Items[$i] -replace '^Title\s+(\d+).*$', '$1')
    $t = $script:Titles | Where-Object { $_.Title -eq $tnum } | Select-Object -First 1
    Update-Grid $t
})
$btnEncode.Add_Click({ Start-Encode })
$btnCancel.Add_Click({ Stop-Encode })

# ----------------------------------------------------------------
# Startup
# ----------------------------------------------------------------
[void]$cmbDrive.Items.AddRange((Get-OpticalDrives))
if ($cmbDrive.Items.Count -gt 0) { $cmbDrive.SelectedIndex = 0 }

$form.Add_Shown({
    Add-Log "Loaded dvd-ripper-encoder from $DvdEncoderPath"
    Add-Log ("HandBrakeCLI: {0}" -f $(if ($script:HandBrakeCLI) { $script:HandBrakeCLI } else { 'NOT FOUND' }))
    Add-Log ("mkvpropedit : {0}" -f $(if ($script:MkvPropEdit) { $script:MkvPropEdit } else { 'not found (language tagging disabled)' }))
    Add-Log ("mkvmerge    : {0}" -f $(if ($script:MkvMerge) { $script:MkvMerge } else { 'not found (stream validation disabled)' }))
    if (-not $script:HandBrakeCLI) { Add-Log 'Install HandBrake to scan/encode.' }
})

$form.Add_FormClosing({
    param($s, $e)
    Stop-Scan
    if ($script:Encoding) {
        $r = [System.Windows.Forms.MessageBox]::Show('An encode is still running. Stop HandBrakeCLI and quit?', 'DVD Encoder GUI', 'YesNo', 'Warning')
        if ($r -ne 'Yes') { $e.Cancel = $true; return }
        if ($script:Timer) { try { $script:Timer.Stop() } catch { } }
        Stop-Encode
        if ($script:Ps) { try { $script:Ps.Dispose() } catch { } }
        if ($script:Rs) { try { $script:Rs.Dispose() } catch { } }
        $script:Encoding = $false
    }
})

[void]$form.ShowDialog()
