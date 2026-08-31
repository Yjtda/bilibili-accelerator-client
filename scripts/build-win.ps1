$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$outputDir = Join-Path $repoRoot 'dist\Bilibili Accelerator Client'
$outputExe = Join-Path $outputDir 'Bilibili Accelerator Client.exe'
$blobPath = Join-Path $repoRoot 'sea-prep.blob'
$postjectCli = Join-Path $repoRoot 'node_modules\postject\dist\cli.js'
$userscript = Join-Path $repoRoot 'vendor\bilibili-accelerator.user.js'
$nodeExe = if ($env:BILIBILI_ACCELERATOR_NODE) {
    $env:BILIBILI_ACCELERATOR_NODE
} else {
    (Get-Command node -ErrorAction Stop).Source
}

New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
Push-Location $repoRoot
try {
    & $nodeExe --experimental-sea-config sea-config.json
    Copy-Item -LiteralPath $nodeExe -Destination $outputExe -Force
    & $nodeExe (Join-Path $PSScriptRoot 'strip-signature.mjs') $outputExe
    & $nodeExe $postjectCli $outputExe NODE_SEA_BLOB $blobPath --sentinel-fuse NODE_SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2
    Copy-Item -LiteralPath $userscript -Destination (Join-Path $outputDir 'bilibili-accelerator.user.js') -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot 'THIRD_PARTY_NOTICES.md') -Destination $outputDir -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot 'LICENSE') -Destination $outputDir -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot 'licenses') -Destination (Join-Path $outputDir 'licenses') -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'install-user-shortcut.ps1') -Destination $outputDir -Force
} finally {
    Pop-Location
}
