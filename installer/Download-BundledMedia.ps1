#requires -version 5.1
$ErrorActionPreference='Stop'
$assets=Join-Path $PSScriptRoot 'assets'
$info=Get-Content -LiteralPath (Join-Path $assets 'bundled-video.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$destination=Join-Path $assets 'shinjuku-rain.mp4'
if((Test-Path -LiteralPath $destination) -and (Get-FileHash -LiteralPath $destination).Hash -eq $info.SHA256){Write-Output 'Bundled video already verified.';exit}
$temporary=$destination+'.download'
try{
 [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
 Invoke-WebRequest -Uri $info.DownloadUrl -OutFile $temporary -UseBasicParsing
 if((Get-FileHash -LiteralPath $temporary).Hash -ne $info.SHA256){throw 'Downloaded media checksum mismatch.'}
 Move-Item -LiteralPath $temporary -Destination $destination -Force
}finally{if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Force}}
