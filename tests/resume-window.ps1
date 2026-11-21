$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\scripts\resume-window.ps1')
Add-Type @'
using System;
public static class AppBootNative {
 public static void Restore(IntPtr h){}
 public static IntPtr FindHidden(uint p){return IntPtr.Zero;}
}
'@
$script:reads=0;$script:launches=0
function Get-TargetWindow {param($Target)$script:reads++;if($script:reads -ge 4){return [IntPtr]99};return [IntPtr]::Zero}
function Get-Process {param($Name,$ErrorAction)return @([pscustomobject]@{Id=12;Path='C:\Apps\WorkBuddy.exe'})}
function Start-Process {param($FilePath,$ArgumentList)$script:launches++;if($FilePath -ne 'C:\Apps\WorkBuddy.exe'){throw 'Wrong activation target'}}
$window=Resume-AppBootWindow @{App='WorkBuddy';Exe='C:\Apps\WorkBuddy.exe'} -TimeoutMilliseconds 1000
if($window -ne [IntPtr]99 -or $script:launches -ne 1){throw 'Destroyed window must activate once and wait for replacement'}
$script:launches=0
$window=Resume-AppBootWindow @{App='WorkBuddy';Exe='C:\Apps\WorkBuddy.exe'}
if($window -ne [IntPtr]99 -or $script:launches -ne 0){throw 'Existing window must not activate a second instance'}
'PASS: waits for a replacement window and reuses existing session'
