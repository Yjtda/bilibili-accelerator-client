$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$packageDir = Join-Path $repoRoot 'dist\Bilibili Accelerator Client'
$stagingDir = Join-Path $repoRoot 'dist\installer-staging'
$outputDir = Join-Path $repoRoot 'dist\installers'
$iexpress = Join-Path $env:SystemRoot 'System32\iexpress.exe'

if (-not (Test-Path -LiteralPath (Join-Path $packageDir 'Bilibili Accelerator Client.exe'))) {
    throw 'Build the Windows package before building installers.'
}

New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

$files = @(
    @{ Source = (Join-Path $packageDir 'Bilibili Accelerator Client.exe'); Name = 'Bilibili Accelerator Client.exe' },
    @{ Source = (Join-Path $packageDir 'bilibili-accelerator.user.js'); Name = 'bilibili-accelerator.user.js' },
    @{ Source = (Join-Path $repoRoot 'THIRD_PARTY_NOTICES.md'); Name = 'THIRD_PARTY_NOTICES.md' },
    @{ Source = (Join-Path $repoRoot 'LICENSE'); Name = 'LICENSE' },
    @{ Source = (Join-Path $repoRoot 'installer\setup.ps1'); Name = 'setup.ps1' },
    @{ Source = (Join-Path $repoRoot 'installer\run-full.cmd'); Name = 'run-full.cmd' },
    @{ Source = (Join-Path $repoRoot 'installer\run-upgrade.cmd'); Name = 'run-upgrade.cmd' }
)
foreach ($file in $files) {
    Copy-Item -LiteralPath $file.Source -Destination (Join-Path $stagingDir $file.Name) -Force
}

function New-IExpressPackage {
    param([string]$Mode, [string]$FriendlyName, [string]$OutputName, [string]$Command)

    $outputPath = Join-Path $outputDir $OutputName
    $sedPath = Join-Path $stagingDir "$Mode.sed"
    if (Test-Path -LiteralPath $outputPath) {
        Remove-Item -LiteralPath $outputPath -Force
    }
    $fileLines = for ($index = 0; $index -lt $files.Count; $index++) {
        "FILE$index=`"$($files[$index].Name)`""
    }
    $sourceLines = for ($index = 0; $index -lt $files.Count; $index++) {
        "%FILE$index%="
    }
    $sed = @"
[Version]
Class=IEXPRESS
SEDVersion=3
[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=1
HideExtractAnimation=0
UseLongFileName=1
InsideCompressed=0
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=
DisplayLicense=
FinishMessage=
TargetName=$outputPath
FriendlyName=$FriendlyName
AppLaunched=$Command
PostInstallCmd=<None>
AdminQuietInstCmd=
UserQuietInstCmd=
SourceFiles=SourceFiles
[Strings]
$($fileLines -join "`r`n")
[SourceFiles]
SourceFiles0=$stagingDir\
[SourceFiles0]
$($sourceLines -join "`r`n")
"@
    Set-Content -LiteralPath $sedPath -Value $sed -Encoding Default
    & $iexpress /N /Q $sedPath
    $deadline = (Get-Date).AddMinutes(3)
    while (-not (Test-Path -LiteralPath $outputPath) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
    }
    if (-not (Test-Path -LiteralPath $outputPath)) {
        throw "IExpress did not create $outputPath"
    }
}

New-IExpressPackage -Mode 'full' -FriendlyName 'Bilibili Accelerator Full Installer' -OutputName 'Bilibili-Accelerator-Full-Installer.exe' -Command 'run-full.cmd'
New-IExpressPackage -Mode 'upgrade' -FriendlyName 'Bilibili Accelerator Upgrade Installer' -OutputName 'Bilibili-Accelerator-Upgrade-Installer.exe' -Command 'run-upgrade.cmd'

Get-ChildItem -LiteralPath $outputDir -Filter '*.exe' | Select-Object FullName, Length
