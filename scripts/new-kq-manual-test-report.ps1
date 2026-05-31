param(
    [string]$OutputRoot = "C:\kq-remote-link-tools",
    [string]$PackageZip,
    [string]$Tester,
    [string]$Controller,
    [string]$Controlled,
    [string]$Network = "same-lan / cross-network / private-server",
    [string]$ServerMode = "public / private",
    [string]$ReportPath
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

$OutputRoot = Get-WritableOutputRoot $OutputRoot
if (-not $ReportPath) {
    $ReportPath = Join-Path $OutputRoot "KQ-Remote-Link-manual-test-$(Get-Date -Format 'yyyyMMdd-HHmm').md"
}

$manifestPath = Join-Path $repo "KQ_RELEASE_MANIFEST.json"
$packageLine = ""
if ($PackageZip) {
    $packageLine = $PackageZip
} elseif (Test-Path $manifestPath) {
    $packageLine = (Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json).packageName
}

function New-Case($Id, $Name, $Expected) {
    "| $Id | $Name | $Expected | TODO | |"
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# KQ Remote Link Manual Test Report")
$lines.Add("")
$lines.Add("## Environment")
$lines.Add("")
$lines.Add("| Item | Value |")
$lines.Add("| --- | --- |")
$lines.Add("| Package | $packageLine |")
$lines.Add("| Controller PC | $Controller |")
$lines.Add("| Controlled PC | $Controlled |")
$lines.Add("| Network | $Network |")
$lines.Add("| Server mode | $ServerMode |")
$lines.Add("| Test time | $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') |")
$lines.Add("| Tester | $Tester |")
$lines.Add("")
$lines.Add("## Automated Checks")
$lines.Add("")
$lines.Add("| ID | Check | Expected | Result | Notes |")
$lines.Add("| --- | --- | --- | --- | --- |")
$lines.Add((New-Case "A1" "test-kq-release.ps1" "No FAIL results"))
$lines.Add((New-Case "A2" "test-kq-oauth.ps1" "Authorize page, token host, and port 6613 are available"))
$lines.Add((New-Case "A3" "test-kq-server.ps1" "Private server TCP ports are reachable"))
$lines.Add((New-Case "A4" "collect-kq-diagnostics.ps1" "Diagnostics zip can be generated"))
$lines.Add("")
$lines.Add("## Feature Acceptance")
$lines.Add("")
$lines.Add("| ID | Check | Expected | Result | Notes |")
$lines.Add("| --- | --- | --- | --- | --- |")
$lines.Add((New-Case "S1" "Launch client" "Window title is 鲲穹远程桌面"))
$lines.Add((New-Case "S2" "Local ID and one-time password" "Both are visible"))
$lines.Add((New-Case "O1" "Kunqiong OAuth login" "Real account login succeeds and user info is visible"))
$lines.Add((New-Case "R1" "Password connection" "Controller connects to controlled client"))
$lines.Add((New-Case "R2" "Remote screen" "Controller can see controlled desktop"))
$lines.Add((New-Case "R3" "Mouse control" "Move, click, and drag work"))
$lines.Add((New-Case "R4" "Keyboard control" "Typing and shortcuts work"))
$lines.Add((New-Case "C1" "Clipboard" "Text copy-paste works both ways"))
$lines.Add((New-Case "F1" "File transfer" "Small files transfer both ways"))
$lines.Add((New-Case "F2" "Chinese file names" "Transferred names are not corrupted"))
$lines.Add((New-Case "N1" "Same-LAN connection" "Connection succeeds with acceptable latency"))
$lines.Add((New-Case "N2" "Cross-network connection" "Connection succeeds"))
$lines.Add((New-Case "N3" "Relay connection" "hbbr relay works when direct connection is unavailable"))
$lines.Add("")
$lines.Add("## Issues")
$lines.Add("")
$lines.Add("| ID | Severity | Description | Repro steps | Attachment/diagnostics |")
$lines.Add("| --- | --- | --- | --- | --- |")
$lines.Add("|  |  |  |  |  |")
$lines.Add("")
$lines.Add("## Conclusion")
$lines.Add("")
$lines.Add("| Item | Value |")
$lines.Add("| --- | --- |")
$lines.Add("| Result | TODO: Pass / Conditional pass / Fail |")
$lines.Add("| Blocking issues | |")
$lines.Add("| Must fix | |")
$lines.Add("| Follow-up improvements | |")

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ReportPath) | Out-Null
[System.IO.File]::WriteAllLines($ReportPath, $lines, (New-Object System.Text.UTF8Encoding($false)))
Get-Item $ReportPath | Select-Object FullName, Length, LastWriteTime
