Set-StrictMode -Version Latest

. "$PSScriptRoot\..\lib\patch.ps1"

$removed = Remove-SgpPatch
if ($removed) {
    Write-Host 'scoop-github-proxy: removed patch from Scoop download pipeline.' -ForegroundColor Green
} else {
    Write-Host 'scoop-github-proxy: no patch was present.' -ForegroundColor Yellow
}
