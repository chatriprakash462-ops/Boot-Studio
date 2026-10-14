function Test-PlayerSurfaceReady([bool]$ShellMode,[IntPtr]$WindowHandle,[IntPtr]$ForegroundHandle,[bool]$IsVisible,[bool]$InputDesktopActive=$false,[bool]$NativeSurfaceVisible=$false) {
    # Fail closed until Windows displays the desktop that owns this window.
    # Shell windows need not own keyboard focus, but must be on screen.
    return $InputDesktopActive -and $NativeSurfaceVisible -and $IsVisible -and $WindowHandle -ne [IntPtr]::Zero -and ($ShellMode -or $WindowHandle -eq $ForegroundHandle)
}
Export-ModuleMember -Function Test-PlayerSurfaceReady
