# upgrade.ps1 - two different jobs, kept apart on purpose:
#
#   .\upgrade.ps1 -Check   Report only: compare the kit's pinned
#                          Hypit / Ollama versions against the official
#                          latest (npm registry + GitHub). Changes
#                          nothing.
#   .\upgrade.ps1          Update THIS machine to the kit's current
#                          pins: git pull when this folder is a clone,
#                          then re-run install.ps1 (idempotent - it only
#                          adds/repairs what the current pins require).
#
# Pin bumps themselves ship as new kit versions (edit windows\
# versions.psd1 with the new official versions + SHA-256 values, as
# SOURCES.md records); this script never rewrites pins on its own.

[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$cfg = Get-KitConfig

if ($Check) {
    Write-Log 'Official version check'
    try {
        $npm = Invoke-RestMethod -Uri 'https://registry.npmjs.org/@hypit/hypit/latest' -TimeoutSec 30
        Write-Info "Hypit CLI: pinned $($cfg.HypitVersion), official latest $($npm.version)"
    } catch { Write-Warn "Hypit check failed: $($_.Exception.Message)" }
    try {
        $headers = @{ 'User-Agent' = 'hypit-video-assistant' }
        $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/ollama/ollama/releases/latest' -Headers $headers -TimeoutSec 30
        $latest = ([string]$rel.tag_name) -replace '^v', ''
        Write-Info "Ollama: pinned $($cfg.OllamaVersion), official latest $latest"
    } catch { Write-Warn "Ollama check failed: $($_.Exception.Message)" }
    Write-Info 'If a newer official version exists, it arrives as a new kit version with refreshed pins - then run .\upgrade.ps1 (without -Check) to apply it.'
    exit 0
}

try {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    if (Test-Path (Join-Path $repoRoot '.git')) {
        $git = Get-Command 'git.exe' -ErrorAction SilentlyContinue
        if ($git) {
            Write-Log 'Updating the kit itself (git pull)'
            Push-Location $repoRoot
            try { & $git.Source pull --ff-only | Out-Host } finally { Pop-Location }
        }
    }
    Write-Log 'Applying the current pins (install.ps1)'
    $installArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'install.ps1'))
    if ($Force) { $installArgs += '-Force' }
    & powershell.exe @installArgs | Out-Host
    if ($LASTEXITCODE -ne 0) { Die 'install.ps1 failed during upgrade' }
    Write-Info 'upgrade complete'
} catch {
    Write-Host "`n$($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
