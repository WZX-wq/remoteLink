param(
    [string]$ReleaseDir,
    [string]$OutputRoot = "C:\kq-remote-link-tools",
    [int]$MaxLogFiles = 10,
    [switch]$SkipLogs
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
if (-not $ReleaseDir) {
    $packagedRelease = Join-Path $repo "Release"
    if (Test-Path (Join-Path $packagedRelease "rustdesk.exe")) {
        $ReleaseDir = $packagedRelease
    } else {
        $ReleaseDir = Join-Path $repo "flutter\build\windows\x64\runner\Release"
    }
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$output = New-Item -ItemType Directory -Force -Path $OutputRoot
$stage = Join-Path $output.FullName "KQ-Remote-Link-diagnostics-$timestamp"
$zip = "$stage.zip"

if (Test-Path $stage) {
    Remove-Item -LiteralPath $stage -Recurse -Force
}
if (Test-Path $zip) {
    Remove-Item -LiteralPath $zip -Force
}
New-Item -ItemType Directory -Path $stage | Out-Null

function Write-Text($RelativePath, $Lines) {
    $path = Join-Path $stage $RelativePath
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
    [System.IO.File]::WriteAllLines($path, [string[]]$Lines, (New-Object System.Text.UTF8Encoding($false)))
}

function Add-FileIfExists($Source, $RelativeDestination) {
    if (Test-Path $Source) {
        $destination = Join-Path $stage $RelativeDestination
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
        Copy-Item -LiteralPath $Source -Destination $destination -Force
    }
}

function Redact-Line($Line) {
    if ($Line -match '^\s*(password|salt|key_pair|access_token|refresh_token|client_secret|secret|trusted_devices|user_info)\s*=') {
        return (($Line -split '=', 2)[0] + '= "<redacted>"')
    }
    return $Line
}

$release = Resolve-Path $ReleaseDir
$appName = [string]::Concat([char[]]@(
    0x9CB2,
    0x7A79,
    0x8FDC,
    0x7A0B,
    0x684C,
    0x9762
))
$appData = Join-Path $env:APPDATA $appName
$configDir = Join-Path $appData "config"
$logDir = Join-Path $appData "log"

$summary = New-Object System.Collections.Generic.List[string]
$summary.Add("# KQ Remote Link Diagnostics")
$summary.Add("")
$summary.Add("- Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$summary.Add("- ComputerName: $env:COMPUTERNAME")
$summary.Add("- UserName: $env:USERNAME")
$summary.Add("- ReleaseDir: $($release.Path)")
$summary.Add("- AppData: $appData")
$summary.Add("- OS: $([System.Environment]::OSVersion.VersionString)")
$summary.Add("- PowerShell: $($PSVersionTable.PSVersion)")

foreach ($file in @("rustdesk.exe", "librustdesk.dll", "flutter_windows.dll", "custom.txt")) {
    $path = Join-Path $release.Path $file
    if (Test-Path $path) {
        $item = Get-Item $path
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
        $summary.Add("- ReleaseFile: $file size=$($item.Length) sha256=$hash")
    } else {
        $summary.Add("- ReleaseFileMissing: $file")
    }
}

Write-Text "summary.md" $summary

Add-FileIfExists (Join-Path $repo "KQ_RELEASE_MANIFEST.json") "release\KQ_RELEASE_MANIFEST.json"
Add-FileIfExists (Join-Path $release.Path "..\KQ_RELEASE_MANIFEST.json") "release\KQ_RELEASE_MANIFEST.json"

$processes = Get-Process rustdesk -ErrorAction SilentlyContinue |
    Select-Object Id, ProcessName, MainWindowTitle, Path, StartTime, Responding
Write-Text "processes.txt" ($processes | Format-List | Out-String)

if (Test-Path $configDir) {
    $configFiles = Get-ChildItem $configDir -Recurse -File |
        Select-Object FullName, Length, LastWriteTime
    Write-Text "config\inventory.txt" ($configFiles | Format-Table -AutoSize | Out-String)

    foreach ($name in @("${appName}2.toml", "${appName}_local.toml")) {
        $path = Join-Path $configDir $name
        if (Test-Path $path) {
            $redacted = Get-Content $path -Encoding UTF8 | ForEach-Object { Redact-Line $_ }
            Write-Text "config\$name.redacted.txt" $redacted
        }
    }
} else {
    Write-Text "config\inventory.txt" @("Config directory not found: $configDir")
}

if (-not $SkipLogs) {
    if (Test-Path $logDir) {
        $logStage = Join-Path $stage "log"
        New-Item -ItemType Directory -Force -Path $logStage | Out-Null
        Get-ChildItem $logDir -File |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First $MaxLogFiles |
            ForEach-Object {
                Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $logStage $_.Name) -Force
            }
    } else {
        Write-Text "log\inventory.txt" @("Log directory not found: $logDir")
    }
}

try {
    $connections = Get-NetTCPConnection -ErrorAction Stop |
        Where-Object { $_.LocalPort -in @(21115, 21116, 21117, 21118, 21119, 6613) -or $_.RemotePort -in @(21115, 21116, 21117, 21118, 21119, 6613) } |
        Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, State, OwningProcess
    Write-Text "network\tcp-connections.txt" ($connections | Format-Table -AutoSize | Out-String)
} catch {
    Write-Text "network\tcp-connections.txt" @("Get-NetTCPConnection failed: $($_.Exception.Message)")
}

try {
    $ipconfig = ipconfig /all
    Write-Text "network\ipconfig.txt" $ipconfig
} catch {
    Write-Text "network\ipconfig.txt" @("ipconfig failed: $($_.Exception.Message)")
}

Add-FileIfExists (Join-Path $repo "TESTING_KQ_REMOTE_LINK.md") "docs\TESTING_KQ_REMOTE_LINK.md"
Add-FileIfExists (Join-Path $repo "SERVER_DEPLOYMENT.md") "docs\SERVER_DEPLOYMENT.md"

Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zip -CompressionLevel Optimal
Get-Item $zip | Select-Object FullName, Length, LastWriteTime
