param(
    [string]$ManifestPath,
    [string]$ApiBaseUrl = "https://api-web.kunqiongai.com",
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

$paths = [ordered]@{
    webLoginUrlPath = "/soft_desktop/get_web_login_url"
    desktopTokenPath = "/user/desktop_get_token"
    checkLoginPath = "/user/check_login"
    userInfoPath = "/soft_desktop/get_user_info"
    logoutPath = "/logout"
}

if (-not $ManifestPath) {
    $candidate = Join-Path $repo "KQ_RELEASE_MANIFEST.json"
    if (Test-Path $candidate) {
        $ManifestPath = $candidate
    }
}
if ($ManifestPath) {
    $manifest = Get-Content $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.oauth.apiBaseUrl) {
        $ApiBaseUrl = $manifest.oauth.apiBaseUrl
    }
    foreach ($key in @($paths.Keys)) {
        if ($manifest.oauth.$key) {
            $paths[$key] = $manifest.oauth.$key
        }
    }
}
if (-not $ReportPath) {
    $ReportPath = Join-Path "C:\kq-remote-link-tools" "KQ-Remote-Link-login-check-$(Get-Date -Format 'yyyyMMdd-HHmm').md"
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

function Join-ApiUrl([string]$Base, [string]$Path) {
    return $Base.TrimEnd("/") + "/" + $Path.TrimStart("/")
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

function Invoke-LoginPost($Name, [string]$Url, [hashtable]$Body, [hashtable]$Headers) {
    try {
        $params = @{
            Uri = $Url
            Method = "Post"
            TimeoutSec = $TimeoutSec
            UseBasicParsing = $true
            ContentType = "application/x-www-form-urlencoded"
        }
        if ($Body) {
            $params.Body = $Body
        }
        if ($Headers) {
            $params.Headers = $Headers
        }
        $response = Invoke-WebRequest @params
        $json = $null
        try {
            $json = $response.Content | ConvertFrom-Json
        } catch {
            Add-Check $Name "WARN" "HTTP $($response.StatusCode); response is not JSON"
            return $null
        }
        Add-Check $Name "PASS" "HTTP $($response.StatusCode), code=$($json.code)"
        return $json
    } catch {
        $status = $null
        if ($_.Exception.Response) {
            $status = $_.Exception.Response.StatusCode.value__
        }
        if ($status -and $status -ge 400 -and $status -lt 500) {
            Add-Check $Name "WARN" "HTTP $status; endpoint is reachable without a real login token"
        } else {
            Add-Check $Name "FAIL" $_.Exception.Message
        }
        return $null
    }
}

function Test-SourceContains($Path, $Needle, $Name) {
    $fullPath = Join-Path $repo $Path
    if (-not (Test-Path $fullPath)) {
        Add-Check $Name "FAIL" "Missing source file: $Path"
        return
    }
    $content = Get-Content $fullPath -Raw -Encoding UTF8
    if ($content.Contains($Needle)) {
        Add-Check $Name "PASS" $Needle
    } else {
        Add-Check $Name "FAIL" "Missing expected source text: $Needle"
    }
}

$apiUri = [Uri]$ApiBaseUrl
Test-TcpEndpoint "tcp:login-api-host" $apiUri
Test-SourceContains "flutter\lib\common\kq_oauth_io.dart" "--app=`${authUri.toString()}" "ui:login-opens-managed-browser-app"
Test-SourceContains "flutter\lib\common\kq_oauth_io.dart" "--window-size=1360,820" "ui:login-browser-desktop-layout-width"

$webLoginUrl = Join-ApiUrl $ApiBaseUrl $paths.webLoginUrlPath
$desktopTokenUrl = Join-ApiUrl $ApiBaseUrl $paths.desktopTokenPath
$checkLoginUrl = Join-ApiUrl $ApiBaseUrl $paths.checkLoginPath
$userInfoUrl = Join-ApiUrl $ApiBaseUrl $paths.userInfoPath
$logoutUrl = Join-ApiUrl $ApiBaseUrl $paths.logoutPath

$webLogin = Invoke-LoginPost "api:web-login-url" $webLoginUrl @{} $null
if ($webLogin -and $webLogin.code -eq 1 -and $webLogin.data.login_url) {
    Add-Check "api:web-login-url-data" "PASS" $webLogin.data.login_url
} elseif ($webLogin) {
    Add-Check "api:web-login-url-data" "FAIL" "Missing data.login_url"
}

$fakeNonce = "codex-login-check"
$desktopToken = Invoke-LoginPost "api:desktop-token-not-ready" $desktopTokenUrl @{
    client_type = "desktop"
    client_nonce = $fakeNonce
} $null
if ($desktopToken -and $desktopToken.code -eq 1 -and $desktopToken.data.token) {
    Add-Check "api:desktop-token-state" "WARN" "Unexpected token returned for fake nonce"
} elseif ($desktopToken) {
    Add-Check "api:desktop-token-state" "PASS" "No token for fake nonce, as expected"
}

$fakeToken = "codex-invalid-token"
Invoke-LoginPost "api:check-login-invalid-token" $checkLoginUrl @{ token = $fakeToken } $null | Out-Null
Invoke-LoginPost "api:user-info-invalid-token" $userInfoUrl @{} @{ token = $fakeToken } | Out-Null
Invoke-LoginPost "api:logout-invalid-token" $logoutUrl @{} @{ token = $fakeToken } | Out-Null

$failed = @($results | Where-Object { $_.Status -eq "FAIL" })
$report = New-Object System.Collections.Generic.List[string]
$report.Add("# KQ Remote Link Login Check")
$report.Add("")
$report.Add("- Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$report.Add("- ApiBaseUrl: $ApiBaseUrl")
$report.Add("- WebLoginUrl: $webLoginUrl")
$report.Add("- DesktopTokenUrl: $desktopTokenUrl")
$report.Add("- CheckLoginUrl: $checkLoginUrl")
$report.Add("- UserInfoUrl: $userInfoUrl")
$report.Add("- LogoutUrl: $logoutUrl")
$report.Add("")
$report.Add("| Status | Check | Detail |")
$report.Add("| --- | --- | --- |")
foreach ($result in $results) {
    $detail = ($result.Detail -replace "\|", "\\|")
    $report.Add("| $($result.Status) | $($result.Name) | $detail |")
}
$report.Add("")
$report.Add("This check proves endpoint reachability and response shape. Real account login still requires completing the browser flow.")

if (-not $NoReport) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ReportPath) | Out-Null
    [System.IO.File]::WriteAllLines($ReportPath, $report, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "Login check report: $ReportPath"
}

if ($failed.Count -gt 0) {
    throw "Login checks failed: $($failed.Count)"
}
