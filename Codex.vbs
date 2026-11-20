Option Explicit
Dim fs, sh, root, cmd
Set fs = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
root = fs.GetParentFolderName(WScript.ScriptFullName)
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Chr(34) & root & "\launch.ps1" & Chr(34) & " -App Codex"
sh.Run cmd, 0, False
