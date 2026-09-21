#--------------------------------------------
# file:     theme.ps1
# author:   Mike Redd
# version:  0.1-dev
# desc:     ThemeEngine loader / PowerShell command bridge
#--------------------------------------------

$global:ThemeEngineRoot = Join-Path $env:LOCALAPPDATA "Typezero\ThemeEngine"
$global:ThemeEngineCurrent = Join-Path $global:ThemeEngineRoot "current.ps1"
$global:ThemeEngineScript = Join-Path $global:PSRootDir "ThemeEngine\ThemeEngine.ps1"

function global:Import-TypezeroTheme {
    if (Test-Path -LiteralPath $global:ThemeEngineCurrent) {
        . $global:ThemeEngineCurrent
    }
}

function global:themeengine {
    if (-not (Test-Path -LiteralPath $global:ThemeEngineScript)) {
        Write-Host "ThemeEngine script not found: $global:ThemeEngineScript" -ForegroundColor Yellow
        return
    }

    & $global:ThemeEngineScript @args

    if ($args.Count -gt 0 -and $args[0] -in @("apply","reload","rollback")) {
        Import-TypezeroTheme

        if (Get-Command Update-TypezeroUiTheme -ErrorAction SilentlyContinue) {
            Update-TypezeroUiTheme
        }
    }
}

Import-TypezeroTheme
