param(
    [string]$ReleaseDir,
    [string]$PackageZip,
    [string]$CustomClientPublicKey,
    [string]$ReportPath,
    [switch]$LaunchSmokeTest,
    [switch]$StopExistingRustDesk,
    [switch]$NoReport
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo
$signerTargetDir = Join-Path $env:TEMP "kq-custom-client-signer-target"

if (-not $ReleaseDir) {
    $packagedRelease = Join-Path $repo "Release"
    if (Test-Path (Join-Path $packagedRelease "rustdesk.exe")) {
        $ReleaseDir = $packagedRelease
    } else {
        $ReleaseDir = Join-Path $repo "flutter\build\windows\x64\runner\Release"
    }
}
if (-not $ReportPath) {
    $ReportPath = Join-Path "C:\kq-remote-link-tools" "KQ-Remote-Link-acceptance-$(Get-Date -Format 'yyyyMMdd-HHmm').md"
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

function Test-RequiredPath($Base, $RelativePath) {
    $path = Join-Path $Base $RelativePath
    if (Test-Path $path) {
        Add-Check "release:$RelativePath" "PASS" $path
    } else {
        Add-Check "release:$RelativePath" "FAIL" "Missing $path"
    }
}

function Test-SourceContains($Path, $Pattern, $Name) {
    if (-not (Test-Path $Path)) {
        Add-Check $Name "SKIP" "Source file not available: $Path"
        return
    }
    $content = Get-Content $Path -Raw -Encoding UTF8
    if ($content -match [regex]::Escape($Pattern)) {
        Add-Check $Name "PASS" $Pattern
    } else {
        Add-Check $Name "FAIL" "Missing expected text: $Pattern"
    }
}

function Test-InstallerUpgradePolicy {
    $source = ".\scripts\new-kq-inno-installer.ps1"
    if (-not (Test-Path $source)) {
        Add-Check "installer:upgrade-policy" "SKIP" "Source file not available: $source"
        return
    }
    $content = Get-Content $source -Raw -Encoding UTF8
    $required = @(
        @("installer:stable-app-id", "AppId={{D0B24C8B-7E7E-4B2C-9A38-0B2026052701}"),
        @("installer:upgrade-default-dir", "DefaultDirName={code:GetDefaultInstallDir}"),
        @("installer:no-language-dialog", "ShowLanguageDialog=no"),
        @("installer:language-detect-ui", "LanguageDetectionMethod=uilanguage"),
        @("installer:use-previous-dir", "UsePreviousAppDir=yes"),
        @("installer:use-previous-language", "UsePreviousLanguage=yes"),
        @("installer:use-previous-tasks", "UsePreviousTasks=yes"),
        @("installer:read-existing-install-dir", "KqReadInstalledString('InstallLocation', KqExistingInstallDir)"),
        @("installer:prefer-existing-install-dir", "if KqExistingInstallDir <> '' then"),
        @("installer:fresh-lang-only", 'Parameters: "--local-option lang {code:SelectedAppLanguage}"; Flags: runhidden waituntilterminated; Check: KqIsFreshInstall'),
        @("installer:fresh-udp-only", 'Parameters: "--local-option enable-udp-punch Y"; Flags: runhidden waituntilterminated; Check: KqIsFreshInstall'),
        @("installer:fresh-relay-only", 'Parameters: "--local-option kq-force-always-relay N"; Flags: runhidden waituntilterminated; Check: KqIsFreshInstall'),
        @("installer:fresh-launch-only", 'Tasks: launch; Check: KqIsFreshInstall'),
        @("installer:upgrade-skip-pages", "function ShouldSkipPage(PageID: Integer): Boolean"),
        @("installer:upgrade-copy-hook", "procedure ApplyUpgradeWizardText(CurPageID: Integer)"),
        @("installer:upgrade-welcome-copy", "WizardForm.WelcomeLabel1.Caption := '`$cnWelcomeTitle'"),
        @("installer:upgrade-ready-copy", "WizardForm.ReadyLabel.Caption :="),
        @("installer:upgrade-button-copy", "WizardForm.NextButton.Caption := '`$cnUpgradeButton'"),
        @("installer:upgrade-page-change-hook", "procedure CurPageChanged(CurPageID: Integer)"),
        @("installer:legacy-hkcu-migration", "function KqLegacyUninstallKey(): String"),
        @("installer:downgrade-guard", "KqCompareVersions(KqExistingVersion, '{#MyAppVersion}') > 0"),
        @("installer:system-desktop-shortcut", 'Name: "{commondesktop}\{#MyAppName}"'),
        @("installer:system-startup-shortcut", 'Name: "{commonstartup}\{#MyAppName}"')
    )
    foreach ($pair in $required) {
        if ($content -match [regex]::Escape($pair[1])) {
            Add-Check $pair[0] "PASS" $pair[1]
        } else {
            Add-Check $pair[0] "FAIL" "Missing expected installer policy: $($pair[1])"
        }
    }

    $forbidden = @(
        @("installer:no-localappdata-default", "DefaultDirName={localappdata}\KQRemoteLink"),
        @("installer:no-forced-language-dialog", "ShowLanguageDialog=yes"),
        @("installer:no-auto-language-dialog", "ShowLanguageDialog=auto"),
        @("installer:no-disabled-language-detection", "LanguageDetectionMethod=none"),
        @("installer:no-user-desktop-task", 'Name: "{autodesktop}\{#MyAppName}"'),
        @("installer:no-user-startup-task", 'Name: "{userstartup}\{#MyAppName}"')
    )
    foreach ($pair in $forbidden) {
        if ($content -match [regex]::Escape($pair[1])) {
            Add-Check $pair[0] "FAIL" "Forbidden installer policy is present: $($pair[1])"
        } else {
            Add-Check $pair[0] "PASS" "Forbidden policy absent"
        }
    }
}

$release = Resolve-Path $ReleaseDir
if ($PackageZip) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
}
Test-RequiredPath $release.Path "rustdesk.exe"
Test-RequiredPath $release.Path "librustdesk.dll"
Test-RequiredPath $release.Path "flutter_windows.dll"
Test-RequiredPath $release.Path "data\flutter_assets\AssetManifest.bin"
Test-RequiredPath $release.Path "data\flutter_assets\assets\kq_toolbox_icon.svg"
Test-RequiredPath $release.Path "drivers\RustDeskPrinterDriver\RustDeskPrinterDriver.inf"
Test-RequiredPath $release.Path "printer_driver_adapter.dll"
Test-InstallerUpgradePolicy

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
$kqDownloadWindowsButton = [string]::Concat([char[]]@(
    0x4E0B,
    0x8F7D,
    0x20,
    0x57,
    0x69,
    0x6E,
    0x64,
    0x6F,
    0x77,
    0x73,
    0x20,
    0x5B89,
    0x88C5,
    0x5305
))

function Test-BuiltInPrivateServerDefaults {
    $source = ".\src\common.rs"
    if (-not (Test-Path $source)) {
        Add-Check "private-server:built-in-defaults" "SKIP" "Source file not available: $source"
        return
    }
    $content = Get-Content $source -Raw -Encoding UTF8
    $required = @(
        "43.154.197.96:21116",
        "43.154.197.96:21117",
        "h9goq/v9ic0Uh0NpB/9Uv4v2MNpSEIVCy7UFSETZ5BA="
    )
    $missing = @($required | Where-Object { $content -notmatch [regex]::Escape($_) })
    if ($missing.Count -eq 0) {
        Add-Check "private-server:built-in-defaults" "PASS" "client defaults point to private hbbs/hbbr"
    } else {
        Add-Check "private-server:built-in-defaults" "FAIL" "Missing defaults: $($missing -join ', ')"
    }
}

$manifestPath = Join-Path $repo "KQ_RELEASE_MANIFEST.json"
if (Test-Path $manifestPath) {
    $manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.appName -eq $kqAppName) {
        Add-Check "manifest:app-name" "PASS" $manifest.appName
    } else {
        Add-Check "manifest:app-name" "FAIL" "Unexpected appName: $($manifest.appName)"
    }
    if ($manifest.oauth.loginButtonText -eq $kqLoginButton) {
        Add-Check "manifest:oauth-login-button" "PASS" $manifest.oauth.loginButtonText
    } else {
        Add-Check "manifest:oauth-login-button" "FAIL" "Unexpected login button text"
    }
    if ($manifest.ui.titleBrandText -eq $kqTitleBrand) {
        Add-Check "manifest:ui-title-brand" "PASS" $manifest.ui.titleBrandText
    } else {
        Add-Check "manifest:ui-title-brand" "FAIL" "Unexpected title brand text"
    }
    if ($manifest.ui.titleBrandIcon -eq "assets/icon.png") {
        Add-Check "manifest:ui-title-icon" "PASS" $manifest.ui.titleBrandIcon
    } else {
        Add-Check "manifest:ui-title-icon" "FAIL" "Unexpected title brand icon"
    }
    foreach ($pair in @(
        @("manifest:oauth-authorize-url", "authorizeUrl", "https://login.kunqiongai.com/authorize.html"),
        @("manifest:oauth-token-url", "tokenUrl", "https://login.kunqiongai.com/api/oauth/token"),
        @("manifest:oauth-redirect-uri", "redirectUri", "http://localhost:6613/oauth/callback")
    )) {
        $actual = $manifest.oauth.($pair[1])
        if ($actual -eq $pair[2]) {
            Add-Check $pair[0] "PASS" $actual
        } else {
            Add-Check $pair[0] "FAIL" "Expected $($pair[2]), got $actual"
        }
    }
    $actualExeHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $release.Path "rustdesk.exe")).Hash.ToLowerInvariant()
    if ($actualExeHash -eq $manifest.release.rustdeskExeSha256) {
        Add-Check "manifest:rustdesk.exe-sha256" "PASS" $actualExeHash
    } else {
        Add-Check "manifest:rustdesk.exe-sha256" "FAIL" "Hash mismatch"
    }
} else {
    Test-SourceContains ".\Cargo.toml" $kqAppName "branding:CARGO"
    Test-SourceContains ".\src\common.rs" $kqAppName "branding:common"
    Test-SourceContains ".\flutter\lib\common\widgets\login.dart" $kqLoginButton "oauth:login-button"
    Test-SourceContains ".\flutter\lib\common\widgets\login.dart" "_isKqOauthCancellation" "oauth:suppress-cancel-toast"
    Test-SourceContains ".\flutter\lib\common\widgets\login.dart" "if (!_isKqOauthCancellation(err))" "oauth:suppress-cancel-toast-branch"
    Test-SourceContains ".\flutter\lib\desktop\widgets\tabbar_widget.dart" $kqTitleBrand "ui:title-brand"
    Test-SourceContains ".\flutter\lib\desktop\widgets\tabbar_widget.dart" "assets/icon.png" "ui:title-icon"
    Test-SourceContains ".\flutter\lib\desktop\pages\desktop_tab_page.dart" "showMaximize: false" "ui:main-hide-maximize"
    Test-SourceContains ".\flutter\lib\desktop\pages\desktop_home_page.dart" "_copyRemoteAssistShare" "ui:remote-assist-share-copy"
    Test-SourceContains ".\flutter\lib\desktop\pages\desktop_home_page.dart" "kq-share-invite-url" "ui:remote-assist-share-url"
    Test-SourceContains ".\flutter\lib\desktop\pages\connection_page.dart" "_passwordController" "ui:remote-password-field"
    Test-SourceContains ".\flutter\lib\desktop\pages\connection_page.dart" "password: password.isEmpty ? null : password" "ui:remote-password-connect-param"
    Test-SourceContains ".\flutter\lib\common.dart" "isSupportedKqUriLink" "deeplink:kqremote-compatible"
    Test-SourceContains ".\src\common.rs" "kqremote://" "deeplink:kqremote-prefix"
    Test-SourceContains ".\scripts\new-kq-inno-installer.ps1" "HKEY_CLASSES_ROOT\kqremote" "installer:kqremote-protocol"
    Test-SourceContains ".\server\src\index.js" "app.get(['/invite', '/api/invite']" "server:invite-page"
    Test-SourceContains ".\server\src\index.js" "kqremote" "server:invite-kqremote-scheme"
    Test-SourceContains ".\server\src\index.js" "function downloadPage()" "server:download-page"
    Test-SourceContains ".\server\src\index.js" $kqDownloadWindowsButton "server:download-windows-button"
    Test-SourceContains ".\server\src\index.js" "sendWindowsInstaller" "server:download-installer-stream"
    Test-SourceContains ".\server\src\index.js" "accept-ranges" "server:download-range-support"
    Test-SourceContains ".\server\src\index.js" "maxGlobalConcurrent" "server:download-global-limit"
    Test-SourceContains ".\server\src\index.js" "maxPerIpConcurrent" "server:download-ip-limit"
    Test-SourceContains ".\server\src\index.js" "Download rate limit exceeded" "server:download-rate-limit"
    Test-SourceContains ".\server\Dockerfile" "COPY public ./public" "server:download-file-packaged"
    Test-SourceContains ".\.gitea\workflows\deploy.yml" "http://43.154.197.96/kq-api/download/windows" "deploy:self-hosted-download-url"
    Test-SourceContains ".\deploy\rustdesk-server.compose.yml" "KQ_DOWNLOAD_MAX_GLOBAL_CONCURRENT" "deploy:download-limit-env"
    Test-SourceContains ".\flutter\lib\common\kq_oauth_io.dart" "https://login.kunqiongai.com/authorize.html" "oauth:authorize-url"
    Test-SourceContains ".\flutter\lib\common\kq_oauth_io.dart" "https://login.kunqiongai.com/api/oauth/token" "oauth:token-url"
    Test-SourceContains ".\flutter\lib\common\kq_oauth_io.dart" "http://localhost:6613/oauth/callback" "oauth:redirect-uri"
    Test-BuiltInPrivateServerDefaults
}

$customTxt = Join-Path $release.Path "custom.txt"
$zipCustomTxtForVerification = $null
if (Test-Path $customTxt) {
    if ($CustomClientPublicKey) {
        cargo run --target-dir $signerTargetDir --manifest-path .\tools\custom_client_signer\Cargo.toml -- verify $customTxt $CustomClientPublicKey
        if ($LASTEXITCODE -eq 0) {
            Add-Check "custom-client:signature" "PASS" "custom.txt verified"
        } else {
            Add-Check "custom-client:signature" "FAIL" "custom.txt verification failed"
        }
    } else {
        Add-Check "custom-client:signature" "WARN" "custom.txt exists; pass -CustomClientPublicKey to verify it"
    }
} elseif ($PackageZip) {
    $zip = Resolve-Path $PackageZip
    $archiveForCustom = [System.IO.Compression.ZipFile]::OpenRead($zip.Path)
    try {
        $customEntry = $archiveForCustom.Entries | Where-Object { $_.FullName -eq "Release\custom.txt" } | Select-Object -First 1
        if ($customEntry) {
            $zipCustomTxtForVerification = Join-Path $env:TEMP ("kq-custom-" + [guid]::NewGuid().ToString("N") + ".txt")
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($customEntry, $zipCustomTxtForVerification, $true)
            if ($CustomClientPublicKey) {
                cargo run --target-dir $signerTargetDir --manifest-path .\tools\custom_client_signer\Cargo.toml -- verify $zipCustomTxtForVerification $CustomClientPublicKey
                if ($LASTEXITCODE -eq 0) {
                    Add-Check "custom-client:signature" "PASS" "zip Release\custom.txt verified"
                } else {
                    Add-Check "custom-client:signature" "FAIL" "zip Release\custom.txt verification failed"
                }
            } else {
                Add-Check "custom-client:signature" "WARN" "zip Release\custom.txt exists; pass -CustomClientPublicKey to verify it"
            }
        } else {
            Add-Check "custom-client:signature" "SKIP" "No custom.txt in release or zip; built-in private server defaults are active"
        }
    } finally {
        $archiveForCustom.Dispose()
        if ($zipCustomTxtForVerification -and (Test-Path $zipCustomTxtForVerification)) {
            Remove-Item -LiteralPath $zipCustomTxtForVerification -Force
        }
    }
} else {
    Add-Check "custom-client:signature" "SKIP" "No custom.txt in release; built-in private server defaults are active"
}

if ($PackageZip) {
    $zip = Resolve-Path $PackageZip
    $archive = [System.IO.Compression.ZipFile]::OpenRead($zip.Path)
    try {
        foreach ($entryName in @(
            "Release\rustdesk.exe",
            "Release\librustdesk.dll",
            "Release\data\flutter_assets\AssetManifest.bin",
            "Release\data\flutter_assets\assets\kq_toolbox_icon.svg",
            "Release\drivers\RustDeskPrinterDriver\RustDeskPrinterDriver.inf",
            "Release\printer_driver_adapter.dll",
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
        )) {
            $entry = $archive.Entries | Where-Object { $_.FullName -eq $entryName } | Select-Object -First 1
            if ($entry) {
                Add-Check "zip:$entryName" "PASS" "$($entry.Length) bytes"
            } else {
                Add-Check "zip:$entryName" "FAIL" "Missing zip entry"
            }
        }
    } finally {
        $archive.Dispose()
    }
}

if ($LaunchSmokeTest) {
    $existing = Get-Process rustdesk -ErrorAction SilentlyContinue
    if ($existing -and -not $StopExistingRustDesk) {
        Add-Check "smoke:launch" "WARN" "rustdesk.exe is already running; close it or pass -StopExistingRustDesk"
    } else {
        if ($existing) {
            $existing | Stop-Process -Force
        }
        $exe = Join-Path $release.Path "rustdesk.exe"
        $process = Start-Process -FilePath $exe -WorkingDirectory $release.Path -PassThru
        try {
            Start-Sleep -Seconds 6
            $process.Refresh()
            if ($process.HasExited) {
                Add-Check "smoke:launch" "FAIL" "rustdesk.exe exited early"
            } elseif ($process.MainWindowTitle -ne $kqAppName) {
                Add-Check "smoke:launch" "FAIL" "Unexpected title: $($process.MainWindowTitle)"
            } elseif (-not $process.Responding) {
                Add-Check "smoke:launch" "FAIL" "Process is not responding"
            } else {
                Add-Check "smoke:launch" "PASS" "Window title is $kqAppName"
            }
        } finally {
            Get-Process rustdesk -ErrorAction SilentlyContinue | Stop-Process -Force
        }
    }
}

$failed = @($results | Where-Object { $_.Status -eq "FAIL" })
$report = New-Object System.Collections.Generic.List[string]
$report.Add("# KQ Remote Link Acceptance Report")
$report.Add("")
$report.Add("- Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$report.Add("- ReleaseDir: $($release.Path)")
if ($PackageZip) {
    $report.Add("- PackageZip: $((Resolve-Path $PackageZip).Path)")
}
$report.Add("")
$report.Add("## Automated Checks")
$report.Add("")
$report.Add("| Status | Check | Detail |")
$report.Add("| --- | --- | --- |")
foreach ($result in $results) {
    $detail = ($result.Detail -replace "\|", "\\|")
    $report.Add("| $($result.Status) | $($result.Name) | $detail |")
}
$report.Add("")
$report.Add("## Manual Two-Client Checks")
$report.Add("")
$report.Add("- OAuth login opens Kunqiong authorization page and returns to localhost callback.")
$report.Add("- Two clients show IDs and can connect with password or accept flow.")
$report.Add("- Remote screen, mouse, keyboard, clipboard, and file transfer work.")
$report.Add("- Cross-network relay works through the configured hbbr server.")
$report.Add("- Controlled side service mode is installed when UAC/lock-screen control is required.")

if (-not $NoReport) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ReportPath) | Out-Null
    [System.IO.File]::WriteAllLines($ReportPath, $report, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "Acceptance report: $ReportPath"
}

if ($failed.Count -gt 0) {
    throw "Acceptance checks failed: $($failed.Count)"
}
