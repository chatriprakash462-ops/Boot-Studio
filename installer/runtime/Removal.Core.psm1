Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Assert-RemovalTree([string]$Root,[string]$ExpectedRoot) {
 $path=[IO.Path]::GetFullPath($Root).TrimEnd('\')
 $expected=[IO.Path]::GetFullPath($ExpectedRoot).TrimEnd('\')
 if($path -ne $expected -or $path -eq [IO.Path]::GetPathRoot($path).TrimEnd('\')){throw 'Unexpected removal root.'}
 $parent=$path
 while($parent){
  if((Test-Path -LiteralPath $parent) -and ((Get-Item -LiteralPath $parent -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Removal refuses directory links.'}
  $parent=Split-Path -Parent $parent
 }
 if(-not(Test-Path -LiteralPath $path -PathType Container)){throw 'Installation directory is missing.'}
 $pending=New-Object 'Collections.Generic.Stack[string]';$pending.Push($path)
 while($pending.Count){
  foreach($item in Get-ChildItem -LiteralPath $pending.Pop() -Force){
   if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw ('Removal refuses links: '+$item.FullName)}
   if(-not $item.FullName.StartsWith($path+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Removal escaped installation.'}
   if($item.PSIsContainer){$pending.Push($item.FullName)}
  }
 }
 return $path
}
function Remove-InstallationTree([string]$Root,[string]$ExpectedRoot) {
 $path=Assert-RemovalTree $Root $ExpectedRoot
 Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
 if(Test-Path -LiteralPath $path){throw 'Installation directory could not be completely removed.'}
}
function Assert-RemovalFilesUnlocked([string]$Root,[string]$ExpectedRoot) {
 $path=Assert-RemovalTree $Root $ExpectedRoot
 foreach($file in Get-ChildItem -LiteralPath $path -File -Recurse -Force){
  # Read-only copies are removable with -Force. Read access with no sharing detects locks.
  $handle=[IO.File]::Open($file.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
  $handle.Dispose()
 }
}
Export-ModuleMember -Function Assert-RemovalTree,Remove-InstallationTree,Assert-RemovalFilesUnlocked
