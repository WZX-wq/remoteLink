param(
    [string]$ManifestPath,
    [string]$AuthorizeUrl = "https://login.kunqiongai.com/authorize.html",
    [string]$TokenUrl = "https://login.kunqiongai.com/api/oauth/token",
    [string]$ClientId = "app_e866d8c8242e2c2b",
    [string]$RedirectUri = "http://localhost:6613/oauth/callback",
    [int]$CallbackPort = 6613,
    [int]$TimeoutSec = 10,
    [string]$ReportPath,
    [switch]$NoReport
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

try {
    [System.Net.ServicePointManager]::SecurityProtocol =
        [System.Net.ServicePointManager]::SecurityProtocol `
        -bor [System.Net.SecurityProtocolType]::Tls12
} catch {
    # Older runtimes may not expose every TLS enum; TCP reachability is checked separately.
}

if (-not $ManifestPath) {
    $candidate = Join-Path $repo "KQ_RELEASE_MANIFEST.json"
    if (Test-Path $candidate) {
        $ManifestPath = $candidate
    }
}
if ($ManifestPath) {
    $manifest = Get-Content $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.oauth.authorizeUrl) {
        $AuthorizeUrl = $manifest.oauth.authorizeUrl
    }
    if ($manifest.oauth.tokenUrl) {
        $TokenUrl = $manifest.oauth.tokenUrl
    }
    if ($manifest.oauth.redirectUri) {
        $RedirectUri = $manifest.oauth.redirectUri
    }
}
if (-not $ReportPath) {
    $ReportPath = Join-Path "C:\kq-remote-link-tools" "KQ-Remote-Link-oauth-check-$(Get-Date -Format 'yyyyMMdd-HHmm').md"
}

$results = New-Object System.Collections.Generic.List[object]

function Add-Check($Name, $Status, $Detail) {
    $results.Add([PSCustomObject]@{
        Name = $Name
        Status = $Status
        Detail = $Detail
    })
    Write-Host "[$Status] $Name - $Detail"
}

function Test-TcpEndpoint($Name, [Uri]$Uri) {
    $port = if ($Uri.Port -gt 0) { $Uri.Port } elseif ($Uri.Scheme -eq "https") { 443 } else { 80 }
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $task = $client.ConnectAsync($Uri.Host, $port)
        if (-not $task.Wait($TimeoutSec * 1000)) {
            Add-Check $Name "FAIL" "TCP $($Uri.Host):$port timed out"
            return
        }
        if ($task.IsFaulted) {
            Add-Check $Name "FAIL" $task.Exception.InnerException.Message
            return
        }
        Add-Check $Name "PASS" "TCP $($Uri.Host):$port reachable"
    } catch {
        Add-Check $Name "FAIL" $_.Exception.Message
    } finally {
        $client.Dispose()
    }
}

function Test-CallbackPort($Port) {
    $listener = $null
    try {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
        $listener.Start()
        Add-Check "callback-port:${Port}" "PASS" "localhost:${Port} is available"
    } catch {
        Add-Check "callback-port:${Port}" "FAIL" "localhost:${Port} is not available: $($_.Exception.Message)"
    } finally {
        if ($listener) {
            $listener.Stop()
        }
    }
}

function Test-AuthorizePage([Uri]$BaseUri) {
    $state = "kq-oauth-check"
    $builder = [System.UriBuilder]::new($BaseUri)
    $query = [System.Web.HttpUtility]::ParseQueryString("")
    $query["response_type"] = "code"
    $query["client_id"] = $ClientId
    $query["redirect_uri"] = $RedirectUri
    $query["state"] = $state
    $builder.Query = $query.ToString()
    $uri = $builder.Uri
    try {
        $response = Invoke-WebRequest -Uri $uri -Method Get -TimeoutSec $TimeoutSec -UseBasicParsing
        if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 400) {
            Add-Check "authorize-page" "PASS" "HTTP $($response.StatusCode)"
        } else {
            Add-Check "authorize-page" "FAIL" "HTTP $($response.StatusCode)"
        }
    } catch {
        $status = $_.Exception.Response.StatusCode.value__
        if ($status -and $status -ge 300 -and $status -lt 500) {
            Add-Check "authorize-page" "WARN" "HTTP $status; page is reachable but returned a non-success status"
        } else {
            Add-Check "authorize-page" "WARN" "GET failed after TCP succeeded: $($_.Exception.Message)"
        }
    }
}

Add-Type -AssemblyName System.Web
$authorizeUri = [Uri]$AuthorizeUrl
$tokenUri = [Uri]$TokenUrl

if ($RedirectUri -ne "http://localhost:${CallbackPort}/oauth/callback") {
    Add-Check "redirect-uri" "WARN" "RedirectUri is $RedirectUri; expected localhost:${CallbackPort}/oauth/callback"
} else {
    Add-Check "redirect-uri" "PASS" $RedirectUri
}

Test-CallbackPort $CallbackPort
Test-TcpEndpoint "tcp:authorize-host" $authorizeUri
Test-TcpEndpoint "tcp:token-host" $tokenUri
Test-AuthorizePage $authorizeUri

$failed = @($results | Where-Object { $_.Status -eq "FAIL" })
$report = New-Object System.Collections.Generic.List[string]
$report.Add("# KQ Remote Link OAuth Check")
$report.Add("")
$report.Add("- Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$report.Add("- AuthorizeUrl: $AuthorizeUrl")
$report.Add("- TokenUrl: $TokenUrl")
$report.Add("- ClientId: $ClientId")
$report.Add("- RedirectUri: $RedirectUri")
$report.Add("")
$report.Add("| Status | Check | Detail |")
$report.Add("| --- | --- | --- |")
foreach ($result in $results) {
    $detail = ($result.Detail -replace "\|", "\\|")
    $report.Add("| $($result.Status) | $($result.Name) | $detail |")
}
$report.Add("")
$report.Add("This check does not prove account login. Finish with a real browser login using a Kunqiong account.")

if (-not $NoReport) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ReportPath) | Out-Null
    [System.IO.File]::WriteAllLines($ReportPath, $report, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "OAuth check report: $ReportPath"
}

if ($failed.Count -gt 0) {
    throw "OAuth checks failed: $($failed.Count)"
}
