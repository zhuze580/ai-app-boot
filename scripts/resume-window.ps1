function Resume-AppBootWindow($Target,[int]$TimeoutMilliseconds=8000) {
    $window=Get-TargetWindow $Target
    if($window -ne [IntPtr]::Zero){[AppBootNative]::Restore($window);return $window}
    $name=[IO.Path]::GetFileNameWithoutExtension($Target.Exe)
    # Do not expose a hidden Chromium HWND with ShowWindow alone: doing so can
    # show its last frame while the app still considers the renderer hidden.
    $themeRoot=Join-Path $env:LOCALAPPDATA 'CodexDreamSkin'
    $state=$null
    if($Target.App -eq 'Codex') {
        try{$state=Get-Content (Join-Path $themeRoot 'state.json') -Raw -Encoding UTF8|ConvertFrom-Json}catch{}
    }
    if($state -and $state.codexExe -ieq $Target.Exe -and $state.profilePath -and (Test-Path -LiteralPath $state.profilePath)) {
        . (Join-Path $themeRoot 'engine\scripts\common-windows.ps1')
        $codex=Get-DreamSkinCodexInstallFromState -State $state
        if(-not $codex -or $codex.Executable -ine $Target.Exe){throw '后台 Codex 身份已变化，未唤起其他应用。'}
        $saved=[Environment]::GetEnvironmentVariable('CODEX_ELECTRON_USER_DATA_PATH','Process')
        try {
            $env:CODEX_ELECTRON_USER_DATA_PATH=$state.profilePath
            # Direct single-instance activation retains the existing session;
            # Store package activation can rewrite flags into a protocol route.
            Start-DreamSkinCodexDirect -Codex $codex -Arguments @('--remote-debugging-address=127.0.0.1',('--remote-debugging-port='+$state.port),('--user-data-dir='+$state.profilePath),'--force-renderer-accessibility') | Out-Null
        }finally{[Environment]::SetEnvironmentVariable('CODEX_ELECTRON_USER_DATA_PATH',$saved,'Process')}
    } else {
        Start-Process -FilePath $Target.Exe -ArgumentList '--force-renderer-accessibility' | Out-Null
    }
    $deadline=[DateTime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
    do {
        $window=Get-TargetWindow $Target
        if($window -ne [IntPtr]::Zero){[AppBootNative]::Restore($window);return $window}
        Start-Sleep -Milliseconds 100
    }while([DateTime]::UtcNow -lt $deadline)
    throw '后台进程仍在，但主窗口尚未恢复。请稍后再次点击启动入口。'
}
