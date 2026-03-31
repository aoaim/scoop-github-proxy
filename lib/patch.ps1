Set-StrictMode -Version Latest

. "$PSScriptRoot\config.ps1"

function Get-SgpScoopRoot {
    return Resolve-SgpScoopRoot -BaseDirectory $PSScriptRoot
}

function Get-SgpDownloadScriptPath {
    $scoopRoot = Get-SgpScoopRoot
    return Join-Path $scoopRoot 'apps\scoop\current\lib\download.ps1'
}

function Get-SgpBackupDirectory {
    param(
        [string]$BaseDirectory = $PSScriptRoot
    )

    return Join-Path (Get-SgpPersistDirectory -BaseDirectory $BaseDirectory) 'backup'
}

function Get-SgpDownloadScriptBackupPath {
    param(
        [string]$BaseDirectory = $PSScriptRoot
    )

    return Join-Path (Get-SgpBackupDirectory -BaseDirectory $BaseDirectory) 'download.ps1.bak'
}

function Get-SgpBackupMetadataPath {
    param(
        [string]$BaseDirectory = $PSScriptRoot
    )

    return Join-Path (Get-SgpBackupDirectory -BaseDirectory $BaseDirectory) 'metadata.json'
}

function Test-SgpBackupPresent {
    param(
        [string]$BaseDirectory = $PSScriptRoot
    )

    return Test-Path (Get-SgpDownloadScriptBackupPath -BaseDirectory $BaseDirectory)
}

function Backup-SgpDownloadScript {
    param(
        [string]$BaseDirectory = $PSScriptRoot,
        [string]$DownloadScriptPath = $(Get-SgpDownloadScriptPath)
    )

    $backupDir = Get-SgpBackupDirectory -BaseDirectory $BaseDirectory
    if (!(Test-Path $backupDir)) {
        New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
    }

    $backupPath = Get-SgpDownloadScriptBackupPath -BaseDirectory $BaseDirectory
    $metadataPath = Get-SgpBackupMetadataPath -BaseDirectory $BaseDirectory
    if (Test-Path $backupPath) {
        return $false
    }

    Copy-Item $DownloadScriptPath $backupPath -Force
    $hash = (Get-FileHash -Path $DownloadScriptPath -Algorithm SHA256).Hash.ToLower()
    $metadata = [ordered]@{
        created_at = (Get-Date).ToString('o')
        source_path = $DownloadScriptPath
        backup_path = $backupPath
        sha256 = $hash
    } | ConvertTo-Json -Depth 4
    [System.IO.File]::WriteAllText($metadataPath, $metadata + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    return $true
}

function Restore-SgpDownloadScriptBackup {
    param(
        [string]$BaseDirectory = $PSScriptRoot,
        [string]$DownloadScriptPath = $(Get-SgpDownloadScriptPath)
    )

    $backupPath = Get-SgpDownloadScriptBackupPath -BaseDirectory $BaseDirectory
    if (!(Test-Path $backupPath)) {
        return $false
    }

    Copy-Item $backupPath $DownloadScriptPath -Force
    return $true
}

function Get-SgpPatchMarkers {
    return [ordered]@{
        Start = '# scoop-github-proxy begin'
        End = '# scoop-github-proxy end'
    }
}

function Get-SgpPatchedBlock {
    param(
        [string]$BaseDirectory = $PSScriptRoot
    )

    $markers = Get-SgpPatchMarkers
    $configPath = Get-SgpConfigPath -BaseDirectory $BaseDirectory

    $block = @'
__START__
function Get-SgpRuntimeConfigPath {
    return '__CONFIG_PATH__'
}

function Get-SgpRuntimeConfig {
    $path = Get-SgpRuntimeConfigPath
    if (!(Test-Path $path)) {
        return $null
    }

    try {
        return ([System.IO.File]::ReadAllText($path, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json)
    } catch {
        warn "scoop-github-proxy: failed to read config from ${path}: $($_.Exception.Message)"
        return $null
    }
}

function Test-SgpCandidateUrl([string]$url) {
    if ([string]::IsNullOrWhiteSpace($url)) {
        return $false
    }

    $config = Get-SgpRuntimeConfig
    if ($null -eq $config -or !$config.enabled) {
        return $false
    }

    if ($config.match.release_download -and $url -match '^https://github\.com/[^/]+/[^/]+/releases/download/') {
        return $true
    }
    if ($config.match.raw_githubusercontent -and $url -match '^https://raw\.githubusercontent\.com/') {
        return $true
    }
    if ($config.match.api_github_releases -and $url -match '^https://api\.github\.com/repos/[^/]+/[^/]+/releases/') {
        return $true
    }

    return $false
}

function Get-SgpCandidateUrls([string]$url) {
    $config = Get-SgpRuntimeConfig
    if ($null -eq $config -or !$config.enabled -or !(Test-SgpCandidateUrl $url)) {
        return @($url)
    }

    $candidates = [System.Collections.Generic.List[string]]::new()
    foreach ($proxy in @($config.proxies)) {
        if ([string]::IsNullOrWhiteSpace($proxy)) {
            continue
        }
        $proxyBase = $proxy.TrimEnd('/')
        $candidates.Add("$proxyBase/$url")
    }

    if ($config.fallback_to_origin) {
        $candidates.Add($url)
    }

    if ($candidates.Count -eq 0) {
        $candidates.Add($url)
    }

    return $candidates.ToArray()
}

function Test-SgpRetriableStatusCode($statusCode) {
    return @('BadGateway', 'ServiceUnavailable', 'GatewayTimeout') -contains [string]$statusCode
}

function Test-SgpRetriableException($exception) {
    if ($null -eq $exception) {
        return $false
    }

    $message = [string]$exception.Message
    if ($message -match 'timed out|timeout|handshake|SSL|TLS|connection.*closed|connection.*forcibly closed|remote name could not be resolved|name resolution|No such host is known|Unable to connect|actively refused') {
        return $true
    }

    if ($exception.PSObject.Properties.Name -contains 'Status' -and [string]$exception.Status -match 'Timeout|ConnectFailure|NameResolutionFailure|SecureChannelFailure|TrustFailure|ReceiveFailure|SendFailure') {
        return $true
    }

    if ($exception.Response -and (Test-SgpRetriableStatusCode $exception.Response.StatusCode)) {
        return $true
    }

    if ($exception.InnerException) {
        return Test-SgpRetriableException $exception.InnerException
    }

    return $false
}

function Invoke-SgpDownloadWithFallback($url, $to, $cookies, $progress) {
    $candidates = Get-SgpCandidateUrls $url
    $lastException = $null

    foreach ($candidate in $candidates) {
        try {
            if ($candidate -ne $url) {
                info "scoop-github-proxy: trying proxy $candidate"
            }
            Invoke-SgpOriginalDownload $candidate $to $cookies $progress
            return
        } catch {
            $lastException = $_.Exception
            if (!(Test-SgpRetriableException $lastException) -or $candidate -eq $candidates[-1]) {
                throw
            }
            warn "scoop-github-proxy: candidate failed, trying next source: $($lastException.Message)"
        }
    }

    if ($null -ne $lastException) {
        throw $lastException
    }
}

Set-Item -Path Function:\Invoke-SgpOriginalDownload -Value ${function:Invoke-Download}
Set-Item -Path Function:\Invoke-Download -Value {
    param($url, $to, $cookies, $progress)
    Invoke-SgpDownloadWithFallback $url $to $cookies $progress
}
__END__
'@

    $block = $block.Replace('__START__', $markers.Start)
    $block = $block.Replace('__END__', $markers.End)
    $block = $block.Replace('__CONFIG_PATH__', ($configPath -replace "'", "''"))

    return $block.TrimEnd()
}

function Test-SgpPatchPresent {
    param(
        [string]$DownloadScriptPath = $(Get-SgpDownloadScriptPath)
    )

    if (!(Test-Path $DownloadScriptPath)) {
        return $false
    }

    $content = [System.IO.File]::ReadAllText($DownloadScriptPath, [System.Text.UTF8Encoding]::new($false))
    $markers = Get-SgpPatchMarkers
    return $content.Contains($markers.Start) -and $content.Contains($markers.End)
}

function Install-SgpPatch {
    param(
        [string]$BaseDirectory = $PSScriptRoot,
        [string]$DownloadScriptPath = $(Get-SgpDownloadScriptPath)
    )

    if (!(Test-Path $DownloadScriptPath)) {
        throw "Scoop download script not found: $DownloadScriptPath"
    }

    $content = [System.IO.File]::ReadAllText($DownloadScriptPath, [System.Text.UTF8Encoding]::new($false))
    if (Test-SgpPatchPresent -DownloadScriptPath $DownloadScriptPath) {
        return $false
    }

    $anchor = '# Setup proxy globally'
    if (!$content.Contains($anchor)) {
        throw 'Unsupported Scoop version: patch anchor not found.'
    }

    Backup-SgpDownloadScript -BaseDirectory $BaseDirectory -DownloadScriptPath $DownloadScriptPath | Out-Null
    $patchBlock = Get-SgpPatchedBlock -BaseDirectory $BaseDirectory
    $updated = $content.Replace($anchor, "$patchBlock`r`n`r`n$anchor")
    [System.IO.File]::WriteAllText($DownloadScriptPath, $updated, [System.Text.UTF8Encoding]::new($false))
    return $true
}

function Remove-SgpPatch {
    param(
        [string]$BaseDirectory = $PSScriptRoot,
        [string]$DownloadScriptPath = $(Get-SgpDownloadScriptPath)
    )

    if (Restore-SgpDownloadScriptBackup -BaseDirectory $BaseDirectory -DownloadScriptPath $DownloadScriptPath) {
        return $true
    }

    if (!(Test-SgpPatchPresent -DownloadScriptPath $DownloadScriptPath)) {
        return $false
    }

    $content = [System.IO.File]::ReadAllText($DownloadScriptPath, [System.Text.UTF8Encoding]::new($false))
    $markers = Get-SgpPatchMarkers
    $pattern = [regex]::Escape($markers.Start) + '.*?' + [regex]::Escape($markers.End) + '\r?\n\r?\n?'
    $updated = [regex]::Replace($content, $pattern, '', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    [System.IO.File]::WriteAllText($DownloadScriptPath, $updated, [System.Text.UTF8Encoding]::new($false))
    return $true
}

function Get-SgpPatchStatus {
    param(
        [string]$BaseDirectory = $PSScriptRoot
    )

    $config = Get-SgpConfig -BaseDirectory $BaseDirectory
    return [pscustomobject]@{
        Enabled = [bool]$config.enabled
        Proxies = @($config.proxies)
        PatchPresent = Test-SgpPatchPresent
        RepairNeeded = -not (Test-SgpPatchPresent)
        BackupPresent = Test-SgpBackupPresent -BaseDirectory $BaseDirectory
        BackupPath = Get-SgpDownloadScriptBackupPath -BaseDirectory $BaseDirectory
        DownloadScript = Get-SgpDownloadScriptPath
        ConfigPath = Get-SgpConfigPath -BaseDirectory $BaseDirectory
    }
}
