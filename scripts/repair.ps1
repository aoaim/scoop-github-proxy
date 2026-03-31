Set-StrictMode -Version Latest

. "$PSScriptRoot\..\lib\config.ps1"
. "$PSScriptRoot\..\lib\patch.ps1"
. "$PSScriptRoot\..\lib\scoop-config.ps1"

Assert-SgpGitAvailable
Initialize-SgpConfig -BaseDirectory (Join-Path $PSScriptRoot '..\lib') | Out-Null
Set-SgpAria2Enabled -Enabled $false
if (Test-SgpPatchPresent) {
    Write-Host 'scoop-github-proxy: patch already present, nothing to repair.' -ForegroundColor Yellow
    Write-Host 'scoop-github-proxy: ensured Scoop config aria2-enabled=false.' -ForegroundColor Yellow
    exit 0
}

$patched = Install-SgpPatch -BaseDirectory (Join-Path $PSScriptRoot '..\lib')
if ($patched) {
    Write-Host 'scoop-github-proxy: repair completed.' -ForegroundColor Green
}
Write-Host 'scoop-github-proxy: ensured Scoop config aria2-enabled=false.' -ForegroundColor Yellow
