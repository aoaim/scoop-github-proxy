# Summary: Manage Scoop GitHub proxy integration

Set-StrictMode -Version Latest

. "$PSScriptRoot\..\lib\config.ps1"
. "$PSScriptRoot\..\lib\patch.ps1"
. "$PSScriptRoot\..\lib\scoop-config.ps1"

function Show-SgpUsage {
    @(
        'Usage: scoop github-proxy <command> [options]'
        ''
        'Commands:'
        '  enable                         Enable proxy chaining'
        '  disable                        Disable proxy chaining'
        '  status                         Show config and patch status'
        '  repair                         Reapply Scoop patch'
        '  proxy list                     List configured proxies'
        '  proxy add <url>                Add a proxy base URL'
        '  proxy remove <url>             Remove a proxy base URL'
    ) | ForEach-Object { Write-Host $_ }
}

function Show-SgpStatus {
    $status = Get-SgpPatchStatus -BaseDirectory (Join-Path $PSScriptRoot '..\lib')
    Write-Host 'scoop-github-proxy status'
    Write-Host "  enabled: $($status.Enabled)"
    Write-Host "  patch_present: $($status.PatchPresent)"
    Write-Host "  repair_needed: $($status.RepairNeeded)"
    Write-Host "  backup_present: $($status.BackupPresent)"
    Write-Host "  scoop_aria2_enabled: $(Get-SgpAria2Enabled)"
    Write-Host "  config_path: $($status.ConfigPath)"
    Write-Host "  backup_path: $($status.BackupPath)"
    Write-Host "  scoop_download_script: $($status.DownloadScript)"
    Write-Host '  proxies:'
    if ($status.Proxies.Count -eq 0) {
        Write-Host '    (none)'
    } else {
        for ($i = 0; $i -lt $status.Proxies.Count; $i++) {
            Write-Host "    $($i + 1). $($status.Proxies[$i])"
        }
    }

    if ($status.RepairNeeded) {
        Write-Host "Run 'scoop github-proxy repair' after 'scoop update scoop'." -ForegroundColor Yellow
    }
    if (Get-SgpAria2Enabled) {
        Write-Host "Run 'scoop config aria2-enabled false' or 'scoop github-proxy repair'." -ForegroundColor Yellow
    }
}

function Show-SgpProxyList {
    $config = Get-SgpConfig -BaseDirectory (Join-Path $PSScriptRoot '..\lib')
    if (@($config.proxies).Count -eq 0) {
        Write-Host 'No proxy configured.'
        return
    }

    for ($i = 0; $i -lt @($config.proxies).Count; $i++) {
        Write-Host "$($i + 1). $($config.proxies[$i])"
    }
}

$command = $Args[0]
if ([string]::IsNullOrWhiteSpace($command)) {
    Show-SgpUsage
    exit 0
}

switch ($command) {
    'enable' {
        Set-SgpEnabled -Enabled $true -BaseDirectory (Join-Path $PSScriptRoot '..\lib')
        Write-Host 'scoop-github-proxy: enabled.' -ForegroundColor Green
    }
    'disable' {
        Set-SgpEnabled -Enabled $false -BaseDirectory (Join-Path $PSScriptRoot '..\lib')
        Write-Host 'scoop-github-proxy: disabled.' -ForegroundColor Yellow
    }
    'status' {
        Show-SgpStatus
    }
    'repair' {
        & (Join-Path $PSScriptRoot 'repair.ps1')
    }
    'proxy' {
        $proxyCommand = $Args[1]
        switch ($proxyCommand) {
            'list' {
                Show-SgpProxyList
            }
            'add' {
                if ($Args.Count -lt 3) {
                    throw 'Missing proxy URL.'
                }
                $added, $url = Add-SgpProxy -Url $Args[2] -BaseDirectory (Join-Path $PSScriptRoot '..\lib')
                if ($added) {
                    Write-Host "Added proxy: $url" -ForegroundColor Green
                } else {
                    Write-Host "Proxy already exists: $url" -ForegroundColor Yellow
                }
            }
            'remove' {
                if ($Args.Count -lt 3) {
                    throw 'Missing proxy URL.'
                }
                $removed, $url = Remove-SgpProxy -Url $Args[2] -BaseDirectory (Join-Path $PSScriptRoot '..\lib')
                if ($removed) {
                    Write-Host "Removed proxy: $url" -ForegroundColor Green
                } else {
                    Write-Host "Proxy not found: $url" -ForegroundColor Yellow
                }
            }
            default {
                Show-SgpUsage
                exit 1
            }
        }
    }
    default {
        Show-SgpUsage
        exit 1
    }
}
