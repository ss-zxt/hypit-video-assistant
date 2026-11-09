# common.ps1 - shared helpers for the Windows kit scripts.
# Dot-source this file; do not run it directly. Windows PowerShell 5.1
# and PowerShell 7 compatible; ASCII only.

$script:KitConfig = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'versions.psd1')

$script:LocalAppData = $env:LOCALAPPDATA
if (-not $script:LocalAppData) {
    $script:LocalAppData = [Environment]::GetFolderPath('LocalApplicationData')
}
$script:KitRoot     = Join-Path $script:LocalAppData 'HypitOllamaKit'
$script:KitBinDir   = Join-Path $script:KitRoot 'bin'
$script:KitStateDir = Join-Path $script:KitRoot 'state'
$script:KitCacheDir = Join-Path $script:KitRoot 'downloads'
$script:HypitPrefix = Join-Path $script:KitRoot 'hypit-cli'
$script:OllamaDir   = Join-Path $script:KitRoot 'ollama'
$script:FfmpegDir   = Join-Path $script:KitRoot 'ffmpeg'
$script:OmnigetDir  = Join-Path $script:KitRoot 'tools\omniget'
$script:SkillDir    = Join-Path $env:USERPROFILE '.agents\skills\hypit'
$script:OllamaApi   = 'http://127.0.0.1:11434'

# IMPORTANT (field-found on Windows PowerShell 5.1): $script: variables
# set in this file are NOT reliably visible from the scripts that
# dot-source it. Consumer scripts must therefore get paths and config
# through these two functions (function definitions DO cross the
# dot-source boundary reliably on 5.1 and 7.x). The $script: variables
# above remain only for this file's own functions below.
function Get-KitPaths {
    $localAppData = $env:LOCALAPPDATA
    if (-not $localAppData) { $localAppData = [Environment]::GetFolderPath('LocalApplicationData') }
    $root = Join-Path $localAppData 'HypitOllamaKit'
    return [PSCustomObject]@{
        Root        = $root
        BinDir      = Join-Path $root 'bin'
        StateDir    = Join-Path $root 'state'
        CacheDir    = Join-Path $root 'downloads'
        HypitPrefix = Join-Path $root 'hypit-cli'
        OllamaDir   = Join-Path $root 'ollama'
        FfmpegDir   = Join-Path $root 'ffmpeg'
        OmnigetDir  = Join-Path $root 'tools\omniget'
        SkillDir    = Join-Path $env:USERPROFILE '.agents\skills\hypit'
        OllamaApi   = 'http://127.0.0.1:11434'
    }
}

function Get-KitConfig {
    return Import-PowerShellDataFile (Join-Path $PSScriptRoot 'versions.psd1')
}

function Write-Log  { param([string]$Text) Write-Host "`n== $Text ==" }
function Write-Info { param([string]$Text) Write-Host "  $Text" }
function Write-Warn { param([string]$Text) Write-Host "  注意: $Text" -ForegroundColor Yellow }
function Die        { param([string]$Text) throw "错误: $Text" }

function Ensure-KitDirs {
    foreach ($d in @($script:KitRoot, $script:KitBinDir, $script:KitStateDir, $script:KitCacheDir)) {
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }
}

function Add-UserPath {
    param([string]$Dir)
    if (-not (Test-Path $Dir)) { return }
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = @()
    if ($userPath) { $parts = $userPath -split ';' | Where-Object { $_ } }
    if ($parts -notcontains $Dir) {
        [Environment]::SetEnvironmentVariable('Path', (($parts + $Dir) -join ';'), 'User')
        Write-Info "added to user PATH: $Dir"
    }
    if (($env:Path -split ';') -notcontains $Dir) { $env:Path = "$Dir;$env:Path" }
}

function Get-Sha256 {
    param([string]$Path)
    return (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Download-File {
    # curl.exe ships with Windows 10/11 and handles big files + resume
    # far better than Invoke-WebRequest. Proxy: pass the environment's
    # HTTPS_PROXY explicitly when one is set (value is never printed).
    param([string]$Url, [string]$OutFile)
    $curl = Get-Command 'curl.exe' -ErrorAction SilentlyContinue
    $args = @('-fL', '--retry', '6', '--retry-delay', '3', '-C', '-', '-o', $OutFile)
    $proxy = $env:HTTPS_PROXY
    if (-not $proxy) { $proxy = $env:https_proxy }
    if ($proxy) { $args += @('--proxy', $proxy) }
    $args += $Url
    if ($curl) {
        & $curl.Source @args
        if ($LASTEXITCODE -ne 0) { Die "download failed: $Url" }
    } else {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
    }
}

function Download-Verified {
    param([string]$Url, [string]$FileName, [string]$Sha256)
    Ensure-KitDirs
    $dest = Join-Path $script:KitCacheDir $FileName
    if ((Test-Path $dest) -and ((Get-Sha256 $dest) -eq $Sha256)) {
        Write-Info "cached copy verified, skip download: $FileName"
        return $dest
    }
    Write-Info "downloading $FileName ..."
    Download-File -Url $Url -OutFile $dest
    $actual = Get-Sha256 $dest
    if ($actual -ne $Sha256) {
        Remove-Item $dest -Force -ErrorAction SilentlyContinue
        Die "SHA-256 mismatch for $FileName (got $actual). Deleted; re-run to retry."
    }
    Write-Info "SHA-256 verified: $FileName"
    return $dest
}

function Expand-ToDir {
    param([string]$ZipPath, [string]$Dir)
    if (Test-Path $Dir) { Remove-Item $Dir -Recurse -Force }
    New-Item -ItemType Directory -Path $Dir -Force | Out-Null
    Expand-Archive -Path $ZipPath -DestinationPath $Dir -Force
}

function Find-FirstFile {
    param([string]$Root, [string]$Name)
    if (-not (Test-Path $Root)) { return $null }
    $hit = Get-ChildItem -Path $Root -Filter $Name -Recurse -File -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($hit) { return $hit.FullName }
    return $null
}

# ------------------------------------------------------------ Ollama

function Get-OllamaCliPath {
    $candidates = @(
        (Join-Path $script:OllamaDir 'ollama.exe'),
        (Join-Path $script:LocalAppData 'Programs\Ollama\ollama.exe')
    )
    $cmd = Get-Command 'ollama.exe' -ErrorAction SilentlyContinue
    if ($cmd) { $candidates += $cmd.Source }
    foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { return $c } }
    return $null
}

function Get-OllamaVersion {
    param([string]$CliPath)
    if (-not $CliPath) { return $null }
    try {
        $out = & $CliPath --version 2>$null | Select-Object -First 1
        if ($out -match '(\d+\.\d+\.\d+)') { return $Matches[1] }
    } catch { }
    return $null
}

function Get-OllamaApiVersion {
    try {
        $r = Invoke-RestMethod -Uri "$script:OllamaApi/api/version" -TimeoutSec 3 -ErrorAction Stop
        return [string]$r.version
    } catch {
        return $null
    }
}

function Start-OllamaServer {
    # Returns 'api' when a server was already answering, 'started' when
    # this call launched one. Throws when no CLI can be found.
    if (Get-OllamaApiVersion) { return 'api' }
    $cli = Get-OllamaCliPath
    if (-not $cli) { Die 'no ollama.exe found (not installed yet)' }
    Start-Process -FilePath $cli -ArgumentList 'serve' -WindowStyle Hidden | Out-Null
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Seconds 1
        if (Get-OllamaApiVersion) { return 'started' }
    }
    Die "Ollama API did not come up within 60s (cli: $cli)"
}

function Save-KitState {
    param([hashtable]$State)
    Ensure-KitDirs
    $path = Join-Path $script:KitStateDir 'install-manifest.json'
    ($State | ConvertTo-Json -Depth 4) | Set-Content -Path $path -Encoding UTF8
    return $path
}

function Get-RecordedModel {
    $file = Join-Path $script:KitStateDir 'resolved-model.txt'
    if (Test-Path $file) {
        $m = (Get-Content $file -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($m) { return $m.Trim() }
    }
    return $null
}

function Save-RecordedModel {
    param([string]$Model)
    Ensure-KitDirs
    $Model | Set-Content -Path (Join-Path $script:KitStateDir 'resolved-model.txt') -Encoding ASCII
}

# Data location: by default, downloads land in the user profile
# (Downloads\omniget\tiktok) and decomposition projects in
# %USERPROFILE%\workspace\hypit-projects - both on the system drive.
# Set the user environment variable HYPIT_DATA_DIR (e.g. D:\HypitData)
# to move both onto another drive:
#   downloads -> <HYPIT_DATA_DIR>\downloads\tiktok
#   projects  -> <HYPIT_DATA_DIR>\projects\<name>
# (references, frame tiles and DRAFT_NOTES.md all live in the project
# folder.) Set it once with:
#   [Environment]::SetEnvironmentVariable('HYPIT_DATA_DIR','D:\HypitData','User')
# then open new windows. Existing data is not moved automatically.
function Get-DataDir {
    if ($env:HYPIT_DATA_DIR) { return $env:HYPIT_DATA_DIR }
    return $null
}
function Get-DownloadsDir {
    $d = Get-DataDir
    if ($d) { return (Join-Path $d 'downloads\tiktok') }
    return (Join-Path $env:USERPROFILE 'Downloads\omniget\tiktok')
}
function Get-ProjectsRoot {
    $d = Get-DataDir
    if ($d) { return (Join-Path $d 'projects') }
    return (Join-Path $env:USERPROFILE 'workspace\hypit-projects')
}
