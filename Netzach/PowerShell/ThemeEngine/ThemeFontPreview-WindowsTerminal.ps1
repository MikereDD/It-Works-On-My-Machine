# Typezero ThemeEngine - Theme + Font visual comparison
# v1.3.0, based on v1.2.2. Preview and selection are read-only.
# The caller handles explicitly approved theme apply and optional preference save.
function Show-TypezeroThemeFontPreview {
    [CmdletBinding()]
    param(
        [string]$ThemesRoot = (Join-Path $env:LOCALAPPDATA 'Typezero\ThemeEngine\themes'),
        [string]$InitialFont = 'JetBrainsMono Nerd Font',
        [ValidateRange(6,36)][double]$InitialSize = 12,
        [ValidateSet('normal','semi-bold')][string]$InitialWeight = 'normal'
    )
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
        throw 'Theme/font preview requires PowerShell running in STA mode (pwsh -STA).'
    }
    if (-not (Test-Path -LiteralPath $ThemesRoot -PathType Container)) {
        throw "Installed ThemeEngine themes not found: $ThemesRoot"
    }
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase

    $themes = [ordered]@{}
    foreach ($dir in (Get-ChildItem -LiteralPath $ThemesRoot -Directory | Sort-Object Name)) {
        $conf = Join-Path $dir.FullName 'theme.conf'
        if (-not (Test-Path -LiteralPath $conf -PathType Leaf)) { continue }
        $values = @{}
        foreach ($raw in [IO.File]::ReadAllLines($conf)) {
            $line = $raw.Trim()
            if (-not $line -or $line.StartsWith('#')) { continue }
            $idx = $line.IndexOf('=')
            if ($idx -lt 1) { continue }
            $key = $line.Substring(0,$idx).Trim().ToUpperInvariant()
            $value = $line.Substring($idx + 1).Trim()
            if ($value.Length -ge 2 -and (
                ($value.StartsWith('"') -and $value.EndsWith('"')) -or
                ($value.StartsWith("'") -and $value.EndsWith("'")))) {
                $value = $value.Substring(1,$value.Length - 2)
            }
            $values[$key] = $value
        }
        if ($values.ContainsKey('BG') -and $values.ContainsKey('TEXT')) {
            $themes[$dir.Name] = $values
        }
    }
    if ($themes.Count -eq 0) { throw 'No themes with BG and TEXT palette values were found.' }

    $fontNames = [Collections.Generic.List[string]]::new()
    foreach ($font in [Windows.Media.Fonts]::SystemFontFamilies) {
        $name = [string]$font.Source
        if ($name -and -not $fontNames.Contains($name)) { $fontNames.Add($name) }
    }
    $fontNames.Sort([StringComparer]::OrdinalIgnoreCase)
    $initialDisplay = if ($InitialFont -ceq 'JetBrainsMono Nerd Font') { 'JetBrainsMono NF' } else { $InitialFont }
    if (-not $fontNames.Contains($initialDisplay)) {
        $initialDisplay = if ($fontNames.Contains('Consolas')) { 'Consolas' } else { $fontNames[0] }
    }

    $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Typezero | Theme + Font Preview" Width="1100" Height="790" MinWidth="750" MinHeight="520" WindowStartupLocation="CenterScreen" Background="#111111">
  <Window.Resources>
    <SolidColorBrush x:Key="TzControlBg" Color="#242424" />
    <SolidColorBrush x:Key="TzPopupBg" Color="#202020" />
    <SolidColorBrush x:Key="TzText" Color="#F0F0F0" />
    <SolidColorBrush x:Key="TzMuted" Color="#B8B8B8" />
    <SolidColorBrush x:Key="TzBorder" Color="#696969" />
    <SolidColorBrush x:Key="TzAccent" Color="#D4AF37" />
    <SolidColorBrush x:Key="TzHighlightText" Color="#101010" />
    <SolidColorBrush x:Key="TzHover" Color="#383838" />
    <Style TargetType="TextBlock">
      <Setter Property="Foreground" Value="{DynamicResource TzText}" />
    </Style>
    <Style TargetType="ComboBoxItem">
      <Setter Property="Foreground" Value="{DynamicResource TzText}" />
      <Setter Property="Background" Value="{DynamicResource TzPopupBg}" />
      <Setter Property="Padding" Value="12,8" />
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBoxItem">
            <Border x:Name="ItemBorder" Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}">
              <ContentPresenter VerticalAlignment="Center" />
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsHighlighted" Value="True">
                <Setter TargetName="ItemBorder" Property="Background" Value="{DynamicResource TzAccent}" />
                <Setter Property="Foreground" Value="{DynamicResource TzHighlightText}" />
              </Trigger>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="ItemBorder" Property="Background" Value="{DynamicResource TzAccent}" />
                <Setter Property="Foreground" Value="{DynamicResource TzHighlightText}" />
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ComboBox">
      <Setter Property="Background" Value="{DynamicResource TzControlBg}" />
      <Setter Property="Foreground" Value="{DynamicResource TzText}" />
      <Setter Property="BorderBrush" Value="{DynamicResource TzBorder}" />
      <Setter Property="FontSize" Value="14" />
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBox">
            <Grid>
              <Border x:Name="Shell" Background="{DynamicResource TzControlBg}" BorderBrush="{DynamicResource TzBorder}" BorderThickness="1" CornerRadius="3" />
              <ToggleButton x:Name="DropToggle" Focusable="False" ClickMode="Press"
                            IsChecked="{Binding IsDropDownOpen, RelativeSource={RelativeSource TemplatedParent}, Mode=TwoWay}"
                            Background="Transparent" BorderThickness="0" HorizontalAlignment="Right" Width="30">
                <ToggleButton.Template>
                  <ControlTemplate TargetType="ToggleButton">
                    <Border Background="{TemplateBinding Background}">
                      <Path Fill="{DynamicResource TzText}" HorizontalAlignment="Center" VerticalAlignment="Center" Data="M 0 0 L 5 5 L 10 0 Z" />
                    </Border>
                  </ControlTemplate>
                </ToggleButton.Template>
              </ToggleButton>
              <!-- Closed selection: show only the first (label) TextBlock.
                   Expanded ComboBoxItems retain their visual specimen content. -->
              <TextBlock x:Name="ContentSite" Margin="12,0,32,0" IsHitTestVisible="False"
                         VerticalAlignment="Center" Foreground="{DynamicResource TzText}"
                         TextTrimming="CharacterEllipsis" TextWrapping="NoWrap"
                         Text="{Binding SelectedItem.Content.Children[0].Text, RelativeSource={RelativeSource TemplatedParent}}" />
              <TextBox x:Name="PART_EditableTextBox" Margin="10,2,32,2" Visibility="Collapsed" Background="Transparent" BorderThickness="0"
                       Foreground="{DynamicResource TzText}" VerticalContentAlignment="Center" FocusVisualStyle="{x:Null}" />
              <Popup x:Name="PART_Popup" Placement="Bottom" AllowsTransparency="True" Focusable="False"
                     IsOpen="{TemplateBinding IsDropDownOpen}" PopupAnimation="Fade">
                <Border x:Name="DropBorder" MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}"
                        MaxHeight="340" Background="{DynamicResource TzPopupBg}" BorderBrush="{DynamicResource TzAccent}" BorderThickness="1">
                  <ScrollViewer CanContentScroll="True" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto">
                    <ItemsPresenter KeyboardNavigation.DirectionalNavigation="Contained" />
                  </ScrollViewer>
                </Border>
              </Popup>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsEditable" Value="True">
                <Setter TargetName="PART_EditableTextBox" Property="Visibility" Value="Visible" />
                <Setter TargetName="ContentSite" Property="Visibility" Value="Collapsed" />
              </Trigger>
              <Trigger Property="IsKeyboardFocusWithin" Value="True">
                <Setter TargetName="Shell" Property="BorderBrush" Value="{DynamicResource TzAccent}" />
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.5" />
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="Button">
      <Setter Property="Background" Value="{DynamicResource TzControlBg}" />
      <Setter Property="Foreground" Value="{DynamicResource TzText}" />
      <Setter Property="BorderBrush" Value="{DynamicResource TzBorder}" />
      <Setter Property="BorderThickness" Value="1" />
      <Setter Property="FontSize" Value="14" />
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="ButtonShell" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3" Padding="16,8">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" />
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="ButtonShell" Property="Background" Value="{DynamicResource TzHover}" />
                <Setter TargetName="ButtonShell" Property="BorderBrush" Value="{DynamicResource TzAccent}" />
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="ButtonShell" Property="Background" Value="{DynamicResource TzAccent}" />
                <Setter Property="Foreground" Value="{DynamicResource TzHighlightText}" />
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.45" />
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <DockPanel Margin="20">
    <TextBlock DockPanel.Dock="Top" Text="TYPEZERO  /  THEME + FONT PREVIEW" Name="MainHeading" Foreground="{DynamicResource TzAccent}" FontSize="20" FontWeight="Bold" Margin="0,0,0,18" />
    <WrapPanel DockPanel.Dock="Top" Margin="0,0,0,12">
      <StackPanel Margin="0,0,14,10"><TextBlock Text="THEME" Foreground="{DynamicResource TzMuted}" Margin="0,0,0,4"/><ComboBox Name="ThemeBox" Width="215" Height="35" /></StackPanel>
      <StackPanel Margin="0,0,14,10"><TextBlock Text="FONT" Foreground="{DynamicResource TzMuted}" Margin="0,0,0,4"/><ComboBox Name="FontBox" Width="360" Height="35" IsEditable="False" IsTextSearchEnabled="True" /></StackPanel>
      <StackPanel Margin="0,0,14,10"><TextBlock Text="SIZE (PT)" Foreground="{DynamicResource TzMuted}" Margin="0,0,0,4"/><ComboBox Name="SizeBox" Width="95" Height="35" IsEditable="False" /></StackPanel>
      <StackPanel Margin="0,0,0,10"><TextBlock Text="WEIGHT" Foreground="{DynamicResource TzMuted}" Margin="0,0,0,4"/><ComboBox Name="WeightBox" Width="145" Height="35" /></StackPanel>
    </WrapPanel>
    <StackPanel DockPanel.Dock="Bottom" Margin="0,12,0,0">
      <TextBlock Text="Use Selection applies the theme. Live Terminal font activation remains disabled." TextWrapping="Wrap" Foreground="{DynamicResource TzMuted}" Margin="0,0,0,8" />
      <CheckBox Name="SaveFontPreferenceBox" IsChecked="False" Content="Save selected font, size and weight as a V2 preference for this theme" Foreground="{DynamicResource TzText}" Margin="0,0,0,6" />
      <TextBlock Text="Saving does not activate the font. Existing V1 mappings migrate to V2 using 12 pt / normal." TextWrapping="Wrap" Foreground="{DynamicResource TzMuted}" Margin="0,0,0,8" />
      <TextBlock Name="StatusLabel" Text="Preview only - no changes yet" TextWrapping="Wrap" Foreground="{DynamicResource TzMuted}" Margin="0,0,0,12" />
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <Button Name="CancelButton" Content="Cancel" Width="120" Height="38" Margin="0,0,10,0" />
        <Button Name="UseButton" Content="Use Selection" Width="150" Height="38" BorderBrush="{DynamicResource TzAccent}" />
      </StackPanel>
    </StackPanel>
    <Border Name="PreviewBorder" Background="#1D2021" Padding="18">
      <ScrollViewer HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Auto">
        <StackPanel>
          <TextBlock Name="ThemeTitle" FontSize="21" FontWeight="Bold" Margin="0,0,0,10" />
          <TextBlock Name="PreviewText" TextWrapping="NoWrap" FontSize="16" Foreground="#EEEEEE" />
          <StackPanel Orientation="Horizontal" Margin="0,20,0,0">
            <TextBlock Name="SuccessText" Text="SUCCESS    " FontWeight="Bold" />
            <TextBlock Name="WarningText" Text="WARNING    " FontWeight="Bold" />
            <TextBlock Name="ErrorText" Text="ERROR    " FontWeight="Bold" />
            <TextBlock Name="InfoText" Text="INFO" FontWeight="Bold" />
          </StackPanel>
        </StackPanel>
      </ScrollViewer>
    </Border>
  </DockPanel>
</Window>
'@
    $xml = [xml]$xaml
    $reader = [Xml.XmlNodeReader]::new($xml)
    $window = [Windows.Markup.XamlReader]::Load($reader)
    $mainHeading = $window.FindName('MainHeading')
    $themeBox = $window.FindName('ThemeBox')
    $fontBox = $window.FindName('FontBox')
    $sizeBox = $window.FindName('SizeBox')
    $weightBox = $window.FindName('WeightBox')
    $status = $window.FindName('StatusLabel')
    $saveFontPreference = $window.FindName('SaveFontPreferenceBox')
    $use = $window.FindName('UseButton')
    $cancel = $window.FindName('CancelButton')
    $border = $window.FindName('PreviewBorder')
    $title = $window.FindName('ThemeTitle')
    $preview = $window.FindName('PreviewText')
    $success = $window.FindName('SuccessText')
    $warning = $window.FindName('WarningText')
    $errorText = $window.FindName('ErrorText')
    $info = $window.FindName('InfoText')
    $preview.Text = @'
ABCDEFGHIJKLMNOPQRSTUVWXYZ  abcdefghijklmnopqrstuvwxyz
0123456789   ! @ # $ % ^ & * ( ) [ ] { } < >

The quick brown fox jumps over the lazy dog.
Sphinx of black quartz, judge my vow.

POWERSHELL 7
PS> Get-ChildItem | Where-Object Length -gt 1MB
PS> git status --short

TYPEZERO PROMPT
┌─[miker@netzach]─[ThemeEngine]
└─╼  _

NERD FONT / UNICODE
  󰊢 󰘳 󰆍 󰚰
✓ ✗ ★ → ← ↑ ↓ ─ │ ┌ ┐ └ ┘

NUMERIC ALIGNMENT
000001   123456   987654
10.00    200.50   999.99
'@
    # Visual ComboBoxItem entries hold their unchanged machine values in Tag.
    # All choices remain UI-only until Use Selection is explicitly clicked.
    $newEntry = {
        param([string]$Value,[string]$Label,[string]$Example,[string]$Face,[double]$Points,[string]$Emphasis)
        $item = [Windows.Controls.ComboBoxItem]::new()
        $item.Tag = $Value
        $item.HorizontalContentAlignment = 'Stretch'
        $layout = [Windows.Controls.StackPanel]::new()
        $layout.Orientation = 'Vertical'
        $labelBlock = [Windows.Controls.TextBlock]::new()
        $labelBlock.Text = $Label
        $labelBlock.FontSize = 14
        $layout.Children.Add($labelBlock) | Out-Null
        if ($Example) {
            $sample = [Windows.Controls.TextBlock]::new()
            $sample.Text = $Example
            $sample.FontSize = $Points
            if ($Face) { $sample.FontFamily = [Windows.Media.FontFamily]::new($Face) }
            if ($Emphasis -eq 'semi-bold') { $sample.FontWeight = [Windows.FontWeights]::SemiBold }
            $sample.Margin = [Windows.Thickness]::new(0,4,0,1)
            $layout.Children.Add($sample) | Out-Null
        }
        $item.Content = $layout
        return $item
    }
    foreach ($id in $themes.Keys) {
        $pal = $themes[$id]
        $friendly = if ($pal.ContainsKey('THEME_NAME') -and $pal['THEME_NAME']) { [string]$pal['THEME_NAME'] } else { [string]$id }
        $item = & $newEntry $id $friendly '' '' 14 ''
        $layout = [Windows.Controls.StackPanel]$item.Content
        $swatches = [Windows.Controls.StackPanel]::new()
        $swatches.Orientation = 'Horizontal'
        foreach ($key in @('BG','ACCENT','TEXT')) {
            $hex = if ($pal.ContainsKey($key)) { [string]$pal[$key] } else { '#777777' }
            if ($hex -notmatch '^#[A-Fa-f0-9]{6}$') { $hex = '#777777' }
            $chip = [Windows.Controls.Border]::new()
            $chip.Width = 26; $chip.Height = 8
            $chip.Margin = [Windows.Thickness]::new(0,5,4,0)
            $chip.Background = [Windows.Media.BrushConverter]::new().ConvertFromString($hex)
            $swatches.Children.Add($chip) | Out-Null
        }
        $layout.Children.Add($swatches) | Out-Null
        [void]$themeBox.Items.Add($item)
    }
    foreach ($font in $fontNames) {
        [void]$fontBox.Items.Add((& $newEntry $font $font 'Aa Bb 012345  {} []' $font 14 'normal'))
    }
    foreach ($n in @(6,8,9,10,11,12,13,14,15,16,18,20,22,24,28,32,36)) {
        $sizeText = [string]$n
        [void]$sizeBox.Items.Add((& $newEntry $sizeText "$sizeText pt" 'Aa Bb 0123' $initialDisplay ([double]$n * 96.0 / 72.0) 'normal'))
    }
    foreach ($w in @('normal','semi-bold')) {
        [void]$weightBox.Items.Add((& $newEntry $w $w 'Aa Bb 0123' $initialDisplay 18 $w))
    }
    $activeFile = Join-Path (Split-Path -Parent $ThemesRoot) 'current-theme'
    $active = if (Test-Path -LiteralPath $activeFile -PathType Leaf) { [IO.File]::ReadAllText($activeFile).Trim() } else { '' }
    $getChoice = { param($box,[string]$value)
        foreach ($entry in $box.Items) { if ([string]$entry.Tag -ceq $value) { return $entry } }
        return $null
    }
    $themeBox.SelectedItem = & $getChoice $themeBox $(if ($themes.Contains($active)) { $active } else { [string]@($themes.Keys)[0] })
    $fontBox.SelectedItem = & $getChoice $fontBox $initialDisplay
    $sizeBox.SelectedItem = & $getChoice $sizeBox ($InitialSize.ToString([Globalization.CultureInfo]::InvariantCulture))
    $weightBox.SelectedItem = & $getChoice $weightBox $InitialWeight
    $window.Tag = $null

    $brush = { param([string]$hex,[string]$fallback)
        if ($hex -notmatch '^#[a-fA-F0-9]{6}$') { $hex = $fallback }
        [Windows.Media.BrushConverter]::new().ConvertFromString($hex)
    }
    $refresh = {
        $id = if ($themeBox.SelectedItem) { [string]$themeBox.SelectedItem.Tag } else { '' }
        $face = if ($fontBox.SelectedItem) { [string]$fontBox.SelectedItem.Tag } else { '' }
        $weight = if ($weightBox.SelectedItem) { [string]$weightBox.SelectedItem.Tag } else { '' }
        $size = 0.0
        $valid = [double]::TryParse($(if ($sizeBox.SelectedItem) { [string]$sizeBox.SelectedItem.Tag } else { '' }),[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$size)
        if (-not $themes.Contains($id) -or -not $fontNames.Contains($face) -or -not $valid -or
            [double]::IsNaN($size) -or [double]::IsInfinity($size) -or $size -lt 6 -or $size -gt 36 -or
            $weight -cnotin @('normal','semi-bold')) {
            $use.IsEnabled = $false
            $status.Text = 'Select an installed font, valid theme, size (6-36), and weight.'
            return
        }
        $palette = $themes[$id]
        $get = { param([string]$key,[string]$fallback)
            if ($palette.ContainsKey($key)) { [string]$palette[$key] } else { $fallback }
        }
        $bg = & $get 'BG' '#101010'
        $fg = & $get 'TEXT' '#eeeeee'
        $accent = & $get 'ACCENT' '#d4af37'
        $surface = & $get 'BG' '#101010'
        $controlBackground = & $get 'BG_ALT' (& $get 'SECONDARY_BG' (& $get 'ANSI_BLACK' '#202020'))
        $popupBackground = & $get 'BG' '#101010'
        $muted = & $get 'SECONDARY' (& $get 'MUTED' '#b8b8b8')
        $controlBorder = & $get 'BORDER' (& $get 'ANSI_BRIGHT_BLACK' '#666666')
        $highlight = & $get 'SELECTION' $accent
        # Update WPF resources in place so open popups and all controls use
        # the selected palette, including item highlights and hover states.
        $resourceColors = @{
            TzControlBg = @($controlBackground, '#242424')
            TzPopupBg = @($popupBackground, '#202020')
            TzText = @($fg, '#eeeeee')
            TzMuted = @($muted, '#b8b8b8')
            TzBorder = @($controlBorder, '#666666')
            TzAccent = @($highlight, '#d4af37')
            TzHighlightText = @($bg, '#101010')
            TzHover = @($controlBorder, '#383838')
        }
        foreach ($key in $resourceColors.Keys) {
            $hex = [string]$resourceColors[$key][0]
            $fallback = [string]$resourceColors[$key][1]
            $window.Resources[$key] = & $brush $hex $fallback
        }
        $mainHeading.Foreground = & $brush $accent '#d4af37'
        $window.Background = & $brush $bg '#101010'
        $border.Background = & $brush $bg '#101010'
        $title.Foreground = & $brush $accent '#d4af37'
        $title.Text = "THEME: $id"
        $preview.Foreground = & $brush $fg '#eeeeee'
        foreach ($entry in $sizeBox.Items) {
            $sample = [Windows.Controls.StackPanel]$entry.Content
            if ($sample.Children.Count -gt 1) {
                $sample.Children[1].FontFamily = [Windows.Media.FontFamily]::new($face)
                $sample.Children[1].FontWeight = if ($weight -eq 'semi-bold') { [Windows.FontWeights]::SemiBold } else { [Windows.FontWeights]::Normal }
            }
        }
        foreach ($entry in $weightBox.Items) {
            $sample = [Windows.Controls.StackPanel]$entry.Content
            if ($sample.Children.Count -gt 1) { $sample.Children[1].FontFamily = [Windows.Media.FontFamily]::new($face) }
        }
        $preview.FontFamily = [Windows.Media.FontFamily]::new($face)
        $preview.FontSize = $size * 96.0 / 72.0
        $preview.FontWeight = if ($weight -eq 'semi-bold') { [Windows.FontWeights]::SemiBold } else { [Windows.FontWeights]::Normal }
        $success.Foreground = & $brush (& $get 'SUCCESS' '#7dbb69') '#7dbb69'
        $warning.Foreground = & $brush (& $get 'WARNING' '#e5b454') '#e5b454'
        $errorText.Foreground = & $brush (& $get 'ERROR' '#e05f65') '#e05f65'
        $info.Foreground = & $brush (& $get 'INFO' '#81b3db') '#81b3db'
        $status.Text = "Preview: $id | $face | $size pt | $weight  (no files changed)"
        $use.IsEnabled = $true
    }.GetNewClosure()
    $themeBox.Add_SelectionChanged({ & $refresh }.GetNewClosure())
    $fontBox.Add_SelectionChanged({ & $refresh }.GetNewClosure())
    $sizeBox.Add_SelectionChanged({ & $refresh }.GetNewClosure())
    $weightBox.Add_SelectionChanged({ & $refresh }.GetNewClosure())
    $cancel.Add_Click({ $window.Tag = $null; $window.Close() }.GetNewClosure())
    $use.Add_Click({
        & $refresh
        if (-not $use.IsEnabled) { return }
        $face = if ($fontBox.SelectedItem) { [string]$fontBox.SelectedItem.Tag } else { '' }
        $selectedFamily = if ($face -ceq 'JetBrainsMono NF' -and $InitialFont -ceq 'JetBrainsMono Nerd Font') { 'JetBrainsMono Nerd Font' } else { $face }
        $savePreference = $saveFontPreference.IsChecked -eq $true
        $themeId = [string]$themeBox.SelectedItem.Tag
        $fontAction = if ($savePreference) {
            "Save V2 font preference: $selectedFamily, $($sizeBox.SelectedItem.Tag) pt, $($weightBox.SelectedItem.Tag). Existing V1 mappings migrate using 12 pt / normal."
        } else { 'Do not save a font preference.' }
        $approval = [Windows.MessageBox]::Show($window,
            "Apply theme '$themeId' through ThemeEngine? This changes theme colors and appearance, and may switch an already-enabled wallpaper mapping.`n`n$fontAction`n`nLive Terminal font activation remains disabled.",
            'Apply selected theme', [Windows.MessageBoxButton]::YesNo,
            [Windows.MessageBoxImage]::Question, [Windows.MessageBoxResult]::No)
        if ($approval -ne [Windows.MessageBoxResult]::Yes) { return }
        $window.Tag = [pscustomobject]@{
            Accepted = $true
            ThemeApplyConsent = $true
            SaveFontPreferenceConsent = [bool]$savePreference
            Theme = [string]$themeBox.SelectedItem.Tag
            Family = $selectedFamily
            Size = [double]::Parse($(if ($sizeBox.SelectedItem) { [string]$sizeBox.SelectedItem.Tag } else { '' }),[Globalization.CultureInfo]::InvariantCulture)
            Weight = [string]$weightBox.SelectedItem.Tag
            PreviewOnly = $true
            SettingsChanged = $false
        }
        $window.Close()
    }.GetNewClosure())
    & $refresh
    $null = $window.ShowDialog()
    return $window.Tag
}
