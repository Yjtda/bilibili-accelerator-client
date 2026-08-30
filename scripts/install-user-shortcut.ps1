$ErrorActionPreference = 'Stop'

$packageDir = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$accelerator = Join-Path $packageDir 'Bilibili Accelerator Client.exe'
$desktop = [Environment]::GetFolderPath('Desktop')
$temporaryShortcut = Join-Path $desktop 'Bilibili Accelerator.lnk'
$finalShortcut = Join-Path $desktop '哔哩哔哩.lnk'
$bilibiliIcon = 'C:\Program Files\bilibili\uninstallerIcon.ico'

if (-not (Test-Path -LiteralPath $accelerator)) {
    throw "Accelerator executable not found: $accelerator"
}

$ws = New-Object -ComObject WScript.Shell
$shortcut = $ws.CreateShortcut($temporaryShortcut)
$shortcut.TargetPath = "$env:SystemRoot\System32\cmd.exe"
$shortcut.Arguments = "/d /c start `"`" `"$accelerator`""
$shortcut.WorkingDirectory = $packageDir
$shortcut.Description = 'Launch Bilibili with Bilibili Accelerator'
if (Test-Path -LiteralPath $bilibiliIcon) {
    $shortcut.IconLocation = "$bilibiliIcon,0"
}
$shortcut.Save()
Move-Item -LiteralPath $temporaryShortcut -Destination $finalShortcut -Force

Write-Output "Installed shortcut: $finalShortcut"
