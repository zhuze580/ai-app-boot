param([ValidateSet('Codex','WorkBuddy')][string]$App='Codex',[switch]$Delayed)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Add-Type -AssemblyName Accessibility
Add-Type -Path (Join-Path $root 'scripts\Native.cs') -ReferencedAssemblies @('Accessibility','System','System.Core')
[AppBootNative]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null
. (Join-Path $root 'scripts\apps.ps1')
$target=Get-AppTarget $App ''
$initialProcessIds=@(Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($target.Exe)) -ErrorAction SilentlyContinue|Where-Object {$_.Path -ieq $target.Exe}|Select-Object -ExpandProperty Id)
if($env:APP_BOOT_TEST_CLOSE -eq '1') {
    $originalWindow=Get-TargetWindow $target
    if($originalWindow -eq [IntPtr]::Zero){throw 'No original window to close'}
    [AppBootNative]::PostMessage($originalWindow,0x0010,[IntPtr]::Zero,[IntPtr]::Zero) | Out-Null
    Start-Sleep -Seconds 2
    if(-not (Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($target.Exe)) -ErrorAction SilentlyContinue)){throw 'Close exited all processes'}
}
if($env:APP_BOOT_TEST_HIDE -eq '1') {
    $originalWindow=Get-TargetWindow $target
    [AppBootNative]::ShowWindowAsync($originalWindow,0) | Out-Null
    Start-Sleep -Milliseconds 500
}
$originalDelay=[Environment]::GetEnvironmentVariable('APP_BOOT_TEST_READY_DELAY_MS','Process')
try {
    $env:APP_BOOT_TEST_READY_DELAY_MS=if($Delayed){'18000'}else{'0'}
    $start=[DateTime]::UtcNow
    $arguments='-NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $root 'launch.ps1')+'" -App '+$App+' -Muted'
    $helper=Start-Process -FilePath powershell.exe -ArgumentList $arguments -WindowStyle Hidden -PassThru
} finally { [Environment]::SetEnvironmentVariable('APP_BOOT_TEST_READY_DELAY_MS',$originalDelay,'Process') }
$log=Join-Path $env:LOCALAPPDATA ('AIAppBoot\last-'+$App.ToLower()+'.json')
$deadline=[DateTime]::UtcNow.AddSeconds(50)
$geometry=$false;$trace=$null;$closedDuringFilm=$false
$closeAt=5
if($env:APP_BOOT_TEST_CLOSE_AT){$closeAt=[double]$env:APP_BOOT_TEST_CLOSE_AT}
while([DateTime]::UtcNow -lt $deadline) {
    try {
        $trace=Get-Content -LiteralPath $log -Raw -Encoding UTF8 | ConvertFrom-Json
        if([DateTime]::Parse($trace.startedAt).ToUniversalTime() -lt $start.AddSeconds(-1)) {$trace=$null}
        if($trace -and $trace.splashPid -and $trace.window -and -not $geometry) {
            $window=[AppBootNative]::Find([uint32]$trace.splashPid)
            $appWindow=Get-TargetWindow $target
            $s=New-Object AppBootNative+Rect;$a=New-Object AppBootNative+Rect;$origin=New-Object AppBootNative+Point
            if($window -ne [IntPtr]::Zero -and $appWindow -ne [IntPtr]::Zero -and
                [AppBootNative]::GetClientRect($window,[ref]$s) -and [AppBootNative]::ClientToScreen($window,[ref]$origin) -and [AppBootNative]::GetWindowRect($appWindow,[ref]$a)) {
                $geometry=($origin.X -le $a.Left -and $origin.Y -le $a.Top -and
                    $origin.X+$s.Right -ge $a.Right -and $origin.Y+$s.Bottom -ge $a.Bottom)
            }
        }
        if($trace -and $trace.phase -eq 'finished'){break}
        if($trace -and $trace.firstFrameAt -and $env:APP_BOOT_TEST_CLOSE_DURING -eq '1' -and -not $closedDuringFilm -and ([DateTime]::UtcNow-[DateTime]::Parse($trace.firstFrameAt).ToUniversalTime()).TotalSeconds -ge $closeAt){
            $activeWindow=Get-TargetWindow $target
            if($activeWindow -ne [IntPtr]::Zero){[AppBootNative]::PostMessage($activeWindow,0x0010,[IntPtr]::Zero,[IntPtr]::Zero)|Out-Null;$closedDuringFilm=$true}
        }
    } catch { }
    Start-Sleep -Milliseconds 150
}
if(-not $trace -or $trace.reason -ne 'ready-after-film'){throw ($App+': splash failed or timed out')}
$first=[DateTime]::Parse($trace.firstFrameAt).ToUniversalTime()
$requested=[DateTime]::Parse($trace.appLaunchRequestedAt).ToUniversalTime()
if(($requested-$first).TotalMilliseconds -lt 0 -or ($requested-$first).TotalMilliseconds -gt 500){throw 'Application did not start with the video first frame'}
$ended=[DateTime]::Parse($trace.filmEndedAt).ToUniversalTime()
$ready=[DateTime]::Parse($trace.appReadyAt).ToUniversalTime()
$finished=[DateTime]::Parse($trace.finishedAt).ToUniversalTime()
if(($ended-$first).TotalSeconds -lt 13.8){throw 'Video was truncated'}
if($finished -lt $ended -or $finished -lt $ready){throw 'Closed before both conditions'}
if($Delayed -and $ready -le $ended){throw 'Delayed readiness did not hold the last frame'}
if(-not $geometry){throw 'Splash geometry did not match target window'}
$handoffWindow=Get-TargetWindow $target
if($handoffWindow -eq [IntPtr]::Zero -or -not [AppBootNative]::Visible($handoffWindow)){throw 'Application not visible after video'}
if([AppBootNative]::GetForegroundWindow() -ne $handoffWindow){throw 'Application did not receive foreground after video'}
if($env:APP_BOOT_TEST_CLOSE -eq '1' -or $env:APP_BOOT_TEST_CLOSE_DURING -eq '1') {
    $remaining=@(Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($target.Exe)) -ErrorAction SilentlyContinue|Where-Object {$_.Path -ieq $target.Exe -and $_.Id -in $initialProcessIds})
    if($remaining.Count -eq 0){throw 'Background session was restarted instead of restored'}
}
$screen=[AppBootNative]::ScreenBounds($handoffWindow);$bounds=New-Object AppBootNative+Rect
[AppBootNative]::GetWindowRect($handoffWindow,[ref]$bounds) | Out-Null
if($bounds.Left -ne $screen.Left -or $bounds.Top -ne $screen.Top -or $bounds.Right -ne $screen.Right -or $bounds.Bottom -ne $screen.Bottom){throw 'Application did not stay fullscreen after playback'}
[pscustomobject]@{App=$App;Delayed=[bool]$Delayed;ParallelStartMs=($requested-$first).TotalMilliseconds;FullFilm=$true;GeometryMatched=$geometry;ReadySeconds=[Math]::Round(($ready-$first).TotalSeconds,2);FilmSeconds=[Math]::Round(($ended-$first).TotalSeconds,2);Result='PASS'} | ConvertTo-Json -Compress
