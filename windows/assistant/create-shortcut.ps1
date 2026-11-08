# create-shortcut.ps1 - create (or refresh) the kit-root shortcut
# "Hypit本地助手.lnk" pointing at the GUI launcher, with the kit icon.
#
# Why this exists: a .lnk stores ABSOLUTE paths, and Explorer only
# accepts the full link format Windows itself writes. A link made
# off-machine with relative paths shows an EMPTY target in Explorer
# (field evidence 2026-11-08) and cannot launch at all. So the zip
# cannot ship a working shortcut - it is generated here, on the
# user's machine, by the same WScript.Shell mechanism Windows uses.
# Called by video-draft-gui.bat on every launch and at the end of
# install.ps1; can also be run by hand (it prints what it wrote).

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
try {
    $assistantDir = $PSScriptRoot
    $kitRoot = Split-Path (Split-Path $assistantDir -Parent) -Parent
    # Target is wscript + launch-gui.vbs, NOT the .bat: the script
    # host starts the GUI with no console window at all, so no black
    # box ever appears (a .bat target always creates one).
    $target = Join-Path $env:SystemRoot 'System32\wscript.exe'
    $vbs = Join-Path $assistantDir 'launch-gui.vbs'
    $icon = Join-Path $kitRoot 'HypitAssistant.ico'
    $lnkPath = Join-Path $kitRoot 'Hypit本地助手.lnk'
    $wsh = New-Object -ComObject WScript.Shell
    $sc = $wsh.CreateShortcut($lnkPath)
    $sc.TargetPath = $target
    $sc.Arguments = "`"$vbs`""
    $sc.WorkingDirectory = $assistantDir
    if (Test-Path $icon) { $sc.IconLocation = "$icon,0" }
    $sc.Description = 'Hypit 本地助手 - 视频拆解初稿'
    $sc.Save()
    Write-Host "快捷方式已生成: $lnkPath"
    Write-Host "  目标: $target `"$vbs`""
    Write-Host "  图标: $icon"
} catch {
    Write-Host "快捷方式生成失败: $($_.Exception.Message)" -ForegroundColor Yellow
    exit 1
}
