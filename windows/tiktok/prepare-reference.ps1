# prepare-reference.ps1 - archive a downloaded TikTok reference video
# into a standard decomposition project and generate the frame
# evidence. The Windows counterpart of tiktok/prepare-reference.sh.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\prepare-reference.ps1 <video-file> <project-name>
#
# Creates <projects-root>\<project-name>\ with: (projects root is
# %USERPROFILE%\workspace\hypit-projects by default, or
# %HYPIT_DATA_DIR%\projects when that environment variable is set)
#   references\source.mp4   the original, renamed
#   references\PROBE.txt    specs + visual-change candidates + audio levels
#   evidence\tiles\         0.5s time-labeled frame grids (hypit media tiles)

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$VideoFile,
    [Parameter(Mandatory = $true, Position = 1)]
    [string]$ProjectName
)

$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'common.ps1')
$paths = Get-KitPaths

try {
    if (-not (Test-Path $VideoFile)) { Die "找不到文件: $VideoFile" }

    $hypitCmd = Join-Path $paths.HypitPrefix 'hypit.cmd'
    if (-not (Test-Path $hypitCmd)) {
        $cmd = Get-Command 'hypit.cmd' -ErrorAction SilentlyContinue
        if ($cmd) { $hypitCmd = $cmd.Source } else { Die '找不到 Hypit CLI —— 请先运行这个包的安装程序' }
    }
    $ffprobePath = $null
    $probeCmd = Get-Command 'ffprobe.exe' -ErrorAction SilentlyContinue
    if ($probeCmd) { $ffprobePath = $probeCmd.Source }
    if (-not $ffprobePath) {
        $ffprobePath = Find-FirstFile $paths.FfmpegDir 'ffprobe.exe'
        if (-not $ffprobePath) { Die '需要 ffprobe (FFmpeg)' }
    }
    $ffmpegPath = $null
    $ffmpegCmd = Get-Command 'ffmpeg.exe' -ErrorAction SilentlyContinue
    if ($ffmpegCmd) { $ffmpegPath = $ffmpegCmd.Source }
    if (-not $ffmpegPath) {
        $ffmpegPath = Find-FirstFile $paths.FfmpegDir 'ffmpeg.exe'
        if (-not $ffmpegPath) { Die '需要 ffmpeg' }
    }

    $project = Join-Path (Get-ProjectsRoot) $ProjectName
    $refDir  = Join-Path $project 'references'
    $tileDir = Join-Path $project 'evidence\tiles'
    New-Item -ItemType Directory -Path $refDir -Force | Out-Null
    # Do NOT pre-create $tileDir: on Windows, hypit media tiles refuses
    # a destination that already exists (CLI_ERROR "Destination ...
    # already exists", field finding 2026-11-08; the Linux CLI accepts
    # it). The tiles step below removes any leftover dir first and lets
    # hypit create it fresh.

    $video = Join-Path $refDir 'source.mp4'
    Copy-Item $VideoFile $video -Force

    $duration = & $ffprobePath -v error -show_entries format=duration -of csv=p=0 $video
    $end = [math]::Max(0.1, [double]$duration - 0.1)

    # Native stderr trap (field bug 2026-11-08): under
    # $ErrorActionPreference='Stop', the FIRST line a native tool writes
    # to stderr - e.g. ffmpeg's version banner during volumedetect -
    # becomes a terminating NativeCommandError and kills the script
    # before the tiles step. Captures that merge stderr therefore run
    # with the preference relaxed, and their results are checked
    # explicitly instead.
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $probe = @()
    $probe += 'file: references/source.mp4'
    $probe += "downloaded_from: $VideoFile"
    $probe += '--- probe ---'
    $probe += (& $hypitCmd media probe $video 2>&1 | ForEach-Object { [string]$_ })
    $probe += '--- boundaries (visual-change candidates, NOT shot labels) ---'
    $bounds = & $hypitCmd media boundaries $video 2>&1 | ForEach-Object { [string]$_ }
    $probe += ($bounds | Select-Object -Last 25)
    $probe += '--- audio levels ---'
    $vol = & $ffmpegPath -i $video -vn -af volumedetect -f null - 2>&1 | ForEach-Object { [string]$_ } |
        Where-Object { $_ -match 'mean_volume|max_volume' }
    $probe += $vol
    $ErrorActionPreference = $prevEAP
    $probe | Set-Content -Path (Join-Path $refDir 'PROBE.txt') -Encoding UTF8

    if (Test-Path $tileDir) { Remove-Item $tileDir -Recurse -Force }
    & $hypitCmd media tiles $video --start 0 --end $end --every 0.5 --cell 320 --columns 5 --to $tileDir | Out-Host
    if ($LASTEXITCODE -ne 0) { Die 'hypit media tiles 拆帧失败' }
    $gridCount = @(Get-ChildItem $tileDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in '.png', '.jpg', '.jpeg' }).Count
    if ($gridCount -eq 0) { Die 'hypit 拆完没有生成拼图' }

    Write-Host "项目已就绪: $project"
    Write-Host "  references\source.mp4  ($duration 秒)"
    Write-Host '  references\PROBE.txt'
    Write-Host '  evidence\tiles\ (0.5 秒拼图)'
    Write-Host '下一步: 看完拼图后写 references\TIMELINE.md + ANALYSIS.md。'
} catch {
    Write-Host "`n$($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
