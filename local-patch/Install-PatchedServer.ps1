# Swaps T3 Code's server.asar for the locally patched build (usage limits keyed by org).
# Run with T3 Code fully quit. Restore with .\Restore-OriginalServer.ps1.
$ErrorActionPreference = 'Stop'

$resources = Join-Path $env:LOCALAPPDATA 'Programs\t3code\resources'
$target    = Join-Path $resources 'server.asar'
$backup    = Join-Path $resources 'server.asar.original'
$patched   = Join-Path $PSScriptRoot 'out\server.asar'

if (Get-Process -Name 'T3 Code*' -ErrorAction SilentlyContinue) {
    throw 'T3 Code is still running. Quit it fully (tray icon too), then run this again.'
}
if (-not (Test-Path $patched)) { throw "Patched build not found at $patched" }

$targetHash  = (Get-FileHash $target -Algorithm SHA256).Hash
$patchedHash = (Get-FileHash $patched -Algorithm SHA256).Hash
if ($targetHash -eq $patchedHash) { Write-Host 'Patched server.asar is already installed.'; return }

# The installed file is not this patch, so it is the original (possibly from a newer update):
# refresh the backup from it so a restore never brings back an older version.
Copy-Item $target $backup -Force
Write-Host "Backed up original to $backup"

Copy-Item $patched $target -Force
if ((Get-FileHash $target -Algorithm SHA256).Hash -ne $patchedHash) { throw 'Copy verification failed.' }
Write-Host 'Installed patched server.asar. Start T3 Code and check the usage panel.'
