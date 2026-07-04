'--------------------------------------------
' file:    cd-ripper-gui.vbs
' author:  Mike Redd
' version: 1.4.0
' updated: 2026-07-04
' desc:    Silent launcher for cd-ripper-gui.ps1
'          (no console window flash). The PS1
'          self-elevates to admin on launch.
'--------------------------------------------
Option Explicit

Dim fso, shell, scriptDir, ps1Path
Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
ps1Path = scriptDir & "\cd-ripper-gui.ps1"

If Not fso.FileExists(ps1Path) Then
    MsgBox "Could not find cd-ripper-gui.ps1 next to this launcher.", 16, "CD -> FLAC Ripper"
    WScript.Quit 1
End If

' 0 = hidden window, False = don't wait. Windows PowerShell -STA for WinForms;
' the PS1 self-elevates from there.
shell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File """ & ps1Path & """", 0, False
