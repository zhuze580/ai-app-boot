function Get-AppTarget([string]$App, [string]$AppPath) {
    $names = if ($App -eq 'Codex') { @('Codex.exe','ChatGPT.exe') } else { @('WorkBuddy.exe','WorkBuddyAI.exe') }
    if ($AppPath) {
        $expanded = [Environment]::ExpandEnvironmentVariables($AppPath)
        if (-not (Test-Path -LiteralPath $expanded -PathType Leaf) -or [IO.Path]::GetFileName($expanded) -notin $names) {
            throw ('AppPath must point to the installed ' + $App + ' executable.')
        }
        return @{ App=$App; Exe=(Get-Item -LiteralPath $expanded).FullName; Kind='exe' }
    }
    $package = if ($App -eq 'Codex') { Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue | Select-Object -First 1 }
    if ($package) {
        $manifest = Get-AppxPackageManifest -Package $package -ErrorAction Stop
        $application = @($manifest.Package.Applications.Application)[0]
        $exe = Join-Path $package.InstallLocation ([string]$application.Executable)
        if (Test-Path -LiteralPath $exe) {
            return @{App=$App; Exe=$exe; Kind='store'; Aumid=($package.PackageFamilyName+'!'+$application.Id)}
        }
    }
    foreach ($name in $names) {
        foreach ($running in @(Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($name)) -ErrorAction SilentlyContinue)) {
            try {
                if ($running.Path -and (Test-Path -LiteralPath $running.Path)) {
                    if ($App -eq 'Codex' -and $running.Path -notmatch '(?i)codex') { continue }
                    return @{App=$App; Exe=$running.Path; Kind='exe'}
                }
            } catch { }
        }
    }
    $shell = New-Object -ComObject WScript.Shell
    foreach ($menu in @([Environment]::GetFolderPath('StartMenu'),[Environment]::GetFolderPath('CommonStartMenu'))) {
        if (-not $menu) { continue }
        foreach ($link in @(Get-ChildItem -LiteralPath $menu -Filter ('*'+$App+'*.lnk') -Recurse -File -ErrorAction SilentlyContinue)) {
            $target = $shell.CreateShortcut($link.FullName).TargetPath
            if ($target -and [IO.Path]::GetFileName($target) -in $names -and (Test-Path -LiteralPath $target)) {
                return @{App=$App; Exe=$target; Kind='exe'}
            }
        }
    }
    $candidates = [Collections.Generic.List[string]]::new()
    foreach ($registryRoot in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
        foreach ($entry in @(Get-ItemProperty -Path $registryRoot -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match ('(?i)^'+$App+'(\s|$)') })) {
            if ($entry.InstallLocation) { foreach ($name in $names) { $candidates.Add((Join-Path $entry.InstallLocation $name)) } }
            if ($entry.DisplayIcon) { $candidates.Add(($entry.DisplayIcon -replace ',\d+$','').Trim('"')) }
        }
    }
    foreach ($base in @($env:LOCALAPPDATA,$env:PROGRAMFILES,${env:PROGRAMFILES(X86)})) {
        if ($base) { foreach ($name in $names) {
            $candidates.Add((Join-Path $base ($App+'\'+$name)))
            $candidates.Add((Join-Path $base ('Programs\'+$App+'\'+$name)))
        } }
    }
    foreach ($candidate in $candidates) {
        if ([IO.Path]::GetFileName($candidate) -in $names -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return @{App=$App; Exe=$candidate; Kind='exe'}
        }
    }
    throw ('Could not find '+$App+'. Install it first or set appPath in config.local.json.')
}

function Get-TargetWindow($Target) {
    $name = [IO.Path]::GetFileNameWithoutExtension($Target.Exe)
    foreach ($process in @(Get-Process -Name $name -ErrorAction SilentlyContinue)) {
        try {
            if ($process.Path -ine $Target.Exe) { continue }
            $handle = [AppBootNative]::FindMain([uint32]$process.Id)
            if ($handle -ne [IntPtr]::Zero) { return $handle }
        } catch { }
    }
    return [IntPtr]::Zero
}

function Start-TargetApp($Target) {
    $window = Get-TargetWindow $Target
    if ($window -ne [IntPtr]::Zero) {
        [AppBootNative]::Restore($window)
        return
    }
    # Electron often hides its main window on close while its process stays alive.
    foreach ($running in @(Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($Target.Exe)) -ErrorAction SilentlyContinue)) {
        if ($running.Path -ine $Target.Exe) {continue}
        $hidden=[AppBootNative]::FindHidden([uint32]$running.Id)
        if ($hidden -ne [IntPtr]::Zero) {
            [AppBootNative]::Restore($hidden)
            if ([AppBootNative]::Visible($hidden)) {return}
        }
    }
    $dreamRoot = Join-Path $env:LOCALAPPDATA 'CodexDreamSkin'
    $dreamStart = Join-Path $dreamRoot 'engine\scripts\start-dream-skin.ps1'
    if ($Target.App -eq 'Codex' -and (Test-Path -LiteralPath $dreamStart)) {
        $state = $null
        try { $state=Get-Content (Join-Path $dreamRoot 'state.json') -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
        if ($state -and $state.codexExe -ieq $Target.Exe) {
            $common=Join-Path $dreamRoot 'engine\scripts\common-windows.ps1'
            . $common
            $codex=Get-DreamSkinCodexInstallFromState -State $state
            if ($codex -and $state.profilePath -and (Test-Path -LiteralPath $state.profilePath)) {
                Assert-DreamSkinCodexDirectLaunchTarget -Codex $codex
                $previous=[Environment]::GetEnvironmentVariable('CODEX_ELECTRON_USER_DATA_PATH','Process')
                try {
                    $env:CODEX_ELECTRON_USER_DATA_PATH=$state.profilePath
                    $arguments=ConvertTo-DreamSkinArgumentLine -Arguments @('--remote-debugging-address=127.0.0.1',('--remote-debugging-port='+$state.port),('--user-data-dir='+$state.profilePath),'--force-renderer-accessibility')
                    Invoke-CommandInDesktopPackage -PackageFamilyName $codex.PackageFamilyName -AppId $codex.ApplicationId -Command $codex.Executable -Args $arguments -PreventBreakaway -ErrorAction Stop | Out-Null
                    return
                } finally { [Environment]::SetEnvironmentVariable('CODEX_ELECTRON_USER_DATA_PATH',$previous,'Process') }
            }
        }
    }
    if ($Target.Kind -eq 'store') {
        $identity=$Target.Aumid -split '!',2
        Invoke-CommandInDesktopPackage -PackageFamilyName $identity[0] -AppId $identity[1] -Command $Target.Exe -Args '--force-renderer-accessibility' -PreventBreakaway -ErrorAction Stop | Out-Null
    } else {
        Start-Process -FilePath $Target.Exe -ArgumentList '--force-renderer-accessibility' | Out-Null
    }
}
