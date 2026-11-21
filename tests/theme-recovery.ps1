$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\scripts\apps.ps1')
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('codex-theme-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $testRoot 'active-theme') -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $testRoot 'active-theme\theme.json'),'{}')
[IO.File]::WriteAllText((Join-Path $testRoot 'state.json'),'{"port":9335,"browserId":"11111111-1111-1111-1111-111111111111","codexExe":"C:\\Codex\\ChatGPT.exe"}')
function Get-NetTCPConnection {throw 'No wallpaper endpoint after update'}
$target=@{App='Codex';Exe='C:\Codex\ChatGPT.exe'}
if(-not (Test-CodexThemeRecoveryNeeded $target $testRoot)){throw 'An update without a wallpaper endpoint must request recovery'}
function Get-NetTCPConnection {[pscustomobject]@{OwningProcess=1234}}
function Get-Process {[pscustomobject]@{Path='C:\Codex\ChatGPT.exe'}}
function Invoke-RestMethod {[pscustomobject]@{webSocketDebuggerUrl='ws://127.0.0.1:9335/devtools/browser/11111111-1111-1111-1111-111111111111'}}
if(Test-CodexThemeRecoveryNeeded $target $testRoot){throw 'A verified working connection must not restart'}
[IO.File]::WriteAllText((Join-Path $testRoot 'paused'),'')
if(Test-CodexThemeRecoveryNeeded $target $testRoot){throw 'An intentionally paused theme must remain paused'}
if(Test-CodexThemeRecoveryNeeded @{App='WorkBuddy'} $testRoot){throw 'WorkBuddy must not request Codex wallpaper recovery'}
Write-Output 'PASS: update recovery, healthy connection, paused theme and WorkBuddy'
