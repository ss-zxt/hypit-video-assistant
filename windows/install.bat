@echo off
rem Double-click launcher for install.ps1. (Pure ASCII on purpose:
rem cmd.exe misparses batch files containing non-ASCII text.)
rem Opens PowerShell with a one-off execution-policy bypass (nothing is
rem changed permanently), runs the installer from this folder, then
rem pauses so the result stays readable.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
echo.
echo Installer finished with exit code %ERRORLEVEL%.
pause
