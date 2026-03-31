Set-StrictMode -Version Latest

. "$PSScriptRoot\..\lib\config.ps1"
. "$PSScriptRoot\..\lib\patch.ps1"

$removed = Remove-SgpPatch
if ($removed) {
    Write-Host 'scoop-github-proxy: restored Scoop download and git pipeline.' -ForegroundColor Green
} else {
    Write-Host 'scoop-github-proxy: no patch was present.' -ForegroundColor Yellow
}

if (Remove-SgpPersistDirectory -BaseDirectory (Join-Path $PSScriptRoot '..\lib')) {
    Write-Host 'scoop-github-proxy: removed persisted configuration.' -ForegroundColor Green
}
