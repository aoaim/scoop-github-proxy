Set-StrictMode -Version Latest

function Get-SgpRoot {
    param(
        [string]$BaseDirectory = $PSScriptRoot
    )

    return [System.IO.Path]::GetFullPath((Join-Path $BaseDirectory '..'))
}

function Resolve-SgpScoopRoot {
    param(
        [string]$BaseDirectory = $PSScriptRoot
    )

    if (![string]::IsNullOrWhiteSpace($env:SCOOP)) {
        return $env:SCOOP
    }

    $current = [System.IO.Path]::GetFullPath($BaseDirectory)
    while ($null -ne $current) {
        $name = [System.IO.Path]::GetFileName($current)
        if ($name -eq 'apps') {
            return Split-Path $current -Parent
        }

        $parent = Split-Path $current -Parent
        if ($parent -eq $current) {
            break
        }
        $current = $parent
    }

    throw 'Unable to resolve Scoop root.'
}

function Get-SgpPersistDirectory {
    param(
        [string]$BaseDirectory = $PSScriptRoot
    )

    $persistRoot = $env:SCOOP_PERSIST_DIR
    if ([string]::IsNullOrWhiteSpace($persistRoot)) {
        $persistRoot = Join-Path (Resolve-SgpScoopRoot -BaseDirectory $BaseDirectory) 'persist'
    }

    return Join-Path $persistRoot 'scoop-github-proxy'
}

function Get-SgpConfigPath {
    param(
        [string]$BaseDirectory = $PSScriptRoot
    )

    return Join-Path (Get-SgpPersistDirectory -BaseDirectory $BaseDirectory) 'config.json'
}

function Get-SgpDefaultConfig {
    return [ordered]@{
        enabled = $true
        proxies = @(
            'https://gh-proxy.org'
        )
        fallback_to_origin = $true
        original_aria2_enabled = $null
        match = [ordered]@{
            release_download = $true
            raw_githubusercontent = $true
            api_github_releases = $true
        }
        log_enabled = $true
    }
}

function Initialize-SgpConfig {
    param(
        [string]$BaseDirectory = $PSScriptRoot
    )

    $persistDir = Get-SgpPersistDirectory -BaseDirectory $BaseDirectory
    if (!(Test-Path $persistDir)) {
        New-Item -Path $persistDir -ItemType Directory -Force | Out-Null
    }

    $configPath = Get-SgpConfigPath -BaseDirectory $BaseDirectory
    if (!(Test-Path $configPath)) {
        $defaultConfig = Get-SgpDefaultConfig | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText($configPath, $defaultConfig + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    }

    return $configPath
}

function Get-SgpConfig {
    param(
        [string]$BaseDirectory = $PSScriptRoot
    )

    $configPath = Initialize-SgpConfig -BaseDirectory $BaseDirectory
    $raw = [System.IO.File]::ReadAllText($configPath, [System.Text.UTF8Encoding]::new($false))
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return [pscustomobject](Get-SgpDefaultConfig)
    }

    $config = $raw | ConvertFrom-Json
    if ($null -eq $config.proxies) {
        $config | Add-Member -NotePropertyName proxies -NotePropertyValue @()
    }
    if ($null -eq $config.match) {
        $config | Add-Member -NotePropertyName match -NotePropertyValue ([pscustomobject](Get-SgpDefaultConfig).match)
    }
    if ($null -eq $config.fallback_to_origin) {
        $config | Add-Member -NotePropertyName fallback_to_origin -NotePropertyValue $true
    }
    if ($null -eq $config.PSObject.Properties['original_aria2_enabled']) {
        $config | Add-Member -NotePropertyName original_aria2_enabled -NotePropertyValue $null
    }
    if ($null -eq $config.log_enabled) {
        $config | Add-Member -NotePropertyName log_enabled -NotePropertyValue $true
    }
    if ($null -eq $config.enabled) {
        $config | Add-Member -NotePropertyName enabled -NotePropertyValue $true
    }

    return $config
}

function Save-SgpConfig {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Config,
        [string]$BaseDirectory = $PSScriptRoot
    )

    $configPath = Initialize-SgpConfig -BaseDirectory $BaseDirectory
    $json = $Config | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($configPath, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    return $configPath
}

function Normalize-SgpProxyUrl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url
    )

    $trimmed = $Url.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        throw 'Proxy URL cannot be empty.'
    }

    $uri = [System.Uri]$trimmed
    if ($uri.Scheme -notin @('http', 'https')) {
        throw "Unsupported proxy URL scheme: $($uri.Scheme)"
    }

    return $trimmed.TrimEnd('/')
}

function Add-SgpProxy {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,
        [string]$BaseDirectory = $PSScriptRoot
    )

    $config = Get-SgpConfig -BaseDirectory $BaseDirectory
    $normalised = Normalize-SgpProxyUrl -Url $Url
    $proxies = @($config.proxies)
    if ($proxies -contains $normalised) {
        return $false, $normalised
    }

    $config.proxies = @($proxies + $normalised)
    Save-SgpConfig -Config $config -BaseDirectory $BaseDirectory | Out-Null
    return $true, $normalised
}

function Remove-SgpProxy {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,
        [string]$BaseDirectory = $PSScriptRoot
    )

    $config = Get-SgpConfig -BaseDirectory $BaseDirectory
    $normalised = Normalize-SgpProxyUrl -Url $Url
    $proxies = @($config.proxies)
    if ($proxies -notcontains $normalised) {
        return $false, $normalised
    }

    $config.proxies = @($proxies | Where-Object { $_ -ne $normalised })
    Save-SgpConfig -Config $config -BaseDirectory $BaseDirectory | Out-Null
    return $true, $normalised
}

function Set-SgpEnabled {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Enabled,
        [string]$BaseDirectory = $PSScriptRoot
    )

    $config = Get-SgpConfig -BaseDirectory $BaseDirectory
    $config.enabled = $Enabled
    Save-SgpConfig -Config $config -BaseDirectory $BaseDirectory | Out-Null
}

function Set-SgpOriginalAria2Enabled {
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [Nullable[bool]]$Value,
        [string]$BaseDirectory = $PSScriptRoot
    )

    $config = Get-SgpConfig -BaseDirectory $BaseDirectory
    $config.original_aria2_enabled = $Value
    Save-SgpConfig -Config $config -BaseDirectory $BaseDirectory | Out-Null
}

function Remove-SgpPersistDirectory {
    param(
        [string]$BaseDirectory = $PSScriptRoot
    )

    $persistDir = Get-SgpPersistDirectory -BaseDirectory $BaseDirectory
    if (Test-Path $persistDir) {
        Remove-Item -LiteralPath $persistDir -Recurse -Force
        return $true
    }

    return $false
}
