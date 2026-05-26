param(
    [string]$ConfigJson,
    [string]$RendezvousServer,
    [string]$RelayServer,
    [string]$ApiServer,
    [string]$ServerKey,
    [int]$TimeoutMs = 3000,
    [string]$ReportPath,
    [switch]$NoReport
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

if (-not $ReportPath) {
    $ReportPath = Join-Path "C:\kq-remote-link-tools" "KQ-Remote-Link-server-check-$(Get-Date -Format 'yyyyMMdd-HHmm').md"
}

if ($ConfigJson) {
    $json = Get-Content $ConfigJson -Raw -Encoding UTF8 | ConvertFrom-Json
    $settings = $json."default-settings"
    if (-not $RendezvousServer) {
        $RendezvousServer = $settings."custom-rendezvous-server"
    }
    if (-not $RelayServer) {
        $RelayServer = $settings."relay-server"
    }
    if (-not $ApiServer) {
        $ApiServer = $settings."api-server"
    }
    if (-not $ServerKey) {
        $ServerKey = $settings."key"
    }
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

function Split-HostPort($Value, $DefaultPort) {
    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "Server value is required."
    }
    $value = $Value.Trim()
    if ($value -match "^\[(.+)\]:(\d+)$") {
        return [PSCustomObject]@{ Host = $Matches[1]; Port = [int]$Matches[2] }
    }
    $lastColon = $value.LastIndexOf(":")
    if ($lastColon -gt 0 -and $value.IndexOf(":") -eq $lastColon) {
        return [PSCustomObject]@{
            Host = $value.Substring(0, $lastColon)
            Port = [int]$value.Substring($lastColon + 1)
        }
    }
    return [PSCustomObject]@{ Host = $value; Port = $DefaultPort }
}

function Test-TcpPort($Name, $HostName, $Port) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $task = $client.ConnectAsync($HostName, $Port)
        if (-not $task.Wait($TimeoutMs)) {
            Add-Check $Name "FAIL" "TCP ${HostName}:${Port} timed out after ${TimeoutMs}ms"
            return
        }
        if ($task.IsFaulted) {
            Add-Check $Name "FAIL" $task.Exception.InnerException.Message
            return
        }
        Add-Check $Name "PASS" "TCP ${HostName}:${Port} reachable"
    } catch {
        Add-Check $Name "FAIL" $_.Exception.Message
    } finally {
        $client.Dispose()
    }
}

function Test-Dns($Name, $HostName) {
    try {
        $addresses = [System.Net.Dns]::GetHostAddresses($HostName)
        if ($addresses.Count -gt 0) {
            Add-Check $Name "PASS" (($addresses | Select-Object -First 4) -join ", ")
        } else {
            Add-Check $Name "FAIL" "No addresses returned"
        }
    } catch {
        Add-Check $Name "FAIL" $_.Exception.Message
    }
}

function Test-UdpSend($Name, $HostName, $Port) {
    $udp = New-Object System.Net.Sockets.UdpClient
    try {
        $payload = [System.Text.Encoding]::ASCII.GetBytes("kq-remote-link-check")
        $udp.Connect($HostName, $Port)
        [void]$udp.Send($payload, $payload.Length)
        Add-Check $Name "WARN" "UDP ${HostName}:${Port} send succeeded; UDP reachability still needs real client test"
    } catch {
        Add-Check $Name "FAIL" $_.Exception.Message
    } finally {
        $udp.Dispose()
    }
}

function Test-Http($Name, $Url) {
    if ([string]::IsNullOrWhiteSpace($Url)) {
        Add-Check $Name "WARN" "No API server configured"
        return
    }
    try {
        $response = Invoke-WebRequest -Uri $Url -Method Head -TimeoutSec ([Math]::Max(1, [int][Math]::Ceiling($TimeoutMs / 1000))) -UseBasicParsing
        Add-Check $Name "PASS" "HTTP $($response.StatusCode)"
    } catch {
        $status = $_.Exception.Response.StatusCode.value__
        if ($status) {
            Add-Check $Name "WARN" "HTTP returned $status; endpoint is reachable but may not support HEAD"
        } else {
            Add-Check $Name "FAIL" $_.Exception.Message
        }
    }
}

function Test-ServerKey($Name, $Key) {
    if ([string]::IsNullOrWhiteSpace($Key) -or $Key -match "PASTE_|<|>") {
        Add-Check $Name "WARN" "Server key is required for private-server client packaging. Ask ops to return: cat /www/wwwroot/KQromoteLink/data/id_ed25519.pub"
        return
    }
    try {
        $bytes = [Convert]::FromBase64String($Key.Trim())
        if ($bytes.Length -eq 32) {
            Add-Check $Name "PASS" "Valid 32-byte base64 RustDesk server public key"
        } else {
            Add-Check $Name "FAIL" "Expected 32 decoded bytes, got $($bytes.Length)"
        }
    } catch {
        Add-Check $Name "FAIL" "Server key is not valid base64: $($_.Exception.Message)"
    }
}

$hbbs = Split-HostPort $RendezvousServer 21116
$hbbr = Split-HostPort $RelayServer 21117

Test-Dns "dns:hbbs" $hbbs.Host
Test-Dns "dns:hbbr" $hbbr.Host
Test-TcpPort "tcp:hbbs-nat:21115" $hbbs.Host 21115
Test-TcpPort "tcp:hbbs" $hbbs.Host $hbbs.Port
Test-UdpSend "udp:hbbs" $hbbs.Host $hbbs.Port
Test-TcpPort "tcp:hbbr" $hbbr.Host $hbbr.Port
Test-Http "http:api-server" $ApiServer
Test-ServerKey "server-key:hbbs-public-key" $ServerKey

$failed = @($results | Where-Object { $_.Status -eq "FAIL" })
$report = New-Object System.Collections.Generic.List[string]
$report.Add("# KQ Remote Link Server Check")
$report.Add("")
$report.Add("- Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$report.Add("- RendezvousServer: $RendezvousServer")
$report.Add("- RelayServer: $RelayServer")
if ($ApiServer) {
    $report.Add("- ApiServer: $ApiServer")
}
if ($ServerKey) {
    $report.Add("- ServerKeyProvided: yes")
} else {
    $report.Add("- ServerKeyProvided: no")
}
$report.Add("")
$report.Add("| Status | Check | Detail |")
$report.Add("| --- | --- | --- |")
foreach ($result in $results) {
    $detail = ($result.Detail -replace "\|", "\\|")
    $report.Add("| $($result.Status) | $($result.Name) | $detail |")
}
$report.Add("")
$report.Add("UDP checks cannot prove hole punching by themselves. Always finish with a two-client connection test.")
$report.Add("For private-server client packaging, the hbbs public key is required. On the server, read it with:")
$report.Add("")
$report.Add('```bash')
$report.Add("cat /www/wwwroot/KQromoteLink/data/id_ed25519.pub")
$report.Add('```')

if (-not $NoReport) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ReportPath) | Out-Null
    [System.IO.File]::WriteAllLines($ReportPath, $report, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "Server check report: $ReportPath"
}

if ($failed.Count -gt 0) {
    throw "Server checks failed: $($failed.Count)"
}
