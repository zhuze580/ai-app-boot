$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\scripts\theme-start.ps1')
function Fake-Theme {
    param([int]$OperationLockTimeoutMilliseconds=0,[switch]$PromptRestart)
    if($OperationLockTimeoutMilliseconds -ne 30000){throw 'Concurrent operation would fail immediately'}
    if(-not $PromptRestart){throw 'Restart consent flag was lost'}
    $script:called=$true
}
$script:called=$false
Invoke-AppBootThemeStart Fake-Theme @{PromptRestart=$true}
if(-not $script:called){throw 'Theme startup never ran'}
function Legacy-Theme {param([switch]$PromptRestart)if(-not $PromptRestart){throw 'Legacy options lost'}}
Invoke-AppBootThemeStart Legacy-Theme @{PromptRestart=$true}
'PASS: theme operation waits, keeps restart consent and supports legacy engines'
