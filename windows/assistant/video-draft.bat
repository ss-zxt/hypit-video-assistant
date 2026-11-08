@echo off
rem Local assistant launcher: give it a video URL or a video file
rem (drag a video file onto this .bat, or double-click and let the
rem PowerShell script ask for the URL - the prompt lives in the .ps1
rem on purpose: cmd.exe misparses batch files containing non-ASCII
rem text (it resumed mid-word and executed comment text as commands,
rem field failure 2026-11-08), so this file stays pure ASCII and the
rem UTF-8-BOM .ps1 shows the Chinese UI instead.
setlocal
rem Data location for this run (downloads + projects): default to
rem D:\HypitData when a D: drive exists, so the double-click flow does
rem not depend on the HYPIT_DATA_DIR environment variable having
rem propagated to Explorer (a running Explorer serves stale env to
rem double-clicked .bat files - field finding 2026-11-08). An env var
rem you set yourself always wins; edit the path below to change it.
if not defined HYPIT_DATA_DIR if exist D:\ set "HYPIT_DATA_DIR=D:\HypitData"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0video-draft.ps1" %*
echo.
echo Assistant finished with exit code %ERRORLEVEL%.
pause
