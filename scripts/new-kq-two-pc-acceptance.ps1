param(
    [ValidateSet("Controller", "Controlled")]
    [string]$Role = "Controlled",
    [string]$OutputRoot = "C:\kq-remote-link-tools",
    [string]$ReleaseDir,
    [string]$PackageZip,
    [string]$Tester,
    [string]$PeerId,
    [string]$RendezvousServer,
    [string]$RelayServer,
    [switch]$LaunchClient
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

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

function Write-Utf8($Path, [string[]]$Lines) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    [System.IO.File]::WriteAllLines($Path, $Lines, (New-Object System.Text.UTF8Encoding($false)))
}

function Add-CheckRow($Id, $Check, $Expected) {
    "| $Id | $Check | $Expected | TODO | |"
}

function Test-TcpTarget($Name, $Target) {
    if (-not $Target) {
        return [PSCustomObject]@{ Name = $Name; Target = ""; Result = "SKIP"; Detail = "not provided" }
    }
    $hostPart = $Target
    $portPart = $null
    if ($Target -match "^\[(.+)\]:(\d+)$") {
        $hostPart = $Matches[1]
        $portPart = [int]$Matches[2]
    } elseif ($Target -match "^(.+):(\d+)$") {
        $hostPart = $Matches[1]
        $portPart = [int]$Matches[2]
    }
    if (-not $portPart) {
        return [PSCustomObject]@{ Name = $Name; Target = $Target; Result = "SKIP"; Detail = "no port in target" }
    }
    try {
        $result = Test-NetConnection -ComputerName $hostPart -Port $portPart -WarningAction SilentlyContinue
        if ($result.TcpTestSucceeded) {
            return [PSCustomObject]@{ Name = $Name; Target = $Target; Result = "PASS"; Detail = "tcp reachable" }
        }
        return [PSCustomObject]@{ Name = $Name; Target = $Target; Result = "FAIL"; Detail = "tcp not reachable" }
    } catch {
        return [PSCustomObject]@{ Name = $Name; Target = $Target; Result = "FAIL"; Detail = $_.Exception.Message }
    }
}

$OutputRoot = Get-WritableOutputRoot $OutputRoot
if (-not $ReleaseDir) {
    $packagedRelease = Join-Path $repo "Release"
    if (Test-Path (Join-Path $packagedRelease "rustdesk.exe")) {
        $ReleaseDir = $packagedRelease
    } else {
        $ReleaseDir = Join-Path $repo "flutter\build\windows\x64\runner\Release"
    }
}

$release = Resolve-Path $ReleaseDir
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$sessionDir = Join-Path $OutputRoot "KQ-Remote-Link-two-pc-$Role-$timestamp"
New-Item -ItemType Directory -Force -Path $sessionDir | Out-Null

$manifestPath = Join-Path $repo "KQ_RELEASE_MANIFEST.json"
$manifest = $null
if (Test-Path $manifestPath) {
    $manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

$envLines = New-Object System.Collections.Generic.List[string]
$envLines.Add("# KQ Remote Link Two-PC Acceptance Environment")
$envLines.Add("")
$envLines.Add("- Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$envLines.Add("- Role: $Role")
$envLines.Add("- Tester: $Tester")
$envLines.Add("- ComputerName: $env:COMPUTERNAME")
$envLines.Add("- UserName: $env:USERNAME")
$envLines.Add("- OS: $([System.Environment]::OSVersion.VersionString)")
$envLines.Add("- PowerShell: $($PSVersionTable.PSVersion)")
$envLines.Add("- ReleaseDir: $($release.Path)")
if ($PackageZip) {
    $envLines.Add("- PackageZip: $PackageZip")
}
if ($manifest) {
    $envLines.Add("- ManifestAppName: $($manifest.appName)")
    $envLines.Add("- ManifestPackage: $($manifest.packageName)")
    $envLines.Add("- ManifestOAuthAuthorize: $($manifest.oauth.authorizeUrl)")
}
$envLines.Add("")
$envLines.Add("## Release Files")
$envLines.Add("")
$envLines.Add("| File | Size | SHA256 |")
$envLines.Add("| --- | ---: | --- |")
foreach ($file in @("rustdesk.exe", "librustdesk.dll", "flutter_windows.dll", "custom.txt")) {
    $path = Join-Path $release.Path $file
    if (Test-Path $path) {
        $item = Get-Item $path
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
        $envLines.Add("| $file | $($item.Length) | $hash |")
    } else {
        $envLines.Add("| $file | missing |  |")
    }
}
$envLines.Add("")
$envLines.Add("## Network Snapshot")
$envLines.Add("")
$envLines.Add("| Name | Value |")
$envLines.Add("| --- | --- |")
$envLines.Add("| DNS host name | $([System.Net.Dns]::GetHostName()) |")
try {
    $addresses = Get-NetIPConfiguration -ErrorAction Stop |
        ForEach-Object {
            $adapter = $_.InterfaceAlias
            $_.IPv4Address | ForEach-Object { "$adapter IPv4=$($_.IPAddress)" }
            $_.IPv6Address | ForEach-Object { "$adapter IPv6=$($_.IPAddress)" }
        }
    foreach ($address in $addresses) {
        $envLines.Add("| IP | $address |")
    }
} catch {
    $envLines.Add("| IP snapshot | unavailable: $($_.Exception.Message) |")
    try {
        $fallbackAddresses = [System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) |
            ForEach-Object { $_.IPAddressToString }
        foreach ($address in $fallbackAddresses) {
            $envLines.Add("| IP fallback | $address |")
        }
    } catch {
        $envLines.Add("| IP fallback | unavailable: $($_.Exception.Message) |")
    }
}

$tcpChecks = @(
    (Test-TcpTarget "Kunqiong OAuth HTTPS" "login.kunqiongai.com:443"),
    (Test-TcpTarget "Rendezvous server" $RendezvousServer),
    (Test-TcpTarget "Relay server" $RelayServer)
)
$envLines.Add("")
$envLines.Add("## Connectivity")
$envLines.Add("")
$envLines.Add("| Result | Name | Target | Detail |")
$envLines.Add("| --- | --- | --- | --- |")
foreach ($check in $tcpChecks) {
    $envLines.Add("| $($check.Result) | $($check.Name) | $($check.Target) | $($check.Detail) |")
}

Write-Utf8 (Join-Path $sessionDir "environment.md") $envLines

$checkLines = New-Object System.Collections.Generic.List[string]
$checkLines.Add("# KQ Remote Link Two-PC Acceptance Checklist")
$checkLines.Add("")
$checkLines.Add("- Role: $Role")
$checkLines.Add("- ComputerName: $env:COMPUTERNAME")
$checkLines.Add("- PeerId: $PeerId")
$checkLines.Add("- Tester: $Tester")
$checkLines.Add("- Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$checkLines.Add("")
if ($Role -eq "Controlled") {
    $checkLines.Add("## Controlled-Side Notes")
    $checkLines.Add("")
    $checkLines.Add("- Start the client and keep it open.")
    $checkLines.Add("- Record this machine's local ID and one-time password.")
    $checkLines.Add("- Keep the diagnostics folder if any test fails.")
} else {
    $checkLines.Add("## Controller-Side Notes")
    $checkLines.Add("")
    $checkLines.Add("- Start the client, enter the controlled machine ID, and connect.")
    $checkLines.Add("- Fill the result column while the controlled-side tester observes the desktop.")
}
$checkLines.Add("")
$checkLines.Add("## Values To Record")
$checkLines.Add("")
$checkLines.Add("| Item | Value |")
$checkLines.Add("| --- | --- |")
$checkLines.Add("| Controlled local ID | $PeerId |")
$checkLines.Add("| Controlled one-time password | |")
$checkLines.Add("| Controller public/network note | |")
$checkLines.Add("| Controlled public/network note | |")
$checkLines.Add("| Server mode | public / private |")
$checkLines.Add("")
$checkLines.Add("## Required Results")
$checkLines.Add("")
$checkLines.Add("| ID | Check | Expected | Result | Notes |")
$checkLines.Add("| --- | --- | --- | --- | --- |")
$checkLines.Add((Add-CheckRow "L1" "Launch" "Window title is KQ Remote Link and main screen is usable"))
$checkLines.Add((Add-CheckRow "L2" "Branding" "Top-left brand shows Kunqiong toolbox icon/text and top-right account badge"))
$checkLines.Add((Add-CheckRow "O1" "Kunqiong OAuth" "Clicking login opens Kunqiong OAuth directly and account badge updates after real login"))
$checkLines.Add((Add-CheckRow "R1" "Connection" "Controller connects to controlled client using ID and password"))
$checkLines.Add((Add-CheckRow "R2" "Remote screen" "Controller sees controlled desktop"))
$checkLines.Add((Add-CheckRow "R3" "Mouse" "Move, click, drag, and scroll work"))
$checkLines.Add((Add-CheckRow "R4" "Keyboard" "Typing, Enter, Backspace, Ctrl+C/Ctrl+V work"))
$checkLines.Add((Add-CheckRow "C1" "Clipboard controller-to-controlled" "Text copied on controller can paste on controlled side"))
$checkLines.Add((Add-CheckRow "C2" "Clipboard controlled-to-controller" "Text copied on controlled side can paste on controller"))
$checkLines.Add((Add-CheckRow "F1" "File transfer controller-to-controlled" "A small file transfers and opens correctly"))
$checkLines.Add((Add-CheckRow "F2" "File transfer controlled-to-controller" "A small file transfers and opens correctly"))
$checkLines.Add((Add-CheckRow "F3" "Chinese filenames" "A file with a Chinese name transfers without corruption"))
$checkLines.Add((Add-CheckRow "N1" "Same LAN" "Connection succeeds on the same LAN"))
$checkLines.Add((Add-CheckRow "N2" "Cross network" "Connection succeeds when clients are on different networks"))
$checkLines.Add((Add-CheckRow "N3" "Relay" "Connection still succeeds when direct connectivity is unavailable"))
$checkLines.Add("")
$checkLines.Add("## Issues")
$checkLines.Add("")
$checkLines.Add("| Severity | Description | Repro steps | Attachment |")
$checkLines.Add("| --- | --- | --- | --- |")
$checkLines.Add("|  |  |  |  |")

Write-Utf8 (Join-Path $sessionDir "role-checklist.md") $checkLines

$quickStart = @(
    "KQ Remote Link two-PC acceptance",
    "",
    "Role: $Role",
    "1. Open environment.md and confirm release files/network checks.",
    "2. Start Release\rustdesk.exe if it is not already running.",
    "3. Fill role-checklist.md during the live two-PC test.",
    "4. If a test fails, run COLLECT_DIAGNOSTICS.cmd from the package root on both PCs.",
    "",
    "Session folder:",
    $sessionDir
)
Write-Utf8 (Join-Path $sessionDir "README.txt") $quickStart

if ($LaunchClient) {
    $exe = Join-Path $release.Path "rustdesk.exe"
    if (-not (Test-Path $exe)) {
        throw "Cannot launch client, rustdesk.exe not found: $exe"
    }
    Start-Process -FilePath $exe -WorkingDirectory $release.Path | Out-Null
}

Get-Item $sessionDir | Select-Object FullName, LastWriteTime
