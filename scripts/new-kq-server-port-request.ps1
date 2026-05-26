param(
    [string]$OutputRoot = "C:\kq-remote-link-tools",
    [string]$ServerHost = "remote.example.com",
    [string]$PublicIp = "",
    [string]$Requester = "",
    [string]$Environment = "test / production",
    [string]$ReportPath,
    [switch]$IncludeOptionalApiPort
)

$ErrorActionPreference = "Stop"

function Get-WritableOutputRoot($PreferredPath) {
    $errors = New-Object System.Collections.Generic.List[string]
    foreach ($candidate in @($PreferredPath, (Join-Path $env:TEMP ("kq-remote-link-tools-" + [guid]::NewGuid().ToString("N"))))) {
        try {
            $dir = New-Item -ItemType Directory -Force -Path $candidate
            $probe = Join-Path $dir.FullName ("write-test-" + [guid]::NewGuid().ToString("N"))
            [System.IO.File]::WriteAllText($probe, "ok")
            Remove-Item -LiteralPath $probe -Force
            return $dir.FullName
        } catch {
            $errors.Add("${candidate}: $($_.Exception.Message)")
            continue
        }
    }
    throw "No writable output directory found. Tried: $($errors -join '; ')"
}

$OutputRoot = Get-WritableOutputRoot $OutputRoot
if (-not $ReportPath) {
    $ReportPath = Join-Path $OutputRoot "KQ-Remote-Link-server-port-request-$(Get-Date -Format 'yyyyMMdd-HHmm').md"
}

$ports = @(
    [PSCustomObject]@{ Port = "21115"; Protocol = "TCP"; Required = "yes"; Purpose = "hbbs NAT type test" },
    [PSCustomObject]@{ Port = "21116"; Protocol = "TCP"; Required = "yes"; Purpose = "hbbs ID/rendezvous service" },
    [PSCustomObject]@{ Port = "21116"; Protocol = "UDP"; Required = "yes"; Purpose = "hbbs UDP hole punching and direct-connection assist" },
    [PSCustomObject]@{ Port = "21117"; Protocol = "TCP"; Required = "yes"; Purpose = "hbbr relay traffic" },
    [PSCustomObject]@{ Port = "21118"; Protocol = "TCP"; Required = "recommended"; Purpose = "web client / websocket support if enabled later" },
    [PSCustomObject]@{ Port = "21119"; Protocol = "TCP"; Required = "recommended"; Purpose = "web relay / websocket support if enabled later" }
)
if ($IncludeOptionalApiPort) {
    $ports += [PSCustomObject]@{ Port = "21114"; Protocol = "TCP"; Required = "optional"; Purpose = "RustDesk Pro/API-compatible service if introduced later" }
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# KQ Remote Link hbbs/hbbr Port Request")
$lines.Add("")
$lines.Add("| Item | Value |")
$lines.Add("| --- | --- |")
$lines.Add("| Requester | $Requester |")
$lines.Add("| Environment | $Environment |")
$lines.Add("| Server host/domain | $ServerHost |")
$lines.Add("| Public IP | $PublicIp |")
$lines.Add("| Generated | $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') |")
$lines.Add("")
$lines.Add("## Firewall / Security Group Rules")
$lines.Add("")
$lines.Add("| Port | Protocol | Required | Purpose |")
$lines.Add("| --- | --- | --- | --- |")
foreach ($port in $ports) {
    $lines.Add("| $($port.Port) | $($port.Protocol) | $($port.Required) | $($port.Purpose) |")
}
$lines.Add("")
$lines.Add("## Minimal Required Set")
$lines.Add("")
$lines.Add("- TCP 21115")
$lines.Add("- TCP 21116")
$lines.Add("- UDP 21116")
$lines.Add("- TCP 21117")
$lines.Add("")
$lines.Add("## Recommended Set")
$lines.Add("")
$lines.Add("- TCP 21115-21119")
$lines.Add("- UDP 21116")
if ($IncludeOptionalApiPort) {
    $lines.Add("- TCP 21114")
}
$lines.Add("")
$lines.Add("## Notes For Ops")
$lines.Add("")
$lines.Add("- Server process: RustDesk OSS server, `hbbs` and `hbbr`.")
$lines.Add("- Deployment mode: Docker Compose with host networking on Linux.")
$lines.Add("- Traffic direction: clients on internet/LAN initiate traffic to the server.")
$lines.Add("- `21116/udp` is required for hole punching; do not approve TCP-only rules.")
$lines.Add("- If a host firewall is enabled on the server, mirror the same rules there.")
$lines.Add("")
$lines.Add("After the rules are open, run:")
$lines.Add("")
$lines.Add('```powershell')
$lines.Add('powershell -ExecutionPolicy Bypass -File .\scripts\test-kq-server.ps1 `')
$lines.Add('  -RendezvousServer "' + $ServerHost + ':21116" `')
$lines.Add('  -RelayServer "' + $ServerHost + ':21117"')
$lines.Add('```')

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ReportPath) | Out-Null
[System.IO.File]::WriteAllLines($ReportPath, $lines, (New-Object System.Text.UTF8Encoding($false)))
Get-Item $ReportPath | Select-Object FullName, Length, LastWriteTime
