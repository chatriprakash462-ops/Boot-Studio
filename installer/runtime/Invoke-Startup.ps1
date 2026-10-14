#requires -version 5.1
param(
    [ValidateSet('Status','Enable','Disable')][string]$Action='Status',
    [string]$Root=(Split-Path -Parent $PSScriptRoot),
    [switch]$Worker,
    [string]$ResultPath,
    [switch]$Simulation,
    [string]$DeadlineUtc
)
$ErrorActionPreference='Stop'
function Get-FailureCode([string]$Message) {
    if($Message -match 'RequestExpired'){return 'RequestExpired'}
    if($Message -match 'Another custom user Shell'){return 'ExistingCustomShell'}
    if($Message -match 'managed Shell policy'){return 'ManagedShellPolicy'}
    if($Message -match 'machine uses a custom Shell'){return 'MachineShellConflict'}
    return 'StartupConfigurationFailed'
}
if($Simulation -or $Worker){
    try{
        # Module load failures must also produce a result instead of a silent timeout.
        if($ResultPath){[IO.File]::WriteAllText($ResultPath+'.started',([DateTime]::UtcNow.ToString('o')))}
        Import-Module (Join-Path $PSScriptRoot 'Startup.Core.psm1') -Force
        Initialize-Context $Root -Simulation:$Simulation
        Set-RequestGuard -DeadlineUtc $DeadlineUtc -CancelPath $(if($ResultPath){$ResultPath+'.cancelled'}else{''})
        $data=Invoke-StartupOperation $Action
        if($ResultPath){Save-JsonAtomic $ResultPath ([pscustomobject]@{Success=$true; Data=$data})}else{$data | ConvertTo-Json -Depth 12}
        exit 0
    }catch{
        if($ResultPath){
            $response=[pscustomobject]@{Success=$false;Code=(Get-FailureCode $_.Exception.Message);Error=$_.Exception.Message}
            if(Get-Command Save-JsonAtomic -ErrorAction SilentlyContinue){Save-JsonAtomic $ResultPath $response}
            else{$temp=$ResultPath+'.failure.tmp';$response|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $temp -Encoding UTF8;[IO.File]::Move($temp,$ResultPath)}
        }
        else{Write-Error $_}
        exit 1
    }
}
# Run in a real interactive account task, rather than trusting the caller's HKCU view.
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if([Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0){throw 'Run this tool from the target user desktop.'}
$rootPath=[IO.Path]::GetFullPath($Root)
$resultFolder=Join-Path $rootPath 'boot-studio-data\installation\operations'
New-Item -ItemType Directory -Path $resultFolder -Force | Out-Null
$operation=[guid]::NewGuid().ToString('N')
$result=Join-Path $resultFolder ($operation+'.json')
$taskName='BootStudioControl-'+$operation
$psExe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$deadline=[DateTime]::UtcNow.AddSeconds(90)
$arguments='-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+$PSCommandPath+'" -Action '+$Action+' -Root "'+$rootPath+'" -Worker -ResultPath "'+$result+'" -DeadlineUtc "'+$deadline.ToString('o')+'"'
$taskRegistered=$false
$failureCode='StartupConfigurationFailed'
try{
    $taskAction=New-ScheduledTaskAction -Execute $psExe -Argument $arguments
    $principal=New-ScheduledTaskPrincipal -UserId $sid -LogonType Interactive -RunLevel Limited
    $settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 2)
    Register-ScheduledTask -TaskName $taskName -Action $taskAction -Principal $principal -Settings $settings | Out-Null
    $taskRegistered=$true
    Start-ScheduledTask -TaskName $taskName
    while(-not(Test-Path -LiteralPath $result)){
        if([DateTime]::UtcNow -gt $deadline){
            [IO.File]::WriteAllText($result+'.cancelled',[DateTime]::UtcNow.ToString('o'))
            $failureCode='TaskTimeout'
            throw 'Timed out while waiting for the interactive account task. The request has expired. Keep installed files until startup status is checked.'
        }
        Start-Sleep -Milliseconds 200
    }
    $response=Get-Content -LiteralPath $result -Raw -Encoding UTF8 | ConvertFrom-Json
    if(-not $response.Success){$failureCode=if($response.PSObject.Properties['Code']){$response.Code}else{Get-FailureCode $response.Error};throw $response.Error}
    # Verify with a separate scheduled task and separate registry handle/environment.
    if($Action -ne 'Status'){
        $statusOutput=& $psExe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Action Status -Root $rootPath
        if($LASTEXITCODE -ne 0){throw 'Independent login-environment verification failed. Keep installed files and use Disable to restore.'}
        $verified=($statusOutput -join "`n") | ConvertFrom-Json
        if($Action -eq 'Enable' -and (-not $verified.Enabled -or -not $verified.Recovery)){throw 'The separate login task cannot see the enabled Shell and recovery task. Keep installed files and use Disable to restore.'}
        if($Action -eq 'Disable' -and $verified.Enabled){throw 'The separate login task still sees the animation Shell. Installed files must be retained.'}
    }
    $response.Data | ConvertTo-Json -Depth 12
} catch {
    $errorMessage=$_.Exception.Message
    $taskState=$null;$lastTaskResult=$null
    if($taskRegistered){
        try{$taskState=[string](Get-ScheduledTask -TaskName $taskName).State;$lastTaskResult=(Get-ScheduledTaskInfo -TaskName $taskName).LastTaskResult}catch{}
    }
    [pscustomobject]@{Success=$false;Code=$failureCode;Error=$errorMessage;Operation=$operation;Action=$Action;WorkerStarted=(Test-Path -LiteralPath ($result+'.started'));TaskState=$taskState;LastTaskResult=$lastTaskResult;ResultPath=$result} | ConvertTo-Json -Depth 8
    exit 1
} finally {
    if($taskRegistered){
        # Do not interrupt an activation worker on timeout: its own task deadline remains.
        $task=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if($task -and (Test-Path -LiteralPath $result)){
            for($i=0;$i -lt 10 -and $task.State -eq 'Running';$i++){Start-Sleep -Milliseconds 100;$task=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue}
        }
        if($task -and $task.State -ne 'Running'){Unregister-ScheduledTask -TaskName $taskName -Confirm:$false}
    }
}
