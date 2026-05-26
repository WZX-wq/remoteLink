param(
    [string]$PackageZip,
    [string]$OutputRoot = "C:\kq-remote-link-tools",
    [string]$RendezvousServer,
    [string]$RelayServer,
    [string]$ApiServer,
    [switch]$SkipOAuth,
    [switch]$SkipDiagnostics,
    [switch]$SkipManualReport,
    [switch]$LaunchSmokeTest,
    [switch]$StopExistingRustDesk,
    [switch]$NoReport
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

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
if (-not $NoReport) {
    $OutputRoot = Get-WritableOutputRoot $OutputRoot
    $suiteDir = Join-Path $OutputRoot "KQ-Remote-Link-smoke-suite-$timestamp"
    New-Item -ItemType Directory -Force -Path $suiteDir | Out-Null
} else {
    $suiteDir = $null
}

function Invoke-SuiteStep($Name, [scriptblock]$Body) {
    Write-Host "==> $Name"
    try {
        & $Body
        [PSCustomObject]@{ Name = $Name; Status = "PASS"; Detail = "" }
    } catch {
        [PSCustomObject]@{ Name = $Name; Status = "FAIL"; Detail = $_.Exception.Message }
    }
}

$results = New-Object System.Collections.Generic.List[object]

$releaseArgs = @{
    NoReport = $NoReport
}
if ($suiteDir) {
    $releaseArgs.ReportPath = Join-Path $suiteDir "release-check.md"
}
if ($PackageZip) {
    $releaseArgs.PackageZip = $PackageZip
}
if ($LaunchSmokeTest) {
    $releaseArgs.LaunchSmokeTest = $true
}
if ($StopExistingRustDesk) {
    $releaseArgs.StopExistingRustDesk = $true
}

$results.Add((Invoke-SuiteStep "release-check" {
    & "$PSScriptRoot\test-kq-release.ps1" @releaseArgs
}))

if (-not $SkipOAuth) {
    $results.Add((Invoke-SuiteStep "oauth-check" {
        $oauthArgs = @{ NoReport = $NoReport }
        if ($suiteDir) {
            $oauthArgs.ReportPath = Join-Path $suiteDir "oauth-check.md"
        }
        & "$PSScriptRoot\test-kq-oauth.ps1" @oauthArgs
    }))
}

if ($RendezvousServer -or $RelayServer) {
    $results.Add((Invoke-SuiteStep "server-check" {
        if (-not $RendezvousServer -or -not $RelayServer) {
            throw "Both -RendezvousServer and -RelayServer are required for server-check."
        }
        $serverArgs = @{
            RendezvousServer = $RendezvousServer
            RelayServer = $RelayServer
            NoReport = $NoReport
        }
        if ($suiteDir) {
            $serverArgs.ReportPath = Join-Path $suiteDir "server-check.md"
        }
        if ($ApiServer) {
            $serverArgs.ApiServer = $ApiServer
        }
        & "$PSScriptRoot\test-kq-server.ps1" @serverArgs
    }))
}

if (-not $SkipManualReport -and -not $NoReport) {
    $results.Add((Invoke-SuiteStep "manual-report-template" {
        $manualArgs = @{
            ReportPath = Join-Path $suiteDir "manual-test-report.md"
        }
        if ($PackageZip) {
            $manualArgs.PackageZip = $PackageZip
        }
        & "$PSScriptRoot\new-kq-manual-test-report.ps1" @manualArgs
    }))
}

if (-not $SkipDiagnostics -and -not $NoReport) {
    $results.Add((Invoke-SuiteStep "diagnostics" {
        & "$PSScriptRoot\collect-kq-diagnostics.ps1" -OutputRoot $suiteDir -MaxLogFiles 5
    }))
}

$summary = New-Object System.Collections.Generic.List[string]
$summary.Add("# KQ Remote Link Smoke Suite")
$summary.Add("")
$summary.Add("- Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
if ($PackageZip) {
    $summary.Add("- PackageZip: $PackageZip")
}
$summary.Add("")
$summary.Add("| Status | Step | Detail |")
$summary.Add("| --- | --- | --- |")
foreach ($result in $results) {
    $detail = ($result.Detail -replace "\|", "\\|")
    $summary.Add("| $($result.Status) | $($result.Name) | $detail |")
}

if ($suiteDir) {
    $summaryPath = Join-Path $suiteDir "summary.md"
    [System.IO.File]::WriteAllLines($summaryPath, $summary, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "Smoke suite summary: $summaryPath"
} else {
    $summary | ForEach-Object { Write-Host $_ }
}

$failed = @($results | Where-Object { $_.Status -eq "FAIL" })
if ($failed.Count -gt 0) {
    throw "Smoke suite failed: $($failed.Count) step(s)"
}
