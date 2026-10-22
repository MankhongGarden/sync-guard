' Starts SyncGuard.ps1 (same folder as this file) without a console window.
' Use it as the action of a Task Scheduler "At log on" task:  wscript.exe "<path>\launch-hidden.vbs"
Set fso = CreateObject("Scripting.FileSystemObject")
here = fso.GetParentFolderName(WScript.ScriptFullName)
CreateObject("WScript.Shell").Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & here & "\SyncGuard.ps1""", 0, False
