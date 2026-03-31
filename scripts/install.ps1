Set-StrictMode -Version Latest

. "$PSScriptRoot\..\lib\config.ps1"
. "$PSScriptRoot\..\lib\patch.ps1"
. "$PSScriptRoot\..\lib\scoop-config.ps1"

$baseDirectory = Join-Path $PSScriptRoot '..\lib'
Initialize-SgpConfig -BaseDirectory $baseDirectory | Out-Null
$originalAria2Enabled = Get-SgpAria2EnabledOrNull
Set-SgpOriginalAria2Enabled -Value $originalAria2Enabled -BaseDirectory $baseDirectory
$patched = Install-SgpPatch -BaseDirectory $baseDirectory
Set-SgpAria2Enabled -Enabled $false

if ($patched) {
    Write-Host 'scoop-github-proxy: installed patch into Scoop download pipeline.' -ForegroundColor Green
} else {
    Write-Host 'scoop-github-proxy: patch already present.' -ForegroundColor Yellow
}

Write-Host 'scoop-github-proxy: set Scoop config aria2-enabled=false.' -ForegroundColor Yellow
