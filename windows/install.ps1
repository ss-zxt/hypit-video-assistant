# install.ps1 - one-click installer for the Hypit + Ollama + qwen3 stack
# on native Windows 10/11 (x64). The Windows counterpart of install.sh.
#
# What it installs (everything in the current user's profile, no admin):
#   1. Hypit skill     -> %USERPROFILE%\.agents\skills\hypit   (npx skills add)
#   2. Hypit CLI 0.3.1 -> %LOCALAPPDATA%\HypitOllamaKit\hypit-cli (npm, pinned)
#   3. Hypit browsers  -> %USERPROFILE%\.cache\puppeteer + .cache\hypit
#   4. FFmpeg 8.1.2    -> %LOCALAPPDATA%\HypitOllamaKit\ffmpeg (Gyan build,
#                         SHA-256 verified; an existing ffmpeg is reused)
#   5. Ollama 0.40.14  -> an existing Windows Ollama install is detected
#                         and REUSED; only when none exists, the pinned
#                         standalone zip goes to ...\HypitOllamaKit\ollama
#   6. A qwen3 model   -> chosen by THIS machine's RAM / GPU VRAM
#                         (select-model.ps1); override with -Model
#   7. TikTok capture  -> omniget-cli (Windows build) + yt-dlp.exe,
#                         via tiktok\install-omniget.ps1
#
# Idempotent: re-running skips whatever is already in place.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\install.ps1 [options]
#   -Model qwen3:8b   force a model tag instead of auto-selecting
#   -SkipBrowsers -SkipModel -SkipSmoke -SkipOmniget
#   -CheckOnly        environment report only, installs nothing
#   -Force            reinstall components even when present

[CmdletBinding()]
param(
    [string]$Model,
    [switch]$SkipBrowsers,
    [switch]$SkipModel,
    [switch]$SkipSmoke,
    [switch]$SkipOmniget,
    [switch]$CheckOnly,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
. (Join-Path $PSScriptRoot 'select-model.ps1')
$cfg = Get-KitConfig
$paths = Get-KitPaths
$RepoRoot = Split-Path $PSScriptRoot -Parent

try {
    # ------------------------------------------------------------ preflight
    Write-Log 'Preflight'
    if ([Environment]::OSVersion.Platform -ne 'Win32NT') { Die 'this installer is for Windows' }
    if ($env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
        Die "unsupported architecture $env:PROCESSOR_ARCHITECTURE (v1 supports x64 only; ARM64 Windows is not covered)"
    }
    $os = Get-CimInstance Win32_OperatingSystem
    Write-Info "OS: $($os.Caption) (build $($os.BuildNumber))"

    $ramGB  = Get-RamGB
    $vramGB = Get-VramGB
    Write-Info "RAM: $ramGB GB, discrete GPU VRAM: $vramGB GB"

    # Node.js >= 22.15.0 is a hard requirement of Hypit 0.3.1.
    $nodeCmd = Get-Command 'node.exe' -ErrorAction SilentlyContinue
    if (-not $nodeCmd -and -not $CheckOnly) {
        $winget = Get-Command 'winget.exe' -ErrorAction SilentlyContinue
        if ($winget) {
            Write-Info 'Node.js missing - installing the LTS via winget ...'
            & $winget.Source install -e --id OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements | Out-Host
            $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                        [Environment]::GetEnvironmentVariable('Path', 'User')
            $nodeCmd = Get-Command 'node.exe' -ErrorAction SilentlyContinue
        }
    }
    if (-not $nodeCmd) { Die 'Node.js is required (>= 22.15.0). Install it from https://nodejs.org and re-run.' }
    $nodeVer = (& $nodeCmd.Source --version) -replace '^v', ''
    $nv = $nodeVer -split '\.' | ForEach-Object { [int]$_ }
    if (-not ($nv[0] -gt 22 -or ($nv[0] -eq 22 -and $nv[1] -ge 15))) {
        Die "Node.js >= 22.15.0 is required by Hypit (found $nodeVer)"
    }
    Write-Info "node $nodeVer, npm $(& npm --version)"

    # Model choice: explicit -Model > recorded choice (stable re-runs) > auto.
    $recorded = Get-RecordedModel
    if ($Model) {
        $selectedModel = $Model; $modelWhy = 'forced by -Model'
    } elseif ($recorded -and -not $Force) {
        $selectedModel = $recorded; $modelWhy = 'recorded from the first install'
    } else {
        $selectedModel = Select-QwenModel -RamGB $ramGB -VramGB $vramGB
        $modelWhy = 'auto-selected for this machine'
    }
    Write-Info "model: $selectedModel ($modelWhy)"

    $drive = Split-Path $env:LOCALAPPDATA -Qualifier
    $freeGB = [math]::Round((Get-PSDrive ($drive -replace ':', '')).Free / 1GB, 1)
    $modelGB = @{ 'qwen3:1.7b' = 1.4; 'qwen3:4b' = 2.5; 'qwen3:8b' = 5.2; 'qwen3:14b' = 9.3 }
    $needGB = 6 + $(if ($modelGB.ContainsKey($selectedModel)) { $modelGB[$selectedModel] } else { 5 })
    Write-Info "free disk on $drive $freeGB GB (estimated need ~$needGB GB)"
    if ($freeGB -lt $needGB) { Write-Warn 'low disk space for the full stack + model' }

    $existingApi = Get-OllamaApiVersion
    $existingCli = Get-OllamaCliPath
    if ($existingApi)     { Write-Info "existing Ollama API found: $existingApi (will be reused)" }
    elseif ($existingCli) { Write-Info "existing Ollama CLI found: $existingCli (will be reused)" }
    else                  { Write-Info 'no existing Ollama found (the pinned standalone build will be installed)' }

    if ($CheckOnly) {
        Write-Info 'check-only: preflight passed, nothing installed.'
        exit 0
    }

    Ensure-KitDirs

    # ------------------------------------------------------------ Hypit skill
    Write-Log 'Hypit skill'
    $skillFile = Join-Path $paths.SkillDir 'SKILL.md'
    if ((Test-Path $skillFile) -and -not $Force) {
        Write-Info "already installed at $($paths.SkillDir) (skip)"
    } else {
        & npx -y skills add hypit-ai/hypit -g -y | Out-Host
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $skillFile)) { Die 'skill install failed' }
        Write-Info "installed to $($paths.SkillDir)"
    }

    # ------------------------------------------------------------ Hypit CLI
    Write-Log "Hypit CLI @hypit/hypit@$($cfg.HypitVersion)"
    $hypitCmd = Join-Path $paths.HypitPrefix 'hypit.cmd'
    $curHypit = $null
    if (Test-Path $hypitCmd) {
        $v = & $hypitCmd --version 2>$null | Select-Object -Last 1
        if ($v -match '(\d+\.\d+\.\d+)') { $curHypit = $Matches[1] }
    }
    if ($curHypit -eq $cfg.HypitVersion -and -not $Force) {
        Write-Info "already at $curHypit (skip)"
    } else {
        & npm install --global --prefix $paths.HypitPrefix "@hypit/hypit@$($cfg.HypitVersion)" | Out-Host
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $hypitCmd)) { Die 'npm install of Hypit CLI failed' }
    }
    Add-UserPath $paths.HypitPrefix
    Write-Info "hypit -> $hypitCmd"

    # ------------------------------------------------------------ FFmpeg
    Write-Log 'FFmpeg'
    $ffmpegCmd = Get-Command 'ffmpeg.exe' -ErrorAction SilentlyContinue
    $kitFfmpegExe = Find-FirstFile $paths.FfmpegDir 'ffmpeg.exe'
    if ($kitFfmpegExe -and -not $Force) {
        Write-Info "kit FFmpeg present: $kitFfmpegExe"
        Add-UserPath (Split-Path $kitFfmpegExe -Parent)
    } elseif ($ffmpegCmd -and -not $Force) {
        Write-Info "existing FFmpeg reused: $($ffmpegCmd.Source)"
    } else {
        $zip = Download-Verified -Url $cfg.FfmpegUrl -FileName $cfg.FfmpegAsset -Sha256 $cfg.FfmpegAssetSha256
        Expand-ToDir -ZipPath $zip -Dir (Join-Path $paths.CacheDir 'ffmpeg-extract')
        $found = Find-FirstFile (Join-Path $paths.CacheDir 'ffmpeg-extract') 'ffmpeg.exe'
        if (-not $found) { Die 'FFmpeg archive did not contain ffmpeg.exe' }
        $binDir = Split-Path $found -Parent
        if (Test-Path $paths.FfmpegDir) { Remove-Item $paths.FfmpegDir -Recurse -Force }
        Move-Item (Split-Path $binDir -Parent) $paths.FfmpegDir
        $kitFfmpegExe = Find-FirstFile $paths.FfmpegDir 'ffmpeg.exe'
        Add-UserPath (Split-Path $kitFfmpegExe -Parent)
        Write-Info "installed: $kitFfmpegExe"
    }

    # ------------------------------------------------------------ Hypit browsers
    if (-not $SkipBrowsers) {
        Write-Log 'Hypit browsers (capture Chrome + renderer headless shell)'
        & $hypitCmd capture install-browser | Out-Host
        if ($LASTEXITCODE -ne 0) { Die 'hypit capture install-browser failed' }
        $smokeDir = Join-Path $paths.StateDir 'smoke-project'
        if (Test-Path $smokeDir) { Remove-Item $smokeDir -Recurse -Force }
        Copy-Item (Join-Path $RepoRoot 'smoke-project') $smokeDir -Recurse
        Push-Location $smokeDir
        try {
            & $hypitCmd runtime use ./hypit.runtime.json | Out-Null
            & $hypitCmd programs prepare | Out-Host
            if ($LASTEXITCODE -ne 0) { Die 'hypit programs prepare failed' }
        } finally { Pop-Location }
        Write-Info 'browser caches: %USERPROFILE%\.cache\puppeteer, %USERPROFILE%\.cache\hypit'
    } else {
        Write-Info 'skipping browsers (-SkipBrowsers)'
    }

    # ------------------------------------------------------------ Ollama
    Write-Log 'Ollama'
    $ollamaSource = $null
    $apiVersion = Get-OllamaApiVersion
    $cli = Get-OllamaCliPath
    if ($apiVersion) {
        $ollamaSource = 'existing'
        Write-Info "reusing the running Ollama $apiVersion"
        if ($apiVersion -ne $cfg.OllamaVersion) {
            Write-Info "note: it differs from the kit pin $($cfg.OllamaVersion); the API is compatible, keeping yours"
        }
    } elseif ($cli) {
        $ollamaSource = 'existing'
        Write-Info "reusing installed Ollama: $cli"
        [void](Start-OllamaServer)
    } else {
        $ollamaSource = 'kit'
        $zip = Download-Verified -Url $cfg.OllamaUrl -FileName $cfg.OllamaAsset -Sha256 $cfg.OllamaAssetSha256
        $extractDir = Join-Path $paths.CacheDir 'ollama-extract'
        Expand-ToDir -ZipPath $zip -Dir $extractDir
        $exe = Find-FirstFile $extractDir 'ollama.exe'
        if (-not $exe) { Die 'Ollama archive did not contain ollama.exe' }
        if (Test-Path $paths.OllamaDir) { Remove-Item $paths.OllamaDir -Recurse -Force }
        Move-Item (Split-Path $exe -Parent) $paths.OllamaDir
        Add-UserPath $paths.OllamaDir
        [void](Start-OllamaServer)
        Write-Info "installed pinned Ollama $($cfg.OllamaVersion) to $($paths.OllamaDir)"
        # Autostart at logon for the kit-managed copy (the official app
        # registers its own; do not add one when reusing an install).
        try {
            $startup = [Environment]::GetFolderPath('Startup')
            $lnk = Join-Path $startup 'HypitOllamaKit-Ollama.lnk'
            $shell = New-Object -ComObject WScript.Shell
            $shortcut = $shell.CreateShortcut($lnk)
            $shortcut.TargetPath = Join-Path $paths.OllamaDir 'ollama.exe'
            $shortcut.Arguments = 'serve'
            $shortcut.WindowStyle = 7
            $shortcut.Save()
            Write-Info 'registered logon autostart for the kit Ollama'
        } catch {
            Write-Warn "could not register autostart: $($_.Exception.Message)"
        }
    }
    $apiVersion = Get-OllamaApiVersion
    if (-not $apiVersion) { Die 'Ollama API is not responding on 127.0.0.1:11434' }
    Write-Info "API is up: $apiVersion"
    $cli = Get-OllamaCliPath

    # ------------------------------------------------------------ Model
    if (-not $SkipModel) {
        Write-Log "Model $selectedModel"
        $tags = Invoke-RestMethod -Uri "$($paths.OllamaApi)/api/tags" -TimeoutSec 10
        $names = @($tags.models | ForEach-Object { $_.name })
        if ($names -contains $selectedModel) {
            Write-Info 'already pulled (skip)'
        } elseif ($cli) {
            & $cli pull $selectedModel | Out-Host
            if ($LASTEXITCODE -ne 0) {
                # Field lesson: on proxied networks Ollama refuses the
                # registry redirect ("resolves to non-public IP") and the
                # pull dies even though everything else works. If the
                # machine already has models, point at the -Model escape
                # hatch instead of leaving a bare failure.
                $have = @()
                try {
                    $tagResp = Invoke-RestMethod -Uri "$($paths.OllamaApi)/api/tags" -TimeoutSec 10 -ErrorAction Stop
                    $have = @($tagResp.models | ForEach-Object { $_.name })
                } catch { }
                if ($have.Count -gt 0) {
                    Die "ollama pull $selectedModel failed. Models already on this machine: $($have -join ', '). Re-run with -Model <one of them> to use an existing model, or fix the network/proxy and retry."
                }
                Die "ollama pull $selectedModel failed (check the network/proxy: Ollama blocks registry redirects that resolve to non-public IPs)"
            }
        } else {
            Write-Info 'no CLI found next to the running API; pulling through the API ...'
            $body = @{ name = $selectedModel; stream = $false } | ConvertTo-Json
            Invoke-RestMethod -Uri "$($paths.OllamaApi)/api/pull" -Method Post -Body $body `
                -ContentType 'application/json' -TimeoutSec 3600 | Out-Null
        }
        Save-RecordedModel $selectedModel
    } else {
        Write-Info 'skipping model (-SkipModel)'
    }

    # ------------------------------------------------------------ TikTok capture tool
    $omnigetState = 'skipped'
    if (-not $SkipOmniget) {
        Write-Log 'TikTok capture tool (omniget-cli + yt-dlp)'
        try {
            $omniInstaller = Join-Path $PSScriptRoot 'tiktok\install-omniget.ps1'
            & $omniInstaller -Force:$Force | Out-Host
            $omnigetState = 'installed'
        } catch {
            # Same rule as the Linux kit: a capture-tool failure warns but
            # never fails the main install; it can be re-run on its own.
            Write-Warn "capture tool install failed (re-run tiktok\install-omniget.ps1 later): $($_.Exception.Message)"
            $omnigetState = 'failed'
        }
    }

    # ------------------------------------------------------------ manifest + verify
    $manifest = Save-KitState @{
        installed_at    = (Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz')
        platform        = 'windows-x64'
        hypit_version   = $cfg.HypitVersion
        ollama_version  = $apiVersion
        ollama_source   = $ollamaSource
        ollama_pinned   = $cfg.OllamaVersion
        model           = $selectedModel
        ffmpeg          = $cfg.FfmpegVersion
        omniget_version = $cfg.OmnigetVersion
        omniget_state   = $omnigetState
        ytdlp_version   = $cfg.YtdlpVersion
        kit_root        = $paths.Root
    }
    Write-Info "manifest written to $manifest"

    Write-Log 'Verification'
    $verifyArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'verify.ps1'))
    if ($SkipSmoke) { $verifyArgs += '-NoSmoke' }
    & powershell.exe @verifyArgs | Out-Host
    if ($LASTEXITCODE -ne 0) { Die 'verification failed - see [FAIL] lines above' }

    # Root shortcut for the assistant GUI (generated on this machine:
    # a working .lnk cannot be shipped in the zip - see
    # assistant\create-shortcut.ps1). Non-fatal if it fails.
    $shortcutScript = Join-Path $PSScriptRoot 'assistant\create-shortcut.ps1'
    if (Test-Path $shortcutScript) {
        try { & $shortcutScript | Out-Host } catch { Write-Warn "shortcut creation skipped: $($_.Exception.Message)" }
    }

    Write-Log 'Done'
    Write-Info "Hypit: hypit --version | Ollama API: $($paths.OllamaApi) | Model: $selectedModel"
    Write-Info 'If this kit helped you, please star the repo: https://github.com/ss-zxt/hypit-video-assistant'
} catch {
    Write-Host "`n$($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
