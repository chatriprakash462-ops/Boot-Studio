# Run from Windows PowerShell 5.1. No host installation or startup changes occur.
param()
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
& (Join-Path $PSScriptRoot 'Build-Package.ps1') -Test
$release=Join-Path $project 'release'
New-Item -ItemType Directory -Path $release -Force | Out-Null
$source=Join-Path $PSScriptRoot 'dist\BootStudio-Setup-0.2.5-preview.5.exe'
Copy-Item -LiteralPath $source -Destination (Join-Path $release 'BootStudio_Setup.exe') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'USER-GUIDE.md') -Destination (Join-Path $release 'README.md') -Force
Copy-Item -LiteralPath (Join-Path $project 'LICENSE') -Destination $release -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'assets\MEDIA-NOTICE.txt') -Destination $release -Force
$report=Join-Path $release 'TEST-REPORT.md'
@'
# Current build validation

Isolated package, configuration, startup simulation, ownership, recovery and removal-boundary tests passed as part of Build-Release.ps1.

Fresh Windows VM installation, visible playback, reboot and complete uninstall: **pending for this exact build**. Windows 10 real-machine testing: **not completed**. Do not carry forward a previous build's success without rerunning the integration cycle.
'@ | Set-Content -LiteralPath $report -Encoding UTF8
$testFolder=Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'test-results') -Directory | Where-Object {Test-Path -LiteralPath (Join-Path $_.FullName 'results.txt')} | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Copy-Item -LiteralPath (Join-Path $testFolder.FullName 'results.txt') -Destination (Join-Path $release 'ISOLATED-TESTS.txt') -Force
$hash=(Get-FileHash -LiteralPath (Join-Path $release 'BootStudio_Setup.exe')).Hash
@(($hash+'  BootStudio_Setup.exe'),((Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'assets\shinjuku-rain.mp4')).Hash+'  shinjuku-rain.mp4')) | Set-Content -LiteralPath (Join-Path $release 'SHA256SUMS.txt') -Encoding ASCII
@{Product='Boot Studio';Release='v0.25';Version='0.2.5.5';InstallerSHA256=$hash;BuiltAt=[DateTime]::UtcNow.ToString('o');Target='Windows 10/11 x64';Signed=$false} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $release 'build-info.json') -Encoding UTF8
Write-Output ('Release: '+$release)
