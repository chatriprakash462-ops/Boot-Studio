#requires -version 5.1
$ErrorActionPreference = 'Stop'
$sessionId = [Diagnostics.Process]::GetCurrentProcess().SessionId
if (@(Get-Process explorer -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $sessionId }).Count -eq 0) {
    Start-Process -FilePath (Join-Path $env:WINDIR 'explorer.exe') -WindowStyle Hidden
}
