param(
    [string]$ReleaseDir,
    [string]$OutputRoot = "C:\kq-remote-link-tools",
    [string]$PackageName,
    [string]$CustomTxt,
    [switch]$LaunchSmokeTest,
    [switch]$StopExistingRustDesk
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

function Invoke-WithRetry($Name, [scriptblock]$Body, [int]$Attempts = 5, [int]$DelaySeconds = 2) {
    for ($i = 1; $i -le $Attempts; $i++) {
        try {
            & $Body
            return
        } catch {
            if ($i -ge $Attempts) {
                throw
            }
            Write-Host "$Name failed on attempt $i/${Attempts}: $($_.Exception.Message)"
            Start-Sleep -Seconds $DelaySeconds
        }
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
if (-not $PackageName) {
    $PackageName = "KQ-Remote-Link-test-$(Get-Date -Format 'yyyyMMdd-HHmm')"
}

$release = Resolve-Path $ReleaseDir
$output = New-Item -ItemType Directory -Force -Path $OutputRoot
$stage = Join-Path $output.FullName $PackageName
$zip = Join-Path $output.FullName "$PackageName.zip"

$required = @(
    "rustdesk.exe",
    "librustdesk.dll",
    "flutter_windows.dll",
    "data\flutter_assets\AssetManifest.bin",
    "data\flutter_assets\assets\kq_toolbox_icon.svg"
)

foreach ($item in $required) {
    $path = Join-Path $release.Path $item
    if (-not (Test-Path $path)) {
        throw "Missing release artifact: $path"
    }
}

if (Test-Path $stage) {
    $resolvedStage = (Resolve-Path $stage).Path
    if (-not $resolvedStage.StartsWith($output.FullName, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove unexpected staging path: $resolvedStage"
    }
    Remove-Item -LiteralPath $resolvedStage -Recurse -Force
}
if (Test-Path $zip) {
    Remove-Item -LiteralPath $zip -Force
}

New-Item -ItemType Directory -Path $stage | Out-Null
$stagedRelease = Join-Path $stage "Release"
Copy-Item -LiteralPath $release.Path -Destination $stagedRelease -Recurse

if ($CustomTxt) {
    $customTxtPath = Resolve-Path $CustomTxt
    if ((Get-Item $customTxtPath.Path).Length -le 0) {
        throw "CustomTxt is empty: $($customTxtPath.Path)"
    }
    Copy-Item -LiteralPath $customTxtPath.Path -Destination (Join-Path $stagedRelease "custom.txt") -Force
}

$kqLoginButton = [string]::Concat([char[]]@(
    0x4F7F,
    0x7528,
    0x9CB2,
    0x7A79,
    0x8D26,
    0x53F7,
    0x767B,
    0x5F55
))
$kqAppName = [string]::Concat([char[]]@(
    0x9CB2,
    0x7A79,
    0x8FDC,
    0x7A0B,
    0x684C,
    0x9762
))
$kqTitleBrand = $kqAppName
$exeHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $stagedRelease "rustdesk.exe")).Hash.ToLowerInvariant()
$dllHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $stagedRelease "librustdesk.dll")).Hash.ToLowerInvariant()
$manifest = [ordered]@{
    "appName" = $kqAppName
    "packageName" = $PackageName
    "generatedAt" = (Get-Date).ToString("o")
    "release" = [ordered]@{
        "rustdeskExeSha256" = $exeHash
        "librustdeskDllSha256" = $dllHash
        "hasCustomTxt" = [bool]$CustomTxt
    }
    "oauth" = [ordered]@{
        "provider" = "kunqiong"
        "loginButtonText" = $kqLoginButton
        "authorizeUrl" = "https://login.kunqiongai.com/authorize.html"
        "tokenUrl" = "https://login.kunqiongai.com/api/oauth/token"
        "redirectUri" = "http://localhost:6613/oauth/callback"
    }
    "ui" = [ordered]@{
        "titleBrandText" = $kqTitleBrand
        "titleBrandIcon" = "assets/icon.png"
    }
    "manualVerificationRequired" = @(
        "real Kunqiong OAuth account login",
        "two-client remote screen control",
        "keyboard and mouse input",
        "clipboard sync",
        "file transfer",
        "cross-network relay"
    )
}
$manifestJson = $manifest | ConvertTo-Json -Depth 6
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $stage "KQ_RELEASE_MANIFEST.json"), "$manifestJson`n", $utf8NoBom)

$launcherFiles = @{
    "START_KQ_REMOTE_LINK.cmd" = @(
        "@echo off",
        "cd /d ""%~dp0Release""",
        "start """" rustdesk.exe"
    )
    "RUN_SMOKE_CHECKS.cmd" = @(
        "@echo off",
        "cd /d ""%~dp0""",
        "powershell -ExecutionPolicy Bypass -File ""%~dp0scripts\run-kq-smoke-suite.ps1""",
        "pause"
    )
    "CREATE_MANUAL_TEST_REPORT.cmd" = @(
        "@echo off",
        "cd /d ""%~dp0""",
        "powershell -ExecutionPolicy Bypass -File ""%~dp0scripts\new-kq-manual-test-report.ps1"" -OutputRoot ""%~dp0reports""",
        "pause"
    )
    "CREATE_TWO_PC_ACCEPTANCE.cmd" = @(
        "@echo off",
        "cd /d ""%~dp0""",
        "powershell -ExecutionPolicy Bypass -File ""%~dp0scripts\new-kq-two-pc-acceptance.ps1"" -OutputRoot ""%~dp0reports""",
        "pause"
    )
    "COLLECT_DIAGNOSTICS.cmd" = @(
        "@echo off",
        "cd /d ""%~dp0""",
        "powershell -ExecutionPolicy Bypass -File ""%~dp0scripts\collect-kq-diagnostics.ps1"" -OutputRoot ""%~dp0reports""",
        "pause"
    )
    "README_START_HERE.txt" = @(
        "KQ Remote Link test package",
        "",
        "1. Double-click START_KQ_REMOTE_LINK.cmd to launch the client.",
        "2. Copy this whole extracted folder to a second Windows PC and launch both clients.",
        "3. Use the ID and one-time password shown on the controlled PC to connect from the controller PC.",
        "4. Verify remote screen, mouse, keyboard, clipboard, file transfer, same-LAN, and cross-network relay.",
        "5. Double-click RUN_SMOKE_CHECKS.cmd for automated local checks.",
        "6. Double-click CREATE_MANUAL_TEST_REPORT.cmd before two-client testing to create a fillable report.",
        "7. Double-click CREATE_TWO_PC_ACCEPTANCE.cmd on each PC to create role-specific evidence folders.",
        "8. If a test fails, double-click COLLECT_DIAGNOSTICS.cmd and send the generated zip from the reports folder.",
        "9. For private hbbs/hbbr packaging, see SERVER_DEPLOYMENT.md and scripts\new-kq-private-server-client-package.ps1.",
        "",
        "Detailed docs: TESTING_KQ_REMOTE_LINK.md, ACCEPTANCE_CHECKLIST.md, SERVER_DEPLOYMENT.md"
    )
}
foreach ($launcher in $launcherFiles.GetEnumerator()) {
    [System.IO.File]::WriteAllLines((Join-Path $stage $launcher.Key), $launcher.Value, $utf8NoBom)
}

$docs = @(
    "docs\TESTING_KQ_REMOTE_LINK.md",
    "docs\ACCEPTANCE_CHECKLIST.md",
    "docs\GITEA_SERVER_DEPLOYMENT.md",
    "docs\SERVER_DEPLOYMENT.md",
    "docs\KQ_REMOTE_LINK.md"
)
foreach ($doc in $docs) {
    $source = Join-Path $repo $doc
    if (Test-Path $source) {
        Copy-Item -LiteralPath $source -Destination (Join-Path $stage (Split-Path -Leaf $doc))
    }
}

New-Item -ItemType Directory -Path (Join-Path $stage "deploy") | Out-Null
Copy-Item -LiteralPath (Join-Path $repo "deploy\rustdesk-server.compose.yml") -Destination (Join-Path $stage "deploy\rustdesk-server.compose.yml")
Copy-Item -LiteralPath (Join-Path $repo "deploy\deploy-rustdesk-server.sh") -Destination (Join-Path $stage "deploy\deploy-rustdesk-server.sh")
Copy-Item -LiteralPath (Join-Path $repo "deploy\check-rustdesk-server.sh") -Destination (Join-Path $stage "deploy\check-rustdesk-server.sh")
Copy-Item -LiteralPath (Join-Path $repo "deploy\export-hbbs-public-key.sh") -Destination (Join-Path $stage "deploy\export-hbbs-public-key.sh")
Copy-Item -LiteralPath (Join-Path $repo "deploy\custom-client.example.json") -Destination (Join-Path $stage "deploy\custom-client.example.json")

if (Test-Path (Join-Path $repo ".gitea\workflows\deploy-rustdesk-server.yml")) {
    New-Item -ItemType Directory -Path (Join-Path $stage ".gitea\workflows") -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $repo ".gitea\workflows\deploy-rustdesk-server.yml") -Destination (Join-Path $stage ".gitea\workflows\deploy-rustdesk-server.yml")
}
if (Test-Path (Join-Path $repo ".gitea\workflows\deploy.yml")) {
    New-Item -ItemType Directory -Path (Join-Path $stage ".gitea\workflows") -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $repo ".gitea\workflows\deploy.yml") -Destination (Join-Path $stage ".gitea\workflows\deploy.yml")
}

New-Item -ItemType Directory -Path (Join-Path $stage "scripts") | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stage "scripts\deploy") -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repo "scripts\deploy\deploy.sh") -Destination (Join-Path $stage "scripts\deploy\deploy.sh")
$packageScripts = @(
    "new-kq-custom-client-config.ps1",
    "new-kq-manual-test-report.ps1",
    "new-kq-private-server-client-package.ps1",
    "new-kq-server-key-pair.ps1",
    "new-kq-server-port-request.ps1",
    "new-kq-two-pc-acceptance.ps1",
    "package-kq-remote-link.ps1",
    "run-kq-smoke-suite.ps1",
    "collect-kq-diagnostics.ps1",
    "test-kq-oauth.ps1",
    "test-kq-release.ps1",
    "test-kq-server.ps1"
)
foreach ($script in $packageScripts) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $script) -Destination (Join-Path $stage "scripts\$script")
}

$signerStage = Join-Path $stage "tools\custom_client_signer"
New-Item -ItemType Directory -Path (Join-Path $signerStage "src") -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repo "tools\custom_client_signer\Cargo.toml") -Destination (Join-Path $signerStage "Cargo.toml")
Copy-Item -LiteralPath (Join-Path $repo "tools\custom_client_signer\Cargo.lock") -Destination (Join-Path $signerStage "Cargo.lock")
Copy-Item -LiteralPath (Join-Path $repo "tools\custom_client_signer\src\main.rs") -Destination (Join-Path $signerStage "src\main.rs")

Invoke-WithRetry "Compress-Archive" {
    if (Test-Path $zip) {
        Remove-Item -LiteralPath $zip -Force
    }
    Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zip -CompressionLevel Optimal
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($zip)
try {
    $expectedEntries = @(
        "Release\rustdesk.exe",
        "Release\librustdesk.dll",
        "Release\data\flutter_assets\AssetManifest.bin",
        "KQ_RELEASE_MANIFEST.json",
        "START_KQ_REMOTE_LINK.cmd",
        "RUN_SMOKE_CHECKS.cmd",
        "CREATE_MANUAL_TEST_REPORT.cmd",
        "CREATE_TWO_PC_ACCEPTANCE.cmd",
        "COLLECT_DIAGNOSTICS.cmd",
        "README_START_HERE.txt",
        "TESTING_KQ_REMOTE_LINK.md",
        "ACCEPTANCE_CHECKLIST.md",
        "GITEA_SERVER_DEPLOYMENT.md",
        "SERVER_DEPLOYMENT.md",
        "deploy\rustdesk-server.compose.yml",
        "deploy\deploy-rustdesk-server.sh",
        "deploy\check-rustdesk-server.sh",
        "deploy\export-hbbs-public-key.sh",
        ".gitea\workflows\deploy.yml",
        ".gitea\workflows\deploy-rustdesk-server.yml",
        "scripts\deploy\deploy.sh",
        "scripts\collect-kq-diagnostics.ps1",
        "scripts\new-kq-manual-test-report.ps1",
        "scripts\new-kq-private-server-client-package.ps1",
        "scripts\new-kq-server-key-pair.ps1",
        "scripts\new-kq-server-port-request.ps1",
        "scripts\new-kq-two-pc-acceptance.ps1",
        "scripts\run-kq-smoke-suite.ps1",
        "scripts\test-kq-oauth.ps1",
        "scripts\test-kq-release.ps1",
        "scripts\test-kq-server.ps1",
        "tools\custom_client_signer\Cargo.toml"
    )
    foreach ($entryName in $expectedEntries) {
        $entry = $archive.Entries | Where-Object { $_.FullName -eq $entryName } | Select-Object -First 1
        if (-not $entry) {
            throw "Package verification failed, missing zip entry: $entryName"
        }
    }
    if ($CustomTxt) {
        $customEntry = $archive.Entries | Where-Object { $_.FullName -eq "Release\custom.txt" } | Select-Object -First 1
        if (-not $customEntry) {
            throw "Package verification failed, missing zip entry: Release\custom.txt"
        }
    }
} finally {
    $archive.Dispose()
}

if ($LaunchSmokeTest) {
    $existing = Get-Process rustdesk -ErrorAction SilentlyContinue
    if ($existing -and -not $StopExistingRustDesk) {
        throw "Smoke test needs rustdesk.exe to be closed. Close it first or pass -StopExistingRustDesk."
    }
    if ($existing) {
        $existing | Stop-Process -Force
    }
    $exe = Join-Path $release.Path "rustdesk.exe"
    $process = Start-Process -FilePath $exe -WorkingDirectory $release.Path -PassThru
    try {
        Start-Sleep -Seconds 6
        $process.Refresh()
        if ($process.HasExited) {
            throw "Smoke test failed: rustdesk.exe exited early."
        }
        if ($process.MainWindowTitle -ne $kqAppName) {
            throw "Smoke test failed: expected window title '$kqAppName', got '$($process.MainWindowTitle)'."
        }
        if (-not $process.Responding) {
            throw "Smoke test failed: process is not responding."
        }
    } finally {
        Get-Process rustdesk -ErrorAction SilentlyContinue | Stop-Process -Force
    }
}

Get-Item $zip | Select-Object FullName, Length, LastWriteTime
