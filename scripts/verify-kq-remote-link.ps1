param(
    [switch]$SkipBuildEnvCheck
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$flutterDir = Join-Path $repo "flutter"
$toolsRoot = "C:\kq-remote-link-tools"

function Add-PathForCurrentProcess($PathToAdd) {
    if ((Test-Path $PathToAdd) -and -not ($env:Path -split ';' | Where-Object { $_ -eq $PathToAdd })) {
        $env:Path = "$PathToAdd;$env:Path"
    }
}

function Invoke-Step($Name, [scriptblock]$Body) {
    Write-Host "==> $Name"
    & $Body
}

Add-PathForCurrentProcess (Join-Path $toolsRoot "flutter\bin")
Add-PathForCurrentProcess (Join-Path $toolsRoot "cmake\bin")
Add-PathForCurrentProcess (Join-Path $toolsRoot "ninja")
Add-PathForCurrentProcess (Join-Path $env:USERPROFILE ".cargo\bin")

if (-not $env:VCPKG_ROOT -and (Test-Path (Join-Path $toolsRoot "vcpkg"))) {
    $env:VCPKG_ROOT = Join-Path $toolsRoot "vcpkg"
}
$signerTargetDir = Join-Path $toolsRoot "custom-client-signer-target"

Set-Location $repo

Invoke-Step "Whitespace check" {
    git diff --check
}

Invoke-Step "Custom client JSON check" {
    python -m json.tool .\deploy\custom-client.example.json | Out-Null
    $customClientExample = Get-Content .\deploy\custom-client.example.json -Raw -Encoding UTF8
    foreach ($needle in @("43.154.197.96:21116", "43.154.197.96:21117", "PASTE_HBBS_PUBLIC_KEY_HERE")) {
        if ($customClientExample -notmatch [regex]::Escape($needle)) {
            throw "custom-client.example.json is missing $needle"
        }
    }
}

Invoke-Step "Server deployment template check" {
    $deployScript = Get-Content .\deploy\deploy-rustdesk-server.sh -Raw -Encoding UTF8
    foreach ($needle in @("docker compose", "docker-compose", "21116", "id_ed25519.pub", "iptables", "21115-21119")) {
        if ($deployScript -notmatch [regex]::Escape($needle)) {
            throw "deploy-rustdesk-server.sh is missing $needle"
        }
    }

    $checkScript = Get-Content .\deploy\check-rustdesk-server.sh -Raw -Encoding UTF8
    foreach ($needle in @("logs --tail=60", "id_ed25519.pub", "21115", "21117", "21119", "require_container", "require_listener", "hbbs/hbbr health check passed")) {
        if ($checkScript -notmatch [regex]::Escape($needle)) {
            throw "check-rustdesk-server.sh is missing $needle"
        }
    }

    $directDeployScript = Get-Content .\scripts\deploy\deploy.sh -Raw -Encoding UTF8
    foreach ($needle in @("/www/wwwroot", "KQromoteLink", "deploy-rustdesk-server.sh", "check-rustdesk-server.sh", "43.154.197.96", "21116", "21117")) {
        if ($directDeployScript -notmatch [regex]::Escape($needle)) {
            throw "scripts/deploy/deploy.sh is missing $needle"
        }
    }

    $directWorkflow = Get-Content .\.gitea\workflows\deploy.yml -Raw -Encoding UTF8
    foreach ($needle in @("runs-on: linux:host", "scripts/deploy/deploy.sh", "/www/wwwroot/KQromoteLink", "43.154.197.96", "bash -n", "secrets.KQ_HBBS_PUBLIC_KEY", "secrets.KQ_HBBS_SECRET_KEY")) {
        if ($directWorkflow -notmatch [regex]::Escape($needle)) {
            throw "Gitea direct deploy workflow is missing $needle"
        }
    }

    $giteaWorkflow = Get-Content .\.gitea\workflows\deploy-rustdesk-server.yml -Raw -Encoding UTF8
    foreach ($needle in @("workflow_dispatch", "runs-on: linux:host", "KQ_DEPLOY_SSH_KEY", "deploy-rustdesk-server.sh", "check-rustdesk-server.sh", "rustdesk-server.compose.yml")) {
        if ($giteaWorkflow -notmatch [regex]::Escape($needle)) {
            throw "Gitea deploy workflow is missing $needle"
        }
    }
}

Invoke-Step "Kunqiong desktop branding source check" {
    $tabbar = Get-Content .\flutter\lib\desktop\widgets\tabbar_widget.dart -Raw -Encoding UTF8
    $login = Get-Content .\flutter\lib\common\widgets\login.dart -Raw -Encoding UTF8
    $brandText = [string]::Concat([char]0x9CB2, [char]0x7A79, [char]0x8FDC, [char]0x7A0B, [char]0x684C, [char]0x9762)
    $loginText = [string]::Concat(
        [char]0x4F7F,
        [char]0x7528,
        [char]0x9CB2,
        [char]0x7A79,
        [char]0x8D26,
        [char]0x53F7,
        [char]0x767B,
        [char]0x5F55
    )
    if ($tabbar -notmatch $brandText) {
        throw "Desktop title bar brand text was not found."
    }
    if ($tabbar -notmatch "assets/icon\.png") {
        throw "Desktop title bar icon asset was not found."
    }
    if ($login -notmatch $loginText) {
        throw "Kunqiong OAuth login button text was not found."
    }
}

Invoke-Step "PowerShell script syntax check" {
    $scriptFiles = @(
        ".\scripts\bootstrap-windows-build-env.ps1",
        ".\scripts\build-windows-flutter.ps1",
        ".\scripts\check-build-env.ps1",
        ".\scripts\collect-kq-diagnostics.ps1",
        ".\scripts\new-kq-custom-client-config.ps1",
        ".\scripts\new-kq-manual-test-report.ps1",
        ".\scripts\new-kq-private-server-client-package.ps1",
        ".\scripts\new-kq-server-port-request.ps1",
        ".\scripts\new-kq-two-pc-acceptance.ps1",
        ".\scripts\package-kq-remote-link.ps1",
        ".\scripts\run-kq-smoke-suite.ps1",
        ".\scripts\start-elevated-bootstrap.ps1",
        ".\scripts\start-elevated-build.ps1",
        ".\scripts\test-kq-oauth.ps1",
        ".\scripts\test-kq-release.ps1",
        ".\scripts\test-kq-server.ps1",
        ".\scripts\verify-kq-remote-link.ps1"
    )
    foreach ($scriptFile in $scriptFiles) {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            (Resolve-Path $scriptFile).Path,
            [ref]$tokens,
            [ref]$errors
        ) | Out-Null
        if ($errors) {
            $errors | Format-List | Out-String | Write-Host
            throw "PowerShell syntax check failed: $scriptFile"
        }
    }
}

Invoke-Step "Custom client signer format check" {
    cargo fmt --check --manifest-path .\tools\custom_client_signer\Cargo.toml
}

Invoke-Step "Custom client signer smoke check" {
    $smokeDir = Join-Path $toolsRoot "custom-client-signer-smoke"
    New-Item -ItemType Directory -Force -Path $smokeDir | Out-Null
    try {
        $keyOutput = cargo run --quiet --target-dir $signerTargetDir --manifest-path .\tools\custom_client_signer\Cargo.toml -- gen-key 2>&1
        if ($LASTEXITCODE -ne 0) {
            $keyOutput | Out-String | Write-Host
            throw "custom_client_signer gen-key failed with exit code $LASTEXITCODE"
        }
        $keyText = $keyOutput | Out-String
        if ($keyText -notmatch "public-key=(\S+)") {
            throw "custom_client_signer gen-key output did not include public-key"
        }
        $publicKey = $Matches[1]
        if ($keyText -notmatch "secret-key=(\S+)") {
            throw "custom_client_signer gen-key output did not include secret-key"
        }
        $secretKey = $Matches[1]

        $jsonPath = Join-Path $smokeDir "custom-client-smoke.json"
        $customTxtPath = Join-Path $smokeDir "custom.txt"
        $config = [ordered]@{
            "app-name" = $brandText
            "default-settings" = [ordered]@{
                "custom-rendezvous-server" = "127.0.0.1:21116"
                "relay-server" = "127.0.0.1:21117"
                "api-server" = ""
                "key" = "smoke-server-key"
                "hide-server-settings" = "Y"
            }
        }
        $json = $config | ConvertTo-Json -Depth 6
        [System.IO.File]::WriteAllText($jsonPath, "$json`n", (New-Object System.Text.UTF8Encoding($false)))

        cargo run --quiet --target-dir $signerTargetDir --manifest-path .\tools\custom_client_signer\Cargo.toml -- sign $jsonPath $secretKey $customTxtPath
        if ($LASTEXITCODE -ne 0) {
            throw "custom_client_signer sign failed with exit code $LASTEXITCODE"
        }
        cargo run --quiet --target-dir $signerTargetDir --manifest-path .\tools\custom_client_signer\Cargo.toml -- verify $customTxtPath $publicKey $jsonPath
        if ($LASTEXITCODE -ne 0) {
            throw "custom_client_signer verify failed with exit code $LASTEXITCODE"
        }

        $scriptJsonPath = Join-Path $smokeDir "script-custom-client.json"
        $scriptCustomTxtPath = Join-Path $smokeDir "script-custom.txt"
        & "$PSScriptRoot\new-kq-custom-client-config.ps1" `
            -RendezvousServer "127.0.0.1:21116" `
            -RelayServer "127.0.0.1:21117" `
            -ApiServer "https://127.0.0.1" `
            -ServerKey "smoke-server-key" `
            -SecretKey $secretKey `
            -PublicKey $publicKey `
            -OutputJson $scriptJsonPath `
            -OutputCustomTxt $scriptCustomTxtPath | Out-Host
        if ($LASTEXITCODE -ne 0) {
            throw "new-kq-custom-client-config.ps1 failed with exit code $LASTEXITCODE"
        }
        if (-not (Test-Path $scriptJsonPath) -or -not (Test-Path $scriptCustomTxtPath)) {
            throw "new-kq-custom-client-config.ps1 did not create expected smoke outputs"
        }

        $privatePackageRoot = Join-Path $smokeDir "private-package"
        $guardFailedAsExpected = $false
        try {
            & "$PSScriptRoot\new-kq-private-server-client-package.ps1" `
                -RendezvousServer "127.0.0.1:21116" `
                -RelayServer "127.0.0.1:21117" `
                -ApiServer "https://127.0.0.1" `
                -ServerKey "smoke-server-key" `
                -PublicKey $publicKey `
                -SecretKey $secretKey `
                -ReleaseDir ".\flutter\build\windows\x64\runner\Release" `
                -OutputRoot (Join-Path $privatePackageRoot "guard") `
                -PackageName "KQ-Remote-Link-private-guard" | Out-Host
        } catch {
            if ($_.Exception.Message -match "Use -BuildClient") {
                $guardFailedAsExpected = $true
            } else {
                throw
            }
        }
        if (-not $guardFailedAsExpected) {
            throw "new-kq-private-server-client-package.ps1 did not require BuildClient or explicit existing-build confirmation"
        }

        & "$PSScriptRoot\new-kq-private-server-client-package.ps1" `
            -RendezvousServer "127.0.0.1:21116" `
            -RelayServer "127.0.0.1:21117" `
            -ApiServer "https://127.0.0.1" `
            -ServerKey "smoke-server-key" `
            -PublicKey $publicKey `
            -SecretKey $secretKey `
            -UseExistingBuildWithMatchingKey `
            -ReleaseDir ".\flutter\build\windows\x64\runner\Release" `
            -OutputRoot $privatePackageRoot `
            -PackageName "KQ-Remote-Link-private-smoke" | Out-Host
        if ($LASTEXITCODE -ne 0) {
            throw "new-kq-private-server-client-package.ps1 failed with exit code $LASTEXITCODE"
        }
        if (-not (Test-Path (Join-Path $privatePackageRoot "KQ-Remote-Link-private-smoke.zip"))) {
            throw "new-kq-private-server-client-package.ps1 did not create expected zip"
        }

        $portRequestPath = Join-Path $smokeDir "port-request.md"
        & "$PSScriptRoot\new-kq-server-port-request.ps1" `
            -ServerHost "remote.example.com" `
            -PublicIp "203.0.113.10" `
            -Requester "smoke" `
            -Environment "test" `
            -ReportPath $portRequestPath | Out-Host
        if (-not (Test-Path $portRequestPath)) {
            throw "new-kq-server-port-request.ps1 did not create expected report"
        }
        $portRequestText = Get-Content $portRequestPath -Raw -Encoding UTF8
        foreach ($needle in @("21115", "21116", "UDP", "21117", "21115-21119")) {
            if ($portRequestText -notmatch [regex]::Escape($needle)) {
                throw "new-kq-server-port-request.ps1 report is missing $needle"
            }
        }
    } finally {
        if (Test-Path $smokeDir) {
            Remove-Item -LiteralPath $smokeDir -Recurse -Force
        }
    }
}

Push-Location $flutterDir
try {
    Invoke-Step "Kunqiong OAuth tests" {
        flutter test test/kq_oauth_payload_test.dart
    }

    Invoke-Step "Targeted Dart analysis" {
        dart analyze `
            lib/common/kq_oauth.dart `
            lib/common/kq_oauth_io.dart `
            lib/common/kq_oauth_stub.dart `
            lib/common/kq_oauth_payload.dart `
            lib/common/widgets/login.dart `
            lib/desktop/widgets/tabbar_widget.dart `
            lib/models/user_model.dart `
            lib/models/ab_model.dart `
            lib/models/group_model.dart `
            test/kq_oauth_payload_test.dart
    }
} finally {
    Pop-Location
}

if (-not $SkipBuildEnvCheck) {
    Invoke-Step "Windows build environment check" {
        & "$PSScriptRoot\check-build-env.ps1"
    }
}

Write-Host "KQ Remote Link verification passed."
