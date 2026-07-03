<#
================================================================
  Media Encoder GUI  -  all-in-one disc -> HEVC front end
  version:  1.0.1  (stable production front end hotfix)  by Mike Redd
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
$form.Text = 'Media Encoder GUI  v1.0.0  (DVD / Blu-ray / File / Audio CD)'
$form.Size = New-Object System.Drawing.Size(1240, 920)
$form.MinimumSize = New-Object System.Drawing.Size(1040, 920)
$form.StartPosition = 'CenterScreen'
$form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 34)
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
        $sb = { $ctl.Style = 'Continuous'; $ctl.Value = $Pct }.GetNewClosure()
        [void]$ctl.BeginInvoke([System.Windows.Forms.MethodInvoker]$sb)
    } else {
        $ctl.Style = 'Continuous'; $ctl.Value = $Pct
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
    Write-DebugLog 'construction: drives populated, UI synced'
}
catch {
    Write-DebugLog ("FINALIZE ERROR: " + $_.Exception.Message + " @ line " + $_.InvocationInfo.ScriptLineNumber)
    try { [System.Windows.Forms.MessageBox]::Show("Startup error before window:`n$($_.Exception.Message)", 'Media Encoder GUI', 'OK', 'Error') | Out-Null } catch { }
}

$form.Add_Shown({
    Write-DebugLog 'Add_Shown: fired'
    try {
        Add-Log 'Media Encoder GUI v1.0.0  (DVD / Blu-ray / File / Audio CD)'
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
