Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
ps1 = fso.BuildPath(scriptDir, "mediaforge-gui.ps1")
cmd = "pwsh.exe -NoProfile -ExecutionPolicy Bypass -STA -File " & Chr(34) & ps1 & Chr(34)
shell.Run cmd, 1, False
