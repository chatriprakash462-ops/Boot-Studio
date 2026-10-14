param([Parameter(Mandatory=$true)][string]$FFmpeg)
$ErrorActionPreference='Stop'
$assets=Join-Path $PSScriptRoot 'assets'
New-Item -ItemType Directory -Path $assets -Force | Out-Null
& $FFmpeg -hide_banner -loglevel error -y -f lavfi -i 'testsrc2=size=1280x720:rate=30:duration=6' -an -c:v libx264 -pix_fmt yuv420p -preset veryfast -crf 27 -movflags +faststart (Join-Path $assets 'sample.mp4')
if($LASTEXITCODE -ne 0){throw 'Sample generation failed.'}
(Get-FileHash -LiteralPath (Join-Path $assets 'sample.mp4')).Hash | Set-Content (Join-Path $assets 'sample.sha256') -Encoding ASCII
