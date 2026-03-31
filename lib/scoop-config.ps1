Set-StrictMode -Version Latest

function Get-SgpScoopConfigPath {
    return Join-Path (Resolve-SgpScoopRoot -BaseDirectory $PSScriptRoot) 'config.json'
}

function Get-SgpScoopConfig {
    $configPath = Get-SgpScoopConfigPath
    if (!(Test-Path $configPath)) {
        return [pscustomobject]@{}
    }

    $raw = [System.IO.File]::ReadAllText($configPath, [System.Text.UTF8Encoding]::new($false))
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return [pscustomobject]@{}
    }

    return ($raw | ConvertFrom-Json)
}

function Save-SgpScoopConfig {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Config
    )

    $configPath = Get-SgpScoopConfigPath
    $json = $Config | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText($configPath, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
}

function Get-SgpAria2Enabled {
    $config = Get-SgpScoopConfig
    if ($null -eq $config.PSObject.Properties['aria2-enabled']) {
        return $true
    }

    return [bool]$config.'aria2-enabled'
}

function Set-SgpAria2Enabled {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Enabled
    )

    $config = Get-SgpScoopConfig
    if ($null -eq $config.PSObject.Properties['aria2-enabled']) {
        $config | Add-Member -NotePropertyName 'aria2-enabled' -NotePropertyValue $Enabled
    } else {
        $config.'aria2-enabled' = $Enabled
    }

    Save-SgpScoopConfig -Config $config
}
