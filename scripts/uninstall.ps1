Set-StrictMode -Version Latest

. "$PSScriptRoot\..\lib\config.ps1"
. "$PSScriptRoot\..\lib\patch.ps1"
. "$PSScriptRoot\..\lib\scoop-config.ps1"

$baseDirectory = Join-Path $PSScriptRoot '..\lib'
$config = Get-SgpConfig -BaseDirectory $baseDirectory
$removed = Remove-SgpPatch -BaseDirectory $baseDirectory
if ($removed) {
    Write-Host 'scoop-github-proxy: restored Scoop download pipeline.' -ForegroundColor Green
} else {
    Write-Host 'scoop-github-proxy: no patch was present.' -ForegroundColor Yellow
}

if ($null -eq $config.original_aria2_enabled) {
    if (Remove-SgpAria2Enabled) {
        Write-Host 'scoop-github-proxy: removed Scoop aria2-enabled override.' -ForegroundColor Green
    }
} else {
    Set-SgpAria2Enabled -Enabled ([bool]$config.original_aria2_enabled)
    Write-Host "scoop-github-proxy: restored Scoop aria2-enabled=$([bool]$config.original_aria2_enabled)." -ForegroundColor Green
}

if (Remove-SgpPersistDirectory -BaseDirectory $baseDirectory) {
    Write-Host 'scoop-github-proxy: removed persisted configuration.' -ForegroundColor Green
}
