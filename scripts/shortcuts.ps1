param([ValidateSet('Codex','WorkBuddy')][string]$App,[switch]$Remove)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$shell=New-Object -ComObject WScript.Shell
$linkPath=Join-Path ([Environment]::GetFolderPath('Desktop')) ($App+' - AI App Boot.lnk')
$wscript=Join-Path $env:WINDIR 'System32\wscript.exe'
$arguments='"'+(Join-Path $root ($App+'.vbs'))+'"'
if (Test-Path -LiteralPath $linkPath) {
    $current=$shell.CreateShortcut($linkPath)
    if ($current.TargetPath -ine $wscript -or $current.Arguments -cne $arguments) {
        throw 'The shortcut name is used by another project. Keep it or rename it before installing.'
    }
    if ($Remove) {Remove-Item -LiteralPath $linkPath; Write-Output 'Removed owned shortcut.'; exit 0}
} elseif ($Remove) {exit 0}
$link=$shell.CreateShortcut($linkPath)
$link.TargetPath=$wscript;$link.Arguments=$arguments;$link.WorkingDirectory=$root
$link.Description='Play startup animation while '+$App+' opens'
$link.IconLocation=(Join-Path $env:WINDIR 'System32\shell32.dll')+',13'
$link.Save()
Write-Output ('Created desktop shortcut: '+$App+' - AI App Boot')
