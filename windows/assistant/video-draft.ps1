# video-draft.ps1 - the kit's local "assistant" pipeline on Windows.
#
# Give it a video URL (TikTok / YouTube / Bilibili / ...) or a local video file. It will:
#   1. download the video (URLs only, via tiktok\download-tiktok.ps1)
#   2. archive it and cut 0.5s frame grids (tiktok\prepare-reference.ps1)
#   3. feed every grid image to the local vision model in Ollama and
#      collect per-grid timeline notes (the model must be a VL model,
#      e.g. qwen3-vl:4b-instruct - a text-only model cannot see frames)
#   4. ask the model to merge the notes into a shot-breakdown draft
#   5. write DRAFT_NOTES.md into the project folder
#
# The output is a DRAFT: local small models miss details and sometimes
# misread actions. Use it as the raw material for a human / stronger
# model to write the final prompt pack - that division of labor is the
# kit's standing rule.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\video-draft.ps1 "<video URL>"
#   powershell -ExecutionPolicy Bypass -File .\video-draft.ps1 "C:\path\video.mp4" [-ProjectName name] [-Model qwen3-vl:4b-instruct]

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$Source,
    [string]$ProjectName,
    [string]$Model,
    [int]$MaxGrids = 12
)

$ErrorActionPreference = 'Stop'
$WindowsDir = Split-Path $PSScriptRoot -Parent
. (Join-Path $WindowsDir 'common.ps1')
$paths = Get-KitPaths

# Data-location default, entry-point independent: D:\HypitData when
# a D: drive exists and HYPIT_DATA_DIR is not already set (the .bat
# launchers set it too; the GUI's wscript launcher sets it in its
# own process env). Keeps downloads/projects off the system drive
# no matter how this script was started.
if (-not $env:HYPIT_DATA_DIR -and (Test-Path 'D:\')) { $env:HYPIT_DATA_DIR = 'D:\HypitData' }

try {
    # Chinese UI: render this script's output as UTF-8 (the launcher
    # stays pure ASCII - cmd.exe misparses non-ASCII batch files - so
    # the prompt lives here, in the UTF-8-BOM script).
    try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
    if (-not $Source) {
        Write-Host '粘贴视频链接 (TikTok / YouTube / Bilibili 等), 或输入本地视频文件的路径 (也可以把视频文件拖到 video-draft.bat 上):'
        $Source = Read-Host '>'
        if (-not $Source) { Die '没有输入任何内容, 退出。' }
        $Source = $Source.Trim().Trim('"')
    }

    # Model: explicit > recorded by the installer > VL default.
    if (-not $Model) { $Model = Get-RecordedModel }
    if (-not $Model) { $Model = 'qwen3-vl:4b-instruct' }
    if ($Model -notmatch 'vl|vision|llava|minicpm-v') {
        Write-Warn "模型 '$Model' 看起来不是视觉模型, 帧图可能被忽略或拒绝; 建议用 VL 模型 (如 qwen3-vl:4b-instruct)。"
    }

    # Make sure the local Ollama API is up before doing any work.
    [void](Start-OllamaServer)
    Write-Info "助手模型: $Model (接口 $($paths.OllamaApi))"

    # ------------------------------------------------------------ 1. get the file
    $videoFile = $null
    if ($Source -match '^https?://') {
        Write-Log '下载参考视频'
        # Do NOT parse the child's console text: download-tiktok.ps1
        # prints its "Downloaded:" line with Write-Host, which renders
        # to the host and never enters a captured pipeline (field bug
        # 2026-11-08: download succeeded, the parse found nothing).
        # Locate the result by snapshotting the download folder instead.
        $dlDir = Get-DownloadsDir
        $before = @{}
        if (Test-Path $dlDir) {
            Get-ChildItem $dlDir -File | ForEach-Object { $before[$_.FullName] = $_.LastWriteTimeUtc }
        }
        $startUtc = [DateTime]::UtcNow
        & (Join-Path $WindowsDir 'tiktok\download-tiktok.ps1') $Source | Out-Host
        $fresh = @(Get-ChildItem $dlDir -File -ErrorAction SilentlyContinue | Where-Object {
            (-not $before.ContainsKey($_.FullName)) -or ($_.LastWriteTimeUtc -gt $before[$_.FullName])
        } | Where-Object { $_.LastWriteTimeUtc -ge $startUtc.AddMinutes(-2) } |
            Sort-Object LastWriteTimeUtc -Descending)
        if ($fresh.Count -gt 0) { $videoFile = $fresh[0].FullName }
        if (-not $videoFile -or -not (Test-Path $videoFile)) { Die "下载没有在 $dlDir 产生新文件" }
        Write-Info "已下载文件: $videoFile"
    } else {
        if (-not (Test-Path $Source)) { Die "找不到文件: $Source" }
        $videoFile = (Resolve-Path $Source).Path
    }

    if (-not $ProjectName) {
        $base = [IO.Path]::GetFileNameWithoutExtension($videoFile) -replace '[^A-Za-z0-9_-]', '-'
        if (-not $base) { $base = 'video' }
        $ProjectName = "$base-draft"
    }

    # ------------------------------------------------------------ 2. archive + frame grids
    Write-Log '准备项目 (归档 + 拆帧拼图)'
    & (Join-Path $WindowsDir 'tiktok\prepare-reference.ps1') $videoFile $ProjectName | Out-Host
    # The child has its own try/catch + exit; check it, or a child
    # failure surfaces later as a misleading "no frame grids" error
    # (field bug 2026-11-08).
    if ($LASTEXITCODE -ne 0) { Die '拆帧失败 —— 看上面那行红字' }

    $projectDir = Join-Path (Get-ProjectsRoot) $ProjectName
    $tileDir = Join-Path $projectDir 'evidence\tiles'
    $grids = @(Get-ChildItem $tileDir -File -ErrorAction Stop |
        Where-Object { $_.Extension -in '.png', '.jpg', '.jpeg' } |
        Sort-Object Name | Select-Object -First $MaxGrids)
    if ($grids.Count -eq 0) { Die "在 $tileDir 没找到帧拼图" }
    Write-Info "共 $($grids.Count) 张拼图待读取"

    # ------------------------------------------------------------ 3. per-grid vision notes
    $gridPrompt = 'This is a frame grid sampled from a short video, one frame every 0.5 seconds, in time order (left to right, top to bottom). Describe the frames one by one: what is in the picture, how the subject moves or changes, and any scene or camera changes. Write ONLY what you can actually see; do not invent anything. Answer in Chinese, as concise timeline notes.'
    $notes = @()
    $notes += "# DRAFT_NOTES —— 本地助手初稿"
    $notes += ""
    $notes += "来源: $Source"
    $notes += "模型: $Model"
    $notes += "生成时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $notes += ""
    $notes += "## 逐拼图笔记"
    $outFile = Join-Path $projectDir 'DRAFT_NOTES.md'

    # One vision call. keep_alive stops Ollama unloading the model
    # between grids (a reload on a CPU-only box wastes minutes).
    function Read-GridImage {
        param([string]$ImagePath, [string]$UseModel, [string]$Api, [string]$Prompt, [int]$MaxTokens)
        $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($ImagePath))
        $body = @{
            model      = $UseModel
            messages   = @(@{ role = 'user'; content = $Prompt; images = @($b64) })
            stream     = $false
            think      = $false
            keep_alive = '30m'
            options    = @{ num_predict = $MaxTokens }
        } | ConvertTo-Json -Depth 6
        $resp = Invoke-RestMethod -Uri "$Api/api/chat" -Method Post -Body $body `
            -ContentType 'application/json' -TimeoutSec 900 -ErrorAction Stop
        return [string]$resp.message.content
    }
    $ffmpegExe = $null
    $ffc = Get-Command 'ffmpeg.exe' -ErrorAction SilentlyContinue
    if ($ffc) { $ffmpegExe = $ffc.Source } else { $ffmpegExe = Find-FirstFile $paths.FfmpegDir 'ffmpeg.exe' }
    $tmpDir = Join-Path ([IO.Path]::GetTempPath()) 'hypit-kit-splits'
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

    $i = 0
    foreach ($grid in $grids) {
        $i++
        Write-Info "正在读取拼图 $i/$($grids.Count): $($grid.Name) ..."
        # Completion first (field lesson 2026-11-08): a full sheet is
        # ~1600x3400 px; on a CPU-only machine one sheet can exceed the
        # 15-minute call timeout. If the full sheet fails, split it
        # into halves and read those; if a half still fails, downscale
        # it and try once more. Every rung exists so the grid DOES get
        # read - a preserved-but-incomplete draft is not the goal.
        $text = $null
        try {
            $text = Read-GridImage $grid.FullName $Model $($paths.OllamaApi) $gridPrompt 900
        } catch {
            Write-Warn "拼图 $i 整张读取失败 ($($_.Exception.Message))"
        }
        if (-not $text -and $ffmpegExe) {
            Write-Info "拼图 $i 改为上下两半分开读 ..."
            $prevEAP = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            $parts = @()
            $splitOk = $true
            foreach ($half in @(@{ n = 'a'; y = '0' }, @{ n = 'b'; y = 'in_h/2' })) {
                $halfPath = Join-Path $tmpDir "$($grid.BaseName)-$($half.n).jpg"
                & $ffmpegExe -y -v error -i $grid.FullName -vf "crop=in_w:in_h/2:0:$($half.y)" $halfPath 2>$null
                if (-not (Test-Path $halfPath)) { $splitOk = $false; break }
                try {
                    $t = Read-GridImage $halfPath $Model $($paths.OllamaApi) $gridPrompt 600
                    $parts += "(拼图 $i · 半张 $($half.n))`n$t"
                } catch {
                    $smallPath = Join-Path $tmpDir "$($grid.BaseName)-$($half.n)-s.jpg"
                    & $ffmpegExe -y -v error -i $halfPath -vf 'scale=1024:-2' $smallPath 2>$null
                    try {
                        $t = Read-GridImage $smallPath $Model $($paths.OllamaApi) $gridPrompt 600
                        $parts += "(拼图 $i · 半张 $($half.n), 缩小版)`n$t"
                    } catch { $splitOk = $false }
                }
            }
            $ErrorActionPreference = $prevEAP
            if ($splitOk -and $parts.Count -eq 2) { $text = ($parts -join "`n") }
        }
        $notes += ""
        $notes += "### $($grid.Name)"
        if ($text) {
            $notes += $text.Trim()
            Write-Info "拼图 $i 读完"
        } else {
            $notes += "(本张拼图读取失败, 已跳过。)"
            Write-Warn "拼图 $i 最终没读出来, 已标记跳过"
        }
        $notes | Set-Content -Path $outFile -Encoding UTF8
    }

    # Save the per-grid notes FIRST. They are the valuable part; the
    # merge below is a convenience extra (and, per QC experience, the
    # part a human/stronger model redoes anyway). A merge failure must
    # never throw the notes away (field bug 2026-11-08: 3 grids read
    # fine, then the merge died with HTTP 400 - the default 4096-token
    # context was too small for all notes at once - and no file was
    # written at all). ($outFile is defined before the grid loop; the
    # loop already re-saves after every grid.)
    $notes | Set-Content -Path $outFile -Encoding UTF8
    Write-Info "逐拼图笔记已先存好: $outFile"

    # ------------------------------------------------------------ 4. merged breakdown draft
    Write-Log '汇总成拆解初稿'
    try {
        $allNotes = ($notes -join "`n")
        if ($allNotes.Length -gt 12000) { $allNotes = $allNotes.Substring(0, 12000) }
        $mergePrompt = "Below are per-grid timeline notes of a short video, written by a vision model. Merge them into ONE shot-breakdown draft in Chinese: combine consecutive frames into continuous actions in time order, mark likely shot boundaries, and for each segment add one draft sentence that could seed a video-generation prompt. Keep only what the notes support; do not invent new content.`n`n$allNotes"
        $body2 = @{
            model      = $Model
            messages   = @(@{ role = 'user'; content = $mergePrompt })
            stream     = $false
            think      = $false
            keep_alive = '30m'
            options    = @{ num_predict = 1200; num_ctx = 16384 }
        } | ConvertTo-Json -Depth 6
        $resp2 = Invoke-RestMethod -Uri "$($paths.OllamaApi)/api/chat" -Method Post -Body $body2 `
            -ContentType 'application/json' -TimeoutSec 900 -ErrorAction Stop
        $notes += ""
        $notes += "## 汇总拆解草案"
        $notes += ""
        $notes += ([string]$resp2.message.content).Trim()
    } catch {
        Write-Warn "自动汇总失败 ($($_.Exception.Message)) —— 逐拼图笔记已完整保留在文件里, 不影响使用。"
        $notes += ""
        $notes += "## 汇总拆解草案"
        $notes += ""
        $notes += "(自动汇总失败, 逐拼图笔记已完整保留在上方, 可直接使用。)"
    }
    $notes | Set-Content -Path $outFile -Encoding UTF8

    # ------------------------------------------------------------ 5. done
    Write-Log '完成'
    Write-Host "初稿已写入: $outFile"
    Write-Host '这是本地模型的第一版初稿 —— 把它发给你的主 AI 或人工, 在初稿上整理成定稿提示词包。'
} catch {
    Write-Host "`n$($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
