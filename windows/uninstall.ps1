# uninstall.ps1 - remove what the Windows kit installed.
#
# Removes: the Hypit skill + CLI, the kit-managed FFmpeg / Ollama /
# omniget copies, the logon autostart shortcut, the state directory and
# the kit's user-PATH entries.
# Keeps by default: pulled models (they live in %USERPROFILE%\.ollama,
# shared with any official Ollama install) and an Ollama that the kit
# merely reused - that install is the user's own and is never touched.
# -Purge also deletes the recorded model via the API/CLI (only the
# kit's chosen model, nothing else).
#
# Usage: powershell -ExecutionPolicy Bypass -File .\uninstall.ps1 -Yes [-Purge]

[CmdletBinding()]
param(
    [switch]$Yes,
    [switch]$Purge
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'common.ps1')
$cfg = Get-KitConfig
$paths = Get-KitPaths

if (-not $Yes) {
    Write-Host 'This removes the Windows kit components listed at the top of this script.'
    $answer = Read-Host 'Continue? [y/N]'
    if ($answer -notmatch '^(y|yes)$') { Write-Host 'Aborted.'; exit 0 }
}

$model = Get-RecordedModel

if ($Purge -and $model) {
    $cli = Get-OllamaCliPath
    if ($cli) {
        Write-Info "purging model $model ..."
        & $cli rm $model 2>$null | Out-Host
    }
}

# Logon autostart shortcut (only exists for kit-managed Ollama).
$lnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'HypitOllamaKit-Ollama.lnk'
if (Test-Path $lnk) { Remove-Item $lnk -Force }

# Kit-managed directories (record the FFmpeg bin dir first: it is one of
# the PATH entries to clean up below, and it is about to be deleted).
$ffBin = Find-FirstFile $paths.FfmpegDir 'ffmpeg.exe'
foreach ($dir in @($paths.HypitPrefix, $paths.FfmpegDir, $paths.OllamaDir, $paths.OmnigetDir)) {
    if (Test-Path $dir) {
        Write-Info "removing $dir"
        Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Hypit skill.
if (Test-Path $paths.SkillDir) {
    Write-Info "removing $($paths.SkillDir)"
    Remove-Item $paths.SkillDir -Recurse -Force -ErrorAction SilentlyContinue
}

# User PATH entries the installer added.
$remove = @($paths.HypitPrefix, $paths.OllamaDir, $paths.OmnigetDir)
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath) {
    $kept = $userPath -split ';' | Where-Object {
        $_ -and ($remove -notcontains $_) -and (-not $ffBin -or $_ -ne (Split-Path $ffBin -Parent))
    }
    [Environment]::SetEnvironmentVariable('Path', ($kept -join ';'), 'User')
}

# State + manifest last (Get-RecordedModel above already read it).
if (Test-Path $paths.StateDir) { Remove-Item $paths.StateDir -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host 'Uninstall done. Models and any pre-existing Ollama install were kept.'
