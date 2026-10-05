# Puts back the server.asar that Install-PatchedServer.ps1 backed up. Run with T3 Code fully quit.
$ErrorActionPreference = 'Stop'

$resources = Join-Path $env:LOCALAPPDATA 'Programs\t3code\resources'
$target    = Join-Path $resources 'server.asar'
$backup    = Join-Path $resources 'server.asar.original'

if (Get-Process -Name 'T3 Code*' -ErrorAction SilentlyContinue) {
    throw 'T3 Code is still running. Quit it fully (tray icon too), then run this again.'
}
if (-not (Test-Path $backup)) { throw "No backup at $backup; nothing to restore." }

Copy-Item $backup $target -Force
Remove-Item $backup
Write-Host 'Restored the original server.asar.'
