# select-model.ps1 - pick the qwen3 size that fits THIS Windows machine.
#
# Prints exactly one model tag on stdout (e.g. qwen3:8b); the reasoning
# goes to stderr so callers can do:  $model = & .\select-model.ps1
#
# Tier logic (same tiers as the Linux select-model.sh; the model must fit
# in VRAM when a discrete GPU exists, else in RAM, with room left for the
# OS, Hypit's Chrome and the context window):
#   VRAM >= 16 GB  or  RAM >= 32 GB   -> qwen3:14b  (~9.3 GB download)
#   VRAM >=  8 GB  or  RAM >= 16 GB   -> qwen3:8b   (~5.2 GB)
#   RAM  >=  8 GB                     -> qwen3:4b   (~2.5 GB)
#   otherwise                         -> qwen3:1.7b (~1.4 GB, safe floor)
#
# Test hooks (not for production): KIT_FAKE_RAM_GB, KIT_FAKE_VRAM_GB
# override the detected values so the tiers can be exercised anywhere.

function Get-RamGB {
    if ($env:KIT_FAKE_RAM_GB) { return [int]$env:KIT_FAKE_RAM_GB }
    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        # Round to the NEAREST GiB: a nominal "16 GB" machine reports a bit
        # less, and flooring would wrongly drop it a tier.
        return [int][math]::Floor(($cs.TotalPhysicalMemory / 1GB) + 0.5)
    } catch {
        return 0
    }
}

function Get-VramGB {
    if ($env:KIT_FAKE_VRAM_GB) { return [int]$env:KIT_FAKE_VRAM_GB }
    $best = 0

    # NVIDIA: nvidia-smi reports exact dedicated memory.
    $smi = Get-Command 'nvidia-smi.exe' -ErrorAction SilentlyContinue
    if ($smi) {
        try {
            $mb = & $smi.Source --query-gpu=memory.total --format=csv,noheader,nounits 2>$null |
                ForEach-Object { [int]($_ -replace '[^0-9]', '') } |
                Sort-Object -Descending | Select-Object -First 1
            if ($mb) { $best = [math]::Max($best, [int][math]::Floor($mb / 1024)) }
        } catch { }
    }

    # Other discrete GPUs (AMD Radeon RX / PRO, Intel Arc, Quadro):
    # Win32_VideoController.AdapterRAM is a 32-bit value capped at 4 GB,
    # so read the 64-bit size the driver registered under the display
    # class key instead. Integrated GPUs are skipped on purpose: their
    # "VRAM" is shared system RAM and must not double-count.
    try {
        $classRoot = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
        foreach ($sub in (Get-ChildItem $classRoot -ErrorAction SilentlyContinue)) {
            $props = Get-ItemProperty $sub.PSPath -ErrorAction SilentlyContinue
            $desc = [string]$props.DriverDesc
            if ($desc -notmatch 'RTX|GTX|Quadro|Radeon RX|Radeon PRO|Arc') { continue }
            $raw = $props.'HardwareInformation.qwMemorySize'
            $bytes = 0
            if ($raw -is [byte[]] -and $raw.Length -ge 8) { $bytes = [BitConverter]::ToInt64($raw, 0) }
            elseif ($raw) { $bytes = [int64]$raw }
            if ($bytes -gt 0) { $best = [math]::Max($best, [int][math]::Floor($bytes / 1GB)) }
        }
    } catch { }

    return [int]$best
}

function Select-QwenModel {
    param([int]$RamGB, [int]$VramGB)
    if ($VramGB -ge 16 -or $RamGB -ge 32) { return 'qwen3:14b' }
    if ($VramGB -ge 8  -or $RamGB -ge 16) { return 'qwen3:8b' }
    if ($RamGB -ge 8)                     { return 'qwen3:4b' }
    return 'qwen3:1.7b'
}

# Run as a script (not when dot-sourced for the functions above).
if ($MyInvocation.InvocationName -ne '.') {
    $ram  = Get-RamGB
    $vram = Get-VramGB
    $model = Select-QwenModel -RamGB $ram -VramGB $vram
    [Console]::Error.WriteLine("detected: RAM $ram GB, GPU VRAM $vram GB -> $model")
    Write-Output $model
}
