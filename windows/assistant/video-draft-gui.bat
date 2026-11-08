@echo off
rem Graphical launcher for the local assistant.
rem Pure ASCII + CRLF on purpose: cmd.exe misparses non-ASCII batch
rem files. The window itself is Chinese (rendered by PowerShell).
rem The real start happens in launch-gui.vbs, which launches the
rem GUI with NO console window at all; this .bat only forwards to
rem it and closes immediately - no black box, nothing minimized
rem in the taskbar.
wscript "%~dp0launch-gui.vbs"
