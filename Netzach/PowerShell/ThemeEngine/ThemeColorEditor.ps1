# Typezero ThemeEngine - WPF theme color editor (Dark Monochrome chrome)
# Edits a copy of an installed theme and saves it as a NEW theme only. The
# preview pane renders the edited palette; the editor chrome stays neutral so
# it does not bias color judgement. Terminal/desktop activation is unchanged:
# the caller's existing Apply actions activate a saved theme.
. (Join-Path $PSScriptRoot 'ThemeEditor-ThemeConf.ps1')

function Show-TypezeroThemeColorEditor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$InstalledThemesRoot,
        [AllowEmptyString()][string]$SharedThemesRoot,
        [Parameter(Mandatory)][string]$ThemeId,
        [Windows.Window]$Owner,
        # Test hook: receives the initialized window and controls without showing it.
        [scriptblock]$OnLoaded
    )
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
        throw 'The theme color editor requires PowerShell running in STA mode (pwsh -STA).'
    }
    $sourcePath = Join-Path (Join-Path $InstalledThemesRoot $ThemeId) 'theme.conf'
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw "Theme not found: $ThemeId" }
    $sourceText = [IO.File]::ReadAllText($sourcePath, [Text.UTF8Encoding]::new($false, $true))
    # Closures below (GetNewClosure) cannot resolve script-scope functions by name when the
    # engine is launched via '& ThemeEngine.ps1'; capture the helpers they call.
    $isHexColor = Get-Command Test-TypezeroThemeHexColor -CommandType Function
    $isThemeId = Get-Command Test-TypezeroThemeId -CommandType Function
    $isDisplayName = Get-Command Test-TypezeroThemeDisplayName -CommandType Function
    $saveDerivedTheme = Get-Command Save-TypezeroDerivedTheme -CommandType Function
    $sourceValues = ConvertFrom-TypezeroThemeConfText -Text $sourceText
    $roles = @(Get-TypezeroThemeColorRoles -Text $sourceText)
    if ($roles.Count -eq 0) { throw "Theme '$ThemeId' defines no #RRGGBB color roles." }
    $sourceName = if ($sourceValues.Contains('THEME_NAME') -and $sourceValues['THEME_NAME']) { [string]$sourceValues['THEME_NAME'] } else { $ThemeId }

    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase

    $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Typezero | Edit Theme Colors" Width="1180" Height="820" MinWidth="900" MinHeight="640"
        WindowStartupLocation="CenterOwner" Background="#111111" FontSize="14">
  <Window.Resources>
    <SolidColorBrush x:Key="TzControlBg" Color="#242424" />
    <SolidColorBrush x:Key="TzText" Color="#F0F0F0" />
    <SolidColorBrush x:Key="TzMuted" Color="#B8B8B8" />
    <SolidColorBrush x:Key="TzBorder" Color="#696969" />
    <SolidColorBrush x:Key="TzAccent" Color="#E6E6E6" />
    <SolidColorBrush x:Key="TzHover" Color="#383838" />
    <Style TargetType="TextBlock"><Setter Property="Foreground" Value="{StaticResource TzText}" /></Style>
    <Style TargetType="TextBox">
      <Setter Property="Background" Value="{StaticResource TzControlBg}" />
      <Setter Property="Foreground" Value="{StaticResource TzText}" />
      <Setter Property="BorderBrush" Value="{StaticResource TzBorder}" />
      <Setter Property="CaretBrush" Value="{StaticResource TzText}" />
      <Setter Property="Padding" Value="8,4" />
      <Setter Property="FontSize" Value="14" />
    </Style>
    <Style TargetType="Button">
      <Setter Property="Background" Value="{StaticResource TzControlBg}" />
      <Setter Property="Foreground" Value="{StaticResource TzText}" />
      <Setter Property="BorderBrush" Value="{StaticResource TzBorder}" />
      <Setter Property="BorderThickness" Value="1" />
      <Setter Property="FontSize" Value="14" />
      <Setter Property="FontWeight" Value="SemiBold" />
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="ButtonShell" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="3" Padding="14,6">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" />
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="ButtonShell" Property="Background" Value="{StaticResource TzHover}" />
                <Setter TargetName="ButtonShell" Property="BorderBrush" Value="{StaticResource TzAccent}" />
              </Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45" /></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <DockPanel Margin="20">
    <StackPanel DockPanel.Dock="Top" Margin="0,0,0,14">
      <TextBlock Name="EditorHeading" Text="TYPEZERO  /  EDIT THEME COLORS" FontSize="20" FontWeight="Bold" />
      <TextBlock Name="SourceLabel" Foreground="{StaticResource TzMuted}" FontWeight="Medium" Margin="0,4,0,0" />
    </StackPanel>
    <StackPanel DockPanel.Dock="Bottom" Margin="0,14,0,0">
      <WrapPanel>
        <StackPanel Margin="0,0,14,8"><TextBlock Text="NEW THEME ID (lowercase letters, numbers, hyphens)" Foreground="{StaticResource TzMuted}" FontWeight="SemiBold" Margin="0,0,0,4"/><TextBox Name="NewIdBox" Width="330" Height="34" /></StackPanel>
        <StackPanel Margin="0,0,0,8"><TextBlock Text="DISPLAY NAME" Foreground="{StaticResource TzMuted}" FontWeight="SemiBold" Margin="0,0,0,4"/><TextBox Name="NameBox" Width="330" Height="34" /></StackPanel>
      </WrapPanel>
      <TextBlock Name="SaveHint" TextWrapping="Wrap" Foreground="{StaticResource TzMuted}" FontWeight="Medium" Margin="0,4,0,4" />
      <TextBlock Text="Saving creates ThemeEngine/themes/&lt;id&gt;/theme.conf in the shared repository source (for Netzach and Arakiel) and installs it here. Existing themes are never changed. Nothing is activated; use the Apply buttons afterwards." TextWrapping="Wrap" Foreground="{StaticResource TzMuted}" Margin="0,0,0,10" />
      <WrapPanel HorizontalAlignment="Right">
        <Button Name="ResetAllButton" Content="Reset All" Width="120" Height="38" Margin="0,0,10,0" />
        <Button Name="CancelButton" Content="Cancel" Width="110" Height="38" Margin="0,0,10,0" />
        <Button Name="SaveButton" Content="Save As New Theme" Width="190" Height="38" BorderBrush="{StaticResource TzAccent}" />
      </WrapPanel>
    </StackPanel>
    <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width="470" /><ColumnDefinition Width="20" /><ColumnDefinition Width="*" /></Grid.ColumnDefinitions>
      <Border Grid.Column="0" BorderBrush="#2E2E2E" BorderThickness="1">
        <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel Name="RolePanel" Margin="12" /></ScrollViewer>
      </Border>
      <Border Grid.Column="2" Name="PreviewBorder" BorderBrush="#2E2E2E" BorderThickness="1" Padding="20">
        <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"><StackPanel Name="PreviewPanel" /></ScrollViewer>
      </Border>
    </Grid>
  </DockPanel>
</Window>
'@
    $window = [Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new([xml]$xaml))
    if ($Owner) { $window.Owner = $Owner } else { $window.WindowStartupLocation = 'CenterScreen' }
    $rolePanel = $window.FindName('RolePanel')
    $previewBorder = $window.FindName('PreviewBorder')
    $previewPanel = $window.FindName('PreviewPanel')
    $newIdBox = $window.FindName('NewIdBox')
    $nameBox = $window.FindName('NameBox')
    $saveHint = $window.FindName('SaveHint')
    $saveButton = $window.FindName('SaveButton')
    $cancelButton = $window.FindName('CancelButton')
    $resetAll = $window.FindName('ResetAllButton')
    $window.FindName('SourceLabel').Text = "Based on: $sourceName ($ThemeId)  |  $($roles.Count) color roles  |  the original theme is never modified"

    $converter = [Windows.Media.BrushConverter]::new()
    $toBrush = { param([string]$Hex) $converter.ConvertFromString($Hex) }.GetNewClosure()
    $errorBrush = & $toBrush '#E05F65'
    $normalBorder = & $toBrush '#696969'
    $state = @{ Rows = [ordered]@{}; Invalid = [Collections.Generic.HashSet[string]]::new() }

    $existingIds = {
        $ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($root in @($InstalledThemesRoot, $SharedThemesRoot)) {
            if ($root -and (Test-Path -LiteralPath $root -PathType Container)) {
                foreach ($d in Get-ChildItem -LiteralPath $root -Directory) { [void]$ids.Add($d.Name) }
            }
        }
        return ,$ids
    }.GetNewClosure()

    $current = {
        # Effective palette: source values, edited values, then the shared
        # interaction fallbacks used by Read-ThemeFile and Arakiel load_theme.
        $v = @{}
        foreach ($k in $sourceValues.Keys) { $v[[string]$k] = [string]$sourceValues[$k] }
        foreach ($key in $state.Rows.Keys) {
            $text = [string]$state.Rows[$key].Box.Text
            if (& $isHexColor $text) { $v[$key] = $text.ToUpperInvariant() }
        }
        if (-not $v['SELECTION']) { $v['SELECTION'] = $v['BORDER'] }
        if (-not $v['CURSOR']) { $v['CURSOR'] = $v['ACCENT_BRIGHT'] }
        if (-not $v['FOCUS']) { $v['FOCUS'] = $v['ACCENT'] }
        return $v
    }.GetNewClosure()

    $changes = {
        $c = [ordered]@{}
        foreach ($key in $state.Rows.Keys) {
            $row = $state.Rows[$key]
            $text = [string]$row.Box.Text
            if ((& $isHexColor $text) -and $text -ine $row.Original) { $c[$key] = $text.ToUpperInvariant() }
        }
        return $c
    }.GetNewClosure()

    $renderPreview = {
        $p = & $current
        $get = { param([string]$k, [string]$fallback) if ((& $isHexColor $p[$k])) { $p[$k] } else { $fallback } }
        $text = { param([string]$value, [string]$fg, [double]$size = 15, [string]$weight = 'Normal', [string]$bg = '')
            $t = [Windows.Controls.TextBlock]::new(); $t.Text = $value; $t.FontSize = $size
            $t.FontWeight = [Windows.FontWeights]::$weight; $t.Foreground = & $toBrush $fg
            if ($bg) { $t.Background = & $toBrush $bg }
            $t.FontFamily = [Windows.Media.FontFamily]::new('Cascadia Mono, Consolas')
            return $t
        }
        $chip = { param([string]$label, [string]$bg, [string]$fg, [string]$border = '')
            $b = [Windows.Controls.Border]::new(); $b.Background = & $toBrush $bg; $b.Padding = [Windows.Thickness]::new(10,5,10,5)
            $b.Margin = [Windows.Thickness]::new(0,0,6,6)
            if ($border) { $b.BorderBrush = & $toBrush $border; $b.BorderThickness = [Windows.Thickness]::new(2) }
            $b.Child = & $text $label $fg 13 'SemiBold'
            return $b
        }
        $row = { $r = [Windows.Controls.WrapPanel]::new(); $r.Margin = [Windows.Thickness]::new(0,4,0,10); return $r }
        $bg = & $get 'BG' '#101010'; $fg = & $get 'TEXT' '#EEEEEE'
        $previewBorder.Background = & $toBrush $bg
        $previewPanel.Children.Clear()
        $name = if ($nameBox.Text) { [string]$nameBox.Text } else { $sourceName }
        [void]$previewPanel.Children.Add((& $text $name (& $get 'ACCENT' $fg) 22 'Bold'))
        [void]$previewPanel.Children.Add((& $text 'The quick brown fox jumps over the lazy dog.  TEXT' $fg 15 'Normal'))
        [void]$previewPanel.Children.Add((& $text 'Bright emphasis line.  BRIGHT' (& $get 'BRIGHT' $fg) 15 'SemiBold'))
        [void]$previewPanel.Children.Add((& $text '# muted comment / secondary detail.  MUTED' (& $get 'MUTED' $fg) 15 'Normal'))
        $accentLine = & $row
        [void]$accentLine.Children.Add((& $text 'ACCENT  ' (& $get 'ACCENT' $fg) 15 'SemiBold'))
        [void]$accentLine.Children.Add((& $text 'ACCENT_BRIGHT  ' (& $get 'ACCENT_BRIGHT' $fg) 15 'SemiBold'))
        [void]$accentLine.Children.Add((& $text ' selected text ' $fg 15 'Normal' (& $get 'SELECTION' $bg)))
        [void]$accentLine.Children.Add((& $text '  cursor ' $fg 15 'Normal'))
        [void]$accentLine.Children.Add((& $text ([string][char]0x2588) (& $get 'CURSOR' $fg) 15 'Normal'))
        [void]$previewPanel.Children.Add($accentLine)

        $card = [Windows.Controls.Border]::new(); $card.Background = & $toBrush (& $get 'SURFACE' $bg)
        $card.BorderBrush = & $toBrush (& $get 'BORDER' $fg); $card.BorderThickness = [Windows.Thickness]::new(1)
        $card.Padding = [Windows.Thickness]::new(14); $card.Margin = [Windows.Thickness]::new(0,2,0,12)
        $cardStack = [Windows.Controls.StackPanel]::new()
        [void]$cardStack.Children.Add((& $text 'SURFACE panel with BORDER' $fg 14 'SemiBold'))
        $inner = [Windows.Controls.Border]::new(); $inner.Background = & $toBrush (& $get 'SURFACE_ALT' $bg)
        $inner.BorderBrush = & $toBrush (& $get 'FOCUS' $fg); $inner.BorderThickness = [Windows.Thickness]::new(1)
        $inner.Padding = [Windows.Thickness]::new(10,6,10,6); $inner.Margin = [Windows.Thickness]::new(0,8,0,0)
        $inner.Child = & $text 'SURFACE_ALT field with FOCUS outline' $fg 14 'Normal'
        [void]$cardStack.Children.Add($inner)
        $card.Child = $cardStack
        [void]$previewPanel.Children.Add($card)

        $semantic = & $row
        foreach ($k in @('SUCCESS','WARNING','ERROR','INFO','SECONDARY')) { [void]$semantic.Children.Add((& $text "$k   " (& $get $k $fg) 15 'Bold')) }
        [void]$previewPanel.Children.Add($semantic)

        [void]$previewPanel.Children.Add((& $text 'i3 WINDOW STATES' (& $get 'MUTED' $fg) 12 'SemiBold'))
        $bar = & $row
        foreach ($state3 in @('FOCUSED','ACTIVE','INACTIVE','URGENT')) {
            [void]$bar.Children.Add((& $chip $state3.ToLowerInvariant() (& $get "${state3}_BG" $bg) $fg (& $get "${state3}_BORDER" $fg)))
        }
        [void]$previewPanel.Children.Add($bar)

        [void]$previewPanel.Children.Add((& $text 'ANSI 0-15' (& $get 'MUTED' $fg) 12 'SemiBold'))
        foreach ($prefix in @('ANSI_','ANSI_BRIGHT_')) {
            $ansiRow = & $row; $ansiRow.Margin = [Windows.Thickness]::new(0,4,0,2)
            foreach ($c in @('BLACK','RED','GREEN','YELLOW','BLUE','PURPLE','CYAN','WHITE')) {
                $hex = & $get "$prefix$c" '#777777'
                $b = [Windows.Controls.Border]::new(); $b.Width = 62; $b.Height = 30; $b.Margin = [Windows.Thickness]::new(0,0,4,0)
                $b.Background = & $toBrush $hex; $b.ToolTip = "$prefix$c $hex"
                [void]$ansiRow.Children.Add($b)
            }
            [void]$previewPanel.Children.Add($ansiRow)
        }
        $sample = & $row; $sample.Margin = [Windows.Thickness]::new(0,10,0,0)
        [void]$sample.Children.Add((& $text 'PS> ' (& $get 'ANSI_GREEN' $fg) 15 'SemiBold'))
        [void]$sample.Children.Add((& $text 'git ' (& $get 'ANSI_YELLOW' $fg) 15 'Normal'))
        [void]$sample.Children.Add((& $text 'status ' (& $get 'ANSI_BLUE' $fg) 15 'Normal'))
        [void]$sample.Children.Add((& $text '--short ' (& $get 'ANSI_CYAN' $fg) 15 'Normal'))
        [void]$sample.Children.Add((& $text '# 2 modified' (& $get 'ANSI_BRIGHT_BLACK' $fg) 15 'Normal'))
        [void]$previewPanel.Children.Add($sample)
    }.GetNewClosure()

    $updateSave = {
        $id = [string]$newIdBox.Text
        $name = [string]$nameBox.Text
        $changed = (& $changes).Count
        $ids = & $existingIds
        $problem = if ($state.Invalid.Count -gt 0) { "Fix invalid colors (use #RRGGBB): $(@($state.Invalid) -join ', ')." }
            elseif (-not $SharedThemesRoot) { 'Save unavailable: the shared ThemeEngine/themes source was not found. Run ThemeEngine.ps1 from the repository checkout.' }
            elseif (-not (& $isThemeId $id)) { 'Enter a new theme id: 1-64 lowercase letters, numbers or hyphens.' }
            elseif ($ids.Contains($id)) { "Theme '$id' already exists. Choose a new id; existing themes are never replaced." }
            elseif (-not (& $isDisplayName $name)) { "Enter a display name: 1-64 letters, numbers, spaces and . _ ( ) & + ' -" }
            else { '' }
        $saveButton.IsEnabled = -not $problem
        $saveHint.Foreground = if ($problem) { & $toBrush '#E5B454' } else { & $toBrush '#B8B8B8' }
        $saveHint.Text = if ($problem) { $problem } else { "Ready: '$id' with $changed changed color role(s). Save creates a new theme; nothing is activated." }
    }.GetNewClosure()

    $group = ''
    foreach ($role in $roles) {
        if ($role.Group -cne $group) {
            $group = $role.Group
            $header = [Windows.Controls.TextBlock]::new(); $header.Text = $group.ToUpperInvariant()
            $header.FontWeight = [Windows.FontWeights]::Bold; $header.Foreground = & $toBrush '#B8B8B8'
            $header.Margin = [Windows.Thickness]::new(0, $(if ($rolePanel.Children.Count) { 14 } else { 0 }), 0, 6)
            [void]$rolePanel.Children.Add($header)
        }
        $grid = [Windows.Controls.Grid]::new(); $grid.Margin = [Windows.Thickness]::new(0,0,0,6)
        foreach ($w in @(190, 44, 130, 80)) { $cd = [Windows.Controls.ColumnDefinition]::new(); $cd.Width = [Windows.GridLength]::new($w); $grid.ColumnDefinitions.Add($cd) }
        $label = [Windows.Controls.TextBlock]::new(); $label.Text = $role.Key; $label.FontWeight = [Windows.FontWeights]::SemiBold
        $label.VerticalAlignment = 'Center'; $label.FontFamily = [Windows.Media.FontFamily]::new('Cascadia Mono, Consolas')
        $swatch = [Windows.Controls.Border]::new(); $swatch.Width = 34; $swatch.Height = 26; $swatch.CornerRadius = [Windows.CornerRadius]::new(3)
        $swatch.BorderBrush = & $toBrush '#696969'; $swatch.BorderThickness = [Windows.Thickness]::new(1); $swatch.Background = & $toBrush $role.Value
        [Windows.Controls.Grid]::SetColumn($swatch, 1)
        $box = [Windows.Controls.TextBox]::new(); $box.Text = $role.Value; $box.Height = 32; $box.MaxLength = 7
        $box.FontFamily = [Windows.Media.FontFamily]::new('Cascadia Mono, Consolas'); $box.Tag = $role.Key
        [Windows.Controls.Grid]::SetColumn($box, 2)
        $reset = [Windows.Controls.Button]::new(); $reset.Content = 'Reset'; $reset.Height = 32; $reset.Margin = [Windows.Thickness]::new(8,0,0,0)
        $reset.Tag = $role.Key; $reset.IsEnabled = $false
        [Windows.Controls.Grid]::SetColumn($reset, 3)
        foreach ($e in @($label, $swatch, $box, $reset)) { [void]$grid.Children.Add($e) }
        [void]$rolePanel.Children.Add($grid)
        $state.Rows[$role.Key] = [pscustomobject]@{ Key = $role.Key; Original = $role.Value; Box = $box; Swatch = $swatch; Reset = $reset }

        $box.Add_TextChanged({
            param($sender)
            $row = $state.Rows[[string]$sender.Tag]
            $value = [string]$sender.Text
            if (& $isHexColor $value) {
                [void]$state.Invalid.Remove($row.Key)
                $sender.BorderBrush = $normalBorder
                $row.Swatch.Background = & $toBrush $value
            } else {
                [void]$state.Invalid.Add($row.Key)
                $sender.BorderBrush = $errorBrush
            }
            $row.Reset.IsEnabled = $value -ine $row.Original
            & $renderPreview
            & $updateSave
        }.GetNewClosure())
        $reset.Add_Click({ param($sender) $row = $state.Rows[[string]$sender.Tag]; $row.Box.Text = $row.Original }.GetNewClosure())
    }

    $ids = & $existingIds
    $suggest = "$ThemeId-custom"; $n = 2
    while ($ids.Contains($suggest) -and $n -lt 100) { $suggest = "$ThemeId-custom-$n"; $n++ }
    $newIdBox.Text = if ((Test-TypezeroThemeId $suggest) -and -not $ids.Contains($suggest)) { $suggest } else { '' }
    $suggestedName = "$sourceName Custom"
    $nameBox.Text = if (Test-TypezeroThemeDisplayName $suggestedName) { $suggestedName } else { '' }

    $newIdBox.Add_TextChanged({ & $updateSave }.GetNewClosure())
    $nameBox.Add_TextChanged({ & $renderPreview; & $updateSave }.GetNewClosure())
    $resetAll.Add_Click({ foreach ($row in $state.Rows.Values) { $row.Box.Text = $row.Original } }.GetNewClosure())
    $window.Tag = $null
    $cancelButton.Add_Click({ $window.Tag = $null; $window.Close() }.GetNewClosure())
    $saveButton.Add_Click({
        & $updateSave
        if (-not $saveButton.IsEnabled) { return }
        try {
            $result = & $saveDerivedTheme -InstalledThemesRoot $InstalledThemesRoot -SharedThemesRoot $SharedThemesRoot `
                -SourceId $ThemeId -NewId ([string]$newIdBox.Text) -DisplayName ([string]$nameBox.Text) -Colors (& $changes)
            $window.Tag = $result
            $window.Close()
        } catch {
            $saveHint.Foreground = $errorBrush
            $saveHint.Text = "Save failed: $($_.Exception.Message)"
        }
    }.GetNewClosure())

    & $renderPreview
    & $updateSave
    if ($OnLoaded) {
        $controls = @{
            Rows = $state.Rows; NewIdBox = $newIdBox; NameBox = $nameBox; SaveHint = $saveHint
            SaveButton = $saveButton; CancelButton = $cancelButton; ResetAllButton = $resetAll
            PreviewBorder = $previewBorder; PreviewPanel = $previewPanel
        }
        try { $null = & $OnLoaded $window $controls }
        finally { $window.Close() }
    } else {
        $null = $window.ShowDialog()
    }
    return $window.Tag
}
