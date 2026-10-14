# Registry and task access is centralized here. Simulation never opens the registry
# or Task Scheduler; it is used to verify transactions without changing login.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:context = $null
function Initialize-Context([string]$Root, [switch]$Simulation) {
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $marker = Get-Content -LiteralPath (Join-Path $rootPath 'install-manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($marker.Product -ne 'BootStudio.Install') { throw 'Invalid installation marker.' }
    $sid = if ($Simulation) { 'TEST-USER' } else { [Security.Principal.WindowsIdentity]::GetCurrent().User.Value }
    if ($marker.OwnerSid -ne $sid) { throw 'This installation belongs to a different account.' }
    if (-not $Simulation) {
        $expected = [IO.Path]::GetFullPath((Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'BootStudio')).TrimEnd('\')
        if ($rootPath -ne $expected) { throw 'Unexpected installation path.' }
    }
    $data = Join-Path $rootPath 'boot-studio-data\installation'
    New-Item -ItemType Directory -Path $data -Force | Out-Null
    $script:context = @{Root=$rootPath; Sid=$sid; Simulation=[bool]$Simulation; Data=$data; TaskName=('BootStudioRecovery-'+$sid); State=$null; Deadline=$null; CancelPath=''}
    if ($Simulation) {
        $script:context.State = Get-Content -LiteralPath (Join-Path $rootPath 'simulation.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    }
}
function Set-RequestGuard([string]$DeadlineUtc,[string]$CancelPath) {
    if($DeadlineUtc){$script:context.Deadline=[DateTime]::Parse($DeadlineUtc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()}
    $script:context.CancelPath=$CancelPath
}
function Assert-RequestActive {
    if(($script:context.Deadline -and [DateTime]::UtcNow -ge $script:context.Deadline) -or ($script:context.CancelPath -and (Test-Path -LiteralPath $script:context.CancelPath))){
        throw 'RequestExpired: this operation timed out or was cancelled. No new startup changes will be made.'
    }
}
function Save-Simulation {
    if ($script:context.Simulation) { $script:context.State | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $script:context.Root 'simulation.json') -Encoding UTF8 }
}
function Get-ShellSnapshot {
    if ($script:context.Simulation) { return $script:context.State.Shell }
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows NT\CurrentVersion\Winlogon')
    try {
        $exists = $null -ne $key -and $key.GetValueNames() -contains 'Shell'
        [pscustomobject]@{Exists=$exists; Value=if($exists){$key.GetValue('Shell',$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)}else{$null}; Kind=if($exists){$key.GetValueKind('Shell').ToString()}else{'String'}}
    } finally { if($key){$key.Dispose()} }
}
function Set-ShellSnapshot($Snapshot) {
    if ($script:context.Simulation) { $script:context.State.Shell=$Snapshot; Save-Simulation; return }
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Software\Microsoft\Windows NT\CurrentVersion\Winlogon')
    try {
        if ($Snapshot.Exists) { $key.SetValue('Shell',$Snapshot.Value,[Enum]::Parse([Microsoft.Win32.RegistryValueKind],$Snapshot.Kind)) }
        else { $key.DeleteValue('Shell',$false) }
    } finally { $key.Dispose() }
}
function Get-PolicyShell {
    if ($script:context.Simulation) { return [string]$script:context.State.PolicyShell }
    foreach ($hive in @([Microsoft.Win32.Registry]::CurrentUser,[Microsoft.Win32.Registry]::LocalMachine)) {
        $key=$hive.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Policies\System')
        try { if($key){$value=[string]$key.GetValue('Shell'); if($value){return $value}} } finally {if($key){$key.Dispose()}}
    }
    return ''
}
function Get-MachineShell {
    if ($script:context.Simulation) { return [string]$script:context.State.MachineShell }
    $key=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('Software\Microsoft\Windows NT\CurrentVersion\Winlogon')
    try { if($key){return [string]$key.GetValue('Shell')} } finally {if($key){$key.Dispose()}}
    return ''
}
function Get-OurShell { return '"'+(Join-Path $script:context.Root 'BootShell.exe')+'"' }
function Test-OurShell($Snapshot) { return $Snapshot.Exists -and ([string]$Snapshot.Value).Trim() -eq (Get-OurShell) }
function Test-PlainExplorer([string]$Value) {
    return $Value.Trim().Trim('"') -ieq 'explorer.exe' -or $Value.Trim().Trim('"') -ieq (Join-Path $env:WINDIR 'explorer.exe')
}
function Get-GuardSnapshot {
    if ($script:context.Simulation) { return $script:context.State.Guard }
    $task=Get-ScheduledTask -TaskName $script:context.TaskName -ErrorAction SilentlyContinue
    [pscustomobject]@{Exists=($null -ne $task); Xml=if($task){Export-ScheduledTask -TaskName $script:context.TaskName}else{''}}
}
function Test-AccountSid([string]$AccountId,[string]$ExpectedSid) {
    if([string]::IsNullOrWhiteSpace($AccountId)){return $false}
    try {
        # Task Scheduler may return an account name even when registered with a SID.
        $identity=if($AccountId -match '^S-\d-'){
            New-Object Security.Principal.SecurityIdentifier($AccountId)
        }else{
            (New-Object Security.Principal.NTAccount($AccountId)).Translate([Security.Principal.SecurityIdentifier])
        }
        return $identity.Value -eq $ExpectedSid
    }catch{return $false}
}
function Register-Guard {
    if ($script:context.Simulation) {
        if($script:context.State.FailGuard){throw 'Simulated task registration failure.'}
        $script:context.State.Guard=[pscustomobject]@{Exists=$true; Xml='BootStudio independent logon guard'}; Save-Simulation; return
    }
    $scriptPath=Join-Path $script:context.Root 'maintenance\Restore-Desktop.ps1'
    if(-not(Test-Path -LiteralPath $scriptPath)){throw 'Desktop recovery script is missing.'}
    $psExe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $action=New-ScheduledTaskAction -Execute $psExe -Argument ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+$scriptPath+'"')
    $trigger=New-ScheduledTaskTrigger -AtLogOn -User $script:context.Sid
    $trigger.Delay='PT60S'
    $principal=New-ScheduledTaskPrincipal -UserId $script:context.Sid -LogonType Interactive -RunLevel Limited
    $settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 2)
    Register-ScheduledTask -TaskName $script:context.TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    $task=Get-ScheduledTask -TaskName $script:context.TaskName
    if($task.State -eq 'Disabled' -or -not(Test-AccountSid ([string]$task.Principal.UserId) $script:context.Sid)){
        throw ('Desktop recovery task verification failed. Task state: '+$task.State+'; principal resolves to expected account: '+(Test-AccountSid ([string]$task.Principal.UserId) $script:context.Sid)+'.')
    }
}
function Restore-Guard($Snapshot) {
    if ($script:context.Simulation) { $script:context.State.Guard=$Snapshot; Save-Simulation; return }
    if($Snapshot.Exists){Register-ScheduledTask -TaskName $script:context.TaskName -Xml $Snapshot.Xml -Force | Out-Null}
    else{Unregister-ScheduledTask -TaskName $script:context.TaskName -Confirm:$false -ErrorAction SilentlyContinue}
}
function Save-JsonAtomic([string]$Path,$Object) {
    $temp=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try {
        $Object | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $temp -Encoding UTF8
        if(Test-Path -LiteralPath $Path){[IO.File]::Replace($temp,$Path,[NullString]::Value)}else{[IO.File]::Move($temp,$Path)}
    } finally {if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp}}
}
function Restore-DefaultAfterLostBackup($Current) {
    if(-not(Test-OurShell $Current)){throw 'Missing backup and Shell is not owned by this installation.'}
    if((Get-PolicyShell) -or -not(Test-PlainExplorer (Get-MachineShell))){throw 'Cannot infer a safe default under custom machine or policy Shell.'}
    # Save the currently observed state before emergency repair; never guess another application's Shell.
    Save-JsonAtomic (Join-Path $script:context.Data 'emergency-before-recovery.json') ([pscustomobject]@{Shell=$Current;Guard=(Get-GuardSnapshot);Time=(Get-Date).ToString('o')})
    Assert-RequestActive
    Set-ShellSnapshot ([pscustomobject]@{Exists=$false;Value=$null;Kind='String'})
    Restore-Guard ([pscustomobject]@{Exists=$false;Xml=''})
    return [pscustomobject]@{Enabled=$false;EmergencyRecovery=$true;Message='Original backup missing or unreadable. Owned animation Shell removed; machine Explorer default retained.'}
}
function Invoke-StartupOperation([ValidateSet('Status','Enable','Disable')][string]$Action) {
    if(-not $script:context){throw 'Context is required.'}
    $current=Get-ShellSnapshot
    $guard=Get-GuardSnapshot
    if($Action -eq 'Status'){
        return [pscustomobject]@{Enabled=(Test-OurShell $current); Recovery=$guard.Exists; Shell=$current; Sid=$script:context.Sid}
    }
    Assert-RequestActive
    $backupPath=Join-Path $script:context.Data 'original-startup.json'
    if($Action -eq 'Enable'){
        if(Get-PolicyShell){throw 'A managed Shell policy exists. No settings were changed.'}
        if(-not(Test-PlainExplorer (Get-MachineShell))){throw 'The machine uses a custom Shell. No settings were changed.'}
        if($current.Exists -and -not(Test-OurShell $current) -and -not(Test-PlainExplorer ([string]$current.Value))){throw 'Another custom user Shell is already configured. No settings were changed.'}
        if(Test-OurShell $current){
            if(-not(Test-Path -LiteralPath $backupPath)){throw 'The original startup backup is missing. Repair is required.'}
        } else {
            # A new activation takes a fresh baseline, including after a previous Disable.
            if(Test-Path -LiteralPath $backupPath){Copy-Item -LiteralPath $backupPath -Destination ($backupPath+'.'+[guid]::NewGuid().ToString('N')+'.previous')}
            Save-JsonAtomic $backupPath ([pscustomobject]@{Sid=$script:context.Sid; Root=$script:context.Root; Shell=$current; Guard=$guard; Captured=(Get-Date).ToString('o')})
        }
        foreach($file in @('BootShell.exe','Start-BootIntro.ps1','boot-intro.config.json','maintenance\Restore-Desktop.ps1')){
            if(-not(Test-Path -LiteralPath (Join-Path $script:context.Root $file))){throw ('Missing required file: '+$file)}
        }
        try{
            Assert-RequestActive
            Register-Guard
            Assert-RequestActive
            Set-ShellSnapshot ([pscustomobject]@{Exists=$true; Value=(Get-OurShell); Kind='String'})
            if(-not(Test-OurShell (Get-ShellSnapshot))){throw 'Shell verification failed.'}
        }catch{
            $failure=$_
            Set-ShellSnapshot $current
            Restore-Guard $guard
            throw $failure
        }
        return [pscustomobject]@{Enabled=$true; Recovery=$true; Message='Startup configured for this account. No reboot was requested.'}
    }
    if(-not(Test-Path -LiteralPath $backupPath)){
        if(Test-OurShell $current){return Restore-DefaultAfterLostBackup $current}
        return [pscustomobject]@{Enabled=$false; Message='Startup was not enabled by this installation.'}
    }
    try{$backup=Get-Content -LiteralPath $backupPath -Raw -Encoding UTF8 | ConvertFrom-Json}catch{return Restore-DefaultAfterLostBackup $current}
    if($backup.Sid -ne $script:context.Sid -or $backup.Root -ne $script:context.Root){throw 'The startup backup belongs to another installation.'}
    if($backup.Shell.Exists -and -not(Test-PlainExplorer ([string]$backup.Shell.Value))){throw 'Unsafe original Shell backup. Keep files and inspect the saved settings.'}
    if(Test-OurShell $current){Set-ShellSnapshot $backup.Shell}
    elseif($current.Exists -ne $backup.Shell.Exists -or [string]$current.Value -ne [string]$backup.Shell.Value){throw 'Shell was changed by another application. Automatic uninstall has been stopped.'}
    $restored=Get-ShellSnapshot
    if($restored.Exists -ne $backup.Shell.Exists -or [string]$restored.Value -ne [string]$backup.Shell.Value){throw 'Startup restore verification failed.'}
    Restore-Guard $backup.Guard
    return [pscustomobject]@{Enabled=$false; Message='Original startup restored. The uninstaller may now remove application data.'}
}
Export-ModuleMember -Function Initialize-Context,Invoke-StartupOperation,Save-JsonAtomic,Set-RequestGuard
