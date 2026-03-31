param(
    [Parameter(Mandatory = $true)]
    [string]$Version,

    [Parameter(Mandatory = $true)]
    [string]$Sha256,

    [Parameter(Mandatory = $true)]
    [string]$Repository,

    [string]$ManifestPath = (Join-Path $PSScriptRoot '..\..\bucket\scoop-github-proxy.json')
)

Set-StrictMode -Version Latest

$manifestFile = [System.IO.Path]::GetFullPath($ManifestPath)
$manifest = Get-Content $manifestFile -Raw | ConvertFrom-Json

$manifest.version = $Version
$manifest.homepage = "https://github.com/$Repository"
$manifest.url = "https://github.com/$Repository/releases/download/v$Version/scoop-github-proxy-$Version.zip"
$manifest.hash = $Sha256
$manifest.extract_dir = 'scoop-github-proxy'

$json = $manifest | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($manifestFile, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
