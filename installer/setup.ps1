param(
    [ValidateSet('full', 'upgrade')]
    [string]$Mode = 'upgrade'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms

trap {
    $message = "Bilibili Accelerator 安装失败。`r`n`r`n$($_.Exception.Message)"
    [System.Windows.Forms.MessageBox]::Show(
        $message,
        'Bilibili Accelerator 安装程序',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    exit 1
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"{0}"' -f $PSCommandPath),
        '-Mode', $Mode
    )
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -Verb RunAs -Wait -PassThru
    exit $process.ExitCode
}

$sourceDir = $PSScriptRoot
$installDir = Join-Path $env:LOCALAPPDATA 'Programs\Bilibili Accelerator Client'
$backupRoot = Join-Path $env:PROGRAMDATA 'Bilibili Accelerator Client\Shortcut Backups'
$acceleratorExe = Join-Path $installDir 'Bilibili Accelerator Client.exe'
$officialDownload = 'https://dl.hdslb.com/mobile/fixed/bili_win/bili_win-install.exe'

# Close previous launcher/client instances so the installed executable and
# shortcuts cannot remain bound to an older build after an upgrade.
Get-Process -Name 'Bilibili Accelerator Client' -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
Get-Process -Name '哔哩哔哩' -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500

New-Item -ItemType Directory -Path $installDir -Force | Out-Null
New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null

$payload = @(
    'Bilibili Accelerator Client.exe',
    'bilibili-accelerator.user.js',
    'THIRD_PARTY_NOTICES.md',
    'LICENSE'
)
foreach ($name in $payload) {
    $source = Join-Path $sourceDir $name
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Missing installer payload: $name"
    }
    Copy-Item -LiteralPath $source -Destination (Join-Path $installDir $name) -Force
}

if ($Mode -eq 'full') {
    $downloadPath = Join-Path $env:TEMP ('bilibili-official-{0}.exe' -f [Guid]::NewGuid().ToString('N'))
    try {
        Write-Host '正在从哔哩哔哩官方服务器下载 Windows 客户端……'
        Invoke-WebRequest -Uri $officialDownload -OutFile $downloadPath -UseBasicParsing
        $signature = Get-AuthenticodeSignature -LiteralPath $downloadPath
        if ($signature.Status -ne 'Valid') {
            throw "Official Bilibili installer signature is not valid: $($signature.Status)"
        }
        Write-Host '正在启动哔哩哔哩官方安装程序……'
        $official = Start-Process -FilePath $downloadPath -Wait -PassThru
        if ($official.ExitCode -ne 0) {
            throw "Official Bilibili installer exited with code $($official.ExitCode)"
        }
    } finally {
        if (Test-Path -LiteralPath $downloadPath) {
            Remove-Item -LiteralPath $downloadPath -Force
        }
    }
}

$knownBilibiliPaths = @(
    (Join-Path $env:ProgramFiles 'bilibili\哔哩哔哩.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'bilibili\哔哩哔哩.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\bilibili\哔哩哔哩.exe')
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

if ($knownBilibiliPaths.Count -eq 0) {
    throw '未检测到哔哩哔哩桌面客户端。请先完成官方客户端安装，再重新运行本安装包。'
}

$shortcutRoots = @(
    [Environment]::GetFolderPath('Desktop'),
    [Environment]::GetFolderPath('CommonDesktopDirectory'),
    [Environment]::GetFolderPath('StartMenu'),
    [Environment]::GetFolderPath('CommonStartMenu')
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDir = Join-Path $backupRoot $timestamp
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

$counter = 0
foreach ($root in $shortcutRoots) {
    Get-ChildItem -LiteralPath $root -Filter '*.lnk' -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.BaseName -like '*哔哩哔哩*' -or $_.BaseName -like '*bilibili*' } |
        ForEach-Object {
            $counter++
            $backupName = '{0:D3}-{1}' -f $counter, $_.Name
            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $backupDir $backupName) -Force
            Remove-Item -LiteralPath $_.FullName -Force
        }
}

$iconPath = Join-Path $env:ProgramFiles 'bilibili\uninstallerIcon.ico'
if (-not (Test-Path -LiteralPath $iconPath)) {
    $iconPath = $knownBilibiliPaths[0]
}

$shell = New-Object -ComObject WScript.Shell
$destinations = @(
    (Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) '哔哩哔哩.lnk'),
    (Join-Path ([Environment]::GetFolderPath('CommonPrograms')) '哔哩哔哩.lnk')
)
foreach ($destination in $destinations) {
    $parent = Split-Path -Parent $destination
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $shortcut = $shell.CreateShortcut($destination)
    $shortcut.TargetPath = $acceleratorExe
    $shortcut.WorkingDirectory = $installDir
    $shortcut.Description = '哔哩哔哩（Bilibili Accelerator）'
    $shortcut.IconLocation = "$iconPath,0"
    $shortcut.Save()
}

Write-Host ''
Write-Host '安装完成。桌面和开始菜单中的“哔哩哔哩”现在会自动启动 Accelerator。'
Write-Host "原快捷方式备份：$backupDir"

[System.Windows.Forms.MessageBox]::Show(
    "安装完成。`r`n`r`n桌面和开始菜单中的哔哩哔哩现在会自动启动 Accelerator。`r`n原快捷方式备份：$backupDir",
    'Bilibili Accelerator 安装程序',
    [System.Windows.Forms.MessageBoxButtons]::OK,
    [System.Windows.Forms.MessageBoxIcon]::Information
) | Out-Null
