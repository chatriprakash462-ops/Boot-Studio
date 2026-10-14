#requires -version 5.1
param([switch]$Test)
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
$build=Join-Path $PSScriptRoot ('build\'+[guid]::NewGuid().ToString('N'))
$payload=Join-Path $build 'payload'
$output=Join-Path $PSScriptRoot 'dist'
New-Item -ItemType Directory -Path $payload,$output -Force | Out-Null
$framework=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
$compiler=Join-Path $framework 'csc.exe'
& (Join-Path $project 'app\Build.ps1') -OutputDirectory (Join-Path $payload 'app\bin') -Test:$Test
& $compiler /nologo /target:winexe /platform:x64 /optimize+ ('/out:'+(Join-Path $payload 'BootShell.exe')) (Join-Path $PSScriptRoot 'runtime\BootShell.cs')
if($LASTEXITCODE -ne 0){throw 'Package launcher build failed.'}
$player=Get-Content -LiteralPath (Join-Path $project 'Start-BootIntro.ps1') -Raw -Encoding UTF8
. (Join-Path $PSScriptRoot 'Prepare-Player.ps1')
$player=ConvertTo-PackagePlayer $player
$player | Set-Content -LiteralPath (Join-Path $payload 'Start-BootIntro.ps1') -Encoding UTF8
Copy-Item -LiteralPath (Join-Path $project 'LICENSE') -Destination $payload
$maintenance=Join-Path $payload 'maintenance'
New-Item -ItemType Directory -Path $maintenance -Force | Out-Null
& $compiler /nologo /target:library /platform:x64 /optimize+ ('/out:'+(Join-Path $maintenance 'Player.Desktop.dll')) (Join-Path $PSScriptRoot 'runtime\Player.Desktop.cs')
if($LASTEXITCODE -ne 0){throw 'Player desktop probe build failed.'}
Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'runtime') -File | Where-Object {$_.Extension -in '.ps1','.psm1'} | ForEach-Object {
    [IO.File]::WriteAllText((Join-Path $maintenance $_.Name),(Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8),(New-Object Text.UTF8Encoding($true)))
}
$uninstallArgs=@('/nologo','/target:winexe','/platform:x64','/codepage:65001',('/out:'+(Join-Path $payload 'Uninstall.exe')),('/reference:'+(Join-Path $framework 'System.Windows.Forms.dll')))
foreach($name in @('Uninstall.ps1','Removal.Core.psm1','Invoke-Startup.ps1','Startup.Core.psm1')){$uninstallArgs+=('/resource:'+(Join-Path $maintenance $name)+','+$name)}
& $compiler @uninstallArgs (Join-Path $PSScriptRoot 'Uninstall.cs') (Join-Path $project 'app\AssemblyInfo.cs')
if($LASTEXITCODE -ne 0){throw 'Uninstaller build failed.'}
$media=Join-Path $payload 'media'
New-Item -ItemType Directory -Path $media | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'assets\sample.mp4') -Destination $media
$config=Get-Content -LiteralPath (Join-Path $project 'boot-intro.config.example.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$config.introVideo='media\sample.mp4'
$config.wallpaperEngineExe=''
$config.launchWallpaperEngineIfMissing=$false
$config.waitForWallpaperEngineSeconds=0
$config.extraRevealDelayMilliseconds=0
$config.hideDesktopIcons=$false
$config.hideTaskbar=$false
$config.sendWallpaperEngineHideIcons=$false
$config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $payload 'boot-intro.config.json') -Encoding UTF8
@'
Boot Studio v0.25 / 0.2.5-preview.3
Original startup project: Rantkid / DARLING-in-the-Windows
https://github.com/Rantkid/DARLING-in-the-Windows
Required Notice: Copyright (c) 2026 Rantkid.
License: PolyForm Noncommercial 1.0.0 (see LICENSE)
No personal videos, account identifiers or credentials are included.
media/sample.mp4 is a generated test pattern, reproducible with Generate-Sample.ps1.
The setup package has not yet been validated across other Windows installations.
'@ | Set-Content -LiteralPath (Join-Path $payload 'NOTICE.txt') -Encoding UTF8
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'USER-GUIDE.md') -Destination (Join-Path $payload 'USER-GUIDE.md')
foreach($operation in @('Enable','Disable')){
    $command='@echo off'+"`r`n"+'"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0maintenance\Invoke-Startup.ps1" -Action '+$operation+' -Root "%~dp0."'+"`r`n"+'pause'+"`r`n"
    [IO.File]::WriteAllText((Join-Path $payload ($operation+'-Animation.cmd')),$command,[Text.Encoding]::ASCII)
}
@'
@echo off
start "" "%~dp0Uninstall.exe"
'@ | Set-Content -LiteralPath (Join-Path $payload 'Uninstall.cmd') -Encoding ASCII
@'
@echo off
start "" "%~dp0app\bin\BootStudio.exe"
'@ | Set-Content -LiteralPath (Join-Path $payload 'Open-Boot-Studio.cmd') -Encoding ASCII
$files=@(Get-ChildItem -LiteralPath $payload -File -Recurse | Sort-Object FullName | ForEach-Object {
    [pscustomobject]@{Path=$_.FullName.Substring($payload.Length+1).Replace('\','/');Hash=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
})
[pscustomobject]@{Product='BootStudio.Install';Version='0.2.5-preview.3';OwnerSid='';Files=$files} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $payload 'payload-manifest.json') -Encoding UTF8
$zip=Join-Path $build 'payload.zip'
Compress-Archive -Path (Join-Path $payload '*') -DestinationPath $zip
$exe=Join-Path $output 'BootStudio-Setup-0.2.5-preview.3.exe'
$references=@('System.dll','System.Core.dll','System.Drawing.dll','System.Windows.Forms.dll','System.Web.Extensions.dll','System.IO.Compression.dll','System.IO.Compression.FileSystem.dll','Microsoft.CSharp.dll')
$arguments=@('/nologo','/target:winexe','/platform:x64','/optimize+','/codepage:65001',('/out:'+$exe),('/resource:'+$zip+',BootStudio.Payload.zip'),('/resource:'+(Join-Path $project 'LICENSE')+',BootStudio.License'),('/win32manifest:'+(Join-Path $PSScriptRoot 'Setup.manifest')))
foreach($reference in $references){$arguments+=('/reference:'+(Join-Path $framework $reference))}
$arguments+=(Join-Path $PSScriptRoot 'Setup.cs')
$arguments+=(Join-Path $project 'app\AssemblyInfo.cs')
& $compiler @arguments
if($LASTEXITCODE -ne 0){throw 'Setup build failed.'}
(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash | Set-Content -LiteralPath ($exe+'.sha256') -Encoding ASCII
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'USER-GUIDE.md') -Destination $output
[pscustomobject]@{Executable=$exe;Payload=$payload;BuildDirectory=$build;FileCount=$files.Count;Size=(Get-Item -LiteralPath $exe).Length}
if($Test){ & (Join-Path $PSScriptRoot 'Test-Package.ps1') -Setup $exe }
