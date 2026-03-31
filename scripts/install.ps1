Set-StrictMode -Version Latest

. "$PSScriptRoot\..\lib\config.ps1"
. "$PSScriptRoot\..\lib\patch.ps1"
. "$PSScriptRoot\..\lib\scoop-config.ps1"

Initialize-SgpConfig -BaseDirectory (Join-Path $PSScriptRoot '..\lib') | Out-Null
$patched = Install-SgpPatch -BaseDirectory (Join-Path $PSScriptRoot '..\lib')
Set-SgpAria2Enabled -Enabled $false

if ($patched) {
    Write-Host 'scoop-github-proxy: installed patch into Scoop download pipeline.' -ForegroundColor Green
} else {
    Write-Host 'scoop-github-proxy: patch already present.' -ForegroundColor Yellow
}

Write-Host 'scoop-github-proxy: set Scoop config aria2-enabled=false.' -ForegroundColor Yellow
