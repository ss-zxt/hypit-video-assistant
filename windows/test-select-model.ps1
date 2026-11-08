# test-select-model.ps1 - self-test for the Windows model tiers.
# Exercises the pure tier function across the boundaries and the
# KIT_FAKE_* environment hooks end to end. Exits non-zero on failure.
# Usage: powershell -ExecutionPolicy Bypass -File .\test-select-model.ps1

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'select-model.ps1')

$script:Failed = 0
function Assert-Model {
    param([int]$Ram, [int]$Vram, [string]$Expected)
    $got = Select-QwenModel -RamGB $Ram -VramGB $Vram
    if ($got -eq $Expected) {
        Write-Host "  [OK]   RAM $Ram GB / VRAM $Vram GB -> $got"
    } else {
        Write-Host "  [FAIL] RAM $Ram GB / VRAM $Vram GB -> $got (expected $Expected)"
        $script:Failed = 1
    }
}

Assert-Model 4  0  'qwen3:1.7b'
Assert-Model 7  0  'qwen3:1.7b'
Assert-Model 8  0  'qwen3:4b'
Assert-Model 15 0  'qwen3:4b'
Assert-Model 16 0  'qwen3:8b'
Assert-Model 31 0  'qwen3:8b'
Assert-Model 32 0  'qwen3:14b'
Assert-Model 8  8  'qwen3:8b'
Assert-Model 8  15 'qwen3:8b'
Assert-Model 8  16 'qwen3:14b'

# End to end through the env hooks, as a child process (stdout must be
# exactly one line: the model tag).
$env:KIT_FAKE_RAM_GB = '16'
$env:KIT_FAKE_VRAM_GB = '0'
$out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'select-model.ps1') 2>$null
if ($out -eq 'qwen3:8b') {
    Write-Host '  [OK]   env-hook run (16 GB / 0 GB) -> qwen3:8b on stdout'
} else {
    Write-Host "  [FAIL] env-hook run returned '$out' (expected qwen3:8b)"
    $script:Failed = 1
}
Remove-Item Env:KIT_FAKE_RAM_GB, Env:KIT_FAKE_VRAM_GB -ErrorAction SilentlyContinue

if ($script:Failed) { Write-Host 'SELECT-MODEL TESTS FAILED'; exit 1 }
Write-Host 'ALL SELECT-MODEL TESTS PASSED'
exit 0
