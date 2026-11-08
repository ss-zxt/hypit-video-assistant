# install-omniget.ps1 - install the TikTok capture tool for Windows:
# omniget-cli (OpenSelena/omniget, GPL-3.0, Windows x64 build) plus a
# pinned yt-dlp.exe engine, both from their official GitHub releases and
# SHA-256 verified (pins live in ..\versions.psd1).
#
# Layout:
#   %LOCALAPPDATA%\HypitOllamaKit\tools\omniget\omniget-cli.exe
#   %LOCALAPPDATA%\HypitOllamaKit\tools\omniget\yt-dlp.exe  (also copied
#   to %LOCALAPPDATA%\com.openselena.omniget\bin\yt-dlp.exe, mirroring
#   the hand-placed engine location the Linux kit uses - omniget's own
#   engine auto-download is unreliable, so the pinned copy is placed
#   where the tool looks for it. Do not delete it on upgrades.)
#
# Idempotent; pass -Force to reinstall.
# Usage: powershell -ExecutionPolicy Bypass -File .\install-omniget.ps1 [-Force]

[CmdletBinding()]
param([switch]$Force)

$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'common.ps1')
$cfg = Get-KitConfig
$paths = Get-KitPaths

try {
    if ($env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
        Die "unsupported architecture $env:PROCESSOR_ARCHITECTURE (the pinned omniget-cli build is x64)"
    }
    if (-not (Test-Path $paths.OmnigetDir)) {
        New-Item -ItemType Directory -Path $paths.OmnigetDir -Force | Out-Null
    }

    # ------------------------------------------------------------ omniget-cli
    $cli = Join-Path $paths.OmnigetDir 'omniget-cli.exe'
    if ((Test-Path $cli) -and -not $Force) {
        Write-Info "omniget-cli already installed (skip; -Force to reinstall): $cli"
    } else {
        $zip = Download-Verified -Url $cfg.OmnigetUrl -FileName $cfg.OmnigetAsset -Sha256 $cfg.OmnigetAssetSha256
        $extractDir = Join-Path $paths.CacheDir 'omniget-extract'
        Expand-ToDir -ZipPath $zip -Dir $extractDir
        $found = Find-FirstFile $extractDir 'omniget-cli.exe'
        if (-not $found) { Die 'omniget archive did not contain omniget-cli.exe' }
        Copy-Item $found $cli -Force
        Write-Info "installed: $cli"
    }
    & $cli --help 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { Die 'omniget-cli does not run' }
    # NOTE: the binary self-reports version 0.1.0 regardless of the
    # release version (upstream internal version lag) - harmless.

    # ------------------------------------------------------------ yt-dlp engine
    $ytdlp = Join-Path $paths.OmnigetDir 'yt-dlp.exe'
    $current = $null
    if (Test-Path $ytdlp) { $current = & $ytdlp --version 2>$null | Select-Object -First 1 }
    if ($current -eq $cfg.YtdlpVersion -and -not $Force) {
        Write-Info "yt-dlp $($cfg.YtdlpVersion) already in place (skip): $ytdlp"
    } else {
        $exe = Download-Verified -Url $cfg.YtdlpUrl -FileName $cfg.YtdlpAsset -Sha256 $cfg.YtdlpAssetSha256
        Copy-Item $exe $ytdlp -Force
        Write-Info "installed: $ytdlp"
    }
    $appdataBin = Join-Path $env:LOCALAPPDATA 'com.openselena.omniget\bin'
    if (-not (Test-Path $appdataBin)) { New-Item -ItemType Directory -Path $appdataBin -Force | Out-Null }
    Copy-Item $ytdlp (Join-Path $appdataBin 'yt-dlp.exe') -Force
    if ((& $ytdlp --version) -ne $cfg.YtdlpVersion) { Die 'yt-dlp version mismatch after install' }

    Add-UserPath $paths.OmnigetDir
    Write-Host 'Done. Capture a TikTok reference with:'
    Write-Host "  powershell -ExecutionPolicy Bypass -File `"$PSScriptRoot\download-tiktok.ps1`" `"<TikTok URL>`""
} catch {
    Write-Host "`n$($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
