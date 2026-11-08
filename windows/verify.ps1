# verify.ps1 - check the Windows Hypit + Ollama stack end to end.
# Default run includes a tiny qwen3 inference smoke test (think:false);
# pass -NoSmoke to skip inference. Exit code 0 only if every hard check
# passes. The Windows counterpart of verify.sh.
#
# Usage: powershell -ExecutionPolicy Bypass -File .\verify.ps1 [-NoSmoke] [-Model qwen3:8b]

[CmdletBinding()]
param(
    [string]$Model,
    [switch]$NoSmoke
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'common.ps1')
$cfg = Get-KitConfig
$paths = Get-KitPaths

$script:Fail = 0
function Ok   { param([string]$Text) Write-Host "  [OK]   $Text" }
function Bad  { param([string]$Text) Write-Host "  [FAIL] $Text"; $script:Fail = 1 }
function Note { param([string]$Text) Write-Host "  [..]   $Text" }

# Model under test: explicit > recorded > (policy says auto but nothing
# recorded yet = install has not chosen one).
if (-not $Model) { $Model = Get-RecordedModel }
if (-not $Model) { $Model = 'qwen3:1.7b' }

# 1. Hypit CLI
$hypitCmd = Join-Path $paths.HypitPrefix 'hypit.cmd'
if (-not (Test-Path $hypitCmd)) {
    $cmd = Get-Command 'hypit.cmd' -ErrorAction SilentlyContinue
    if ($cmd) { $hypitCmd = $cmd.Source }
}
if (Test-Path $hypitCmd) {
    $v = & $hypitCmd --version 2>$null | Select-Object -Last 1
    $ver = $null
    if ($v -match '(\d+\.\d+\.\d+)') { $ver = $Matches[1] }
    if ($ver -eq $cfg.HypitVersion) { Ok "hypit CLI $ver" } else { Note "hypit CLI present (version '$ver', expected $($cfg.HypitVersion))" }
} else {
    Bad 'hypit CLI not found'
}

# 2. Hypit skill
if (Test-Path (Join-Path $paths.SkillDir 'SKILL.md')) { Ok 'hypit skill present' } else { Bad 'hypit skill missing' }

# 3. FFmpeg
$ffmpegPath = $null
$ffmpegCmd = Get-Command 'ffmpeg.exe' -ErrorAction SilentlyContinue
if ($ffmpegCmd) { $ffmpegPath = $ffmpegCmd.Source }
if (-not $ffmpegPath) { $ffmpegPath = Find-FirstFile $paths.FfmpegDir 'ffmpeg.exe' }
if ($ffmpegPath) {
    $line = & $ffmpegPath -version 2>$null | Select-Object -First 1
    $fv = $null
    if ($line -match 'ffmpeg version (\S+)') { $fv = $Matches[1] }
    Ok "ffmpeg $fv"
} else {
    Bad 'ffmpeg missing'
}

# 4. Capture Chrome (Puppeteer cache, win64 builds)
$pupRoot = Join-Path $env:USERPROFILE '.cache\puppeteer'
if (Find-FirstFile $pupRoot 'chrome.exe') { Ok 'capture Chrome present' }
else { Note 'capture Chrome cache not found (run: hypit capture install-browser)' }

# 5. Renderer headless shell
$hypitCache = Join-Path $env:USERPROFILE '.cache\hypit'
if (Find-FirstFile $hypitCache 'chrome-headless-shell.exe') { Ok 'renderer headless shell present' }
else { Note 'renderer headless shell not found (run: hypit programs prepare)' }

# 6. Ollama CLI
$cli = Get-OllamaCliPath
if ($cli) {
    $ov = Get-OllamaVersion $cli
    if ($ov -eq $cfg.OllamaVersion) { Ok "ollama binary $ov" }
    else { Note "ollama binary present (version '$ov', kit pin $($cfg.OllamaVersion); an existing install is reused as-is)" }
} else {
    Bad 'ollama CLI not found'
}

# 7. Ollama API
$apiVer = Get-OllamaApiVersion
if ($apiVer) { Ok "ollama API up: $apiVer" }
else { Bad "ollama API not responding on $($paths.OllamaApi) (run: .\start-ollama.ps1)" }

# 8. Model present
$modelOk = $false
if ($apiVer) {
    try {
        $tags = Invoke-RestMethod -Uri "$($paths.OllamaApi)/api/tags" -TimeoutSec 10 -ErrorAction Stop
        $names = @($tags.models | ForEach-Object { $_.name })
        if ($names -contains $Model) { $modelOk = $true }
    } catch { }
}
if ($modelOk) { Ok "model $Model present" } else { Bad "model $Model not in /api/tags (run: ollama pull $Model)" }

# 9. omniget-cli (soft check, like the Linux kit)
$omniExe = Join-Path $paths.OmnigetDir 'omniget-cli.exe'
if ((Test-Path $omniExe) -and ((& $omniExe --help 2>$null | Select-Object -First 1) -ne $null)) {
    Ok "omniget-cli present (TikTok capture, release $($cfg.OmnigetVersion))"
} else {
    Note 'omniget-cli not found (run: tiktok\install-omniget.ps1)'
}

# 10. yt-dlp engine (soft check)
$ytdlpExe = Join-Path $paths.OmnigetDir 'yt-dlp.exe'
if (Test-Path $ytdlpExe) {
    $yv = & $ytdlpExe --version 2>$null | Select-Object -First 1
    if ($yv -eq $cfg.YtdlpVersion) { Ok "yt-dlp $yv (omniget engine)" }
    else { Note "yt-dlp present (version '$yv', expected $($cfg.YtdlpVersion))" }
} else {
    Note 'yt-dlp engine not found (run: tiktok\install-omniget.ps1)'
}

# 11. Inference smoke test
if (-not $NoSmoke -and $script:Fail -eq 0) {
    try {
        $body = @{
            model   = $Model
            prompt  = 'Please introduce yourself in one short sentence.'
            stream  = $false
            think   = $false
            options = @{ num_predict = 64 }
        } | ConvertTo-Json
        $resp = Invoke-RestMethod -Uri "$($paths.OllamaApi)/api/generate" -Method Post -Body $body `
            -ContentType 'application/json' -TimeoutSec 300 -ErrorAction Stop
        $line = ([string]$resp.response).Trim() -split "`n" | Select-Object -First 1
        if ($line) { Ok "inference smoke test: $line" } else { Bad 'inference returned an empty response' }
    } catch {
        Bad "inference smoke test failed: $($_.Exception.Message)"
    }
}

if ($script:Fail -eq 0) {
    Write-Host 'ALL CHECKS PASSED'
    exit 0
} else {
    Write-Host 'SOME CHECKS FAILED - see [FAIL] lines above'
    exit 1
}
