[CmdletBinding()]
param(
    [ValidateSet('Codex','WorkBuddy')][string]$App='Codex',
    [ValidateSet('Start','Preview','Check','Test','Install','Remove')][string]$Action='Start',
    [string]$AppPath,
    [switch]$Muted
)
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
try {
    if ($Action -in @('Install','Remove')) {
        & (Join-Path $root 'scripts\shortcuts.ps1') -App $App -Remove:($Action -eq 'Remove')
        exit 0
    }
    $nodeCommand=Get-Command node.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    $node=if ($nodeCommand) { $nodeCommand.Source } else { Join-Path $env:LOCALAPPDATA 'CodexDreamSkin\engine\runtime\node\node.exe' }
    if (-not (Test-Path -LiteralPath $node)) { throw 'Install Node.js 22 or newer from https://nodejs.org and reopen this launcher.' }
    $major=& $node -p 'parseInt(process.versions.node)'
    if ($LASTEXITCODE -ne 0 -or [int]$major -lt 22) { throw 'Node.js 22 or newer is required.' }
    if ($Action -eq 'Test') {
        Push-Location $root
        try { & $node --test tests/core.test.mjs tests/media.test.mjs tests/theme.test.mjs; exit $LASTEXITCODE } finally { Pop-Location }
    }
    $localPath=Join-Path $root 'config.local.json'
    if (-not $AppPath -and (Test-Path -LiteralPath $localPath)) {
        $settings=Get-Content -LiteralPath $localPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($settings.apps.$App.appPath) { $AppPath=$settings.apps.$App.appPath }
        elseif ($settings.appPath) { $AppPath=$settings.appPath }
    }
    $chrome=@($env:LOCALAPPDATA,$env:PROGRAMFILES,${env:PROGRAMFILES(X86)}) |
        Where-Object { $_ } | ForEach-Object {Join-Path $_ 'Google\Chrome\Application\chrome.exe'} |
        Where-Object {Test-Path -LiteralPath $_ -PathType Leaf} | Select-Object -First 1
    if (-not $chrome -and $Action -ne 'Start') { throw 'Install Google Chrome before running the animation.' }
    if ($Action -eq 'Check') {
        & $node (Join-Path $root 'src\check.mjs') $App
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        $hostArguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $root 'scripts\host.ps1'),'-App',$App,'-CheckOnly')
        if ($AppPath) {$hostArguments+=@('-AppPath',$AppPath)}
        & powershell.exe @hostArguments
        exit $LASTEXITCODE
    }
    $mutex=New-Object Threading.Mutex($false,('Local\AIAppBoot-'+$App))
    $held=$false
    try {
        try {$held=$mutex.WaitOne(0)} catch [Threading.AbandonedMutexException] {$held=$true}
        if (-not $held) { exit 0 }
        $arguments=@((Join-Path $root 'src\boot.mjs'),$App)
        if ($AppPath) {$arguments+=@('--app-path',$AppPath)}
        if ($Action -eq 'Preview') {$arguments+='--preview'}
        if ($Muted) {$arguments+='--muted'}
        & $node @arguments
        if ($LASTEXITCODE -ne 0) {
            $logPath=Join-Path $env:LOCALAPPDATA ('AIAppBoot\last-'+$App.ToLower()+'.json')
            $lastLaunch=$null;try{$lastLaunch=Get-Content -LiteralPath $logPath -Raw -Encoding UTF8|ConvertFrom-Json}catch{}
            if($lastLaunch.failureCode -eq 'theme-busy'){throw '壁纸服务仍在完成另一个启动操作。请等待该操作结束，再点击一次启动入口。'}
            throw ('应用启动未完成，请查看本机诊断记录：'+$logPath)
        }
        exit $LASTEXITCODE
    } finally {
        if ($held) {$mutex.ReleaseMutex()}
        $mutex.Dispose()
    }
} catch {
    if ($Action -in @('Start','Preview')) {
        Add-Type -AssemblyName System.Windows.Forms
        [Windows.Forms.MessageBox]::Show($_.Exception.Message,'AI App Boot') | Out-Null
    }
    Write-Error $_.Exception.Message
    exit 1
}
