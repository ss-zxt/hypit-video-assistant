@echo off
rem Double-click launcher for verify.ps1 (11 checks + inference smoke).
rem Pure ASCII on purpose: cmd.exe misparses non-ASCII batch files.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0verify.ps1" %*
echo.
echo Verify finished with exit code %ERRORLEVEL%.
pause
