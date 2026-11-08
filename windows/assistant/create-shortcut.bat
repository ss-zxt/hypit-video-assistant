@echo off
rem Double-clickable runner for create-shortcut.ps1.
rem Pure ASCII + CRLF (cmd.exe misparses non-ASCII batch files).
rem The window STAYS OPEN and prints exactly where the root
rem shortcut was written - if it is missing afterwards, that
rem printed path tells us which kit copy it landed in.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0create-shortcut.ps1"
echo.
pause
