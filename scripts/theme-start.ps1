function Invoke-AppBootThemeStart([string]$ScriptPath,[hashtable]$Options=@{}) {
    # Wait for an existing DreamSkin install/tray/recovery operation.
    $parameters=(Get-Command $ScriptPath -ErrorAction Stop).Parameters
    $effective=@{};foreach($key in $Options.Keys){$effective[$key]=$Options[$key]}
    if($parameters.ContainsKey('OperationLockTimeoutMilliseconds')){$effective.OperationLockTimeoutMilliseconds=30000}
    & $ScriptPath @effective | Out-Null
}

function Start-AppBootThemeSession([string]$ThemeRoot,[switch]$AllowRestart,[string]$ExpectedExe) {
    . (Join-Path $ThemeRoot 'engine\scripts\common-windows.ps1')
    $lock=Enter-DreamSkinOperationLock -TimeoutMilliseconds 30000
    try {
        $codex=Get-DreamSkinCodexInstall
        if($ExpectedExe -and $codex.Executable -ine $ExpectedExe){throw '所选 Codex 路径与已验证安装不一致，未重启应用。'}
        $file=Join-Path $ThemeRoot 'state.json'
        $previous=$null;try{$previous=Get-Content $file -Raw -Encoding UTF8|ConvertFrom-Json}catch{}
        $port=9335
        if($previous.codexExe -ieq $codex.Executable -and $previous.port -ge 1024 -and $previous.port -le 65535){$port=[int]$previous.port}
        $identity=Get-DreamSkinVerifiedCdpIdentity -Port $port -Codex $codex
        $running=@(Get-DreamSkinCodexProcesses -Codex $codex)
        if(-not $identity -and $running.Count -gt 0) {
            if(-not $AllowRestart){throw '当前 Codex 缺少壁纸连接。请保存工作并完全退出 Codex，再从动画入口打开。'}
            Stop-DreamSkinCodex -Codex $codex -AllowForce
        }
        $profile=Join-Path $ThemeRoot 'cdp-profile'
        if($previous.profilePath -and (Test-Path -LiteralPath $previous.profilePath)){$profile=$previous.profilePath}
        if(-not $identity) {
            $port=Select-DreamSkinPort -PreferredPort $port
            $arguments=@('--remote-debugging-address=127.0.0.1',('--remote-debugging-port='+$port),('--user-data-dir='+$profile),'--force-renderer-accessibility')
            $saved=[Environment]::GetEnvironmentVariable('CODEX_ELECTRON_USER_DATA_PATH','Process')
            try {
                $env:CODEX_ELECTRON_USER_DATA_PATH=$profile
                Start-DreamSkinCodexForDebugging -Codex $codex -Port $port -Arguments $arguments | Out-Null
            }finally{[Environment]::SetEnvironmentVariable('CODEX_ELECTRON_USER_DATA_PATH',$saved,'Process')}
            $deadline=[DateTime]::UtcNow.AddSeconds(30)
            do {$identity=Get-DreamSkinVerifiedCdpIdentity -Port $port -Codex $codex;if($identity){break};Start-Sleep -Milliseconds 200}while([DateTime]::UtcNow -lt $deadline)
            if(-not $identity){throw '未能建立 Codex 壁纸连接；已保留应用窗口，请查看启动记录。'}
        }
        if($previous.browserId -ceq $identity.BrowserId -and $previous.codexExe -ieq $codex.Executable){return}
        $state=@{schemaVersion=3;platform='windows';port=$port;browserId=$identity.BrowserId;codexExe=$codex.Executable;codexPackageRoot=$codex.PackageRoot;codexPackageFullName=$codex.PackageFullName;codexPackageFamilyName=$codex.PackageFamilyName;codexVersion=$codex.Version;profilePath=$profile;themeDir=(Join-Path $ThemeRoot 'active-theme');pauseFile=(Join-Path $ThemeRoot 'paused');injectorPid=0}
        Write-DreamSkinState -Path $file -State $state
    }finally{Exit-DreamSkinOperationLock -Mutex $lock}
}
