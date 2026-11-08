' launch-gui.vbs - silent launcher for the assistant GUI.
' Starts PowerShell with NO console window at all (window style 0):
' going through cmd / a .bat always creates a black console window
' that lingers in the taskbar even when hidden afterwards. wscript
' has no console, and its child starts hidden from birth - the only
' window that ever appears is the form itself (with its own icon).
Option Explicit
Dim sh, fso, dir, envp
Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
' Same data-location default as the .bat launchers: D:\HypitData
' when a D: drive exists and the variable is not already set.
Set envp = sh.Environment("Process")
If envp("HYPIT_DATA_DIR") = "" Then
  If fso.DriveExists("D:") Then envp("HYPIT_DATA_DIR") = "D:\HypitData"
End If
sh.Run "powershell -NoProfile -STA -ExecutionPolicy Bypass -File """ & dir & "\video-draft-gui.ps1""", 0, False
