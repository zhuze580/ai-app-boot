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
    $chrome=Get-Process -Id $ChromePid -ErrorAction Stop
    $command=(Get-CimInstance Win32_Process -Filter ('ProcessId='+$ChromePid)).CommandLine
    if ($chrome.ProcessName -ne 'chrome' -or -not $ProfilePath -or -not $command.Contains($ProfilePath)) { throw 'Unverified splash process.' }
    $consecutive=0;$ready=$false;$splash=[IntPtr]::Zero;$lastRect=''
    while (Test-Path -LiteralPath $ControlFile) {
        $chrome.Refresh()
        if ($chrome.HasExited) { break }
        $window=Get-TargetWindow $target
        $status=@{app=$App;ready=$false;failed=$false}
        if ($window -ne [IntPtr]::Zero) {
            if ([AppBootNative]::IsIconic($window)) { [AppBootNative]::ShowWindowAsync($window,4) | Out-Null }
            $rect=New-Object AppBootNative+Rect
            if ([AppBootNative]::GetWindowRect($window,[ref]$rect) -and $rect.Right-$rect.Left -gt 200) {
                $status.window=$window.ToInt64();$status.x=$rect.Left;$status.y=$rect.Top
                $status.width=$rect.Right-$rect.Left;$status.height=$rect.Bottom-$rect.Top
                if ($splash -eq [IntPtr]::Zero) { $splash=[AppBootNative]::Find([uint32]$ChromePid) }
                $key="$($status.x),$($status.y),$($status.width),$($status.height)"
                if ($splash -ne [IntPtr]::Zero -and $key -ne $lastRect) {
                    $style=[AppBootNative]::GetWindowLong($splash,-16)
                    [AppBootNative]::SetWindowLong($splash,-16,($style -band (-bnot 0x00C80000))) | Out-Null
                    [AppBootNative]::SetWindowPos($splash,[IntPtr](-1),$status.x,$status.y,$status.width,$status.height,0x0030) | Out-Null
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
    if ($window -ne [IntPtr]::Zero) { [AppBootNative]::SetForegroundWindow($window) | Out-Null }
} catch {
    Write-Status @{app=$App;ready=$false;failed=$true;error=$_.Exception.Message}
    Write-Error $_.Exception.Message
    exit 1
}
