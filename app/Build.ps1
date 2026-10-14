param([switch]$Test, [string]$OutputDirectory)
$ErrorActionPreference='Stop'
$framework=Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319'
$compiler=Join-Path $framework 'csc.exe'
if(-not (Test-Path -LiteralPath $compiler)){throw '.NET Framework C# compiler is not installed.'}
$output=if($OutputDirectory){[IO.Path]::GetFullPath($OutputDirectory)}else{Join-Path $PSScriptRoot 'bin'}
New-Item -ItemType Directory -Path $output -Force | Out-Null
$references=@('System.dll','System.Core.dll','System.Xaml.dll','System.Web.Extensions.dll','WPF\WindowsBase.dll','WPF\PresentationCore.dll','WPF\PresentationFramework.dll')
$arguments=@('/nologo','/target:winexe','/platform:x64','/optimize+','/codepage:65001',('/out:'+(Join-Path $output 'BootStudio.exe')),('/resource:'+(Join-Path $PSScriptRoot 'MainWindow.xaml')+',BootStudio.MainWindow.xaml'))
foreach($reference in $references){$arguments+=('/reference:'+(Join-Path $framework $reference))}
$arguments+=@(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.cs' -File | ForEach-Object {$_.FullName})
& $compiler @arguments
if($LASTEXITCODE -ne 0){throw 'Boot Studio build failed.'}
@'
<?xml version="1.0" encoding="utf-8"?>
<configuration><startup useLegacyV2RuntimeActivationPolicy="true"><supportedRuntime version="v4.0" sku=".NETFramework,Version=v4.8"/></startup></configuration>
'@ | Set-Content -LiteralPath (Join-Path $output 'BootStudio.exe.config') -Encoding UTF8
if($Test){
 $results=Join-Path $PSScriptRoot 'test-results\store-tests.txt'
 New-Item -ItemType Directory -Path (Split-Path -Parent $results) -Force | Out-Null
 $process=Start-Process -FilePath (Join-Path $output 'BootStudio.exe') -ArgumentList ('--self-test "'+$results+'"') -Wait -PassThru -WindowStyle Hidden
 Get-Content -LiteralPath $results
 if($process.ExitCode -ne 0){throw 'Boot Studio tests failed.'}
}
Write-Host ('Built: '+(Join-Path $output 'BootStudio.exe'))
