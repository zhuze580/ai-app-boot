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
    if ($LaunchOnly) {Start-TargetApp $target; exit 0 }
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
    $splash=[IntPtr]::Zero;$splashDeadline=[DateTime]::UtcNow.AddSeconds(4)
    do {$splash=[AppBootNative]::Find([uint32]$ChromePid);if($splash -ne [IntPtr]::Zero){break};Start-Sleep -Milliseconds 50}while([DateTime]::UtcNow -lt $splashDeadline)
    if($splash -eq [IntPtr]::Zero){throw 'Splash native window not ready'}
    [AppBootNative]::Cover($splash,[AppBootNative]::ScreenBounds($splash)) | Out-Null
    $startupWarning=$null
    try {Start-TargetApp $target} catch {
        $visibleWindow=Get-TargetWindow $target
        if($visibleWindow -eq [IntPtr]::Zero){throw}
        $startupWarning='theme-recovery-incomplete'
    }
    $consecutive=0;$ready=$false;$lastRect='';$mainWindow=[IntPtr]::Zero;$screenKey=''
    $themeRequired=$App -eq 'Codex' -and (Test-Path (Join-Path $env:LOCALAPPDATA 'CodexDreamSkin\engine\scripts\injector.mjs'))
    $nextConnectionCheck=[DateTime]::MinValue;$themeWatcherAlive=$false;$nextResume=[DateTime]::UtcNow.AddSeconds(2)
    while (Test-Path -LiteralPath $ControlFile) {
        $chrome.Refresh()
        if ($chrome.HasExited) { break }
        $window=Get-TargetWindow $target
        if($window -eq [IntPtr]::Zero){
            $ready=$false;$consecutive=0
            Write-Status @{app=$App;ready=$false;failed=$false;recoveringWindow=$true}
        }
        if($window -eq [IntPtr]::Zero -and [DateTime]::UtcNow -ge $nextResume) {
            $nextResume=[DateTime]::UtcNow.AddSeconds(10)
            try {
                . (Join-Path $PSScriptRoot 'resume-window.ps1')
                $window=Resume-AppBootWindow $target
            }catch{}
        }
        if($window -eq [IntPtr]::Zero){$ready=$false;$consecutive=0}
        $status=@{app=$App;ready=$false;failed=$false}
        if($startupWarning){$status.warning=$startupWarning}
        if($themeRequired){
            $status.themeRequired=$false
            if([DateTime]::UtcNow -ge $nextConnectionCheck){
                $nextConnectionCheck=[DateTime]::UtcNow.AddSeconds(2)
                $codexConnection=$null;$themeWatcherAlive=$false
                try {
                    $state=Get-Content (Join-Path $env:LOCALAPPDATA 'CodexDreamSkin\state.json') -Raw -Encoding UTF8 | ConvertFrom-Json
                    $owners=@(Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort $state.port -State Listen -ErrorAction Stop|Select-Object -ExpandProperty OwningProcess -Unique)
                    if($owners.Count -eq 1 -and (Get-Process -Id $owners[0]).Path -ieq $target.Exe -and $state.codexExe -ieq $target.Exe){
                        $version=Invoke-RestMethod ('http://127.0.0.1:'+$state.port+'/json/version') -TimeoutSec 2
                        $expected='^ws://127\.0\.0\.1:'+$state.port+'/devtools/browser/([a-fA-F0-9-]{36})$'
                        if($version.webSocketDebuggerUrl -match $expected){
                            $browserId=$Matches[1];$codexConnection=@{port=[int]$state.port;browserId=$browserId}
                            $watcher=Get-CimInstance Win32_Process -Filter ('ProcessId='+[int]$state.injectorPid) -ErrorAction SilentlyContinue
                            $themeWatcherAlive=$watcher -and $watcher.Name -eq 'node.exe' -and $watcher.CommandLine -like '*injector.mjs*' -and $watcher.CommandLine -like ('*'+$browserId+'*')
                        }
                    }
                }catch{}
            }
            if($codexConnection){
                $status.codexConnection=$codexConnection;$status.themeWatcherAlive=[bool]$themeWatcherAlive
                $themeRoot=Join-Path $env:LOCALAPPDATA 'CodexDreamSkin'
                if((Test-Path (Join-Path $state.themeDir 'theme.json')) -and -not (Test-Path (Join-Path $themeRoot 'paused'))){$status.themeRequired=$true}
            }
        }
        if ($window -ne [IntPtr]::Zero) {
            $screen=[AppBootNative]::ScreenBounds($window)
            $nextScreenKey="$($screen.Left),$($screen.Top),$($screen.Right),$($screen.Bottom)"
            if ($window -ne $mainWindow -or $nextScreenKey -ne $screenKey) {
                if($window -ne $mainWindow){$ready=$false;$consecutive=0}
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
        # Z-order only: never toggle frame styles while decoding video.
        [AppBootNative]::SetWindowPos($splash,[IntPtr](-1),0,0,0,0,0x0013) | Out-Null
        Write-Status $status
        Start-Sleep -Milliseconds 250
    }
    $window=Get-TargetWindow $target
    if ($window -eq [IntPtr]::Zero) {
        . (Join-Path $PSScriptRoot 'resume-window.ps1')
        $window=Resume-AppBootWindow $target
    }
    if ($window -ne [IntPtr]::Zero) {
        [AppBootNative]::Fullscreen($window)
        $activationDeadline=[DateTime]::UtcNow.AddSeconds(3)
        do {$activated=[AppBootNative]::Activate($window);if($activated){break};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $activationDeadline)
        Write-Status @{app=$App;ready=$ready;failed=$false;handoffVisible=[AppBootNative]::Visible($window);handoffFocused=$activated}
    }
} catch {
    Write-Status @{app=$App;ready=$false;failed=$true;error=$_.Exception.Message}
    Write-Error $_.Exception.Message
    exit 1
} finally {
    foreach($tool in $hiddenTools){if([AppBootNative]::IsWindow($tool)){[AppBootNative]::ShowWindowAsync($tool,4) | Out-Null}}
}
