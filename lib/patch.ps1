Set-StrictMode -Version Latest

. "$PSScriptRoot\config.ps1"

function Get-SgpScoopRoot {
    return Resolve-SgpScoopRoot -BaseDirectory $PSScriptRoot
}

function Get-SgpDownloadScriptPath {
    $scoopRoot = Get-SgpScoopRoot
    return Join-Path $scoopRoot 'apps\scoop\current\lib\download.ps1'
}

function Get-SgpCoreScriptPath {
    $scoopRoot = Get-SgpScoopRoot
    return Join-Path $scoopRoot 'apps\scoop\current\lib\core.ps1'
}

function Get-SgpScoopRepoPath {
    $scoopRoot = Get-SgpScoopRoot
    return Join-Path $scoopRoot 'apps\scoop\current'
}

function Restore-SgpDownloadScriptFromGit {
    param(
        [string]$DownloadScriptPath = $(Get-SgpDownloadScriptPath)
    )

    $repoPath = Get-SgpScoopRepoPath
    if (!(Test-Path (Join-Path $repoPath '.git'))) {
        return $false
    }

    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($null -eq $git) {
        return $false
    }

    & $git.Source -C $repoPath restore --worktree --source=HEAD -- 'lib/download.ps1' | Out-Null
    if ($LASTEXITCODE -ne 0) {
        return $false
    }

    return Test-Path $DownloadScriptPath
}

function Restore-SgpCoreScriptFromGit {
    param(
        [string]$CoreScriptPath = $(Get-SgpCoreScriptPath)
    )

    $repoPath = Get-SgpScoopRepoPath
    if (!(Test-Path (Join-Path $repoPath '.git'))) {
        return $false
    }

    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($null -eq $git) {
        return $false
    }

    & $git.Source -C $repoPath restore --worktree --source=HEAD -- 'lib/core.ps1' | Out-Null
    if ($LASTEXITCODE -ne 0) {
        return $false
    }

    return Test-Path $CoreScriptPath
}

function Get-SgpPatchMarkers {
    return [ordered]@{
        DownloadStart = '# scoop-github-proxy download begin'
        DownloadEnd = '# scoop-github-proxy download end'
        CoreStart = '# scoop-github-proxy core begin'
        CoreEnd = '# scoop-github-proxy core end'
    }
}

function Get-SgpDownloadPatchedBlock {
    param(
        [string]$BaseDirectory = $PSScriptRoot
    )

    $markers = Get-SgpPatchMarkers
    $configPath = Get-SgpConfigPath -BaseDirectory $BaseDirectory

    $block = @'
__DOWNLOAD_START__
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

function Test-SgpIsProxyCandidate([string]$candidate, [string]$originalUrl) {
    return ![string]::IsNullOrWhiteSpace($candidate) -and ![string]::IsNullOrWhiteSpace($originalUrl) -and $candidate -ne $originalUrl
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
            $shouldRetry = Test-SgpRetriableException $lastException
            if (!$shouldRetry -and (Test-SgpIsProxyCandidate $candidate $url) -and $lastException.Response) {
                $shouldRetry = $true
            }
            if (!$shouldRetry -or $candidate -eq $candidates[-1]) {
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
__DOWNLOAD_END__
'@

    $block = $block.Replace('__DOWNLOAD_START__', $markers.DownloadStart)
    $block = $block.Replace('__DOWNLOAD_END__', $markers.DownloadEnd)
    $block = $block.Replace('__CONFIG_PATH__', ($configPath -replace "'", "''"))

    return $block.TrimEnd()
}

function Get-SgpCorePatchedBlock {
    param(
        [string]$BaseDirectory = $PSScriptRoot
    )

    $markers = Get-SgpPatchMarkers
    $configPath = Get-SgpConfigPath -BaseDirectory $BaseDirectory

    $block = @'
__CORE_START__
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

function Test-SgpGitHubRepoUrl([string]$url) {
    if ([string]::IsNullOrWhiteSpace($url)) {
        return $false
    }

    return $url -match '^https://github\.com/[^/]+/[^/]+(?:\.git)?/?$'
}

function ConvertTo-SgpProxyUrl([string]$url, [string]$proxyBase) {
    return "$($proxyBase.TrimEnd('/'))/$url"
}

function Get-SgpGitCandidateUrls([string]$url) {
    $config = Get-SgpRuntimeConfig
    if ($null -eq $config -or !$config.enabled -or !(Test-SgpGitHubRepoUrl $url)) {
        return @($url)
    }

    $candidates = [System.Collections.Generic.List[string]]::new()
    foreach ($proxy in @($config.proxies)) {
        if ([string]::IsNullOrWhiteSpace($proxy)) {
            continue
        }
        $candidates.Add((ConvertTo-SgpProxyUrl $url $proxy))
    }

    if ($config.fallback_to_origin -or $candidates.Count -eq 0) {
        $candidates.Add($url)
    }

    return $candidates.ToArray()
}

function Get-SgpGitRepoUrlIndex($argumentList) {
    for ($i = 0; $i -lt $argumentList.Count; $i++) {
        $arg = [string]$argumentList[$i]
        if (Test-SgpGitHubRepoUrl $arg) {
            return $i
        }
    }

    return -1
}

function Get-SgpGitRemoteNameIndex($argumentList) {
    $networkOps = @('pull', 'fetch', 'ls-remote')
    for ($i = 0; $i -lt $argumentList.Count; $i++) {
        $arg = [string]$argumentList[$i]
        if ($networkOps -contains $arg) {
            $nextIndex = $i + 1
            if ($nextIndex -lt $argumentList.Count) {
                $nextArg = [string]$argumentList[$nextIndex]
                if ($nextArg -and $nextArg -notmatch '^-') {
                    return $nextIndex
                }
            }
            return -2
        }
    }

    return -1
}

function Get-SgpRemoteUrl($workingDirectory, $remoteName) {
    if ([string]::IsNullOrWhiteSpace($workingDirectory) -or [string]::IsNullOrWhiteSpace($remoteName)) {
        return $null
    }

    $git = Get-HelperPath -Helper Git
    try {
        $url = (& $git -C $workingDirectory config --get "remote.$remoteName.url" 2>$null | Select-Object -First 1)
        if ([string]::IsNullOrWhiteSpace($url)) {
            return $null
        }
        return [string]$url
    } catch {
        return $null
    }
}

Set-Item -Path Function:\Invoke-SgpOriginalGit -Value ${function:Invoke-Git}
Set-Item -Path Function:\Invoke-Git -Value {
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [Alias('PSPath', 'Path')]
        [ValidateNotNullOrEmpty()]
        [String]$WorkingDirectory,
        [Parameter(Mandatory = $true, Position = 1)]
        [Alias('Args')]
        [String[]]$ArgumentList
    )

    $gitOps = @('clone', 'pull', 'fetch', 'ls-remote')
    $isGitNetworkOp = $false
    foreach ($op in $gitOps) {
        if ($ArgumentList -contains $op) {
            $isGitNetworkOp = $true
            break
        }
    }

    if (!$isGitNetworkOp) {
        Invoke-SgpOriginalGit -WorkingDirectory $WorkingDirectory -ArgumentList $ArgumentList
        return
    }

    $repoUrlIndex = Get-SgpGitRepoUrlIndex $ArgumentList
    $remoteNameIndex = -1
    $originalUrl = $null

    if ($repoUrlIndex -ge 0) {
        $originalUrl = [string]$ArgumentList[$repoUrlIndex]
    } else {
        $remoteNameIndex = Get-SgpGitRemoteNameIndex $ArgumentList
        if ($remoteNameIndex -eq -2) {
            $remoteName = 'origin'
            $originalUrl = Get-SgpRemoteUrl $WorkingDirectory $remoteName
        } elseif ($remoteNameIndex -ge 0) {
            $remoteName = [string]$ArgumentList[$remoteNameIndex]
            $originalUrl = Get-SgpRemoteUrl $WorkingDirectory $remoteName
        }
    }

    if ([string]::IsNullOrWhiteSpace($originalUrl)) {
        Invoke-SgpOriginalGit -WorkingDirectory $WorkingDirectory -ArgumentList $ArgumentList
        return
    }

    $candidates = Get-SgpGitCandidateUrls $originalUrl
    foreach ($candidate in $candidates) {
        $candidateArgs = @($ArgumentList)
        if ($repoUrlIndex -ge 0) {
            $candidateArgs[$repoUrlIndex] = $candidate
        } elseif ($remoteNameIndex -ge 0) {
            $candidateArgs[$remoteNameIndex] = $candidate
        } elseif ($remoteNameIndex -eq -2) {
            $opIndex = [Array]::IndexOf($candidateArgs, (($gitOps | Where-Object { $candidateArgs -contains $_ }) | Select-Object -First 1))
            if ($opIndex -ge 0) {
                $insertAt = $opIndex + 1
                if ($insertAt -lt $candidateArgs.Count) {
                    $candidateArgs = @($candidateArgs[0..$opIndex] + $candidate + $candidateArgs[$insertAt..($candidateArgs.Count - 1)])
                } else {
                    $candidateArgs = @($candidateArgs + $candidate)
                }
            }
        }
        if ($candidate -ne $originalUrl) {
            info "scoop-github-proxy: trying git proxy $candidate"
        }
        $result = Invoke-SgpOriginalGit -WorkingDirectory $WorkingDirectory -ArgumentList $candidateArgs
        if ($LASTEXITCODE -eq 0) {
            return $result
        }
    }

    Invoke-SgpOriginalGit -WorkingDirectory $WorkingDirectory -ArgumentList $ArgumentList
}
__CORE_END__
'@

    $block = $block.Replace('__CORE_START__', $markers.CoreStart)
    $block = $block.Replace('__CORE_END__', $markers.CoreEnd)
    $block = $block.Replace('__CONFIG_PATH__', ($configPath -replace "'", "''"))

    return $block.TrimEnd()
}

function Test-SgpPatchPresent {
    param(
        [string]$DownloadScriptPath = $(Get-SgpDownloadScriptPath),
        [string]$CoreScriptPath = $(Get-SgpCoreScriptPath)
    )

    if (!(Test-Path $DownloadScriptPath) -or !(Test-Path $CoreScriptPath)) {
        return $false
    }

    $downloadContent = [System.IO.File]::ReadAllText($DownloadScriptPath, [System.Text.UTF8Encoding]::new($false))
    $coreContent = [System.IO.File]::ReadAllText($CoreScriptPath, [System.Text.UTF8Encoding]::new($false))
    $markers = Get-SgpPatchMarkers
    return $downloadContent.Contains($markers.DownloadStart) -and $downloadContent.Contains($markers.DownloadEnd) -and $coreContent.Contains($markers.CoreStart) -and $coreContent.Contains($markers.CoreEnd)
}

function Install-SgpPatch {
    param(
        [string]$BaseDirectory = $PSScriptRoot,
        [string]$DownloadScriptPath = $(Get-SgpDownloadScriptPath),
        [string]$CoreScriptPath = $(Get-SgpCoreScriptPath)
    )

    if (!(Test-Path $DownloadScriptPath)) {
        throw "Scoop download script not found: $DownloadScriptPath"
    }
    if (!(Test-Path $CoreScriptPath)) {
        throw "Scoop core script not found: $CoreScriptPath"
    }

    $downloadContent = [System.IO.File]::ReadAllText($DownloadScriptPath, [System.Text.UTF8Encoding]::new($false))
    $coreContent = [System.IO.File]::ReadAllText($CoreScriptPath, [System.Text.UTF8Encoding]::new($false))
    if (Test-SgpPatchPresent -DownloadScriptPath $DownloadScriptPath -CoreScriptPath $CoreScriptPath) {
        return $false
    }

    $downloadAnchor = '# Setup proxy globally'
    $coreAnchor = 'function Invoke-GitLog {'
    if (!$downloadContent.Contains($downloadAnchor)) {
        throw 'Unsupported Scoop version: patch anchor not found.'
    }
    if (!$coreContent.Contains($coreAnchor)) {
        throw 'Unsupported Scoop version: git patch anchor not found.'
    }

    $downloadPatchBlock = Get-SgpDownloadPatchedBlock -BaseDirectory $BaseDirectory
    $downloadUpdated = $downloadContent.Replace($downloadAnchor, "$downloadPatchBlock`r`n`r`n$downloadAnchor")
    [System.IO.File]::WriteAllText($DownloadScriptPath, $downloadUpdated, [System.Text.UTF8Encoding]::new($false))

    $corePatchBlock = Get-SgpCorePatchedBlock -BaseDirectory $BaseDirectory
    $coreUpdated = $coreContent.Replace($coreAnchor, "$corePatchBlock`r`n`r`n$coreAnchor")
    [System.IO.File]::WriteAllText($CoreScriptPath, $coreUpdated, [System.Text.UTF8Encoding]::new($false))
    return $true
}

function Remove-SgpPatch {
    param(
        [string]$DownloadScriptPath = $(Get-SgpDownloadScriptPath),
        [string]$CoreScriptPath = $(Get-SgpCoreScriptPath)
    )

    $downloadRestored = Restore-SgpDownloadScriptFromGit -DownloadScriptPath $DownloadScriptPath
    $coreRestored = Restore-SgpCoreScriptFromGit -CoreScriptPath $CoreScriptPath
    if ($downloadRestored -and $coreRestored) {
        return $true
    }

    if (!(Test-SgpPatchPresent -DownloadScriptPath $DownloadScriptPath -CoreScriptPath $CoreScriptPath)) {
        return $false
    }

    $downloadContent = [System.IO.File]::ReadAllText($DownloadScriptPath, [System.Text.UTF8Encoding]::new($false))
    $coreContent = [System.IO.File]::ReadAllText($CoreScriptPath, [System.Text.UTF8Encoding]::new($false))
    $markers = Get-SgpPatchMarkers
    $downloadPattern = [regex]::Escape($markers.DownloadStart) + '.*?' + [regex]::Escape($markers.DownloadEnd) + '\r?\n\r?\n?'
    $downloadUpdated = [regex]::Replace($downloadContent, $downloadPattern, '', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    [System.IO.File]::WriteAllText($DownloadScriptPath, $downloadUpdated, [System.Text.UTF8Encoding]::new($false))

    $corePattern = [regex]::Escape($markers.CoreStart) + '.*?' + [regex]::Escape($markers.CoreEnd) + '\r?\n\r?\n?'
    $coreUpdated = [regex]::Replace($coreContent, $corePattern, '', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    [System.IO.File]::WriteAllText($CoreScriptPath, $coreUpdated, [System.Text.UTF8Encoding]::new($false))
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
        DownloadScript = Get-SgpDownloadScriptPath
        CoreScript = Get-SgpCoreScriptPath
        ConfigPath = Get-SgpConfigPath -BaseDirectory $BaseDirectory
    }
}
