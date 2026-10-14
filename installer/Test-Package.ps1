#requires -version 5.1
param([string]$Setup=(Join-Path $PSScriptRoot 'dist\BootStudio-Setup-0.2.5-preview.2.exe'))
$ErrorActionPreference='Stop'
$testRoot=Join-Path $PSScriptRoot ('test-results\'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$root=Join-Path $testRoot 'clean-install'
$process=Start-Process -FilePath $Setup -ArgumentList ('--extract-test "'+$root+'"') -Wait -PassThru -WindowStyle Hidden
if($process.ExitCode -ne 0){throw 'Isolated package extraction failed.'}
$manifest=Get-Content -LiteralPath (Join-Path $root 'install-manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($entry in $manifest.Files){if((Get-FileHash -LiteralPath (Join-Path $root $entry.Path)).Hash -ne $entry.Hash){throw 'Package hash mismatch.'}}
$config=Get-Content -LiteralPath (Join-Path $root 'boot-intro.config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if($config.wallpaperEngineExe -or $config.launchWallpaperEngineIfMissing -or $config.hideTaskbar -or $config.hideDesktopIcons){throw 'Unexpected machine-specific or desktop settings.'}
$mediaFiles=@(Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object {$_.Extension -in '.mp4','.wmv','.mov','.m4v'})
if($mediaFiles.Count -ne 1 -or $mediaFiles[0].Name -ne 'sample.mp4' -or (Get-FileHash $mediaFiles[0].FullName).Hash -ne (Get-FileHash (Join-Path $PSScriptRoot 'assets\sample.mp4')).Hash){throw 'Unexpected media was packaged.'}
if(-not(Test-Path (Join-Path $root 'Uninstall.exe'))){throw 'Standalone uninstaller missing.'}
$errors=@()
Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object {$_.Extension -in '.ps1','.psm1'} | ForEach-Object {
    $tokens=$null;$parseErrors=$null
    [Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$tokens,[ref]$parseErrors)|Out-Null
    $errors+=@($parseErrors)
}
if($errors.Count){throw ($errors | Out-String)}
Import-Module (Join-Path $root 'maintenance\Startup.Core.psm1') -Force
function New-State([bool]$Exists=$false,[string]$Value='',[bool]$FailGuard=$false){
    [pscustomobject]@{Shell=[pscustomobject]@{Exists=$Exists;Value=$Value;Kind='String'};Guard=[pscustomobject]@{Exists=$false;Xml=''};PolicyShell='';MachineShell='explorer.exe';FailGuard=$FailGuard}
}
function Write-State($State){$State|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $root 'simulation.json') -Encoding UTF8;Initialize-Context $root -Simulation}
function Read-State {Get-Content -LiteralPath (Join-Path $root 'simulation.json') -Raw -Encoding UTF8|ConvertFrom-Json}
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Must-Fail([scriptblock]$Operation,[string]$Message){$failed=$false;try{& $Operation|Out-Null}catch{$failed=$true};Assert $failed $Message}
$passed=New-Object Collections.Generic.List[string]
$passed.Add('PASS: clean extraction; package hashes; no personal videos; no Wallpaper Engine dependency; PowerShell syntax')
$accountChecks=& (Get-Module Startup.Core) {
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    try{
        $sid=$identity.User.Value
        if(-not(Test-AccountSid $sid $sid)){throw 'Canonical task principal SID was rejected.'}
        if(-not(Test-AccountSid $identity.Name $sid)){throw 'Equivalent task principal account name was rejected.'}
        $foreign=if($sid -eq 'S-1-5-18'){'S-1-5-19'}else{'S-1-5-18'}
        if(Test-AccountSid $foreign $sid){throw 'A different task principal was accepted.'}
        if(Test-AccountSid '' $sid){throw 'An empty task principal was accepted.'}
        if(Test-AccountSid 'S-INVALID' $sid){throw 'An invalid task principal was accepted.'}
        'PASS: real Windows account name and SID resolve to the same principal; different, empty and invalid identities rejected'
    }finally{$identity.Dispose()}
}
$passed.Add($accountChecks)
Import-Module (Join-Path $root 'maintenance\Player.WindowState.psm1') -Force
Assert (Test-PlayerSurfaceReady $true ([IntPtr]42) ([IntPtr]99) $true $true $true) 'Displayed shell overlay waited indefinitely for foreground focus.'
Assert (-not (Test-PlayerSurfaceReady $false ([IntPtr]42) ([IntPtr]99) $true $true $true)) 'Manual overlay played behind another foreground window.'
Assert (Test-PlayerSurfaceReady $false ([IntPtr]42) ([IntPtr]42) $true $true $true) 'Focused manual overlay could not play.'
Assert (-not (Test-PlayerSurfaceReady $true ([IntPtr]0) ([IntPtr]99) $true $true $true)) 'Shell playback started without a native window.'
Assert (-not (Test-PlayerSurfaceReady $true ([IntPtr]42) ([IntPtr]99) $false $true $true)) 'Shell playback started before the overlay was visible.'
Assert (-not (Test-PlayerSurfaceReady $true ([IntPtr]42) ([IntPtr]99) $true $false $true)) 'Video played while Winlogon still owned the visible desktop.'
Assert (-not (Test-PlayerSurfaceReady $true ([IntPtr]42) ([IntPtr]99) $true $true $false)) 'Hidden/cloaked native window was accepted.'
Assert (-not (Test-PlayerSurfaceReady $true ([IntPtr]42) ([IntPtr]99) $true)) 'Missing desktop probe result allowed playback.'
Add-Type -Path (Join-Path $root 'maintenance\Player.Desktop.dll')
$probe=[BootStudio.Player.DesktopProbe]::Read([IntPtr]::Zero)
Assert (-not $probe.InputDesktopActive -and -not $probe.SurfaceVisible) 'Missing real window reported ready.'
$passed.Add('PASS: Winlogon/unknown desktop and hidden native surfaces block playback; active desktop permits Shell; manual mode still requires focus; native probe loads')
Write-State (New-State)
Invoke-StartupOperation Enable|Out-Null
$state=Read-State
Assert ($state.Shell.Exists -and $state.Guard.Exists) 'Activation did not configure both simulated Shell and guard.'
Invoke-StartupOperation Enable|Out-Null
Invoke-StartupOperation Disable|Out-Null
$state=Read-State
Assert (-not $state.Shell.Exists -and -not $state.Guard.Exists) 'Absent Shell was not restored exactly.'
$passed.Add('PASS: fresh enable; idempotent enable; restore absent user Shell and absent guard')
Write-State (New-State $true 'explorer.exe')
Invoke-StartupOperation Enable|Out-Null
Invoke-StartupOperation Disable|Out-Null
Assert ((Read-State).Shell.Value -eq 'explorer.exe') 'Explicit explorer Shell was not restored.'
$passed.Add('PASS: exact restoration of explicit explorer Shell')
Write-State (New-State $true '"C:\OtherProduct\CustomShell.exe"')
Must-Fail {Invoke-StartupOperation Enable} 'Custom Shell conflict was not rejected.'
Assert ((Read-State).Shell.Value -eq '"C:\OtherProduct\CustomShell.exe"') 'Existing custom Shell changed.'
$state=New-State;$state.PolicyShell='policy.exe';Write-State $state
Must-Fail {Invoke-StartupOperation Enable} 'Managed policy was not rejected.'
$state=New-State;$state.MachineShell='machine-shell.exe';Write-State $state
Must-Fail {Invoke-StartupOperation Enable} 'Machine Shell conflict was not rejected.'
$passed.Add('PASS: existing custom user Shell; managed policy; custom machine Shell all preserved')
Write-State (New-State $false '' $true)
Must-Fail {Invoke-StartupOperation Enable} 'Recovery-task failure was ignored.'
$state=Read-State
Assert (-not $state.Shell.Exists -and -not $state.Guard.Exists) 'Failed activation did not roll back.'
$passed.Add('PASS: recovery task failure leaves original startup unchanged')
Write-State (New-State)
Invoke-StartupOperation Enable|Out-Null
$state=Read-State;$state.Shell.Value='new-owner-shell.exe';Write-State $state
Must-Fail {Invoke-StartupOperation Disable} 'External Shell replacement was overwritten.'
Assert ((Read-State).Shell.Value -eq 'new-owner-shell.exe') 'External Shell replacement changed during disable.'
$passed.Add('PASS: external Shell changes stop automatic restoration')
Write-State (New-State)
Set-RequestGuard -DeadlineUtc ([DateTime]::UtcNow.AddMinutes(-1).ToString('o')) -CancelPath ''
Must-Fail {Invoke-StartupOperation Enable} 'Expired startup request was accepted.'
Assert (-not (Read-State).Shell.Exists -and -not (Read-State).Guard.Exists) 'Expired request changed startup.'
Write-State (New-State)
$cancelPath=Join-Path $testRoot 'cancelled-request'
Set-Content -LiteralPath $cancelPath -Value 'cancelled'
Set-RequestGuard -DeadlineUtc ([DateTime]::UtcNow.AddMinutes(1).ToString('o')) -CancelPath $cancelPath
Must-Fail {Invoke-StartupOperation Enable} 'Cancelled startup request was accepted.'
Assert (-not (Read-State).Shell.Exists -and -not (Read-State).Guard.Exists) 'Cancelled request changed startup.'
$passed.Add('PASS: expired and cancelled requests cannot change Shell or recovery task')
Write-State (New-State)
Invoke-StartupOperation Enable|Out-Null
Remove-Item -LiteralPath (Join-Path $root 'boot-studio-data\installation\original-startup.json')
$emergency=Invoke-StartupOperation Disable
Assert ($emergency.EmergencyRecovery -and -not (Read-State).Shell.Exists -and -not (Read-State).Guard.Exists) 'Missing backup did not safely restore machine Explorer.'
Write-State (New-State)
Invoke-StartupOperation Enable|Out-Null
Set-Content -LiteralPath (Join-Path $root 'boot-studio-data\installation\original-startup.json') -Value '{invalid-json'
Invoke-StartupOperation Disable|Out-Null
Assert (-not (Read-State).Shell.Exists) 'Corrupt backup left our Shell configured.'
Write-State (New-State)
Invoke-StartupOperation Enable|Out-Null
$state=Read-State;$state.Shell.Value='foreign.exe';Write-State $state
Remove-Item -LiteralPath (Join-Path $root 'boot-studio-data\installation\original-startup.json')
Invoke-StartupOperation Disable|Out-Null
Assert ((Read-State).Shell.Value -eq 'foreign.exe') 'Emergency fallback changed a foreign Shell.'
$passed.Add('PASS: lost/corrupt backup restores only our own Shell to the machine Explorer default; foreign Shell remains untouched')
Import-Module (Join-Path $root 'maintenance\Removal.Core.psm1') -Force
$removeRoot=Join-Path $testRoot 'removal-fixture';$outside=Join-Path $testRoot 'original-video'
New-Item -ItemType Directory -Path (Join-Path $removeRoot 'media'),$outside -Force|Out-Null
Set-Content (Join-Path $outside 'keep.txt') 'original remains'
Set-Content (Join-Path $removeRoot 'media\copied.mp4') 'imported copy'
Set-Content (Join-Path $removeRoot 'config.json') '{}'
$readOnlyMedia=Join-Path $removeRoot 'media\copied.mp4'
[IO.File]::SetAttributes($readOnlyMedia,[IO.FileAttributes]::ReadOnly)
Assert-RemovalFilesUnlocked $removeRoot $removeRoot
$lockedFile=[IO.File]::Open($readOnlyMedia,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
try{Must-Fail {Assert-RemovalFilesUnlocked $removeRoot $removeRoot} 'Locked media was not detected.'}finally{$lockedFile.Dispose()}
Must-Fail {Remove-InstallationTree $outside $removeRoot} 'Wrong removal root accepted.'
$junction=Join-Path $removeRoot 'linked'
New-Item -ItemType Junction -Path $junction -Target $outside | Out-Null
Must-Fail {Remove-InstallationTree $removeRoot $removeRoot} 'Directory junction was followed.'
[IO.Directory]::Delete($junction)
Remove-InstallationTree $removeRoot $removeRoot
Assert (-not(Test-Path $removeRoot) -and (Test-Path (Join-Path $outside 'keep.txt'))) 'Full cleanup deleted source data or left the install directory.'
$passed.Add('PASS: read-only media accepted and removed; locked media rejected; complete directory cleanup; wrong root and junction blocked; external original media preserved')
$diagnostics=Join-Path $testRoot 'diagnostics-tests.txt'
$process=Start-Process -FilePath $Setup -ArgumentList ('--diagnostics-test "'+$diagnostics+'"') -Wait -PassThru -WindowStyle Hidden
if($process.ExitCode -ne 0 -or -not(Test-Path -LiteralPath $diagnostics)){throw 'Failure message diagnostics test failed.'}
$passed.Add((Get-Content -LiteralPath $diagnostics -Raw -Encoding UTF8).Trim())
$foreign=Get-Content -LiteralPath (Join-Path $root 'install-manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
$foreign.OwnerSid='OTHER-USER';$foreign|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $root 'install-manifest.json') -Encoding UTF8
Must-Fail {Initialize-Context $root -Simulation} 'Account ownership mismatch was ignored.'
$passed.Add('PASS: different-account installation rejected')
$passed.Add('NOT TESTED: real registry/task mutation, logoff/reboot, multi-computer install/uninstall, digital signing')
$passed | Set-Content -LiteralPath (Join-Path $testRoot 'results.txt') -Encoding UTF8
$passed
Write-Output ('Results: '+$testRoot)
