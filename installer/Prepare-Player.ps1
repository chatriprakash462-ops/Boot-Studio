# Build-time adaptation; never overwrite the user's working player.
function ConvertTo-PackagePlayer([string]$Source) {
    $Source=$Source.Replace("`r`n","`n").Replace("`n","`r`n")
    function Replace-PlayerSection([string]$Text,[string]$Old,[string]$New) {
        if(-not $Text.Contains($Old)){throw 'The source player changed; review the package adaptation.'}
        return $Text.Replace($Old,$New)
    }
    $Source=Replace-PlayerSection $Source "if (Get-Process -Name 'explorer' -ErrorAction SilentlyContinue) {" "if (Get-Process -Name 'explorer' -ErrorAction SilentlyContinue | Where-Object { `$_.SessionId -eq [Diagnostics.Process]::GetCurrentProcess().SessionId }) {"
    $logger=@'
$scriptRoot = Split-Path -Parent $PSCommandPath
function Write-PlayerTrace([string]$Message) {
    try {
        [IO.File]::AppendAllText((Join-Path $scriptRoot 'boot-player.log'),[DateTime]::UtcNow.ToString('o')+' '+$Message+[Environment]::NewLine)
    } catch { }
}
Write-PlayerTrace 'Script started.'
Import-Module (Join-Path $scriptRoot 'maintenance\Player.WindowState.psm1') -Force
Add-Type -Path (Join-Path $scriptRoot 'maintenance\Player.Desktop.dll')
$script:lastSurfaceTrace = ''
'@
    $Source=Replace-PlayerSection $Source '$scriptRoot = Split-Path -Parent $PSCommandPath' $logger
    $Source=Replace-PlayerSection $Source 'function Get-CurrentLogonSessionKey {' "Write-PlayerTrace 'Native helpers loaded.'`r`nfunction Get-CurrentLogonSessionKey {"
    $Source=Replace-PlayerSection $Source '$script:isClosing = $true' "Write-PlayerTrace ('Closing overlay: '+`$Reason)`r`n        `$script:isClosing = `$true"
    $Source=Replace-PlayerSection $Source '$media.Add_MediaOpened({' "`$media.Add_MediaOpened({`r`n        Write-PlayerTrace 'Media opened.'"
    $Source=Replace-PlayerSection $Source '$script:mediaStarted = $true' "Write-PlayerTrace 'Playback started.'`r`n        `$script:mediaStarted = `$true"
    $Source=Replace-PlayerSection $Source '$window.Add_ContentRendered({' "`$window.Add_ContentRendered({`r`n        Write-PlayerTrace 'Overlay rendered.'"
    $surfaceCheck=@'
$surface = [BootStudio.Player.DesktopProbe]::Read($windowHandle)
        $surfaceTrace = $surface.ToString()
        if ($surfaceTrace -ne $script:lastSurfaceTrace) {
            Write-PlayerTrace ('Surface: '+$surfaceTrace)
            $script:lastSurfaceTrace = $surfaceTrace
        }
        if (-not (Test-PlayerSurfaceReady -ShellMode ([bool]$ShellMode) -WindowHandle $windowHandle -ForegroundHandle $surface.Foreground -IsVisible $window.IsVisible -InputDesktopActive $surface.InputDesktopActive -NativeSurfaceVisible $surface.SurfaceVisible)) {
'@
    $Source=Replace-PlayerSection $Source 'if ($windowHandle -eq [IntPtr]::Zero -or [BootIntro.NativeMethods]::GetForegroundWindow() -ne $windowHandle) {' $surfaceCheck
    $Source=Replace-PlayerSection $Source '$window.ShowDialog() | Out-Null' "Write-PlayerTrace 'Opening overlay.'`r`n    `$window.ShowDialog() | Out-Null`r`n    Write-PlayerTrace 'Overlay closed.'"
    # Stop alone keeps the media source open with Manual UnloadedBehavior.
    # Close releases the decoder before the standalone PowerShell process exits.
    $Source=Replace-PlayerSection $Source "    if (`$media -ne `$null) {`r`n        `$media.Stop()`r`n    }" "    if (`$media -ne `$null) {`r`n        `$media.Stop()`r`n        `$media.Close()`r`n        Write-PlayerTrace 'Media resources closed.'`r`n    }"
    $Source += "`r`nWrite-PlayerTrace 'Player cleanup complete.'`r`n[System.Windows.Threading.Dispatcher]::CurrentDispatcher.InvokeShutdown()`r`n"
    return $Source
}
