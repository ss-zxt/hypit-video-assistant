# start-ollama.ps1 - make sure a local Ollama server is answering on
# 127.0.0.1:11434, starting one from whichever install exists (the
# official app or the kit-managed standalone copy) when needed.
# Usage: powershell -ExecutionPolicy Bypass -File .\start-ollama.ps1

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

try {
    $state = Start-OllamaServer
    $ver = Get-OllamaApiVersion
    if ($state -eq 'api') { Write-Info "Ollama API already up: $ver" }
    else { Write-Info "Ollama started, API up: $ver" }
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
