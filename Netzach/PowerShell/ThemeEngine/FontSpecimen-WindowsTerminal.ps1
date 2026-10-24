
# Typezero ThemeEngine - Interactive Visual Font Specimen
# WPF preview only. No Windows Terminal or config writes.

function Show-TypezeroFontSpecimen {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Family,

        [ValidateRange(6,36)]
        [double]$Size = 12,

        [ValidateSet('normal','semi-bold')]
        [string]$Weight = 'normal'
    )

    if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
        throw 'WPF font preview requires an STA PowerShell session.'
    }

    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase

    $sampleText = @'
TYPEZERO / FONT SPECIMEN

ABCDEFGHIJKLMNOPQRSTUVWXYZ
abcdefghijklmnopqrstuvwxyz
0123456789

The quick brown fox jumps over the lazy dog.
Sphinx of black quartz, judge my vow.

SYMBOLS
! @ # $ % ^ & * ( ) _ + - =
{ } [ ] < > / \ | : ; " ' ` ~ ? . ,

POWERSHELL
PS> Get-ChildItem | Where-Object Length -gt 1MB
PS> git status --short
PS> Get-Process | Sort-Object CPU -Descending

TYPEZERO TERMINAL
┌─[miker@netzach]─[It-Works-On-My-Machine]
└─╼  _

NERD FONT / UNICODE
  󰊢 󰘳 󰆍 󰚰
✓ ✗ ★ → ← ↑ ↓ ─ │ ┌ ┐ └ ┘

NUMERIC ALIGNMENT
000001  123456  987654
10.00   200.50  999.99

ERROR     WARNING     SUCCESS
'@

    $background = [Windows.Media.BrushConverter]::new().
        ConvertFromString('#101010')
    $surface = [Windows.Media.BrushConverter]::new().
        ConvertFromString('#1B1B1B')
    $foreground = [Windows.Media.BrushConverter]::new().
        ConvertFromString('#F0F0F0')
    $secondary = [Windows.Media.BrushConverter]::new().
        ConvertFromString('#B8B8B8')
    $accent = [Windows.Media.BrushConverter]::new().
        ConvertFromString('#D4AF37')

    $fontNames = [Collections.Generic.List[string]]::new()

    foreach ($item in [Windows.Media.Fonts]::SystemFontFamilies) {
        $name = [string]$item.Source
        if (-not [string]::IsNullOrWhiteSpace($name) -and
            -not $fontNames.Contains($name)) {
            $fontNames.Add($name)
        }
    }

    $fontNames.Sort([StringComparer]::OrdinalIgnoreCase)

    $aliases = @{
        'JetBrainsMono Nerd Font' = 'JetBrainsMono NF'
    }

    $initialDisplay = if ($aliases.ContainsKey($Family)) {
        $aliases[$Family]
    } else {
        $Family
    }

    if (-not $fontNames.Contains($initialDisplay)) {
        throw "Font not found in WPF: $initialDisplay"
    }

    $window = [Windows.Window]::new()
    $window.Title = 'Typezero | Font Comparison'
    $window.Width = 1050
    $window.Height = 780
    $window.MinWidth = 720
    $window.MinHeight = 500
    $window.WindowStartupLocation = 'CenterScreen'
    $window.Background = $background
    $window.Tag = $null

    $root = [Windows.Controls.DockPanel]::new()
    $root.Margin = [Windows.Thickness]::new(20)

    $heading = [Windows.Controls.TextBlock]::new()
    $heading.Text = 'TYPEZERO  /  FONT COMPARISON'
    $heading.FontSize = 21
    $heading.FontWeight = [Windows.FontWeights]::Bold
    $heading.Foreground = $accent
    $heading.Margin = [Windows.Thickness]::new(0,0,0,14)

    [Windows.Controls.DockPanel]::SetDock(
        $heading, [Windows.Controls.Dock]::Top
    )
    $root.Children.Add($heading) | Out-Null

    $controls = [Windows.Controls.WrapPanel]::new()
    $controls.Margin = [Windows.Thickness]::new(0,0,0,12)

    $fontPanel = [Windows.Controls.StackPanel]::new()
    $fontPanel.Margin = [Windows.Thickness]::new(0,0,12,8)

    $fontLabel = [Windows.Controls.TextBlock]::new()
    $fontLabel.Text = 'FONT FAMILY'
    $fontLabel.Foreground = $secondary
    $fontLabel.Margin = [Windows.Thickness]::new(0,0,0,5)
    $fontPanel.Children.Add($fontLabel) | Out-Null

    $fontCombo = [Windows.Controls.ComboBox]::new()
    $fontCombo.Width = 440
    $fontCombo.Height = 36
    $fontCombo.IsEditable = $true
    $fontCombo.IsTextSearchEnabled = $true

    foreach ($name in $fontNames) {
        $fontCombo.Items.Add($name) | Out-Null
    }

    $fontCombo.Text = $initialDisplay
    $fontPanel.Children.Add($fontCombo) | Out-Null
    $controls.Children.Add($fontPanel) | Out-Null

    $sizePanel = [Windows.Controls.StackPanel]::new()
    $sizePanel.Margin = [Windows.Thickness]::new(0,0,12,8)

    $sizeLabel = [Windows.Controls.TextBlock]::new()
    $sizeLabel.Text = 'SIZE (PT)'
    $sizeLabel.Foreground = $secondary
    $sizeLabel.Margin = [Windows.Thickness]::new(0,0,0,5)
    $sizePanel.Children.Add($sizeLabel) | Out-Null

    $sizeCombo = [Windows.Controls.ComboBox]::new()
    $sizeCombo.Width = 95
    $sizeCombo.Height = 36
    $sizeCombo.IsEditable = $true

    foreach ($pointSize in @(6,8,9,10,11,12,13,14,15,16,18,20,22,24,28,32,36)) {
        $sizeCombo.Items.Add([string]$pointSize) | Out-Null
    }

    $sizeCombo.Text = $Size.ToString(
        [Globalization.CultureInfo]::InvariantCulture
    )
    $sizePanel.Children.Add($sizeCombo) | Out-Null
    $controls.Children.Add($sizePanel) | Out-Null

    $weightPanel = [Windows.Controls.StackPanel]::new()
    $weightPanel.Margin = [Windows.Thickness]::new(0,0,0,8)

    $weightLabel = [Windows.Controls.TextBlock]::new()
    $weightLabel.Text = 'WEIGHT'
    $weightLabel.Foreground = $secondary
    $weightLabel.Margin = [Windows.Thickness]::new(0,0,0,5)
    $weightPanel.Children.Add($weightLabel) | Out-Null

    $weightCombo = [Windows.Controls.ComboBox]::new()
    $weightCombo.Width = 145
    $weightCombo.Height = 36
    $weightCombo.Items.Add('normal') | Out-Null
    $weightCombo.Items.Add('semi-bold') | Out-Null
    $weightCombo.SelectedItem = $Weight
    $weightPanel.Children.Add($weightCombo) | Out-Null
    $controls.Children.Add($weightPanel) | Out-Null

    [Windows.Controls.DockPanel]::SetDock(
        $controls, [Windows.Controls.Dock]::Top
    )
    $root.Children.Add($controls) | Out-Null

    $footer = [Windows.Controls.StackPanel]::new()
    $footer.Margin = [Windows.Thickness]::new(0,12,0,0)

    $status = [Windows.Controls.TextBlock]::new()
    $status.Text = 'PREVIEW ONLY - Windows Terminal unchanged'
    $status.Foreground = $secondary
    $status.Margin = [Windows.Thickness]::new(0,0,0,12)
    $footer.Children.Add($status) | Out-Null

    $buttons = [Windows.Controls.StackPanel]::new()
    $buttons.Orientation = 'Horizontal'
    $buttons.HorizontalAlignment = 'Right'

    $cancel = [Windows.Controls.Button]::new()
    $cancel.Content = 'Cancel'
    $cancel.Width = 130
    $cancel.Height = 38
    $cancel.Margin = [Windows.Thickness]::new(0,0,10,0)
    $buttons.Children.Add($cancel) | Out-Null

    $accept = [Windows.Controls.Button]::new()
    $accept.Content = 'Use Selection'
    $accept.Width = 150
    $accept.Height = 38
    $buttons.Children.Add($accept) | Out-Null

    $footer.Children.Add($buttons) | Out-Null

    [Windows.Controls.DockPanel]::SetDock(
        $footer, [Windows.Controls.Dock]::Bottom
    )
    $root.Children.Add($footer) | Out-Null

    $preview = [Windows.Controls.TextBox]::new()
    $preview.Text = $sampleText
    $preview.IsReadOnly = $true
    $preview.AcceptsReturn = $true
    $preview.TextWrapping = 'NoWrap'
    $preview.VerticalScrollBarVisibility = 'Auto'
    $preview.HorizontalScrollBarVisibility = 'Auto'
    $preview.Background = $surface
    $preview.Foreground = $foreground
    $preview.BorderThickness = [Windows.Thickness]::new(0)
    $preview.Padding = [Windows.Thickness]::new(18)
    $preview.FontFamily = [Windows.Media.FontFamily]::new(
        $initialDisplay
    )
    $preview.FontSize = $Size * 96.0 / 72.0
    $preview.FontWeight = if ($Weight -eq 'semi-bold') {
        [Windows.FontWeights]::SemiBold
    } else {
        [Windows.FontWeights]::Normal
    }

    $root.Children.Add($preview) | Out-Null
    $window.Content = $root

    # All interaction remains within this modal preview window.
    $refresh = {
        $selectedFont = [string]$fontCombo.Text
        $selectedWeight = [string]$weightCombo.SelectedItem
        $selectedSize = 0.0

        $validSize = [double]::TryParse(
            [string]$sizeCombo.Text,
            [Globalization.NumberStyles]::Float,
            [Globalization.CultureInfo]::InvariantCulture,
            [ref]$selectedSize
        )

        if (-not $fontNames.Contains($selectedFont)) {
            $status.Text = 'Select an installed font family.'
            $accept.IsEnabled = $false
            return
        }

        if (-not $validSize -or
            $selectedSize -lt 6 -or $selectedSize -gt 36) {
            $status.Text = 'Font size must be between 6 and 36 pt.'
            $accept.IsEnabled = $false
            return
        }

        if ($selectedWeight -cnotin @('normal','semi-bold')) {
            $accept.IsEnabled = $false
            return
        }

        $preview.FontFamily = [Windows.Media.FontFamily]::new(
            $selectedFont
        )
        $preview.FontSize = $selectedSize * 96.0 / 72.0
        $preview.FontWeight = if ($selectedWeight -eq 'semi-bold') {
            [Windows.FontWeights]::SemiBold
        } else {
            [Windows.FontWeights]::Normal
        }

        $status.Text = "PREVIEW: $selectedFont / $selectedSize pt / $selectedWeight"
        $accept.IsEnabled = $true
    }.GetNewClosure()

    $fontCombo.Add_SelectionChanged({
        & $refresh
    }.GetNewClosure())

    $fontCombo.Add_KeyUp({
        & $refresh
    }.GetNewClosure())

    $sizeCombo.Add_SelectionChanged({
        & $refresh
    }.GetNewClosure())

    $sizeCombo.Add_KeyUp({
        & $refresh
    }.GetNewClosure())

    $weightCombo.Add_SelectionChanged({
        & $refresh
    }.GetNewClosure())

    $cancel.Add_Click({
        $window.Tag = $null
        $window.Close()
    }.GetNewClosure())

    $accept.Add_Click({
        & $refresh

        if (-not $accept.IsEnabled) {
            return
        }

        $chosenDisplay = [string]$fontCombo.Text
        $chosenFamily = if (
            $Family -ceq 'JetBrainsMono Nerd Font' -and
            $chosenDisplay -ceq 'JetBrainsMono NF'
        ) {
            'JetBrainsMono Nerd Font'
        } else {
            $chosenDisplay
        }

        $chosenSize = [double]::Parse(
            [string]$sizeCombo.Text,
            [Globalization.CultureInfo]::InvariantCulture
        )

        $window.Tag = [pscustomobject]@{
            Accepted = $true
            Family = $chosenFamily
            Size = $chosenSize
            Weight = [string]$weightCombo.SelectedItem
            PreviewOnly = $true
            SettingsChanged = $false
        }

        $window.Close()
    }.GetNewClosure())

    & $refresh
    $null = $window.ShowDialog()

    return $window.Tag
}
