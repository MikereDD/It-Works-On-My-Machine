<#
================================================================
  Media Encoder GUI  -  all-in-one disc -> HEVC front end
  version:  1.3.1  (embedded app icon hotfix)  by Mike Redd
----------------------------------------------------------------
  One window over the existing toolset. It does NOT reimplement any
  pipeline; each engine is dot-sourced inside its OWN background
  runspace (so their many same-named functions never collide) and
  its real functions are called:

    DVD      -> dvd-ripper-encoder.ps1  (Encode-DvdTitle)
    Blu-ray  -> bluray-backup.ps1       (MakeMKV decrypt + Save-TrackMeta)
                BRencoder.ps1           (Encode-File, reads the sidecar)
    File     -> ffprobe scan; tools run on an existing video
    Sample   -> mkv-sample.ps1          (Create-SampleFile)
    Minfo    -> minfocreate.ps1         (NFO/HTML/poster via MediaInfo + OMDb)
    Sidecar  -> bluray-trackdump.ps1    (info-only BRTrackMeta, no decrypt)

  Each engine carries a *_NOMENU guard so dot-sourcing never starts
  its menu. Run under Windows PowerShell, STA:

    powershell -ExecutionPolicy Bypass -STA -File media-encoder-gui.ps1

  Sample + minfo run after an encode (checkboxes) or standalone on any file.
================================================================
#>

[CmdletBinding()]
param(
    [string]$DvdEncoderPath,
    [string]$BREncoderPath,
    [string]$BlurayBackupPath,
    [string]$MkvSamplePath,
    [string]$MinfoPath,
    [string]$TrackdumpPath,
    [string]$CdTracksPath,
    [string]$CdImagePath
)

# ── WinForms needs a single-threaded apartment. If we're launched from a host
# ── that isn't STA (pwsh / PowerShell 7 is MTA by default), the window can't
# ── be shown and the script just falls through. Detect that and relaunch under
# ── Windows PowerShell with -STA so a bare .\media-encoder-gui.ps1 works too.
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA) {
    $winPS = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
    if ($winPS) {
        # Preserve bound engine-path parameters when relaunching from pwsh/MTA.
        $launchArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-File', $PSCommandPath)
        foreach ($kv in $PSBoundParameters.GetEnumerator()) {
            if ($null -ne $kv.Value -and ([string]$kv.Value).Length -gt 0) {
                $launchArgs += ('-' + $kv.Key)
                $launchArgs += [string]$kv.Value
            }
        }
        $launchArgs += $args
        & $winPS @launchArgs
        return
    }
    Write-Host "This GUI must run in a single-threaded apartment (STA)."
    Write-Host "Run it with:  powershell -ExecutionPolicy Bypass -STA -File `"$PSCommandPath`""
    return
}

# Be immune to whatever the launching session set up. A profile that runs
# Set-StrictMode -Version Latest turns the GUI's harmless loose access into
# terminating errors during form construction (a direct `powershell.exe -File`
# without -NoProfile loads that profile; the -NoProfile relaunch above doesn't).
Set-StrictMode -Off
$ErrorActionPreference = 'Continue'

function Resolve-Engine {
    param([string]$Given, [string]$FileName)
    if ($Given) { return [Environment]::ExpandEnvironmentVariables($Given) }

    $personalRoot = Join-Path $HOME 'PS\scripts\personaltools'
    $parent       = Split-Path $PSScriptRoot -Parent
    $cands = @(
        (Join-Path $PSScriptRoot $FileName),
        (Join-Path $personalRoot $FileName),
        $(if ($parent) { Join-Path $parent "personaltools\$FileName" } else { $null })
    ) | Where-Object { $_ }

    $hit = $cands | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if ($hit) { return $hit }
    return (Join-Path $PSScriptRoot $FileName)
}
$DvdEncoderPath   = Resolve-Engine $DvdEncoderPath   'dvd-ripper-encoder.ps1'
$BREncoderPath    = Resolve-Engine $BREncoderPath    'BRencoder.ps1'
$BlurayBackupPath = Resolve-Engine $BlurayBackupPath 'bluray-backup.ps1'
$MkvSamplePath    = Resolve-Engine $MkvSamplePath    'mkv-sample.ps1'
$MinfoPath        = Resolve-Engine $MinfoPath        'minfocreate.ps1'
$TrackdumpPath    = Resolve-Engine $TrackdumpPath    'bluray-trackdump.ps1'
$CdTracksPath     = Resolve-Engine $CdTracksPath     'cd-tracks-flac.ps1'
$CdImagePath      = Resolve-Engine $CdImagePath      'cd-image-flac.ps1'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ── Script state ─────────────────────────────────────────────
$script:Titles      = @()
$script:CurrentTitle = $null
$script:Encoding    = $false
$script:CancelRequested = $false
$script:Stage       = 'idle'   # idle | scan | dvd-encode | bd-backup | bd-encode | sample | minfo | trackdump
$script:Ps = $null; $script:Rs = $null; $script:Async = $null; $script:Timer = $null
$script:InfoIdx = 0; $script:WarnIdx = 0
$script:ProgFile = $null
$script:TotalSeconds = 0
# carried between the two Blu-ray stages
$script:BdMovie = $null; $script:BdSourceM2ts = $null; $script:BdAudioCodes = @(); $script:BdSubCodes = @()
$script:BdBackupOnly = $false   # Blu-ray "Backup only": decrypt to a full disc folder, skip BRencoder
$script:BdBackupRoot = $null
$script:BdCleanupAfterEncode = $false
# pass 2: post-encode chaining + standalone tools
$script:LastOutput = $null     # last good encode/tool output, target for the tools
$script:PostQueue  = @()       # queued post-encode steps (sample/minfo) after an encode

$MinTitleSecs = 900

# ── Self-contained helpers (no engine deps on the UI thread) ──
# Disk log: written regardless of whether the RichTextBox paints, so startup
# and scan can be diagnosed from %TEMP%\media-encoder-gui.log even if the UI
# log box stays blank.
$script:DebugLog = Join-Path $env:TEMP 'media-encoder-gui.log'
function Write-DebugLog {
    param([string]$Text)
    try { Add-Content -LiteralPath $script:DebugLog -Value ("{0}  {1}" -f (Get-Date -Format 'HH:mm:ss.fff'), $Text) -ErrorAction SilentlyContinue } catch { }
}
try {
    Set-Content -LiteralPath $script:DebugLog -Value ("==== media-encoder-gui start {0} ====" -f (Get-Date)) -ErrorAction SilentlyContinue
    Write-DebugLog ("PSVersion={0}  Host={1}  Apartment={2}" -f $PSVersionTable.PSVersion, $Host.Name, [System.Threading.Thread]::CurrentThread.GetApartmentState())
    Write-DebugLog ("DVD={0}" -f $DvdEncoderPath)
    Write-DebugLog ("BD ={0}" -f $BlurayBackupPath)
    Write-DebugLog ("BR ={0}" -f $BREncoderPath)
    Write-DebugLog ("SMP={0}" -f $MkvSamplePath)
    Write-DebugLog ("NFO={0}" -f $MinfoPath)
    Write-DebugLog ("DMP={0}" -f $TrackdumpPath)
    Write-DebugLog ("CDT={0}" -f $CdTracksPath)
    Write-DebugLog ("CDI={0}" -f $CdImagePath)
} catch { }

function Strip-Ansi { param([string]$s); if (-not $s) { return '' }; return [regex]::Replace($s, "\x1b\[[0-9;]*[A-Za-z]", '') }

function Get-OpticalDrives {
    $d = @()
    try { $d = @(Get-CimInstance Win32_CDROMDrive -ErrorAction Stop | Where-Object { $_.Drive } | ForEach-Object { $_.Drive }) } catch { }
    if (-not $d -or $d.Count -eq 0) { $d = @('D:') }
    return $d
}

function Resolve-GuiLanguageCode {
    param([AllowNull()][string]$Code)
    $c = ([string]$Code).Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($c)) { return 'und' }
    $c = $c -replace '[^a-z]', ''
    if ([string]::IsNullOrWhiteSpace($c)) { return 'und' }
    $map = @{
        'en'='eng'; 'eng'='eng'; 'english'='eng'
        'fr'='fra'; 'fre'='fra'; 'fra'='fra'; 'french'='fra'
        'es'='spa'; 'spa'='spa'; 'spanish'='spa'
        'de'='deu'; 'ger'='deu'; 'deu'='deu'; 'german'='deu'
        'it'='ita'; 'ita'='ita'; 'italian'='ita'
        'ja'='jpn'; 'jp'='jpn'; 'jpn'='jpn'; 'japanese'='jpn'
        'ko'='kor'; 'kor'='kor'; 'korean'='kor'
        'zh'='zho'; 'chi'='zho'; 'zho'='zho'; 'chinese'='zho'
        'pt'='por'; 'por'='por'; 'portuguese'='por'
        'ru'='rus'; 'rus'='rus'; 'russian'='rus'
        'nl'='nld'; 'dut'='nld'; 'nld'='nld'; 'dutch'='nld'
        'sv'='swe'; 'swe'='swe'; 'swedish'='swe'
        'no'='nor'; 'nor'='nor'; 'norwegian'='nor'
        'da'='dan'; 'dan'='dan'; 'danish'='dan'
        'fi'='fin'; 'fin'='fin'; 'finnish'='fin'
        'pl'='pol'; 'pol'='pol'; 'polish'='pol'
        'tr'='tur'; 'tur'='tur'; 'turkish'='tur'
        'ar'='ara'; 'ara'='ara'; 'arabic'='ara'
        'hi'='hin'; 'hin'='hin'; 'hindi'='hin'
        'und'='und'; 'unknown'='und'; 'undefined'='und'
    }
    if ($map.ContainsKey($c)) { return $map[$c] }
    if ($c.Length -eq 3) { return $c }
    return 'und'
}

function Test-EngineAvailable {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Name)
    if ($Path -and (Test-Path -LiteralPath $Path -PathType Leaf)) { return $true }
    Add-LogColor ("    ERROR: {0} not found -> {1}" -f $Name, $Path) ([System.Drawing.Color]::FromArgb(240, 120, 120))
    return $false
}

function Get-BluRayBackupRootFromM2ts {
    param([string]$M2tsPath)
    if (-not $M2tsPath) { return $null }
    try {
        $fi = Get-Item -LiteralPath $M2tsPath -ErrorAction Stop
        $dir = $fi.Directory
        while ($dir) {
            if ($dir.Name -ieq 'BDMV') { return $dir.Parent.FullName }
            $dir = $dir.Parent
        }
    } catch { }
    return $null
}

function Remove-BluRayBackupRoot {
    param([string]$Root)
    if (-not $Root -or -not (Test-Path -LiteralPath $Root -PathType Container)) { return }
    $safeRoot = (Join-Path 'G:\Rip' 'bluray')
    try {
        $fullRoot = [System.IO.Path]::GetFullPath($Root)
        $fullSafe = [System.IO.Path]::GetFullPath($safeRoot)
        if (-not $fullRoot.StartsWith($fullSafe, [System.StringComparison]::OrdinalIgnoreCase)) {
            Add-Log "    backup cleanup skipped: outside expected Blu-ray root ($fullRoot)"
            return
        }
        Add-Log "    removing Blu-ray backup: $fullRoot"
        Remove-Item -LiteralPath $fullRoot -Recurse -Force -ErrorAction Stop
    } catch {
        Add-Log "    backup cleanup failed: $($_.Exception.Message)"
    }
}

# ════════════════════════════════════════════════════════════════
#  FORM (dark theme)
# ════════════════════════════════════════════════════════════════
$form = New-Object System.Windows.Forms.Form
$script:GuiVersion = '1.3.1'
$form.Text = "Media Encoder GUI  v$($script:GuiVersion)  (DVD / Blu-ray / File / Audio CD)"
$form.Size = New-Object System.Drawing.Size(1440, 1040)
$form.MinimumSize = New-Object System.Drawing.Size(1280, 980)
$form.StartPosition = 'CenterScreen'
$form.BackColor = [System.Drawing.Color]::FromArgb(9, 9, 11)
$form.ForeColor = [System.Drawing.Color]::WhiteSmoke
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9.75)   # bigger labels/buttons/checkboxes
$mono = New-Object System.Drawing.Font('Consolas', 10.5)        # bigger log / grid / list / fields
$dark = [System.Drawing.Color]::FromArgb(22, 22, 26)
Write-DebugLog 'construction: form + base styling'

# --- source ---
$lblSource = New-Object System.Windows.Forms.Label
$lblSource.Text = 'Source'; $lblSource.Location = '12,10'; $lblSource.AutoSize = $true
$form.Controls.Add($lblSource)

$rbDvd = New-Object System.Windows.Forms.RadioButton
$rbDvd.Text = 'DVD'; $rbDvd.Location = '12,30'; $rbDvd.Size = '60,24'; $rbDvd.Checked = $true
$form.Controls.Add($rbDvd)
$rbBd = New-Object System.Windows.Forms.RadioButton
$rbBd.Text = 'Blu-ray'; $rbBd.Location = '76,30'; $rbBd.Size = '80,24'
$form.Controls.Add($rbBd)
$rbFile = New-Object System.Windows.Forms.RadioButton
$rbFile.Text = 'File'; $rbFile.Location = '160,30'; $rbFile.Size = '60,24'
$form.Controls.Add($rbFile)
$rbCd = New-Object System.Windows.Forms.RadioButton
$rbCd.Text = 'Audio CD'; $rbCd.Location = '224,30'; $rbCd.Size = '96,24'
$form.Controls.Add($rbCd)

$cmbDrive = New-Object System.Windows.Forms.ComboBox
$cmbDrive.Location = '12,58'; $cmbDrive.Size = '150,24'; $cmbDrive.DropDownStyle = 'DropDownList'
$cmbDrive.BackColor = $dark; $cmbDrive.ForeColor = [System.Drawing.Color]::Gainsboro
$form.Controls.Add($cmbDrive)
$btnScan = New-Object System.Windows.Forms.Button
$btnScan.Text = 'Scan'; $btnScan.Location = '170,57'; $btnScan.Size = '80,26'
$btnScan.BackColor = [System.Drawing.Color]::FromArgb(40, 70, 110)
$form.Controls.Add($btnScan)
$txtFile = New-Object System.Windows.Forms.TextBox
$txtFile.Location = '12,58'; $txtFile.Size = '150,24'; $txtFile.Visible = $false
$txtFile.Font = $mono; $txtFile.BackColor = $dark; $txtFile.ForeColor = [System.Drawing.Color]::Gainsboro
$form.Controls.Add($txtFile)
$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = 'Browse'; $btnBrowse.Location = '256,57'; $btnBrowse.Size = '76,26'; $btnBrowse.Visible = $false
$btnBrowse.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 70)
$form.Controls.Add($btnBrowse)

# --- titles ---
$lblTitles = New-Object System.Windows.Forms.Label
$lblTitles.Text = 'Titles'; $lblTitles.Location = '12,92'; $lblTitles.AutoSize = $true
$form.Controls.Add($lblTitles)
$lstTitles = New-Object System.Windows.Forms.ListBox
$lstTitles.Location = '12,112'; $lstTitles.Size = '320,340'; $lstTitles.Anchor = 'Top, Left'
$lstTitles.Font = $mono; $lstTitles.BackColor = $dark; $lstTitles.ForeColor = [System.Drawing.Color]::Gainsboro
$form.Controls.Add($lstTitles)

# --- settings ---
$grpSet = New-Object System.Windows.Forms.GroupBox
$grpSet.Text = 'Encode settings'; $grpSet.Location = '12,462'; $grpSet.Size = '320,392'
$grpSet.ForeColor = [System.Drawing.Color]::Gainsboro; $grpSet.Anchor = 'Top, Left'
$form.Controls.Add($grpSet)

$lblRF = New-Object System.Windows.Forms.Label
$lblRF.Text = 'RF / quality'; $lblRF.Location = '14,28'; $lblRF.AutoSize = $true; $grpSet.Controls.Add($lblRF)
$numRF = New-Object System.Windows.Forms.NumericUpDown
$numRF.Location = '120,26'; $numRF.Size = '60,24'; $numRF.Minimum = 16; $numRF.Maximum = 28; $numRF.Value = 20
$numRF.BackColor = $dark; $numRF.ForeColor = [System.Drawing.Color]::Gainsboro
$grpSet.Controls.Add($numRF)
$lblRFnote = New-Object System.Windows.Forms.Label
$lblRFnote.Text = '(DVD only)'; $lblRFnote.ForeColor = [System.Drawing.Color]::Gray
$lblRFnote.Location = '186,28'; $lblRFnote.AutoSize = $true; $grpSet.Controls.Add($lblRFnote)

$lblPreset = New-Object System.Windows.Forms.Label
$lblPreset.Text = 'Preset'; $lblPreset.Location = '14,60'; $lblPreset.AutoSize = $true; $grpSet.Controls.Add($lblPreset)
$cmbPreset = New-Object System.Windows.Forms.ComboBox
$cmbPreset.Location = '120,58'; $cmbPreset.Size = '120,24'; $cmbPreset.DropDownStyle = 'DropDownList'
[void]$cmbPreset.Items.AddRange(@('slow','slower','veryslow')); $cmbPreset.SelectedItem = 'slower'
$grpSet.Controls.Add($cmbPreset)

$lblCont = New-Object System.Windows.Forms.Label
$lblCont.Text = 'Container'; $lblCont.Location = '14,92'; $lblCont.AutoSize = $true; $grpSet.Controls.Add($lblCont)
$cmbCont = New-Object System.Windows.Forms.ComboBox
$cmbCont.Location = '120,90'; $cmbCont.Size = '120,24'; $cmbCont.DropDownStyle = 'DropDownList'
[void]$cmbCont.Items.AddRange(@('mkv','mp4')); $cmbCont.SelectedItem = 'mkv'
$grpSet.Controls.Add($cmbCont)

$lblTune = New-Object System.Windows.Forms.Label
$lblTune.Text = 'Tune (DVD)'; $lblTune.Location = '14,124'; $lblTune.AutoSize = $true; $grpSet.Controls.Add($lblTune)
$cmbTune = New-Object System.Windows.Forms.ComboBox
$cmbTune.Location = '120,122'; $cmbTune.Size = '120,24'; $cmbTune.DropDownStyle = 'DropDownList'
[void]$cmbTune.Items.AddRange(@('auto','none','animation','grain')); $cmbTune.SelectedItem = 'auto'
$grpSet.Controls.Add($cmbTune)

$chkArchive = New-Object System.Windows.Forms.CheckBox
$chkArchive.Text = 'Archive source (DVD VIDEO_TS)'; $chkArchive.Location = '14,158'; $chkArchive.Size = '290,22'; $chkArchive.Checked = $true
$grpSet.Controls.Add($chkArchive)
$chkRemux = New-Object System.Windows.Forms.CheckBox
$chkRemux.Text = 'Tag languages (DVD mkvpropedit)'; $chkRemux.Location = '14,182'; $chkRemux.Size = '290,22'; $chkRemux.Checked = $true
$grpSet.Controls.Add($chkRemux)
$chkKeepBackup = New-Object System.Windows.Forms.CheckBox
$chkKeepBackup.Text = 'Keep Blu-ray backup after encode'; $chkKeepBackup.Location = '14,206'; $chkKeepBackup.Size = '290,22'; $chkKeepBackup.Checked = $true
$grpSet.Controls.Add($chkKeepBackup)
$chkDry = New-Object System.Windows.Forms.CheckBox
$chkDry.Text = 'Dry run (DVD)'; $chkDry.Location = '14,230'; $chkDry.Size = '160,22'
$grpSet.Controls.Add($chkDry)
$chkBackupOnly = New-Object System.Windows.Forms.CheckBox
$chkBackupOnly.Text = 'Backup only (decrypt full disc, no encode)'; $chkBackupOnly.Location = '14,230'; $chkBackupOnly.Size = '300,22'; $chkBackupOnly.Visible = $false
$grpSet.Controls.Add($chkBackupOnly)
$lblBdNote = New-Object System.Windows.Forms.Label
$lblBdNote.Text = 'Blu-ray mode: BRencoder controls quality / preset / HDR. Only "Keep backup" applies here.'
$lblBdNote.ForeColor = [System.Drawing.Color]::FromArgb(150, 180, 210)
$lblBdNote.Location = '14,258'; $lblBdNote.Size = '296,48'; $lblBdNote.Visible = $false
$grpSet.Controls.Add($lblBdNote)
# --- Audio CD rip mode (shown only in CD mode; overlaps the DVD/BD checkboxes,
#     which are hidden in CD mode) ---
$lblCdMode = New-Object System.Windows.Forms.Label
$lblCdMode.Text = 'Audio CD -> FLAC:'; $lblCdMode.Location = '14,158'; $lblCdMode.AutoSize = $true; $lblCdMode.Visible = $false
$grpSet.Controls.Add($lblCdMode)
$rbCdTracks = New-Object System.Windows.Forms.RadioButton
$rbCdTracks.Text = 'Per-track FLAC'; $rbCdTracks.Location = '14,182'; $rbCdTracks.Size = '290,22'; $rbCdTracks.Checked = $true; $rbCdTracks.Visible = $false
$grpSet.Controls.Add($rbCdTracks)
$rbCdImage = New-Object System.Windows.Forms.RadioButton
$rbCdImage.Text = 'Single image + CUE'; $rbCdImage.Location = '14,206'; $rbCdImage.Size = '290,22'; $rbCdImage.Visible = $false
$grpSet.Controls.Add($rbCdImage)
$lblCdNote = New-Object System.Windows.Forms.Label
$lblCdNote.Text = 'Rips in its own elevated window (UAC) — reads the disc and resolves MusicBrainz there. Uses the ripper''s configured CD drive.'
$lblCdNote.ForeColor = [System.Drawing.Color]::FromArgb(150, 180, 210)
$lblCdNote.Location = '14,234'; $lblCdNote.Size = '296,60'; $lblCdNote.Visible = $false
$grpSet.Controls.Add($lblCdNote)
$lblPost = New-Object System.Windows.Forms.Label
$lblPost.Text = 'After encode:'; $lblPost.Location = '14,314'; $lblPost.AutoSize = $true
$lblPost.ForeColor = [System.Drawing.Color]::Gainsboro; $grpSet.Controls.Add($lblPost)
$chkPostSample = New-Object System.Windows.Forms.CheckBox
$chkPostSample.Text = 'Create sample clip'; $chkPostSample.Location = '14,336'; $chkPostSample.Size = '290,22'
$grpSet.Controls.Add($chkPostSample)
$chkPostMinfo = New-Object System.Windows.Forms.CheckBox
$chkPostMinfo.Text = 'Create minfo (NFO/HTML/poster)'; $chkPostMinfo.Location = '14,360'; $chkPostMinfo.Size = '290,22'
$grpSet.Controls.Add($chkPostMinfo)

# --- movie name + year ---
$lblName = New-Object System.Windows.Forms.Label
$lblName.Text = 'Movie name'; $lblName.Location = '352,10'; $lblName.AutoSize = $true
$form.Controls.Add($lblName)
$txtName = New-Object System.Windows.Forms.TextBox
$txtName.Location = '352,30'; $txtName.Size = '540,24'; $txtName.Anchor = 'Top, Left, Right'
$txtName.Font = $mono; $txtName.BackColor = $dark; $txtName.ForeColor = [System.Drawing.Color]::Gainsboro
$form.Controls.Add($txtName)
$lblYear = New-Object System.Windows.Forms.Label
$lblYear.Text = 'Year'; $lblYear.Location = '1100,12'; $lblYear.AutoSize = $true; $lblYear.Anchor = 'Top, Right'
$form.Controls.Add($lblYear)
$txtYear = New-Object System.Windows.Forms.TextBox
$txtYear.Location = '1138,30'; $txtYear.Size = '70,24'; $txtYear.Anchor = 'Top, Right'
$txtYear.Font = $mono; $txtYear.BackColor = $dark; $txtYear.ForeColor = [System.Drawing.Color]::Gainsboro
$form.Controls.Add($txtYear)
$lblImdb = New-Object System.Windows.Forms.Label
$lblImdb.Text = 'IMDb (tt...)'; $lblImdb.Location = '900,12'; $lblImdb.AutoSize = $true; $lblImdb.Anchor = 'Top, Right'
$form.Controls.Add($lblImdb)
$txtImdb = New-Object System.Windows.Forms.TextBox
$txtImdb.Location = '900,30'; $txtImdb.Size = '190,24'; $txtImdb.Anchor = 'Top, Right'
$txtImdb.Font = $mono; $txtImdb.BackColor = $dark; $txtImdb.ForeColor = [System.Drawing.Color]::Gainsboro
$form.Controls.Add($txtImdb)

# --- grid ---
$lblGrid = New-Object System.Windows.Forms.Label
$lblGrid.Text = 'Tracks  (edit Lang to fix undefined codes; Incl applies to DVD)'
$lblGrid.Location = '352,62'; $lblGrid.AutoSize = $true
$form.Controls.Add($lblGrid)
$grid = New-Object System.Windows.Forms.DataGridView
$grid.Location = '352,84'; $grid.Size = '856,440'; $grid.Anchor = 'Top, Bottom, Left, Right'
$grid.AllowUserToAddRows = $false; $grid.RowHeadersVisible = $false; $grid.AutoSizeColumnsMode = 'Fill'
$grid.BackgroundColor = $dark; $grid.Font = $mono
$grid.EnableHeadersVisualStyles = $false
$grid.GridColor = [System.Drawing.Color]::FromArgb(60, 60, 70)
$grid.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 48)
$grid.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::WhiteSmoke
$grid.ColumnHeadersHeightSizeMode = 'DisableResizing'; $grid.ColumnHeadersHeight = 28
$grid.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(28, 28, 34)
$grid.DefaultCellStyle.ForeColor = [System.Drawing.Color]::WhiteSmoke
$grid.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(38, 90, 140)
$grid.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White
$grid.RowTemplate.Height = 26
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
$log.BackColor = [System.Drawing.Color]::FromArgb(16, 16, 20); $log.ForeColor = [System.Drawing.Color]::FromArgb(170, 220, 170)
$form.Controls.Add($log)
$script:log = $log

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = '352,798'; $progress.Size = '660,22'; $progress.Anchor = 'Bottom, Left'; $progress.Style = 'Continuous'
$form.Controls.Add($progress)
$script:progress = $progress

$lblStat = New-Object System.Windows.Forms.Label
$lblStat.Location = '352,824'; $lblStat.Size = '660,18'; $lblStat.Anchor = 'Bottom, Left'; $lblStat.Font = $mono; $lblStat.Text = ''
$form.Controls.Add($lblStat)
$lblPlan = New-Object System.Windows.Forms.Label
$lblPlan.Location = '352,846'; $lblPlan.Size = '700,24'; $lblPlan.Anchor = 'Bottom, Left'
$lblPlan.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$lblPlan.ForeColor = [System.Drawing.Color]::FromArgb(120, 200, 255); $lblPlan.Text = ''
$form.Controls.Add($lblPlan)
$btnEncode = New-Object System.Windows.Forms.Button
$btnEncode.Text = 'Encode'; $btnEncode.Location = '1058,797'; $btnEncode.Size = '72,26'; $btnEncode.Anchor = 'Bottom, Right'
$btnEncode.BackColor = [System.Drawing.Color]::FromArgb(40, 90, 50)
$form.Controls.Add($btnEncode)
$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = 'Cancel'; $btnCancel.Location = '1136,797'; $btnCancel.Size = '72,26'; $btnCancel.Anchor = 'Bottom, Right'; $btnCancel.Enabled = $false
$btnCancel.BackColor = [System.Drawing.Color]::FromArgb(110, 45, 45)
$form.Controls.Add($btnCancel)

# --- Tools (run on the File source or the last encode output) ---
$lblTools = New-Object System.Windows.Forms.Label
$lblTools.Text = 'Tools'; $lblTools.Location = '12,840'; $lblTools.AutoSize = $true; $lblTools.Anchor = 'Top, Left'
$form.Controls.Add($lblTools)
$btnSample = New-Object System.Windows.Forms.Button
$btnSample.Text = 'Create sample'; $btnSample.Location = '12,862'; $btnSample.Size = '100,26'; $btnSample.Anchor = 'Top, Left'
$btnSample.BackColor = [System.Drawing.Color]::FromArgb(50, 60, 80); $form.Controls.Add($btnSample)
$btnMinfo = New-Object System.Windows.Forms.Button
$btnMinfo.Text = 'Create minfo'; $btnMinfo.Location = '118,862'; $btnMinfo.Size = '100,26'; $btnMinfo.Anchor = 'Top, Left'
$btnMinfo.BackColor = [System.Drawing.Color]::FromArgb(50, 60, 80); $form.Controls.Add($btnMinfo)
$btnDump = New-Object System.Windows.Forms.Button
$btnDump.Text = 'Dump sidecar'; $btnDump.Location = '224,862'; $btnDump.Size = '100,26'; $btnDump.Anchor = 'Top, Left'
$btnDump.BackColor = [System.Drawing.Color]::FromArgb(50, 60, 80); $form.Controls.Add($btnDump)

# --- monochrome polish shell ---------------------------------
$monoBack  = [System.Drawing.Color]::FromArgb(9, 9, 11)
$cardBack  = [System.Drawing.Color]::FromArgb(13, 13, 16)
$cardBack2 = [System.Drawing.Color]::FromArgb(17, 17, 21)
$lineSoft  = [System.Drawing.Color]::FromArgb(54, 54, 60)
$lineHard  = [System.Drawing.Color]::FromArgb(108, 108, 116)
$inkMain   = [System.Drawing.Color]::FromArgb(236, 236, 236)
$inkSoft   = [System.Drawing.Color]::FromArgb(190, 190, 196)
$inkMute   = [System.Drawing.Color]::FromArgb(132, 132, 140)
$selBack   = [System.Drawing.Color]::FromArgb(36, 36, 44)
$goodInk   = [System.Drawing.Color]::FromArgb(240, 240, 240)
$badInk    = [System.Drawing.Color]::FromArgb(168, 168, 174)

function New-MonoPanel {
    param([int]$X,[int]$Y,[int]$W,[int]$H)
    $p = New-Object System.Windows.Forms.Panel
    $p.Location = New-Object System.Drawing.Point($X,$Y)
    $p.Size = New-Object System.Drawing.Size($W,$H)
    $p.BackColor = $cardBack
    $p.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    return $p
}
function New-SectionTitle {
    param([string]$Text,[int]$X,[int]$Y,[int]$W=160)
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text
    $l.Location = New-Object System.Drawing.Point($X,$Y)
    $l.Size = New-Object System.Drawing.Size($W,24)
    $l.ForeColor = $inkMain
    $l.BackColor = [System.Drawing.Color]::Transparent
    $l.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    return $l
}
function Style-MonoInput {
    param($ctl)
    try {
        $ctl.BackColor = $cardBack2
        $ctl.ForeColor = $inkMain
        if ($ctl -is [System.Windows.Forms.ComboBox]) { $ctl.FlatStyle = 'Flat' }
        if ($ctl -is [System.Windows.Forms.TextBox]) { $ctl.BorderStyle = 'FixedSingle' }
    } catch { }
}
function Style-MonoButton {
    param($btn, [string]$Variant = 'default')
    $btn.FlatStyle = 'Flat'
    $btn.FlatAppearance.BorderSize = 1
    $btn.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Regular)
    switch ($Variant) {
        'primary' {
            $btn.BackColor = [System.Drawing.Color]::FromArgb(20,20,24)
            $btn.ForeColor = [System.Drawing.Color]::White
            $btn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(236,236,240)
        }
        'danger' {
            $btn.BackColor = [System.Drawing.Color]::FromArgb(18,18,22)
            $btn.ForeColor = [System.Drawing.Color]::FromArgb(210,210,214)
            $btn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(124,124,132)
        }
        'soft' {
            $btn.BackColor = [System.Drawing.Color]::FromArgb(18,18,22)
            $btn.ForeColor = $inkMain
            $btn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(96,96,104)
        }
        default {
            $btn.BackColor = [System.Drawing.Color]::FromArgb(18,18,22)
            $btn.ForeColor = $inkMain
            $btn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(76,76,84)
        }
    }
}
function Style-SourceCard {
    param($rb,[bool]$Selected)
    $rb.Appearance = 'Button'
    $rb.TextAlign = 'MiddleCenter'
    $rb.FlatStyle = 'Flat'
    $rb.FlatAppearance.BorderSize = 1
    $rb.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Regular)
    if ($Selected) {
        $rb.BackColor = [System.Drawing.Color]::FromArgb(22,22,26)
        $rb.ForeColor = [System.Drawing.Color]::White
        $rb.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(242,242,246)
    } else {
        $rb.BackColor = [System.Drawing.Color]::FromArgb(14,14,18)
        $rb.ForeColor = $inkSoft
        $rb.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(64,64,72)
    }
}
function Update-SourceCardVisuals {
    Style-SourceCard $rbDvd  $rbDvd.Checked
    Style-SourceCard $rbBd   $rbBd.Checked
    Style-SourceCard $rbFile $rbFile.Checked
    Style-SourceCard $rbCd   $rbCd.Checked
}
function Update-EngineBadges {
    if (-not $script:EngineBadges) { return }
    $map = [ordered]@{
        'DVD'       = $DvdEncoderPath
        'Blu-ray'   = $BlurayBackupPath
        'BRencoder' = $BREncoderPath
        'Sample'    = $MkvSamplePath
        'Minfo'     = $MinfoPath
    }
    foreach ($name in $map.Keys) {
        if (-not $script:EngineBadges.ContainsKey($name)) { continue }
        $ok = $false
        try { $ok = (Test-Path -LiteralPath $map[$name]) } catch { $ok = $false }
        $b = $script:EngineBadges[$name]
        $b.Text = ('{0}  {1}  {2}' -f $(if ($ok) { '●' } else { '○' }), $name, $(if ($ok) { 'OK' } else { 'MISS' }))
        $b.ForeColor = $(if ($ok) { $goodInk } else { $badInk })
        $b.BackColor = $(if ($ok) { [System.Drawing.Color]::FromArgb(12,12,16) } else { [System.Drawing.Color]::FromArgb(18,18,22) })
        $b.BorderStyle = 'FixedSingle'
    }
}
function Update-StageStrip {
    if (-not $script:StageDots -or -not $script:StageCaptions) { return }
    $order = @('Scan','Decrypt','Encode','Sample','Minfo')
    $curMap = @{ idle=0; scan=1; 'bd-backup'=2; 'trackdump'=2; 'bd-encode'=3; 'dvd-encode'=3; sample=4; minfo=5 }
    $n = 0
    if ($curMap.ContainsKey($script:Stage)) { $n = [int]$curMap[$script:Stage] }
    for ($i=0; $i -lt $order.Count; $i++) {
        $dot = $script:StageDots[$order[$i]]
        $cap = $script:StageCaptions[$order[$i]]
        if (($i + 1) -lt $n) {
            $dot.ForeColor = [System.Drawing.Color]::White
            $cap.ForeColor = [System.Drawing.Color]::White
        } elseif (($i + 1) -eq $n -and $n -gt 0) {
            $dot.ForeColor = [System.Drawing.Color]::White
            $cap.ForeColor = [System.Drawing.Color]::White
        } elseif (($i + 1) -eq $n) {
            $dot.ForeColor = [System.Drawing.Color]::White
            $cap.ForeColor = [System.Drawing.Color]::White
        } else {
            $dot.ForeColor = $inkMute
            $cap.ForeColor = $inkMute
        }
    }
}
function Update-FooterStatus {
    if (-not $script:FooterLabel) { return }
    $src = if ($rbFile.Checked) { $txtFile.Text } else { $cmbDrive.Text }
    if ([string]::IsNullOrWhiteSpace($src)) { $src = '-' }

    # Do not call Get-SourceKind here. This chrome timer is created while the file
    # is still being parsed, so the function may not exist yet during startup.
    $modeText = if ($rbFile.Checked) {
        'File tools'
    } elseif ($rbCd.Checked) {
        'Audio CD'
    } elseif ($rbBd.Checked) {
        'BRencoder'
    } else {
        'DVD'
    }

    $space = ''
    try {
        $drv = Get-PSDrive -Name 'G' -ErrorAction SilentlyContinue
        if ($drv) { $space = ('{0:N1} GB free' -f ($drv.Free / 1GB)) }
    } catch { }

    $script:FooterLabel.Text = "Source: $src    |    Mode: $modeText    |    Space: $space"
}
function Update-TitlesPlaceholder {
    if (-not $script:TitlesPlaceholder) { return }
    $script:TitlesPlaceholder.Visible = ($lstTitles.Items.Count -eq 0)
}
$script:EmbeddedMediaEncoderIconBase64 = @'
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
'@

function Get-MediaEncoderIconPath {
    try {
        $iconCandidates = @(
            (Join-Path $PSScriptRoot 'media-encoder.ico'),
            (Join-Path (Split-Path -Parent $PSCommandPath) 'media-encoder.ico'),
            (Join-Path $env:TEMP 'media-encoder.ico')
        ) | Select-Object -Unique

        foreach ($iconPath in $iconCandidates) {
            if ($iconPath -and (Test-Path -LiteralPath $iconPath)) { return $iconPath }
        }

        $fallback = Join-Path $env:TEMP 'media-encoder.ico'
        [System.IO.File]::WriteAllBytes($fallback, [Convert]::FromBase64String($script:EmbeddedMediaEncoderIconBase64))
        return $fallback
    } catch {
        return $null
    }
}

function Set-AppIcon {
    try {
        $iconPath = Get-MediaEncoderIconPath
        if ($iconPath -and (Test-Path -LiteralPath $iconPath)) {
            $script:AppIconPath = $iconPath
            $form.Icon = New-Object System.Drawing.Icon($iconPath)
        }
    } catch { }
}

# Header
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$hdrGlyph = New-Object System.Windows.Forms.PictureBox
$hdrGlyph.Location = New-Object System.Drawing.Point(18,18)
$hdrGlyph.Size = New-Object System.Drawing.Size(42,42)
$hdrGlyph.BackColor = [System.Drawing.Color]::FromArgb(12,12,16)
$hdrGlyph.BorderStyle = 'FixedSingle'
$hdrGlyph.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::CenterImage
try {
    $iconPathForHeader = Get-MediaEncoderIconPath
    if ($iconPathForHeader -and (Test-Path -LiteralPath $iconPathForHeader)) {
        $icoForHeader = New-Object System.Drawing.Icon($iconPathForHeader, 32, 32)
        $hdrGlyph.Image = $icoForHeader.ToBitmap()
    }
} catch { }
$form.Controls.Add($hdrGlyph)
$hdrTitle = New-Object System.Windows.Forms.Label
$hdrTitle.Location = New-Object System.Drawing.Point(82,17)
$hdrTitle.Size = New-Object System.Drawing.Size(300,36)
$hdrTitle.Text = 'Media Encoder'
$hdrTitle.Font = New-Object System.Drawing.Font('Segoe UI', 19, [System.Drawing.FontStyle]::Bold)
$hdrTitle.ForeColor = [System.Drawing.Color]::White
$form.Controls.Add($hdrTitle)
$hdrVer = New-Object System.Windows.Forms.Label
$hdrVer.Location = New-Object System.Drawing.Point(292,25)
$hdrVer.Size = New-Object System.Drawing.Size(80,22)
$hdrVer.Text = ('v{0}' -f $script:GuiVersion)
$hdrVer.ForeColor = $inkSoft
$hdrVer.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Regular)
$form.Controls.Add($hdrVer)
try { Set-AppIcon } catch { }
$hdrDivider = New-Object System.Windows.Forms.Label
$hdrDivider.Location = New-Object System.Drawing.Point(14,64)
$hdrDivider.Size = New-Object System.Drawing.Size(1394,1)
$hdrDivider.BackColor = [System.Drawing.Color]::FromArgb(72,72,78)
$form.Controls.Add($hdrDivider)
$script:EngineBadges = @{}
$badgeNames = @('DVD','Blu-ray','BRencoder','Sample','Minfo')
for ($i = 0; $i -lt $badgeNames.Count; $i++) {
    $b = New-Object System.Windows.Forms.Label
    $b.Location = New-Object System.Drawing.Point((468 + ($i * 128)), 18)
    $b.Size = New-Object System.Drawing.Size(118, 32)
    $b.TextAlign = 'MiddleCenter'
    $b.Font = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Bold)
    $b.ForeColor = $inkMain
    $b.BackColor = [System.Drawing.Color]::FromArgb(12,12,16)
    $b.BorderStyle = 'FixedSingle'
    $form.Controls.Add($b)
    $script:EngineBadges[$badgeNames[$i]] = $b
}

# Background cards
$cards = @(
    (New-MonoPanel 14 76 430 196),
    (New-MonoPanel 14 286 430 220),
    (New-MonoPanel 14 520 430 346),
    (New-MonoPanel 14 880 430 102),
    (New-MonoPanel 460 76 948 118),
    (New-MonoPanel 460 208 948 356),
    (New-MonoPanel 460 578 948 266),
    (New-MonoPanel 460 858 948 124)
)
foreach ($p in $cards) { $form.Controls.Add($p); $p.SendToBack() }

# Source section
$lblSource.Text = 'SOURCE'; $lblSource.Location = '30,92'; $lblSource.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold); $lblSource.ForeColor = [System.Drawing.Color]::White; $lblSource.BackColor = [System.Drawing.Color]::FromArgb(8,8,10)
$rbDvd.Location = '30,126'; $rbDvd.Size = '92,84'; $rbDvd.Text = 'DVD'
$rbBd.Location  = '132,126'; $rbBd.Size = '98,84'; $rbBd.Text = 'Blu-ray'
$rbFile.Location= '240,126'; $rbFile.Size= '92,84'; $rbFile.Text = 'File'
$rbCd.Location  = '342,126'; $rbCd.Size = '86,84'; $rbCd.Text = "Audio CD"
$driveHdr = New-Object System.Windows.Forms.Label
$driveHdr.Location = New-Object System.Drawing.Point(30,224)
$driveHdr.Size = New-Object System.Drawing.Size(46,22)
$driveHdr.Text = 'Drive'
$driveHdr.ForeColor = $inkSoft
$form.Controls.Add($driveHdr)
$cmbDrive.Location = '82,220'; $cmbDrive.Size = '248,30'; Style-MonoInput $cmbDrive
$txtFile.Location = '82,220'; $txtFile.Size = '248,30'; Style-MonoInput $txtFile; $txtFile.Font = $mono
$btnScan.Location = '338,219'; $btnScan.Size = '90,32'; Style-MonoButton $btnScan 'soft'
$btnBrowse.Location = '338,219'; $btnBrowse.Size = '90,32'; Style-MonoButton $btnBrowse 'soft'

# Titles
$lblTitles.Text = 'TITLES'; $lblTitles.Location = '30,302'; $lblTitles.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold); $lblTitles.ForeColor = [System.Drawing.Color]::White; $lblTitles.BackColor = [System.Drawing.Color]::FromArgb(8,8,10)
$lstTitles.Location = '30,338'; $lstTitles.Size = '398,148'; $lstTitles.BackColor = [System.Drawing.Color]::FromArgb(12,12,16); $lstTitles.BorderStyle = 'FixedSingle'; $lstTitles.ForeColor = $inkMain
$ph = New-Object System.Windows.Forms.Label
$ph.Location = New-Object System.Drawing.Point(62,376)
$ph.Size = New-Object System.Drawing.Size(334,72)
$ph.TextAlign = 'MiddleCenter'
$ph.Text = "No titles loaded.`r`nInsert a disc and click Scan`r`nto load titles."
$ph.ForeColor = $inkMute
$ph.BackColor = [System.Drawing.Color]::Transparent
$ph.Font = New-Object System.Drawing.Font('Segoe UI', 11)
$form.Controls.Add($ph)
$script:TitlesPlaceholder = $ph

# Settings / tools
$grpSet.Text = 'ENCODE SETTINGS'; $grpSet.Location = '26,536'; $grpSet.Size = '404,310'; $grpSet.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold); $grpSet.ForeColor = [System.Drawing.Color]::White; $grpSet.BackColor = $cardBack
foreach ($ctl in @($cmbPreset,$cmbCont,$cmbTune,$numRF)) { Style-MonoInput $ctl }
foreach ($ctl in @($lblRF,$lblRFnote,$lblPreset,$lblCont,$lblTune,$chkArchive,$chkRemux,$chkKeepBackup,$chkDry,$chkBackupOnly,$lblBdNote,$lblCdMode,$rbCdTracks,$rbCdImage,$lblCdNote,$lblPost,$chkPostSample,$chkPostMinfo)) {
    try { $ctl.ForeColor = $inkSoft; $ctl.BackColor = $cardBack } catch { }
}
$lblPost.Location = '14,224'; $chkPostSample.Location = '14,248'; $chkPostMinfo.Location = '14,272'
$lblBdNote.Location = '14,224'; $lblBdNote.Size = '372,44'
$lblCdMode.Location = '14,156'; $rbCdTracks.Location = '14,180'; $rbCdImage.Location = '14,204'; $lblCdNote.Location = '14,228'; $lblCdNote.Size = '372,40'
$lblTools.Text = 'AFTER ENCODE'; $lblTools.Location = '30,892'; $lblTools.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold); $lblTools.ForeColor = [System.Drawing.Color]::White; $lblTools.BackColor = [System.Drawing.Color]::FromArgb(8,8,10)
$btnSample.Location = '30,930'; $btnSample.Size = '120,32'; Style-MonoButton $btnSample 'soft'
$btnMinfo.Location = '164,930'; $btnMinfo.Size = '120,32'; Style-MonoButton $btnMinfo 'soft'
$btnDump.Location = '298,930'; $btnDump.Size = '130,32'; Style-MonoButton $btnDump 'soft'

# Movie info
$lblName.Text = 'MOVIE INFO'; $lblName.Location = '478,92'; $lblName.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold); $lblName.ForeColor = [System.Drawing.Color]::White; $lblName.BackColor = [System.Drawing.Color]::FromArgb(8,8,10)
$txtName.Location = '478,126'; $txtName.Size = '560,36'; $txtName.Font = New-Object System.Drawing.Font('Segoe UI', 12); Style-MonoInput $txtName
$lblImdb.Location = '1062,96'; $lblImdb.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold); $lblImdb.ForeColor = $inkSoft
$txtImdb.Location = '1062,126'; $txtImdb.Size = '150,36'; $txtImdb.Font = New-Object System.Drawing.Font('Segoe UI', 12); Style-MonoInput $txtImdb
$lblYear.Location = '1232,96'; $lblYear.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold); $lblYear.ForeColor = $inkSoft
$txtYear.Location = '1232,126'; $txtYear.Size = '96,36'; $txtYear.Font = New-Object System.Drawing.Font('Segoe UI', 12); Style-MonoInput $txtYear

# Tracks
$lblGrid.Text = 'TRACKS   (edit Lang to fix undefined codes; Incl applies to DVD)'; $lblGrid.Location = '478,224'; $lblGrid.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold); $lblGrid.ForeColor = [System.Drawing.Color]::White; $lblGrid.BackColor = [System.Drawing.Color]::FromArgb(8,8,10)
$grid.Location = '478,260'; $grid.Size = '912,286'; $grid.BackgroundColor = [System.Drawing.Color]::FromArgb(12,12,16); $grid.BorderStyle = 'FixedSingle'; $grid.RowHeadersBorderStyle='None'
$grid.GridColor = [System.Drawing.Color]::FromArgb(46,46,52)
$grid.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(18,18,22)
$grid.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
$grid.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(12,12,16)
$grid.DefaultCellStyle.ForeColor = [System.Drawing.Color]::WhiteSmoke
$grid.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(34,34,40)
$grid.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White

# Log console
$logHdr = New-Object System.Windows.Forms.Label
$logHdr.Location = New-Object System.Drawing.Point(478,594)
$logHdr.Size = New-Object System.Drawing.Size(180,22)
$logHdr.Text = 'LOG CONSOLE'
$logHdr.ForeColor = [System.Drawing.Color]::White; $logHdr.BackColor = [System.Drawing.Color]::FromArgb(8,8,10)
$logHdr.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($logHdr)
$log.Location = '478,628'; $log.Size = '912,192'; $log.BackColor = [System.Drawing.Color]::FromArgb(8,8,10); $log.ForeColor = [System.Drawing.Color]::FromArgb(222,222,222); $log.BorderStyle='FixedSingle'
$btnClearLog = New-Object System.Windows.Forms.Button
$btnClearLog.Text = 'Clear'; $btnClearLog.Location = '1188,590'; $btnClearLog.Size = '88,30'; Style-MonoButton $btnClearLog 'soft'; $form.Controls.Add($btnClearLog)
$btnSaveLog = New-Object System.Windows.Forms.Button
$btnSaveLog.Text = 'Save log'; $btnSaveLog.Location = '1282,590'; $btnSaveLog.Size = '108,30'; Style-MonoButton $btnSaveLog 'soft'; $form.Controls.Add($btnSaveLog)
$btnClearLog.Add_Click({ $log.Clear() })
$btnSaveLog.Add_Click({
    try {
        $dlg = New-Object System.Windows.Forms.SaveFileDialog
        $dlg.Filter = 'Text file|*.txt|All files|*.*'
        $dlg.FileName = 'media-encoder-gui-log.txt'
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            [System.IO.File]::WriteAllText($dlg.FileName, $log.Text)
        }
    } catch { }
})

# Progress / actions
$progressHdr = New-Object System.Windows.Forms.Label
$progressHdr.Location = New-Object System.Drawing.Point(478,874)
$progressHdr.Size = New-Object System.Drawing.Size(120,22)
$progressHdr.Text = 'PROGRESS'
$progressHdr.ForeColor = [System.Drawing.Color]::White; $progressHdr.BackColor = [System.Drawing.Color]::FromArgb(8,8,10)
$progressHdr.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($progressHdr)
$progress.Location = '584,878'; $progress.Size = '464,12'; $progress.Style = 'Continuous'; $progress.ForeColor = [System.Drawing.Color]::White
$lblStat.Location = '1060,870'; $lblStat.Size = '72,24'; $lblStat.Text = '0%'; $lblStat.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold); $lblStat.ForeColor = [System.Drawing.Color]::White
$lblPlan.Location = '478,902'; $lblPlan.Size = '540,22'; $lblPlan.Font = New-Object System.Drawing.Font('Segoe UI', 10.5, [System.Drawing.FontStyle]::Bold); $lblPlan.ForeColor = $inkSoft
$btnEncode.Location = '1054,896'; $btnEncode.Size = '154,56'; Style-MonoButton $btnEncode 'primary'; $btnEncode.Font = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
$btnCancel.Location = '1220,896'; $btnCancel.Size = '170,56'; Style-MonoButton $btnCancel 'danger'; $btnCancel.Font = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
$script:StageDots = @{}
$script:StageCaptions = @{}
$stageNames = @('Scan','Decrypt','Encode','Sample','Minfo')
$stageX = 486
foreach ($name in $stageNames) {
    $dot = New-Object System.Windows.Forms.Label
    $dotX = [int]$stageX
    $dot.Location = New-Object System.Drawing.Point($dotX, 932)
    $dot.Size = New-Object System.Drawing.Size(22,22)
    $dot.Text = '●'
    $dot.TextAlign = 'MiddleCenter'
    $dot.Font = New-Object System.Drawing.Font('Segoe UI Symbol', 13)
    $dot.ForeColor = $inkMute
    $form.Controls.Add($dot)
    $cap = New-Object System.Windows.Forms.Label
    $capX = [int]$stageX + 24
    $cap.Location = New-Object System.Drawing.Point($capX, 932)
    $cap.Size = New-Object System.Drawing.Size(82,22)
    $cap.Text = $name
    $cap.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $cap.ForeColor = $inkMute
    $form.Controls.Add($cap)
    $script:StageDots[$name] = $dot
    $script:StageCaptions[$name] = $cap
    if ($name -ne 'Minfo') {
        $line = New-Object System.Windows.Forms.Label
        $lineX = [int]$stageX + 104
        $line.Location = New-Object System.Drawing.Point($lineX, 936)
        $line.Size = New-Object System.Drawing.Size(26, 14)
        $line.Text = '—'
        $line.TextAlign = 'MiddleCenter'
        $line.ForeColor = $inkMute
        $form.Controls.Add($line)
    }
    $stageX = [int]$stageX + 126
}
$footer = New-Object System.Windows.Forms.Label
$footer.Location = New-Object System.Drawing.Point(478,958)
$footer.Size = New-Object System.Drawing.Size(912,18)
$footer.ForeColor = $inkMute; $footer.BackColor = [System.Drawing.Color]::Transparent
$footer.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$form.Controls.Add($footer)
$script:FooterLabel = $footer

# anchor polish
$lstTitles.Anchor = 'Top, Left'
$grpSet.Anchor = 'Top, Left'
$log.Anchor = 'Bottom, Left, Right'
$grid.Anchor = 'Top, Left, Right'
$btnEncode.Anchor = 'Bottom, Right'
$btnCancel.Anchor = 'Bottom, Right'
$progress.Anchor = 'Bottom, Left, Right'
$lblStat.Anchor = 'Bottom, Right'
$lblPlan.Anchor = 'Bottom, Left'
$btnClearLog.Anchor = 'Bottom, Right'
$btnSaveLog.Anchor = 'Bottom, Right'

# UI refresh timer for shell visuals
$script:UiChromeTimer = New-Object System.Windows.Forms.Timer
$script:UiChromeTimer.Interval = 300
$script:UiChromeTimer.Add_Tick({
    try { Update-SourceCardVisuals } catch { }
    try { Update-EngineBadges } catch { }
    try { Update-StageStrip } catch { }
    try { Update-FooterStatus } catch { }
    try { Update-TitlesPlaceholder } catch { }
})
# Timer is started after startup wiring completes.
Update-SourceCardVisuals
Update-EngineBadges
Update-StageStrip
Update-FooterStatus
Update-TitlesPlaceholder

Write-DebugLog 'construction: all controls built'

# ── thread-safe UI helpers ───────────────────────────────────
function Add-Log {
    param([string]$Text)
    Write-DebugLog $Text
    # Bind the control to a LOCAL so GetNewClosure captures it for sure (a
    # script-scope $log isn't reliably closed over). The common case — called
    # on the UI thread, e.g. the startup banner — takes the closure-free direct
    # path so the text always lands even if marshaling/closure capture misbehaves.
    $ctl = $script:log
    if (-not $ctl) { return }
    if ($ctl.IsHandleCreated -and $ctl.InvokeRequired) {
        $sb = { $ctl.AppendText("$Text`r`n"); $ctl.ScrollToCaret() }.GetNewClosure()
        [void]$ctl.BeginInvoke([System.Windows.Forms.MethodInvoker]$sb)
    } else {
        $ctl.AppendText("$Text`r`n"); $ctl.ScrollToCaret()
    }
}
function Add-LogColor {
    param([string]$Text, [System.Drawing.Color]$Color)
    Write-DebugLog $Text
    $ctl = $script:log
    if (-not $ctl) { return }
    $apply = {
        $ctl.SelectionStart = $ctl.TextLength; $ctl.SelectionLength = 0
        $ctl.SelectionColor = $Color
        $ctl.AppendText("$Text`r`n")
        $ctl.SelectionColor = $ctl.ForeColor
        $ctl.ScrollToCaret()
    }.GetNewClosure()
    if ($ctl.IsHandleCreated -and $ctl.InvokeRequired) { [void]$ctl.BeginInvoke([System.Windows.Forms.MethodInvoker]$apply) } else { & $apply }
}
function Set-Progress {
    param([int]$Pct)
    if ($Pct -lt 0) { $Pct = 0 } elseif ($Pct -gt 100) { $Pct = 100 }
    $ctl = $script:progress
    if (-not $ctl) { return }
    if ($ctl.IsHandleCreated -and $ctl.InvokeRequired) {
        $sb = { $ctl.Style = 'Continuous'; $ctl.Value = $Pct; try { if ($lblStat) { $lblStat.Text = ('{0}%' -f $Pct) } } catch { } }.GetNewClosure()
        [void]$ctl.BeginInvoke([System.Windows.Forms.MethodInvoker]$sb)
    } else {
        $ctl.Style = 'Continuous'; $ctl.Value = $Pct; try { if ($lblStat) { $lblStat.Text = ('{0}%' -f $Pct) } } catch { }
    }
}
function Set-Busy {
    param([bool]$On)
    $btnScan.Enabled   = -not $On
    $btnSample.Enabled = -not $On
    $btnMinfo.Enabled  = -not $On
    $btnDump.Enabled   = -not $On
    $btnEncode.Enabled = (-not $On -and -not $rbFile.Checked)
    $btnCancel.Enabled = $On
    if (-not $On) { Update-SourceUi }
}

function Get-MovieName {
    $n = $txtName.Text.Trim()
    if (-not $n) { $n = "encode_$(Get-Date -Format 'yyyyMMdd_HHmmss')" }
    $y = $txtYear.Text.Trim()
    if ($y -match '^\d{4}$') { $n = "$n [$y]" }
    return $n
}
function Get-DriveLetter {
    $d = [string]$cmbDrive.SelectedItem
    if ($d -and $d -notmatch ':$') { $d += ':' }
    return $d
}
function Get-SourceKind { if ($rbFile.Checked) { 'file' } elseif ($rbCd.Checked) { 'cd' } elseif ($rbBd.Checked) { 'bluray' } else { 'dvd' } }
function Get-ToolTarget {
    # A standalone tool runs on the File-mode file if set, else the last encode output.
    $f = $txtFile.Text.Trim()
    if ($rbFile.Checked -and $f -and (Test-Path -LiteralPath $f)) { return $f }
    if ($script:LastOutput -and (Test-Path -LiteralPath $script:LastOutput)) { return $script:LastOutput }
    return $null
}
function Read-FileTitle {
    # ffprobe an existing video into a normalized title for the grid (info only).
    param([string]$Path)
    try {
        $json = (& ffprobe -v quiet -print_format json -show_format -show_streams -- "$Path" 2>$null | Out-String)
        if (-not $json) { Add-Log '    ffprobe returned nothing (is ffprobe on PATH?).'; return $null }
        $o = $json | ConvertFrom-Json
        $audio = @(); $sub = @()
        foreach ($s in $o.streams) {
            $lang = if ($s.tags.language) { [string]$s.tags.language } else { 'und' }
            $desc = (@($s.codec_long_name, $s.tags.title, $s.channel_layout) | Where-Object { $_ }) -join '  '
            if     ($s.codec_type -eq 'audio')    { $audio += [pscustomobject]@{ Num=[int]$s.index; Code=$lang; Codec=[string]$s.codec_name; Desc=$desc } }
            elseif ($s.codec_type -eq 'subtitle') { $sub   += [pscustomobject]@{ Num=[int]$s.index; Code=$lang; Codec=[string]$s.codec_name; Desc=$desc } }
        }
        $dur = ''
        if ($o.format.duration) { $ts=[TimeSpan]::FromSeconds([double]$o.format.duration); $dur = '{0:00}:{1:00}:{2:00}' -f [int]$ts.TotalHours, $ts.Minutes, $ts.Seconds }
        return [pscustomobject]@{ Kind='file'; Num=0; Duration=$dur; Audio=@($audio); Sub=@($sub); Raw=$o; Path=$Path }
    } catch { Add-Log "    ffprobe error: $($_.Exception.Message)"; return $null }
}

# ── grid population from a normalized title ──────────────────
function Update-Grid {
    param($T)
    $grid.Rows.Clear(); $script:CurrentTitle = $T
    if (-not $T) { return }
    $ai = 0
    foreach ($a in $T.Audio) {
        $ai++
        $idx = $grid.Rows.Add(("a{0}" -f $ai), 'audio', $a.Codec, $(if ($a.Code) { $a.Code } else { 'und' }), $true, $a.Desc)
        $grid.Rows[$idx].Tag = [pscustomobject]@{ Num = $a.Num; Kind = 'audio' }
    }
    $si = 0
    foreach ($s in $T.Sub) {
        $si++
        $idx = $grid.Rows.Add(("s{0}" -f $si), 'subtitle', $s.Codec, $(if ($s.Code) { $s.Code } else { 'und' }), $true, $s.Desc)
        $grid.Rows[$idx].Tag = [pscustomobject]@{ Num = $s.Num; Kind = 'subtitle' }
    }
}
function Get-GridSelections {
    $grid.EndEdit() | Out-Null
    # Two flavours of code arrays:
    #   *Codes    — included tracks only, in output order. Correct for DVD, whose
    #               output MKV contains only the included tracks (a1,a2,... line up).
    #   *CodesAll — every track in grid/source order, inclusion ignored. Correct for
    #               Blu-ray, where BRencoder encodes ALL source tracks from the sidecar
    #               and the language override is applied positionally to that full list.
    #               Using the compacted array here shifts codes onto the wrong tracks
    #               whenever a track is unchecked.
    $aNums = @(); $aCodes = @(); $aCodesAll = @(); $aTotal = 0
    $sNums = @(); $sCodes = @(); $sCodesAll = @(); $sTotal = 0
    foreach ($row in $grid.Rows) {
        if ($row.IsNewRow) { continue }
        $tag = $row.Tag; if (-not $tag) { continue }
        $lang = Resolve-GuiLanguageCode ([string]$row.Cells['Lang'].Value)
        $incl = [bool]$row.Cells['Incl'].Value
        if ($tag.Kind -eq 'audio') { $aTotal++; $aCodesAll += $lang; if ($incl) { $aNums += [int]$tag.Num; $aCodes += $lang } }
        elseif ($tag.Kind -eq 'subtitle') { $sTotal++; $sCodesAll += $lang; if ($incl) { $sNums += [int]$tag.Num; $sCodes += $lang } }
    }
    $aSel = if ($aTotal -eq 0) { 'all' } elseif ($aNums.Count -eq 0) { 'none' } elseif ($aNums.Count -eq $aTotal) { 'all' } else { ($aNums -join ',') }
    $sSel = if ($sTotal -eq 0) { 'all' } elseif ($sNums.Count -eq 0) { 'none' } elseif ($sNums.Count -eq $sTotal) { 'all' } else { ($sNums -join ',') }
    return @{ AudioSel = $aSel; SubSel = $sSel; AudioCodes = $aCodes; SubCodes = $sCodes; AudioCodesAll = $aCodesAll; SubCodesAll = $sCodesAll }
}

# ════════════════════════════════════════════════════════════════
#  SCAN  (DVD via HandBrake, Blu-ray via MakeMKV info — no decrypt)
# ════════════════════════════════════════════════════════════════
function Start-Scan {
    if ($script:Encoding -or $script:Stage -ne 'idle') { return }

    if ($rbFile.Checked) {
        $f = $txtFile.Text.Trim()
        if (-not $f -or -not (Test-Path -LiteralPath $f)) { Add-Log '    No file selected - click Browse first.'; return }
        $log.Clear(); $lstTitles.Items.Clear(); $grid.Rows.Clear(); $script:Titles = @()
        Add-Log "==> Probing file: $f"
        $title = Read-FileTitle $f
        if (-not $title) { return }
        $script:Titles = @($title)
        [void]$lstTitles.Items.Add(("File   {0}   (a:{1} s:{2})" -f $title.Duration, $title.Audio.Count, $title.Sub.Count))
        $lstTitles.SelectedIndex = 0
        Update-Grid $title
        $script:TotalSeconds = Get-DurSec $title.Duration
        if (-not $txtName.Text.Trim()) { $txtName.Text = [System.IO.Path]::GetFileNameWithoutExtension($f) }
        Add-Log ("==> File ready: a:{0} s:{1}.  Use the Tools row." -f $title.Audio.Count, $title.Sub.Count)
        return
    }

    $drive = Get-DriveLetter
    if (-not $drive) { Add-Log '    No drive selected.'; return }

    $disc = Get-DiscType $drive
    if     ($disc -eq 'dvd')    { $rbDvd.Checked = $true }
    elseif ($disc -eq 'bluray') { $rbBd.Checked  = $true }

    if ($rbDvd.Checked -and -not (Test-EngineAvailable -Path $DvdEncoderPath -Name 'dvd-ripper-encoder.ps1')) { return }
    if ($rbBd.Checked  -and -not (Test-EngineAvailable -Path $BlurayBackupPath -Name 'bluray-backup.ps1')) { return }

    $log.Clear(); $lstTitles.Items.Clear(); $grid.Rows.Clear(); $script:Titles = @()
    if ($disc) { Add-Log "==> Detected $($disc.ToUpper()) in $drive" }
    else       { Add-Log "    No DVD/Blu-ray video structure on $drive; trying $(if ($rbDvd.Checked) {'DVD'} else {'Blu-ray'}) mode anyway." }
    $script:Stage = 'scan'; Set-Busy $true
    $progress.Style = 'Marquee'; $lblStat.Text = '  scanning...'

    $rs = [runspacefactory]::CreateRunspace(); $rs.ApartmentState = 'MTA'; $rs.Open()
    $ps = [powershell]::Create(); $ps.Runspace = $rs

    if ($rbDvd.Checked) {
        Add-Log "==> Scanning DVD $drive"
        $rs.SessionStateProxy.SetVariable('DvdPath', $DvdEncoderPath)
        $rs.SessionStateProxy.SetVariable('Drive',   $drive)
        $rs.SessionStateProxy.SetVariable('MinDur',  $MinTitleSecs)
        [void]$ps.AddScript({
            $env:DVDENCODER_NOMENU = '1'; . $DvdPath
            # The engine sets $ErrorActionPreference='Stop' globally; that leaks into
            # this runspace and turns HandBrake's normal stderr logging (captured via
            # 2>&1) into a terminating error. Reset it so native stderr stays non-fatal.
            $ErrorActionPreference = 'Continue'
            Write-Host 'engine: dvd-ripper-encoder loaded (HandBrake title scan)'
            try { Ensure-Dependencies } catch { Write-Host "ERROR: $($_.Exception.Message)"; return [pscustomobject]@{ Titles = @() } }
            Write-Host "HandBrakeCLI: $Script:HandBrakeCLI"
            $text = (& $Script:HandBrakeCLI --input $Drive --title 0 --scan --min-duration $MinDur 2>&1 | Out-String)
            # parse HandBrake scan -> normalized titles (reuses Get-TrackLangFromDesc)
            $titles = @(); $cur = $null; $section = $null
            foreach ($line in ($text -split "`r?`n")) {
                if ($line -match '^\+\s+title\s+(\d+):') {
                    if ($cur) { $titles += [pscustomobject]$cur }
                    $cur = @{ Kind='dvd'; Num=[int]$matches[1]; Duration=''; Audio=@(); Sub=@(); Raw=$null }; $section=$null
                }
                if ($cur) {
                    if     ($line -match '^\s*\+\s+duration:\s+(.+)$')    { $cur.Duration = $matches[1].Trim() }
                    elseif ($line -match '^\s*\+\s+audio tracks:\s*$')    { $section='audio' }
                    elseif ($line -match '^\s*\+\s+subtitle tracks:\s*$') { $section='subtitle' }
                    elseif ($line -match '^\s*\+\s+\w[\w ]*:\s*$')        { $section=$null }
                    elseif ($line -match '^\s*\+\s+(\d+),\s*(.+)$') {
                        $num=[int]$matches[1]; $desc=$matches[2].Trim()
                        $lang = Get-TrackLangFromDesc -Desc $desc
                        $codec = ''
                        if ($section -eq 'audio'    -and $desc -match '\b(TrueHD|E?AC-?3|DTS(?:-HD)?|AAC|MP2|MP3|LPCM|PCM|FLAC)\b') { $codec = $matches[1] }
                        if ($section -eq 'subtitle' -and $desc -match '\b(VOBSUB|PGS|Bitmap|Text|CC)\b') { $codec = $matches[1] }
                        $obj = [pscustomobject]@{ Num=$num; Code=$lang.Code; Codec=$codec; Desc=$desc }
                        if ($section -eq 'audio') { $cur.Audio += $obj } elseif ($section -eq 'subtitle') { $cur.Sub += $obj }
                    }
                }
            }
            if ($cur) { $titles += [pscustomobject]$cur }

            if ($titles.Count -eq 0) {
                # Surface what HandBrake actually reported so a zero-title scan is diagnosable.
                Write-Host 'no titles parsed - HandBrake scan summary:'
                $hbDir = Split-Path -Parent $Script:HandBrakeCLI
                $hasCss = @('libdvdcss-2.dll','libdvdcss.dll') | Where-Object { Test-Path -LiteralPath (Join-Path $hbDir $_) }
                foreach ($l in ($text -split "`r?`n")) {
                    if ($l -match 'title\(s\)|dvdnav|libdvd|css|encrypt|VTS|\.IFO|unrecognized|invalid|cannot|failed|error') {
                        Write-Host ('  | ' + ($l.Trim()))
                    }
                }
                if (-not $hasCss) {
                    Write-Host 'HINT: libdvdcss is missing and auto-install did not complete (see the libdvdcss line above).'
                    Write-Host "      Install VLC (the GUI will reuse its copy), check your internet, or drop a bitness-matched libdvdcss-2.dll into: $hbDir"
                    Write-Host "      Alternatively rip VIDEO_TS with MakeMKV first, then use 'Encode from existing folder'."
                }
            }

            return [pscustomobject]@{ Titles = @($titles) }
        })
    }
    else {
        Add-Log "==> Scanning Blu-ray (MakeMKV info, no decrypt)"
        $rs.SessionStateProxy.SetVariable('BackupPath', $BlurayBackupPath)
        $rs.SessionStateProxy.SetVariable('DriveLetter', $drive)
        [void]$ps.AddScript({
            $env:BLURAYBACKUP_NOMENU = '1'; . $BackupPath
            $ErrorActionPreference = 'Continue'   # MakeMKV/native stderr must not be fatal

function Get-MakeMKVPath {
    $names = @('makemkvcon.exe','makemkvcon64.exe')
    $roots = @(
        $env:MAKEMKV_HOME,
        $env:MAKEMKVCON,
        "$env:ProgramFiles\MakeMKV",
        "${env:ProgramFiles(x86)}\MakeMKV",
        "$env:LOCALAPPDATA\Programs\MakeMKV"
    ) | Where-Object { $_ }

    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($r in $roots) {
        if ($r -match '\.exe$') { [void]$candidates.Add($r) }
        else { foreach ($n in $names) { [void]$candidates.Add((Join-Path $r $n)) } }
    }
    foreach ($n in $names) {
        $cmd = Get-Command $n -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Source) { [void]$candidates.Add($cmd.Source) }
    }
    foreach ($reg in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )) {
        try {
            Get-ItemProperty $reg -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -like '*MakeMKV*' -and $_.InstallLocation } |
                ForEach-Object { foreach ($n in $names) { [void]$candidates.Add((Join-Path $_.InstallLocation $n)) } }
        } catch { }
    }
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ($base -and (Test-Path -LiteralPath $base)) {
            foreach ($n in $names) {
                try {
                    Get-ChildItem -LiteralPath $base -Directory -Filter '*MakeMKV*' -ErrorAction SilentlyContinue |
                        ForEach-Object { [void]$candidates.Add((Join-Path $_.FullName $n)) }
                } catch { }
            }
        }
    }
    $seen = @{}
    foreach ($path in $candidates) {
        if (-not $path) { continue }
        $full = [Environment]::ExpandEnvironmentVariables([string]$path).Trim('"')
        if ($seen.ContainsKey($full)) { continue }
        $seen[$full] = $true
        if (Test-Path -LiteralPath $full -PathType Leaf) { return $full }
    }
    Write-Host 'ERROR: MakeMKV CLI not found. Install MakeMKV or add its folder to PATH.'
    Write-Host '       Checked Program Files, Program Files (x86), PATH, registry, MAKEMKV_HOME, and MAKEMKVCON.'
    return $null
}

            Write-Host 'engine: bluray-backup loaded (Get-MakeMKVPath, Get-MakeMKVInfoLines, ConvertFrom-MakeMKVInfo)'
            $exe = Get-MakeMKVPath
            if (-not $exe) { Write-Host 'ERROR: MakeMKV (makemkvcon) not found.'; return [pscustomobject]@{ Titles = @() } }
            Write-Host "makemkvcon: $exe"
            # Map the selected optical drive to MakeMKV's disc index (was hardcoded disc:0).
            $Script:Drive = Resolve-MakeMKVDiscIndex -Exe $exe -DriveLetter $DriveLetter
            Write-Host "MakeMKV source: $Script:Drive  (resolved from drive $DriveLetter)"
            foreach ($d in (Get-MakeMKVDrives -Exe $exe)) {
                Write-Host ("  drive disc:{0}  device={1}  disc='{2}'  [{3}]" -f $d.Index, $d.Device, $d.DiscName, $(if ($d.HasDisc) { 'disc loaded' } else { 'empty' }))
            }
            Write-Host "reading disc info: makemkvcon -r info $Script:Drive  (can take a moment)..."
            $lines  = Get-MakeMKVInfoLines -Exe $exe -Source $Script:Drive
            $titles = ConvertFrom-MakeMKVInfo -Lines $lines
            Write-Host "parsed $(@($titles).Count) title(s) via ConvertFrom-MakeMKVInfo"
            $norm = foreach ($t in $titles) {
                $audio = foreach ($a in @($t.AudioTracks)) {
                    [pscustomobject]@{ Num=$a.TrackId; Code=$a.LanguageCode; Codec=$(if ($a.CodecShort){$a.CodecShort}else{$a.CodecLong}); Desc=$a.Description }
                }
                $sub = foreach ($s in @($t.SubtitleTracks)) {
                    [pscustomobject]@{ Num=$s.TrackId; Code=$s.LanguageCode; Codec=$(if ($s.CodecShort){$s.CodecShort}else{'PGS'}); Desc=$s.Description }
                }
                [pscustomobject]@{ Kind='bluray'; Num=$t.TitleId; Duration=$t.Duration; Audio=@($audio); Sub=@($sub); Raw=$t }
            }
            return [pscustomobject]@{ Titles = @($norm) }
        })
    }

    $script:Ps = $ps; $script:Rs = $rs; $script:Async = $ps.BeginInvoke()
    $t = New-Object System.Windows.Forms.Timer; $t.Interval = 250; $script:Timer = $t
    $t.Add_Tick({
        if ($script:Ps) {
            $inf = $script:Ps.Streams.Information
            while ($script:InfoIdx -lt $inf.Count) { Add-Log ('    ' + (Strip-Ansi $inf[$script:InfoIdx].ToString())); $script:InfoIdx++ }
        }
        if (-not ($script:Async -and $script:Async.IsCompleted)) { return }
        $script:Timer.Stop()
        $titlesOut = @()
        try { $wrap = @($script:Ps.EndInvoke($script:Async))[0]; if ($wrap) { $titlesOut = @($wrap.Titles) } } catch { Add-Log "    scan error: $($_.Exception.Message)" }
        $inf = $script:Ps.Streams.Information
        while ($script:InfoIdx -lt $inf.Count) { Add-Log ('    ' + (Strip-Ansi $inf[$script:InfoIdx].ToString())); $script:InfoIdx++ }
        try { $script:Ps.Dispose() } catch { }; try { $script:Rs.Dispose() } catch { }
        $script:Ps=$null; $script:Rs=$null; $script:Async=$null; $script:Timer=$null
        $script:InfoIdx = 0
        $script:Stage = 'idle'; Set-Busy $false; $progress.Style='Continuous'; Set-Progress 0; $lblStat.Text=''

        $script:Titles = @($titlesOut)
        if (-not $script:Titles -or $script:Titles.Count -eq 0) { Add-Log '    No titles found.'; return }
        $main = $script:Titles | Sort-Object { Get-DurSec $_.Duration } -Descending | Select-Object -First 1
        foreach ($ti in $script:Titles) {
            [void]$lstTitles.Items.Add(("Title {0}   {1}   (a:{2} s:{3})" -f $ti.Num, $ti.Duration, $ti.Audio.Count, $ti.Sub.Count))
        }
        for ($i=0; $i -lt $script:Titles.Count; $i++) { if ($script:Titles[$i].Num -eq $main.Num) { $lstTitles.SelectedIndex=$i; break } }
        Add-Log ("==> {0} title(s). Main: title {1} ({2})." -f $script:Titles.Count, $main.Num, $main.Duration)
    })
    $t.Start()
}

function Get-DurSec { param([string]$d); if ($d -match '^\d{1,2}:\d{2}:\d{2}$') { try { return [int][TimeSpan]::Parse($d).TotalSeconds } catch { } }; return 0 }

# ════════════════════════════════════════════════════════════════
#  ENCODE  (DVD: Encode-DvdTitle ; Blu-ray: backup -> BRencoder)
# ════════════════════════════════════════════════════════════════
function Start-Encode {
    if ($script:Encoding) { return }
    if (-not $script:CurrentTitle) { [System.Windows.Forms.MessageBox]::Show('Scan and pick a title first.', 'Media Encoder GUI') | Out-Null; return }
    if ($script:CurrentTitle.Kind -eq 'file') { [System.Windows.Forms.MessageBox]::Show('File mode is for tools only. Use Create sample or Create minfo, or use BRencoder/DVD GUI for direct file encodes.', 'Media Encoder GUI') | Out-Null; return }
    if ($script:CurrentTitle.Kind -eq 'dvd' -and -not (Test-EngineAvailable -Path $DvdEncoderPath -Name 'dvd-ripper-encoder.ps1')) { return }
    if ($script:CurrentTitle.Kind -eq 'bluray') {
        if (-not (Test-EngineAvailable -Path $BlurayBackupPath -Name 'bluray-backup.ps1')) { return }
        if (-not $chkBackupOnly.Checked -and -not (Test-EngineAvailable -Path $BREncoderPath -Name 'BRencoder.ps1')) { return }
    }
    $drive = Get-DriveLetter
    $movie = Get-MovieName
    $sel   = Get-GridSelections
    $log.Clear(); $script:InfoIdx = 0; $script:WarnIdx = 0
    $script:Encoding = $true; $script:CancelRequested = $false
    Set-Busy $true

    if ($script:CurrentTitle.Kind -eq 'dvd') {
        $script:Stage = 'dvd-encode'
        $tune = [string]$cmbTune.SelectedItem
        $progress.Style='Marquee'; $lblStat.Text='  encoding (DVD)...'
        Add-Log "==> DVD encode '$movie' (title $($script:CurrentTitle.Num))"
        $rs=[runspacefactory]::CreateRunspace(); $rs.ApartmentState='MTA'; $rs.Open()
        foreach ($kv in @{ CliPath=$DvdEncoderPath; InputPath=$drive; TitleNum=[int]$script:CurrentTitle.Num; Movie=$movie;
                           Tune=$tune; Container=[string]$cmbCont.SelectedItem; RF=[int]$numRF.Value; Preset=[string]$cmbPreset.SelectedItem;
                           AudioSel=[string]$sel.AudioSel; SubSel=[string]$sel.SubSel; AudioCodes=[string[]]$sel.AudioCodes; SubCodes=[string[]]$sel.SubCodes;
                           DoArchive=[bool]$chkArchive.Checked; DoRemux=[bool]$chkRemux.Checked; DoDry=[bool]$chkDry.Checked }.GetEnumerator()) {
            $rs.SessionStateProxy.SetVariable($kv.Key, $kv.Value)
        }
        $ps=[powershell]::Create(); $ps.Runspace=$rs
        [void]$ps.AddScript({
            $env:DVDENCODER_NOMENU='1'; . $CliPath
            $ErrorActionPreference = 'Continue'   # don't let the engine's global Stop turn HandBrake stderr into a fatal error
            try { Ensure-Dependencies } catch { Write-Host "ERROR: $($_.Exception.Message)"; return }
            Ensure-Directories
            $AutoAccept=$true; $DryRun=[bool]$DoDry; $Script:ArchiveSource=[bool]$DoArchive
            if (-not $DoRemux) { $Script:MkvPropEdit=$null }
            if ($Tune -eq 'auto') { try { $Tune=[string](Get-AutoTune -MovieName $Movie).Tune } catch { $Tune='' } }
            if ($Tune -eq 'none') { $Tune='' }
            Write-Host "encode: entering Encode-DvdTitle (title=$TitleNum, container=$Container, dryrun=$DoDry, archive=$DoArchive, remux=$DoRemux, tune='$Tune')"
            Write-Host "encode: OutputRoot=$Script:OutputRoot  HandBrake=$Script:HandBrakeCLI"
            try {
                Encode-DvdTitle -InputPath $InputPath -TitleNumber $TitleNum -MovieName $Movie -Tune $Tune `
                    -Container $Container -RF $RF -Preset $Preset -AudioSelection $AudioSel -SubtitleSelection $SubSel `
                    -AudioCodes $AudioCodes -SubtitleCodes $SubCodes
                Write-Host "encode: Encode-DvdTitle returned."
            }
            catch {
                Write-Host "ENCODE ERROR: $($_.Exception.Message)"
                Write-Host "ENCODE ERROR at: $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)  -> $($_.InvocationInfo.Line.Trim())"
            }
            try {
                # Only report an output that belongs to this movie, and never report
                # the temporary .__encoding file as a completed encode.
                $safe = New-SafeName -Name $Movie
                $patterns = @("$safe.$Container", "${safe}_*.$Container")
                $candidates = foreach ($pat in $patterns) {
                    Get-ChildItem -LiteralPath $Script:OutputRoot -Filter $pat -File -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -notmatch '\.__encoding_' }
                }
                $newest = @($candidates) | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                if ($newest) { Write-Output $newest.FullName }
            } catch { }
        })
        $script:Ps=$ps; $script:Rs=$rs; $script:Async=$ps.BeginInvoke()
        Start-EncodeTimer
    }
    else {
        # Blu-ray: stage A (decrypt + sidecar) then stage B (BRencoder).
        # Use the full-length (inclusion-independent) code arrays: BRencoder encodes
        # every source track from the sidecar and applies the language override
        # positionally, so the codes must line up with ALL source tracks, not just
        # the checked ones. (Incl is a DVD-only control — see the grid label.)
        $script:BdMovie = $movie
        $script:BdAudioCodes = [string[]]$sel.AudioCodesAll
        $script:BdSubCodes   = [string[]]$sel.SubCodesAll
        $script:BdBackupOnly = [bool]$chkBackupOnly.Checked
        Start-BdBackup
    }
}

function Start-BdBackup {
    $script:Stage = 'bd-backup'
    $progress.Style='Marquee'; $lblStat.Text='  MakeMKV decrypt...'
    Add-Log "==> Blu-ray decrypt + track metadata '$($script:BdMovie)'"
    $rs=[runspacefactory]::CreateRunspace(); $rs.ApartmentState='MTA'; $rs.Open()
    $rs.SessionStateProxy.SetVariable('BackupPath',  $BlurayBackupPath)
    $rs.SessionStateProxy.SetVariable('Movie',       $script:BdMovie)
    $rs.SessionStateProxy.SetVariable('TitleId',     [int]$script:CurrentTitle.Num)
    $rs.SessionStateProxy.SetVariable('ACodes',      $script:BdAudioCodes)
    $rs.SessionStateProxy.SetVariable('SCodes',      $script:BdSubCodes)
    $rs.SessionStateProxy.SetVariable('DriveLetter', (Get-DriveLetter))
    $ps=[powershell]::Create(); $ps.Runspace=$rs
    [void]$ps.AddScript({
        $env:BLURAYBACKUP_NOMENU='1'; . $BackupPath
        $ErrorActionPreference = 'Continue'   # MakeMKV/native stderr must not be fatal

function Get-MakeMKVPath {
    $names = @('makemkvcon.exe','makemkvcon64.exe')
    $roots = @(
        $env:MAKEMKV_HOME,
        $env:MAKEMKVCON,
        "$env:ProgramFiles\MakeMKV",
        "${env:ProgramFiles(x86)}\MakeMKV",
        "$env:LOCALAPPDATA\Programs\MakeMKV"
    ) | Where-Object { $_ }

    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($r in $roots) {
        if ($r -match '\.exe$') { [void]$candidates.Add($r) }
        else { foreach ($n in $names) { [void]$candidates.Add((Join-Path $r $n)) } }
    }
    foreach ($n in $names) {
        $cmd = Get-Command $n -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Source) { [void]$candidates.Add($cmd.Source) }
    }
    foreach ($reg in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )) {
        try {
            Get-ItemProperty $reg -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -like '*MakeMKV*' -and $_.InstallLocation } |
                ForEach-Object { foreach ($n in $names) { [void]$candidates.Add((Join-Path $_.InstallLocation $n)) } }
        } catch { }
    }
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ($base -and (Test-Path -LiteralPath $base)) {
            foreach ($n in $names) {
                try {
                    Get-ChildItem -LiteralPath $base -Directory -Filter '*MakeMKV*' -ErrorAction SilentlyContinue |
                        ForEach-Object { [void]$candidates.Add((Join-Path $_.FullName $n)) }
                } catch { }
            }
        }
    }
    $seen = @{}
    foreach ($path in $candidates) {
        if (-not $path) { continue }
        $full = [Environment]::ExpandEnvironmentVariables([string]$path).Trim('"')
        if ($seen.ContainsKey($full)) { continue }
        $seen[$full] = $true
        if (Test-Path -LiteralPath $full -PathType Leaf) { return $full }
    }
    Write-Host 'ERROR: MakeMKV CLI not found. Install MakeMKV or add its folder to PATH.'
    Write-Host '       Checked Program Files, Program Files (x86), PATH, registry, MAKEMKV_HOME, and MAKEMKVCON.'
    return $null
}

        Write-Host 'engine: bluray-backup (MakeMKV decrypt + Save-TrackMeta)'
        Ensure-Dirs
        $exe = Get-MakeMKVPath
        if (-not $exe) { Write-Host 'ERROR: MakeMKV not found.'; return $null }
        # Map the selected optical drive to MakeMKV's disc index (was hardcoded disc:0).
        $Script:Drive = Resolve-MakeMKVDiscIndex -Exe $exe -DriveLetter $DriveLetter
        Write-Host "MakeMKV source: $Script:Drive  (resolved from drive $DriveLetter)"
        $safe = Get-SafeName -Name $Movie
        $dest = Join-Path $Script:OutputRoot $safe
        $metaBase = Join-Path $Script:MetaRoot $safe
        Write-Host "bluray-backup: makemkvcon backup --decrypt -> $dest"
        & $exe backup --decrypt --cache=512 -r --progress=-same $Script:Drive $dest 2>&1 | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: MakeMKV exit $LASTEXITCODE"; return $null }
        $stream = Get-StreamPath -RootPath $dest
        if (-not $stream) { Write-Host 'ERROR: no STREAM folder'; return $null }
        $largest = Get-LargestM2TS -Path $stream
        if (-not $largest) { Write-Host 'ERROR: no m2ts'; return $null }
        # rebuild title metadata, apply the GUI's language edits, write sidecar.
        # Production rule: preserve CLPI-derived physical stream language order
        # so BRencoder can map/tag the actual raw .m2ts streams deterministically.
        $physicalStreams = if (Get-Command Read-ClpiStreamLanguages -ErrorAction SilentlyContinue) {
            Read-ClpiStreamLanguages -M2tsPath $largest.FullName
        } else {
            [pscustomobject]@{ Audio=@(); Subtitle=@(); Status='clpi: helper unavailable'; Source=$null }
        }
        Write-Host ("physical streams: {0}" -f $physicalStreams.Status)

        $lines = Get-MakeMKVInfoLines -Exe $exe -Source $Script:Drive
        $titles = ConvertFrom-MakeMKVInfo -Lines $lines
        $main = $titles | Where-Object { $_.TitleId -eq $TitleId } | Select-Object -First 1
        if (-not $main) { $main = Get-MainTitleFromInfo -Titles $titles }
        if (-not $main) { Write-Host 'ERROR: could not determine title metadata'; return $null }
        for ($i=0; $i -lt @($main.AudioTracks).Count; $i++) { if ($i -lt $ACodes.Count -and $ACodes[$i]) { $main.AudioTracks[$i].LanguageCode = $ACodes[$i] } }
        for ($i=0; $i -lt @($main.SubtitleTracks).Count; $i++) { if ($i -lt $SCodes.Count -and $SCodes[$i]) { $main.SubtitleTracks[$i].LanguageCode = $SCodes[$i] } }
        $meta = [pscustomobject]@{
            MovieName       = $Movie
            LargestM2TS     = $largest.Name
            LargestPath     = $largest.FullName
            PhysicalStreams = [pscustomobject]@{
                Source            = $physicalStreams.Source
                Status            = $physicalStreams.Status
                AudioLanguages    = @($physicalStreams.Audio)
                SubtitleLanguages = @($physicalStreams.Subtitle)
            }
            Title           = $main
        }
        Save-TrackMeta -Meta $meta -BasePath $metaBase
        Write-Host "bluray-backup Save-TrackMeta -> $metaBase.json"
        Write-Host "MAINM2TS=$($largest.FullName)"
        return $largest.FullName
    })
    $script:Ps=$ps; $script:Rs=$rs; $script:Async=$ps.BeginInvoke()
    Start-EncodeTimer
}

function Start-BdEncode {
    param([string]$M2ts)
    $script:Stage = 'bd-encode'
    $script:BdSourceM2ts = $M2ts
    $script:BdBackupRoot = Get-BluRayBackupRootFromM2ts -M2tsPath $M2ts
    $script:BdCleanupAfterEncode = (-not [bool]$chkKeepBackup.Checked)
    $progress.Style='Continuous'; Set-Progress 0; $lblStat.Text='  encoding (BRencoder)...'
    Add-Log "==> HEVC encode (BRencoder) '$($script:BdMovie)'"
    Add-Log "    $M2ts"
    $script:ProgFile = Join-Path $env:TEMP ('mediagui-prog-{0}.txt' -f ([guid]::NewGuid().ToString('N')))
    Remove-Item -LiteralPath $script:ProgFile -ErrorAction SilentlyContinue
    $rs=[runspacefactory]::CreateRunspace(); $rs.ApartmentState='MTA'; $rs.Open()
    $rs.SessionStateProxy.SetVariable('BRPath',     $BREncoderPath)
    $rs.SessionStateProxy.SetVariable('SourceFull', $M2ts)
    $rs.SessionStateProxy.SetVariable('Movie',      $script:BdMovie)
    $rs.SessionStateProxy.SetVariable('ProgFile',   $script:ProgFile)
    $ps=[powershell]::Create(); $ps.Runspace=$rs
    [void]$ps.AddScript({
        $env:BRENCODER_NOMENU='1'; . $BRPath
        $ErrorActionPreference = 'Continue'   # HandBrake stderr must not be fatal
        Write-Host 'engine: BRencoder Encode-File (HEVC, reads BRTrackMeta sidecar)'
        $fi = Get-Item -LiteralPath $SourceFull
        Encode-File -SourceFile $fi -MovieName $Movie -AutoAccept -ProgressFile $ProgFile
        try { Write-Output (Get-OutputPath -MovieName $Movie) } catch { }
    })
    $script:Ps=$ps; $script:Rs=$rs; $script:Async=$ps.BeginInvoke()
    $script:InfoIdx=0; $script:WarnIdx=0
    Start-EncodeTimer
}

# ════════════════════════════════════════════════════════════════
#  TOOLS  (sample / minfo / sidecar) — chained after an encode or standalone
# ════════════════════════════════════════════════════════════════
function Start-Sample {
    param([string]$Target)
    if (-not (Test-EngineAvailable -Path $MkvSamplePath -Name 'mkv-sample.ps1')) { Finish-Encode 'failed'; return }
    $script:Stage = 'sample'
    $progress.Style='Marquee'; $lblStat.Text='  creating sample clip...'
    Add-Log "==> Sample clip from $Target"
    $rs=[runspacefactory]::CreateRunspace(); $rs.ApartmentState='MTA'; $rs.Open()
    $rs.SessionStateProxy.SetVariable('SamplePath', $MkvSamplePath)
    $rs.SessionStateProxy.SetVariable('Target',     $Target)
    $ps=[powershell]::Create(); $ps.Runspace=$rs
    [void]$ps.AddScript({
        $env:MKVSAMPLE_NOMENU='1'; . $SamplePath
        $ErrorActionPreference = 'Continue'   # ffmpeg logs to stderr; don't let the engine's global Stop make that fatal
        Write-Host 'engine: mkv-sample Create-SampleFile'
        try { Ensure-Dependencies } catch { }
        try { Ensure-Directories } catch { }
        $fi = Get-Item -LiteralPath $Target
        Create-SampleFile -SourceFile $fi
    })
    $script:Ps=$ps; $script:Rs=$rs; $script:Async=$ps.BeginInvoke()
    $script:InfoIdx=0; $script:WarnIdx=0
    Start-EncodeTimer
}

function Start-Minfo {
    param([string]$Target)
    if (-not (Test-EngineAvailable -Path $MinfoPath -Name 'minfocreate.ps1')) { Finish-Encode 'failed'; return }
    $script:Stage = 'minfo'
    $imdbId = $txtImdb.Text.Trim()
    $progress.Style='Marquee'; $lblStat.Text='  creating minfo (MediaInfo + OMDb)...'
    Add-Log "==> Minfo / NFO for $Target"
    if ($imdbId) { Add-Log "    IMDb id: $imdbId" }
    $rs=[runspacefactory]::CreateRunspace(); $rs.ApartmentState='MTA'; $rs.Open()
    $rs.SessionStateProxy.SetVariable('MinfoPath', $MinfoPath)
    $rs.SessionStateProxy.SetVariable('Target',    $Target)
    $rs.SessionStateProxy.SetVariable('ImdbId',    $imdbId)
    $ps=[powershell]::Create(); $ps.Runspace=$rs
    [void]$ps.AddScript({
        Write-Host 'engine: minfocreate (MediaInfo + OMDb -> NFO/HTML/poster)'
        # Runspace has no console, so run minfocreate -NonInteractive. Pass the
        # GUI IMDb id when present so OMDb resolves without any prompts.
        try {
            if ($ImdbId) { & $MinfoPath -VideoFile $Target -NonInteractive -ImdbId $ImdbId }
            else         { & $MinfoPath -VideoFile $Target -NonInteractive }
        } catch { Write-Host "minfo error: $($_.Exception.Message)"; throw }
    })
    $script:Ps=$ps; $script:Rs=$rs; $script:Async=$ps.BeginInvoke()
    $script:InfoIdx=0; $script:WarnIdx=0
    Start-EncodeTimer
}

function Run-NextPost {
    # Pop and run the next queued post-encode step; finish when the queue empties.
    if (-not $script:PostQueue -or $script:PostQueue.Count -eq 0) { Finish-Encode 'done'; return }
    $next = $script:PostQueue[0]
    $script:PostQueue = @($script:PostQueue | Select-Object -Skip 1)
    $tgt = $script:LastOutput
    if (-not ($tgt -and (Test-Path -LiteralPath $tgt))) { Add-Log "    (post step '$next' skipped: no output file)"; Run-NextPost; return }
    switch ($next) {
        'sample' { Start-Sample -Target $tgt }
        'minfo'  { Start-Minfo  -Target $tgt }
        default  { Run-NextPost }
    }
}

function Start-Tool {
    # Standalone Tools-row run on the File source or the last encode output.
    param([string]$Kind)
    if ($script:Encoding -or $script:Stage -ne 'idle') { return }
    if ($Kind -eq 'sample' -and -not (Test-EngineAvailable -Path $MkvSamplePath -Name 'mkv-sample.ps1')) { return }
    if ($Kind -eq 'minfo'  -and -not (Test-EngineAvailable -Path $MinfoPath -Name 'minfocreate.ps1')) { return }
    $tgt = Get-ToolTarget
    if (-not $tgt) { [System.Windows.Forms.MessageBox]::Show('No target file. Pick a File source (Browse + Scan) or run an encode first.', 'Media Encoder GUI') | Out-Null; return }
    $log.Clear(); $script:InfoIdx=0; $script:WarnIdx=0
    $script:Encoding=$true; $script:CancelRequested=$false; Set-Busy $true
    $script:LastOutput = $tgt
    $script:PostQueue  = @($Kind)
    Run-NextPost
}

function Start-Dump {
    # Info-only BRTrackMeta sidecar via the trackdump engine (no decrypt, no prompts).
    if ($script:Encoding -or $script:Stage -ne 'idle') { return }
    $dumpPath = $TrackdumpPath
    $dumpMode = 'trackdump'
    if (-not ($dumpPath -and (Test-Path -LiteralPath $dumpPath -PathType Leaf))) {
        # Stable fallback: bluray-backup.ps1 contains the same MakeMKV info parser
        # and Save-TrackMeta writer, so the Dump Sidecar button still works even
        # when the optional bluray-trackdump.ps1 helper is not installed.
        $dumpPath = $BlurayBackupPath
        $dumpMode = 'backup-fallback'
    }
    if (-not (Test-EngineAvailable -Path $dumpPath -Name $(if ($dumpMode -eq 'trackdump') { 'bluray-trackdump.ps1' } else { 'bluray-backup.ps1 fallback for sidecar dump' }))) { return }
    if (-not $rbBd.Checked)        { [System.Windows.Forms.MessageBox]::Show('Dump sidecar is for Blu-ray. Select the Blu-ray source.', 'Media Encoder GUI') | Out-Null; return }
    if (-not $script:CurrentTitle) { [System.Windows.Forms.MessageBox]::Show('Scan the Blu-ray and pick a title first.', 'Media Encoder GUI') | Out-Null; return }
    $movie = Get-MovieName; $sel = Get-GridSelections
    $log.Clear(); $script:InfoIdx=0; $script:WarnIdx=0
    $script:Encoding=$true; $script:CancelRequested=$false; Set-Busy $true
    $script:Stage='trackdump'
    $progress.Style='Marquee'; $lblStat.Text='  dumping sidecar...'
    Add-Log "==> Dump BRTrackMeta sidecar '$movie' (info only, no decrypt)"
    $rs=[runspacefactory]::CreateRunspace(); $rs.ApartmentState='MTA'; $rs.Open()
    $rs.SessionStateProxy.SetVariable('DumpPath', $dumpPath)
    $rs.SessionStateProxy.SetVariable('DumpMode', $dumpMode)
    $rs.SessionStateProxy.SetVariable('Movie',    $movie)
    $rs.SessionStateProxy.SetVariable('TitleId',  [int]$script:CurrentTitle.Num)
    $rs.SessionStateProxy.SetVariable('ACodes',   [string[]]$sel.AudioCodesAll)
    $rs.SessionStateProxy.SetVariable('SCodes',      [string[]]$sel.SubCodesAll)
    $rs.SessionStateProxy.SetVariable('DriveLetter', (Get-DriveLetter))
    $ps=[powershell]::Create(); $ps.Runspace=$rs
    [void]$ps.AddScript({
        if ($DumpMode -eq 'backup-fallback') { $env:BLURAYBACKUP_NOMENU='1' }
        else { $env:BLURAYTRACKDUMP_NOMENU='1' }
        . $DumpPath
        $ErrorActionPreference = 'Continue'   # native tool stderr must not be fatal

function Get-MakeMKVPath {
    $names = @('makemkvcon.exe','makemkvcon64.exe')
    $roots = @(
        $env:MAKEMKV_HOME,
        $env:MAKEMKVCON,
        "$env:ProgramFiles\MakeMKV",
        "${env:ProgramFiles(x86)}\MakeMKV",
        "$env:LOCALAPPDATA\Programs\MakeMKV"
    ) | Where-Object { $_ }

    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($r in $roots) {
        if ($r -match '\.exe$') { [void]$candidates.Add($r) }
        else { foreach ($n in $names) { [void]$candidates.Add((Join-Path $r $n)) } }
    }
    foreach ($n in $names) {
        $cmd = Get-Command $n -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Source) { [void]$candidates.Add($cmd.Source) }
    }
    foreach ($reg in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )) {
        try {
            Get-ItemProperty $reg -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -like '*MakeMKV*' -and $_.InstallLocation } |
                ForEach-Object { foreach ($n in $names) { [void]$candidates.Add((Join-Path $_.InstallLocation $n)) } }
        } catch { }
    }
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ($base -and (Test-Path -LiteralPath $base)) {
            foreach ($n in $names) {
                try {
                    Get-ChildItem -LiteralPath $base -Directory -Filter '*MakeMKV*' -ErrorAction SilentlyContinue |
                        ForEach-Object { [void]$candidates.Add((Join-Path $_.FullName $n)) }
                } catch { }
            }
        }
    }
    $seen = @{}
    foreach ($path in $candidates) {
        if (-not $path) { continue }
        $full = [Environment]::ExpandEnvironmentVariables([string]$path).Trim('"')
        if ($seen.ContainsKey($full)) { continue }
        $seen[$full] = $true
        if (Test-Path -LiteralPath $full -PathType Leaf) { return $full }
    }
    Write-Host 'ERROR: MakeMKV CLI not found. Install MakeMKV or add its folder to PATH.'
    Write-Host '       Checked Program Files, Program Files (x86), PATH, registry, MAKEMKV_HOME, and MAKEMKVCON.'
    return $null
}

        Write-Host 'engine: bluray-trackdump (info-only sidecar)'
        Ensure-Dirs
        $exe = Get-MakeMKVPath
        if (-not $exe) { Write-Host 'ERROR: MakeMKV not found.'; return }
        # bluray-trackdump v1.4 defaults to disc:0. When a newer helper exposes
        # Resolve-MakeMKVDiscIndex, use it; otherwise keep the safe default.
        if (Get-Command Resolve-MakeMKVDiscIndex -ErrorAction SilentlyContinue) {
            try { $Script:Drive = Resolve-MakeMKVDiscIndex -Exe $exe -DriveLetter $DriveLetter } catch { $Script:Drive = 'disc:0' }
        } elseif (-not $Script:Drive) {
            $Script:Drive = 'disc:0'
        }
        Write-Host "MakeMKV source: $Script:Drive  (drive $DriveLetter)"
        Write-Host "reading disc info: makemkvcon -r info $Script:Drive  (no decrypt)..."
        $lines = Get-MakeMKVInfoLines -Exe $exe -Source $Script:Drive
        $titles = ConvertFrom-MakeMKVInfo -Lines $lines
        $main = $titles | Where-Object { $_.TitleId -eq $TitleId } | Select-Object -First 1
        if (-not $main) { $main = Get-MainTitleFromInfo -Titles $titles }
        if (-not $main) { Write-Host 'ERROR: could not determine main title'; return }
        for ($i=0; $i -lt @($main.AudioTracks).Count; $i++)    { if ($i -lt $ACodes.Count -and $ACodes[$i]) { $main.AudioTracks[$i].LanguageCode = $ACodes[$i] } }
        for ($i=0; $i -lt @($main.SubtitleTracks).Count; $i++) { if ($i -lt $SCodes.Count -and $SCodes[$i]) { $main.SubtitleTracks[$i].LanguageCode = $SCodes[$i] } }
        $safe = Get-SafeName $Movie
        $metaBase = Join-Path $Script:MetaRoot $safe
        $meta = [pscustomobject]@{ MovieName=$Movie; LargestM2TS=''; LargestPath=''; Title=$main }
        Save-TrackMeta -Meta $meta -BasePath $metaBase
        Write-Host "sidecar saved: $metaBase.json"
    })
    $script:Ps=$ps; $script:Rs=$rs; $script:Async=$ps.BeginInvoke()
    $script:InfoIdx=0; $script:WarnIdx=0
    Start-EncodeTimer
}

function Start-RipCd {
    # Audio CD -> FLAC. The CD rippers are interactive (MusicBrainz prompts) and
    # self-elevate (UAC), so they can't run in a silent runspace — launch the
    # chosen one in its OWN console window and let it drive the disc there.
    if ($script:Encoding -or $script:Stage -ne 'idle') { return }
    $image  = $rbCdImage.Checked
    $target = if ($image) { $CdImagePath } else { $CdTracksPath }
    $mode   = if ($image) { 'single image + CUE' } else { 'per-track FLAC' }
    if (-not (Test-Path -LiteralPath $target)) {
        [System.Windows.Forms.MessageBox]::Show("CD ripper not found:`n$target", 'Media Encoder GUI', 'OK', 'Error') | Out-Null
        return
    }
    $launcher = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
    if (-not $launcher) { $launcher = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source }
    if (-not $launcher) {
        [System.Windows.Forms.MessageBox]::Show('No pwsh / powershell.exe found to launch the CD ripper.', 'Media Encoder GUI', 'OK', 'Error') | Out-Null
        return
    }
    Add-Log "==> Launching Audio CD ripper ($mode) in its own window"
    Add-Log "    $target"
    Add-Log '    It will request elevation (UAC), read the disc, and prompt for MusicBrainz matches there.'
    try {
        Start-Process -FilePath $launcher -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File', $target)
        Add-Log '    Launched. Continue in the new window — this GUI stays free.'
    } catch {
        Add-Log "    ERROR launching CD ripper: $($_.Exception.Message)"
    }
}

function Start-EncodeTimer {
    $timer = New-Object System.Windows.Forms.Timer; $timer.Interval = 500; $script:Timer = $timer
    $timer.Add_Tick({
        if ($script:Ps) {
            $inf = $script:Ps.Streams.Information
            while ($script:InfoIdx -lt $inf.Count) { Add-Log ('    ' + (Strip-Ansi $inf[$script:InfoIdx].ToString())); $script:InfoIdx++ }
            $wrn = $script:Ps.Streams.Warning
            while ($script:WarnIdx -lt $wrn.Count) { Add-Log ('    WARN ' + (Strip-Ansi $wrn[$script:WarnIdx].ToString())); $script:WarnIdx++ }
        }
        # real % for the BRencoder (ffmpeg) stage
        if ($script:Stage -eq 'bd-encode' -and $script:ProgFile -and (Test-Path -LiteralPath $script:ProgFile)) {
            try {
                $tail = Get-Content -LiteralPath $script:ProgFile -Tail 12 -ErrorAction SilentlyContinue
                $ln = $tail | Where-Object { $_ -like 'out_time_us=*' } | Select-Object -Last 1
                if ($ln -and $script:TotalSeconds -gt 0) {
                    $secs = [double]($ln -replace 'out_time_us=','') / 1e6
                    Set-Progress ([int](($secs / $script:TotalSeconds) * 100))
                }
            } catch { }
        }
        if (-not ($script:Async -and $script:Async.IsCompleted)) { return }
        $script:Timer.Stop()
        $threw = $false; $ret = $null
        try { $ret = $script:Ps.EndInvoke($script:Async) } catch { $threw = $true; Add-Log "    ERROR: $($_.Exception.Message)" }
        $inf = $script:Ps.Streams.Information
        while ($script:InfoIdx -lt $inf.Count) { Add-Log ('    ' + (Strip-Ansi $inf[$script:InfoIdx].ToString())); $script:InfoIdx++ }
        try {
            $errs = $script:Ps.Streams.Error
            foreach ($e in $errs) { Add-Log ('    ERR ' + (Strip-Ansi $e.ToString())) }
        } catch { }
        $finishedStage = $script:Stage
        try { $script:Ps.Dispose() } catch { }; try { $script:Rs.Dispose() } catch { }
        $script:Ps=$null; $script:Rs=$null; $script:Async=$null; $script:Timer=$null

        if ($script:CancelRequested) { Finish-Encode 'cancelled'; return }
        if ($threw)                  { Finish-Encode 'failed'; return }

        switch ($finishedStage) {
            'bd-backup' {
                # extract the m2ts path the backup runspace reported
                $m2ts = $null
                foreach ($r in @($ret)) { if ($r -is [string] -and $r -match '\.m2ts$') { $m2ts = $r } }
                if ($script:BdBackupOnly) {
                    if ($m2ts) {
                        Add-Log "    decrypted backup: $m2ts"
                        Add-Log "    (full decrypted disc in: $(Split-Path -Parent $m2ts))"
                    } else {
                        Add-Log '    decrypt finished (see MakeMKV output above for the backup folder).'
                    }
                    Add-Log '    Backup only — skipped BRencoder.'
                    Finish-Encode 'done'; return
                }
                # otherwise chain to the BRencoder encode stage
                if (-not $m2ts) { Add-Log '    Could not locate decrypted m2ts.'; Finish-Encode 'failed'; return }
                $script:InfoIdx = 0
                Start-BdEncode -M2ts $m2ts
                return
            }
            { $_ -eq 'bd-encode' -or $_ -eq 'dvd-encode' } {
                # capture the output file, then run any queued post-encode steps.
                # Stable rule: a non-dry encode with no finished output is a failure,
                # not a soft "done".
                $out = $null
                foreach ($r in @($ret)) { if ($r -is [string] -and $r -match '\.(mkv|mp4)$' -and (Test-Path -LiteralPath $r)) { $out = $r } }
                if ($out) {
                    $script:LastOutput = $out
                    Add-Log "    output: $out"
                }
                elseif ($finishedStage -eq 'dvd-encode' -and $chkDry.Checked) {
                    Add-Log '    DVD dry run complete.'
                    Finish-Encode 'done'
                    return
                }
                else {
                    Add-Log '    ERROR: no finished output file was detected.'
                    Finish-Encode 'failed'
                    return
                }
                $script:PostQueue = @()
                if ($chkPostSample.Checked) { $script:PostQueue += 'sample' }
                if ($chkPostMinfo.Checked)  { $script:PostQueue += 'minfo' }
                $script:InfoIdx = 0
                Run-NextPost
                return
            }
            { $_ -eq 'sample' -or $_ -eq 'minfo' } {
                $script:InfoIdx = 0
                Run-NextPost
                return
            }
            default { Finish-Encode 'done'; return }
        }
    })
    $timer.Start()
}

function Finish-Encode {
    param([string]$How)
    if ($How -eq 'done' -and $script:BdCleanupAfterEncode -and $script:BdBackupRoot) {
        Remove-BluRayBackupRoot -Root $script:BdBackupRoot
    }
    elseif ($How -eq 'done' -and $script:BdBackupRoot -and -not $script:BdCleanupAfterEncode) {
        Add-Log "    Blu-ray backup retained: $($script:BdBackupRoot)"
    }
    $script:BdCleanupAfterEncode = $false
    $script:BdBackupRoot = $null
    $progress.Style='Continuous'
    switch ($How) {
        'done'      { Set-Progress 100; Add-Log '==> Done.' }
        'cancelled' { Set-Progress 0;   Add-Log '==> Cancelled.' }
        default     { Set-Progress 0;   Add-Log '==> Failed (see log).' }
    }
    if ($script:ProgFile) { Remove-Item -LiteralPath $script:ProgFile -ErrorAction SilentlyContinue; $script:ProgFile=$null }
    $script:Encoding = $false; $script:Stage = 'idle'; $lblStat.Text=''
    $script:PostQueue = @()
    Set-Busy $false
}

function Stop-Encode {
    if (-not $script:Encoding -and $script:Stage -eq 'idle') { return }
    $script:CancelRequested = $true; $btnCancel.Enabled = $false
    Add-Log '==> Cancelling...'
    $targets = switch ($script:Stage) {
        'dvd-encode' { @('HandBrakeCLI.exe') }
        'bd-backup'  { @('makemkvcon.exe','makemkvcon64.exe') }
        'bd-encode'  { @('ffmpeg.exe') }
        'sample'     { @('ffmpeg.exe') }
        'minfo'      { @('MediaInfo.exe','curl.exe') }
        'trackdump'  { @('makemkvcon.exe','makemkvcon64.exe') }
        default      { @('HandBrakeCLI.exe','makemkvcon.exe','makemkvcon64.exe','ffmpeg.exe','MediaInfo.exe') }
    }
    foreach ($name in $targets) {
        try {
            Get-CimInstance Win32_Process -Filter "Name='$name'" -ErrorAction SilentlyContinue |
                Where-Object { $_.ParentProcessId -eq $PID } |
                ForEach-Object { Add-Log "    kill $name PID $($_.ProcessId)"; Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        } catch { }
    }
    if ($script:Ps) { try { $script:Ps.Stop() } catch { } }
}

# ── events ───────────────────────────────────────────────────
function Get-DiscType {
    param([string]$Drive)
    if (-not $Drive) { return $null }
    if (Test-Path -LiteralPath (Join-Path $Drive 'BDMV'))     { return 'bluray' }
    if (Test-Path -LiteralPath (Join-Path $Drive 'VIDEO_TS')) { return 'dvd' }
    return $null
}
function Sync-DiscType {
    if ($rbFile.Checked) { return $null }
    $t = Get-DiscType (Get-DriveLetter)
    if     ($t -eq 'dvd')    { $rbDvd.Checked = $true }
    elseif ($t -eq 'bluray') { $rbBd.Checked  = $true }
    return $t
}
function Update-SourceUi {
    $kind = Get-SourceKind
    $dvd  = ($kind -eq 'dvd'); $bd = ($kind -eq 'bluray'); $file = ($kind -eq 'file'); $cd = ($kind -eq 'cd')
    foreach ($c in @($numRF, $cmbPreset, $cmbCont, $cmbTune, $chkArchive, $chkRemux, $chkDry)) { $c.Enabled = $dvd }
    $chkDry.Visible        = $dvd
    $chkBackupOnly.Visible = $bd
    $chkKeepBackup.Enabled = $bd
    $lblBdNote.Visible     = $bd
    # DVD/BD checkboxes hide in CD mode; the CD rip-mode controls take their slot
    $chkArchive.Visible    = -not $cd
    $chkRemux.Visible      = -not $cd
    $chkKeepBackup.Visible = -not $cd
    $lblCdMode.Visible     = $cd
    $rbCdTracks.Visible    = $cd
    $rbCdImage.Visible     = $cd
    $lblCdNote.Visible     = $cd
    # 'After encode' post steps don't apply to a CD rip (it runs in its own window)
    $lblPost.Visible       = -not $cd
    $chkPostSample.Visible = -not $cd
    $chkPostMinfo.Visible  = -not $cd
    $cmbDrive.Visible      = -not $file
    $txtFile.Visible       = $file
    $btnBrowse.Visible     = $file
    $btnDump.Enabled       = $bd
    $btnScan.Enabled       = -not $cd          # no in-GUI scan for an audio CD
    $btnEncode.Enabled     = -not $file
    $btnScan.Text          = if ($file) { 'Probe' } else { 'Scan' }
    $btnEncode.Text        = if ($cd)   { 'Rip CD' } else { 'Encode' }
    try { if (Get-Command Update-SourceCardVisuals -ErrorAction SilentlyContinue) { Update-SourceCardVisuals } } catch { }
    Update-Plan
}
function Update-Plan {
    # Live one-line summary of exactly what the Encode button will run, so the
    # chain is visible before it kicks off.
    if (-not $lblPlan) { return }
    $kind = Get-SourceKind
    if ($kind -eq 'file') {
        $lblPlan.Text = 'Plan:  File mode — tools only (use Create sample / Create minfo)'
        return
    }
    if ($kind -eq 'cd') {
        $m = if ($rbCdImage.Checked) { 'single image + CUE' } else { 'per-track FLAC' }
        $lblPlan.Text = "Plan:  Audio CD -> $m   (FLAC + MusicBrainz, runs in its own elevated window)"
        return
    }
    $steps = @()
    if ($kind -eq 'bluray') {
        if ($chkBackupOnly.Checked) { $lblPlan.Text = 'Plan:  decrypt full Blu-ray backup  (backup only — no encode)'; return }
        $steps += 'decrypt'; $steps += 'HEVC encode'
    } else {
        if ($chkDry.Checked) { $lblPlan.Text = 'Plan:  DVD dry run  (no encode)'; return }
        $steps += 'HandBrake encode'
        if ($chkArchive.Checked) { $steps += 'archive VIDEO_TS' }
        if ($chkRemux.Checked)   { $steps += 'tag languages' }
    }
    if ($chkPostSample.Checked) { $steps += 'sample' }
    if ($chkPostMinfo.Checked)  { $steps += 'minfo' }
    $lblPlan.Text = 'Plan:  ' + ($steps -join '   ->   ')
}
$rbDvd.Add_CheckedChanged({ Update-SourceUi })
$rbBd.Add_CheckedChanged({ Update-SourceUi })
$rbFile.Add_CheckedChanged({ Update-SourceUi })
$rbCd.Add_CheckedChanged({ Update-SourceUi })
$rbCdTracks.Add_CheckedChanged({ Update-Plan })
$rbCdImage.Add_CheckedChanged({ Update-Plan })
$cmbDrive.Add_SelectedIndexChanged({ $t = Sync-DiscType; if ($t) { Add-Log "Detected $($t.ToUpper()) in $(Get-DriveLetter)" } })
$btnScan.Add_Click({ Start-Scan })
$lstTitles.Add_SelectedIndexChanged({
    $i = $lstTitles.SelectedIndex; if ($i -lt 0 -or $i -ge $script:Titles.Count) { return }
    $T = $script:Titles[$i]
    Update-Grid $T
    # for the BRencoder progress bar we need a duration estimate
    $script:TotalSeconds = Get-DurSec $T.Duration
})
$btnEncode.Add_Click({ if ((Get-SourceKind) -eq 'cd') { Start-RipCd } else { Start-Encode } })
$btnCancel.Add_Click({ Stop-Encode })
# keep the live Plan line in sync with the toggles that change the chain
foreach ($cb in @($chkBackupOnly, $chkArchive, $chkRemux, $chkDry, $chkPostSample, $chkPostMinfo)) {
    $cb.Add_CheckedChanged({ Update-Plan })
}
$btnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = 'Video files|*.mkv;*.mp4;*.m2ts;*.ts;*.avi;*.mov;*.m4v|All files|*.*'
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $txtFile.Text = $dlg.FileName; Add-Log "File: $($dlg.FileName)" }
})
$btnSample.Add_Click({ Start-Tool 'sample' })
$btnMinfo.Add_Click({ Start-Tool 'minfo' })
$btnDump.Add_Click({ Start-Dump })
Write-DebugLog 'construction: events wired'

try {
    [void]$cmbDrive.Items.AddRange((Get-OpticalDrives))
    if ($cmbDrive.Items.Count -gt 0) { $cmbDrive.SelectedIndex = 0 }
    Update-SourceUi
    try { if ($script:UiChromeTimer) { $script:UiChromeTimer.Start() } } catch { }
    Write-DebugLog 'construction: drives populated, UI synced'
}
catch {
    Write-DebugLog ("FINALIZE ERROR: " + $_.Exception.Message + " @ line " + $_.InvocationInfo.ScriptLineNumber)
    try { [System.Windows.Forms.MessageBox]::Show("Startup error before window:`n$($_.Exception.Message)", 'Media Encoder GUI', 'OK', 'Error') | Out-Null } catch { }
}

$form.Add_Shown({
    Write-DebugLog 'Add_Shown: fired'
    try {
        Add-Log ("Media Encoder GUI v{0}  (DVD / Blu-ray / File / Audio CD)" -f $script:GuiVersion)
        Add-Log 'Engines:'
        $engineMap = [ordered]@{
            'dvd-ripper-encoder.ps1' = $DvdEncoderPath
            'bluray-backup.ps1'      = $BlurayBackupPath
            'BRencoder.ps1'          = $BREncoderPath
            'mkv-sample.ps1'         = $MkvSamplePath
            'minfocreate.ps1'        = $MinfoPath
            'bluray-trackdump.ps1'   = $TrackdumpPath
            'cd-tracks-flac.ps1'     = $CdTracksPath
            'cd-image-flac.ps1'      = $CdImagePath
        }
        $okColor   = [System.Drawing.Color]::FromArgb(120, 220, 120)
        $badColor  = [System.Drawing.Color]::FromArgb(240, 120, 120)
        foreach ($name in $engineMap.Keys) {
            $p = $engineMap[$name]
            if ($p -and (Test-Path -LiteralPath $p)) {
                Add-LogColor ("  [ OK ]    {0}" -f $name) $okColor
            }
            elseif ($name -eq 'bluray-trackdump.ps1' -and (Test-Path -LiteralPath $BlurayBackupPath)) {
                Add-LogColor ("  [FALLBACK] {0}   ->  using bluray-backup.ps1" -f $name) ([System.Drawing.Color]::FromArgb(120, 200, 255))
            }
            else {
                Add-LogColor ("  [MISSING] {0}   ->  {1}" -f $name, $p) $badColor
            }
        }
        Add-Log 'Pick a source, choose the drive, then Scan.'
        $dt = Sync-DiscType
        if ($dt) { Add-Log "Disc in $(Get-DriveLetter): $($dt.ToUpper()) — ready to Scan." } else { Add-Log 'No DVD/Blu-ray detected in the drive yet.' }
        Update-Plan
        Write-DebugLog 'Add_Shown: completed'
    }
    catch {
        Write-DebugLog ("Add_Shown ERROR: " + $_.Exception.Message)
        try { [System.Windows.Forms.MessageBox]::Show("Startup error:`n$($_.Exception.Message)", 'Media Encoder GUI', 'OK', 'Error') | Out-Null } catch { }
    }
})
if ($script:UiChromeTimer) { $form.Add_FormClosing({ try { $script:UiChromeTimer.Stop() } catch { } }) }
$form.Add_FormClosing({
    param($s,$e)
    if ($script:Encoding -or $script:Stage -ne 'idle') {
        $r = [System.Windows.Forms.MessageBox]::Show('A job is running. Stop it and quit?', 'Media Encoder GUI', 'YesNo', 'Warning')
        if ($r -ne 'Yes') { $e.Cancel = $true; return }
        if ($script:Timer) { try { $script:Timer.Stop() } catch { } }
        Stop-Encode
        if ($script:Ps) { try { $script:Ps.Dispose() } catch { } }
        if ($script:Rs) { try { $script:Rs.Dispose() } catch { } }
    }
})

Write-DebugLog 'reached ShowDialog'
try {
    [void]$form.ShowDialog()
    Write-DebugLog 'ShowDialog returned (window closed)'
}
catch {
    Write-DebugLog ("ShowDialog ERROR: " + $_.Exception.Message)
    try { [System.Windows.Forms.MessageBox]::Show("Fatal: $($_.Exception.Message)", 'Media Encoder GUI', 'OK', 'Error') | Out-Null } catch { }
}
