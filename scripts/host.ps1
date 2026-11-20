param(
    [ValidateSet('Codex','WorkBuddy')][string]$App,
    [string]$AppPath,
    [string]$StatusFile,
    [string]$ControlFile,
    [int]$ChromePid,
    [string]$ProfilePath,
    [switch]$LaunchOnly,
    [switch]$CheckOnly
)
$ErrorActionPreference='Stop'
$hiddenTools=@()
. (Join-Path $PSScriptRoot 'apps.ps1')
function Write-Status($Status) {
    if ($StatusFile) { [IO.File]::WriteAllText($StatusFile,($Status | ConvertTo-Json -Compress),(New-Object Text.UTF8Encoding($false))) }
}
try {
    $target=Get-AppTarget $App $AppPath
    if ($CheckOnly) { @{app=$App;found=$true;kind=$target.Kind} | ConvertTo-Json -Compress; exit 0 }
    Add-Type -AssemblyName Accessibility
    Add-Type -Path (Join-Path $PSScriptRoot 'Native.cs') -ReferencedAssemblies @('Accessibility','System','System.Core')
    [AppBootNative]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null
    Start-TargetApp $target
    if ($LaunchOnly) { exit 0 }
    $codexConnection=$null
    if($App -eq 'Codex') {
        try {
            $state=Get-Content (Join-Path $env:LOCALAPPDATA 'CodexDreamSkin\state.json') -Raw -Encoding UTF8 | ConvertFrom-Json
            $owners=@(Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort $state.port -State Listen -ErrorAction Stop | Select-Object -ExpandProperty OwningProcess -Unique)
            if($owners.Count -eq 1 -and (Get-Process -Id $owners[0]).Path -ieq $target.Exe -and $state.codexExe -ieq $target.Exe) {
                $codexConnection=@{port=[int]$state.port;browserId=$state.browserId}
            }
        }catch{}
    }
    $chrome=Get-Process -Id $ChromePid -ErrorAction Stop
    $command=(Get-CimInstance Win32_Process -Filter ('ProcessId='+$ChromePid)).CommandLine
    if ($chrome.ProcessName -ne 'chrome' -or -not $ProfilePath -or -not $command.Contains($ProfilePath)) { throw 'Unverified splash process.' }
    $consecutive=0;$ready=$false;$splash=[IntPtr]::Zero;$lastRect='';$mainWindow=[IntPtr]::Zero;$screenKey=''
    while (Test-Path -LiteralPath $ControlFile) {
        $chrome.Refresh()
        if ($chrome.HasExited) { break }
        $window=Get-TargetWindow $target
        $status=@{app=$App;ready=$false;failed=$false}
        if ($window -ne [IntPtr]::Zero) {
            $screen=[AppBootNative]::ScreenBounds($window)
            $nextScreenKey="$($screen.Left),$($screen.Top),$($screen.Right),$($screen.Bottom)"
            if ($window -ne $mainWindow -or $nextScreenKey -ne $screenKey) {
                [AppBootNative]::Fullscreen($window)
                $hiddenTools=@([AppBootNative]::HideTools($window))
                Start-Sleep -Milliseconds 120
                $mainWindow=$window;$screenKey=$nextScreenKey
            }
            if ([AppBootNative]::IsIconic($window)) { [AppBootNative]::Restore($window) }
            $rect=New-Object AppBootNative+Rect
            $rect=[AppBootNative]::ScreenBounds($window)
            if ($rect.Right-$rect.Left -gt 200) {
                $status.window=$window.ToInt64();$status.x=$rect.Left;$status.y=$rect.Top
                $status.width=$rect.Right-$rect.Left;$status.height=$rect.Bottom-$rect.Top
                if($codexConnection){$status.codexConnection=$codexConnection}
                if ($splash -eq [IntPtr]::Zero) { $splash=[AppBootNative]::Find([uint32]$ChromePid) }
                $key="$($status.x),$($status.y),$($status.width),$($status.height)"
                if ($splash -ne [IntPtr]::Zero -and $key -ne $lastRect) {
                    [AppBootNative]::Cover($splash,$rect) | Out-Null
                    $lastRect=$key
                }
                if (-not $ready) {
                    if ([AppBootNative]::PageReady($window)) { $consecutive++ } else { $consecutive=0 }
                    if ($consecutive -ge 2) { $ready=$true }
                }
                $status.ready=$ready
            }
        }
        Write-Status $status
        Start-Sleep -Milliseconds 250
    }
    $window=Get-TargetWindow $target
    if ($window -eq [IntPtr]::Zero) {Start-TargetApp $target;$window=Get-TargetWindow $target}
    if ($window -ne [IntPtr]::Zero) {
        $activated=[AppBootNative]::Activate($window)
        Write-Status @{app=$App;ready=$ready;failed=$false;handoffVisible=[AppBootNative]::Visible($window);handoffFocused=$activated}
    }
} catch {
    Write-Status @{app=$App;ready=$false;failed=$true;error=$_.Exception.Message}
    Write-Error $_.Exception.Message
    exit 1
} finally {
    foreach($tool in $hiddenTools){if([AppBootNative]::IsWindow($tool)){[AppBootNative]::ShowWindowAsync($tool,4) | Out-Null}}
}
