#requires -version 5.1
param([string]$Root=(Split-Path -Parent $PSScriptRoot),[int]$LauncherPid=0,[switch]$ConfirmRemoval,[switch]$Quiet)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework
if(-not $ConfirmRemoval){ & (Join-Path $Root 'Uninstall.exe'); exit }
$resultPath=Join-Path $PSScriptRoot 'uninstall-result.json'
try {
 if($LauncherPid){$launcher=Get-Process -Id $LauncherPid -ErrorAction SilentlyContinue;if($launcher -and -not $launcher.WaitForExit(10000)){throw 'Uninstall launcher is still running.'}}
 Import-Module (Join-Path $PSScriptRoot 'Removal.Core.psm1') -Force
 $expected=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'BootStudio'
 $root=Assert-RemovalTree $Root $expected
 $manifest=Get-Content -LiteralPath (Join-Path $root 'install-manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
 $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 if($manifest.Product -ne 'BootStudio.Install' -or $manifest.OwnerSid -ne $sid){throw 'Installation ownership mismatch.'}
 foreach($process in @(Get-CimInstance Win32_Process -Filter "Name='BootStudio.exe' OR Name='BootShell.exe'")){
  if($process.ExecutablePath -and $process.ExecutablePath.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){throw '请先关闭 Boot Studio，并等待动画播放结束，再卸载。'}
 }
 Assert-RemovalFilesUnlocked $root $expected
 $psExe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
 $output=& $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Invoke-Startup.ps1') -Action Disable -Root $root
 if($LASTEXITCODE -ne 0){throw ('启动恢复未通过，已保留程序和恢复文件。'+($output -join "`n"))}
 $statusOutput=& $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Invoke-Startup.ps1') -Action Status -Root $root
 if($LASTEXITCODE -ne 0){throw 'Independent startup verification failed; files retained.'}
 $status=($statusOutput -join "`n") | ConvertFrom-Json
 if($status.Enabled -or $status.Recovery){throw 'Startup/recovery remains enabled; files retained.'}
 $shell=New-Object -ComObject WScript.Shell
 $links=@()
 foreach($folder in @([Environment]::GetFolderPath('Programs'),[Environment]::GetFolderPath('Desktop'))){
  $linkPath=Join-Path $folder 'Boot Studio.lnk'
  if((Test-Path -LiteralPath $linkPath) -and $shell.CreateShortcut($linkPath).TargetPath -eq (Join-Path $root 'app\bin\BootStudio.exe')){$links+=$linkPath}
 }
 Remove-InstallationTree $root $expected
 foreach($linkPath in $links){Remove-Item -LiteralPath $linkPath -Force}
 $key='HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\BootStudio'
 if((Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue).InstallLocation -eq $root){Remove-Item -LiteralPath $key}
 @{Success=$true;Startup=$status;RemovedRoot=$root} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $resultPath -Encoding UTF8
 if(-not $Quiet){[Windows.MessageBox]::Show('Boot Studio 已卸载。启动设置已恢复；程序、配置、日志、导入的视频副本和快捷方式已删除。原始视频不受影响。','Boot Studio') | Out-Null}
 $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
 if((Split-Path -Parent $PSScriptRoot) -eq $temp -and (Split-Path -Leaf $PSScriptRoot) -match '^BootStudio-Uninstall-[a-f0-9]{32}$'){Remove-InstallationTree $PSScriptRoot $PSScriptRoot}
}catch{
 @{Success=$false;Error=$_.Exception.Message} | ConvertTo-Json | Set-Content -LiteralPath $resultPath -Encoding UTF8
 if(-not $Quiet){[Windows.MessageBox]::Show(('卸载未完成：'+$_.Exception.Message+"`n`n诊断记录："+$resultPath+"`n请关闭应用后重试；不要手动删除仍被启动入口引用的文件。"),'Boot Studio') | Out-Null}
 exit 1
}
