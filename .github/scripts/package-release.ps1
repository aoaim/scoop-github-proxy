param(
    [Parameter(Mandatory = $true)]
    [string]$Version,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '..\..')
)

Set-StrictMode -Version Latest

$repoRoot = [System.IO.Path]::GetFullPath($RepositoryRoot)
$outputRoot = [System.IO.Path]::GetFullPath($OutputDirectory)
$stageRoot = Join-Path $outputRoot 'stage'
$packageRoot = Join-Path $stageRoot 'scoop-github-proxy'
$assetName = "scoop-github-proxy-$Version.zip"
$assetPath = Join-Path $outputRoot $assetName

if (Test-Path $stageRoot) {
    Remove-Item $stageRoot -Recurse -Force
}
if (Test-Path $assetPath) {
    Remove-Item $assetPath -Force
}

New-Item -Path $packageRoot -ItemType Directory -Force | Out-Null

$includePaths = @(
    '.github',
    'bucket',
    'lib',
    'scripts',
    'LICENSE',
    'README.md'
)

foreach ($item in $includePaths) {
    $source = Join-Path $repoRoot $item
    $destination = Join-Path $packageRoot $item
    Copy-Item $source $destination -Recurse -Force
}

Compress-Archive -Path (Join-Path $stageRoot '*') -DestinationPath $assetPath -Force

$hash = (Get-FileHash -Path $assetPath -Algorithm SHA256).Hash.ToLower()

"ASSET_PATH=$assetPath"
"ASSET_NAME=$assetName"
"ASSET_SHA256=$hash"
