$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\scripts\theme-start.ps1')
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('appboot-theme-session-'+[guid]::NewGuid().ToString('N'))
$engine=Join-Path $fixture 'engine\scripts'
New-Item -ItemType Directory -Path $engine -Force | Out-Null
$fake=@'
function Enter-DreamSkinOperationLock {param($TimeoutMilliseconds)if($TimeoutMilliseconds -ne 30000){throw 'No bounded operation wait'};return 'test-lock'}
function Exit-DreamSkinOperationLock {param($Mutex)$global:AppBootTestReleased=$true}
function Get-DreamSkinCodexInstall {return @{Executable='C:\Apps\Codex\ChatGPT.exe'}}
function Get-DreamSkinVerifiedCdpIdentity {param($Port,$Codex)if($global:AppBootTestHealthy){return @{BrowserId='11111111-1111-1111-1111-111111111111'}};return $null}
function Get-DreamSkinCodexProcesses {param($Codex)return @(@{ProcessId=123})}
function Stop-DreamSkinCodex {param($Codex,[switch]$AllowForce)throw 'Unauthorized process termination'}
function Write-DreamSkinState {param($Path,$State)$global:AppBootTestWritten=$State}
'@
[IO.File]::WriteAllText((Join-Path $engine 'common-windows.ps1'),$fake)
$global:AppBootTestHealthy=$false;$global:AppBootTestReleased=$false
$caught=$false
try {Start-AppBootThemeSession $fixture -ExpectedExe 'C:\Apps\Codex\ChatGPT.exe'}catch{$caught=$true}
if(-not $caught -or -not $global:AppBootTestReleased){throw 'Live app without permission must be preserved and lock released'}
$global:AppBootTestHealthy=$true;$global:AppBootTestReleased=$false
Start-AppBootThemeSession $fixture -ExpectedExe 'C:\Apps\Codex\ChatGPT.exe'
if(-not $global:AppBootTestWritten -or -not $global:AppBootTestReleased){throw 'Healthy app must reuse connection and release lock'}
if($global:AppBootTestWritten.profilePath -ne (Join-Path $fixture 'cdp-profile')){throw 'Missing state must use the persistent managed theme profile'}
$caught=$false
try {Start-AppBootThemeSession $fixture -ExpectedExe 'C:\Other\ChatGPT.exe'}catch{$caught=$true}
if(-not $caught){throw 'Mismatched executable must not launch'}
'PASS: session lock wait, no unauthorized restart, healthy reuse and executable identity'
