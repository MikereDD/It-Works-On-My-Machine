# Windows Terminal's named OpenType weights, shared by shell, presets and WPF.
# Loading this module does not load WPF or change appearance.
function Get-TypezeroTerminalFontWeights {
    [ordered]@{
        'thin'=100; 'extra-light'=200; 'light'=300; 'semi-light'=350
        'normal'=400; 'medium'=500; 'semi-bold'=600; 'bold'=700
        'extra-bold'=800; 'black'=900; 'extra-black'=950
    }
}

function Assert-TypezeroTerminalFontWeight {
    param([Parameter(Mandatory)][string]$Weight)
    if ($Weight -cnotin @((Get-TypezeroTerminalFontWeights).Keys)) {
        throw ('Select a Windows Terminal font weight: ' + ((Get-TypezeroTerminalFontWeights).Keys -join ', ') + '.')
    }
}

function ConvertTo-TypezeroWpfFontWeight {
    param([Parameter(Mandatory)][string]$Weight)
    Assert-TypezeroTerminalFontWeight -Weight $Weight
    # WPF can represent these OpenType values; available faces and synthesis
    # depend on the selected font, just as they do in Windows Terminal.
    [Windows.FontWeight]::FromOpenTypeWeight((Get-TypezeroTerminalFontWeights)[$Weight])
}
