param(
    [string]$RendezvousServer,
    [string]$RelayServer,
    [string]$ApiServer = "",
    [string]$ServerKey,
    [string]$PublicKey,
    [string]$SecretKey,
    [switch]$GenerateSigningKey,
    [switch]$BuildClient,
    [switch]$UseExistingBuildWithMatchingKey,
    [string]$ReleaseDir,
    [string]$OutputRoot = "C:\kq-remote-link-tools",
    [string]$PackageName,
    [ValidateSet("Y", "N")]
    [string]$HideServerSettings = "Y"
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo
$signerTargetDir = if ($env:KQ_CUSTOM_CLIENT_SIGNER_TARGET_DIR) {
    [System.IO.Path]::GetFullPath($env:KQ_CUSTOM_CLIENT_SIGNER_TARGET_DIR)
} else {
    Join-Path $env:TEMP "kq-custom-client-signer-target"
}

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

function Assert-NotPlaceholder($Name, $Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "$Name is required."
    }
    if ($Value -match "example\.com|PASTE_|<|>") {
        throw "$Name still looks like a placeholder: $Value"
    }
}

Assert-NotPlaceholder "RendezvousServer" $RendezvousServer
Assert-NotPlaceholder "RelayServer" $RelayServer
Assert-NotPlaceholder "ServerKey" $ServerKey

$OutputRoot = Get-WritableOutputRoot $OutputRoot
$workspace = Join-Path $OutputRoot "private-server-client-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
New-Item -ItemType Directory -Force -Path $workspace | Out-Null

if ($GenerateSigningKey) {
    $keyOutput = cargo run --quiet --target-dir $signerTargetDir --manifest-path .\tools\custom_client_signer\Cargo.toml -- gen-key 2>&1
    if ($LASTEXITCODE -ne 0) {
        $keyOutput | Out-String | Write-Host
        throw "custom_client_signer gen-key failed with exit code $LASTEXITCODE"
    }
    $keyText = $keyOutput | Out-String
    if ($keyText -notmatch "public-key=(\S+)") {
        throw "Generated key output did not include public-key."
    }
    $PublicKey = $Matches[1]
    if ($keyText -notmatch "secret-key=(\S+)") {
        throw "Generated key output did not include secret-key."
    }
    $SecretKey = $Matches[1]
}

Assert-NotPlaceholder "PublicKey" $PublicKey
Assert-NotPlaceholder "SecretKey" $SecretKey

if (-not $BuildClient -and -not $UseExistingBuildWithMatchingKey) {
    throw "Use -BuildClient so the executable is compiled with this PublicKey, or pass -UseExistingBuildWithMatchingKey only if the ReleaseDir was already built with the same KQ_CUSTOM_CLIENT_PUBKEY. A signed custom.txt will not load if the executable has a different baked public key."
}

$jsonPath = Join-Path $workspace "custom-client.generated.json"
$customTxtPath = Join-Path $workspace "custom.txt"

$previousSignerTargetDir = $env:KQ_CUSTOM_CLIENT_SIGNER_TARGET_DIR
try {
    $env:KQ_CUSTOM_CLIENT_SIGNER_TARGET_DIR = $signerTargetDir
    & "$PSScriptRoot\new-kq-custom-client-config.ps1" `
        -RendezvousServer $RendezvousServer `
        -RelayServer $RelayServer `
        -ApiServer $ApiServer `
        -ServerKey $ServerKey `
        -SecretKey $SecretKey `
        -PublicKey $PublicKey `
        -OutputJson $jsonPath `
        -OutputCustomTxt $customTxtPath `
        -HideServerSettings $HideServerSettings | Out-Host
} finally {
    if ($null -eq $previousSignerTargetDir) {
        Remove-Item Env:\KQ_CUSTOM_CLIENT_SIGNER_TARGET_DIR -ErrorAction SilentlyContinue
    } else {
        $env:KQ_CUSTOM_CLIENT_SIGNER_TARGET_DIR = $previousSignerTargetDir
    }
}
if ($LASTEXITCODE -ne 0) {
    throw "new-kq-custom-client-config.ps1 failed with exit code $LASTEXITCODE"
}

if ($BuildClient) {
    $previousPubKey = $env:KQ_CUSTOM_CLIENT_PUBKEY
    try {
        $env:KQ_CUSTOM_CLIENT_PUBKEY = $PublicKey
        & "$PSScriptRoot\build-windows-flutter.ps1" -SkipPortablePack
        if ($LASTEXITCODE -ne 0) {
            throw "build-windows-flutter.ps1 failed with exit code $LASTEXITCODE"
        }
    } finally {
        $env:KQ_CUSTOM_CLIENT_PUBKEY = $previousPubKey
    }
}

if (-not $ReleaseDir) {
    $ReleaseDir = Join-Path $repo "flutter\build\windows\x64\runner\Release"
}
if (-not $PackageName) {
    $PackageName = "KQ-Remote-Link-private-server-$(Get-Date -Format 'yyyyMMdd-HHmm')"
}

$packageResult = & "$PSScriptRoot\package-kq-remote-link.ps1" `
    -ReleaseDir $ReleaseDir `
    -OutputRoot $OutputRoot `
    -PackageName $PackageName `
    -CustomTxt $customTxtPath
if ($LASTEXITCODE -ne 0) {
    throw "package-kq-remote-link.ps1 failed with exit code $LASTEXITCODE"
}

$packageZip = Join-Path $OutputRoot "$PackageName.zip"
$previousSignerTargetDir = $env:KQ_CUSTOM_CLIENT_SIGNER_TARGET_DIR
try {
    $env:KQ_CUSTOM_CLIENT_SIGNER_TARGET_DIR = $signerTargetDir
    & "$PSScriptRoot\test-kq-release.ps1" `
        -ReleaseDir $ReleaseDir `
        -PackageZip $packageZip `
        -CustomClientPublicKey $PublicKey | Out-Host
} finally {
    if ($null -eq $previousSignerTargetDir) {
        Remove-Item Env:\KQ_CUSTOM_CLIENT_SIGNER_TARGET_DIR -ErrorAction SilentlyContinue
    } else {
        $env:KQ_CUSTOM_CLIENT_SIGNER_TARGET_DIR = $previousSignerTargetDir
    }
}
if ($LASTEXITCODE -ne 0) {
    throw "test-kq-release.ps1 failed with exit code $LASTEXITCODE"
}

$summary = @(
    "# KQ Remote Link Private Server Client Package",
    "",
    "- Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "- RendezvousServer: $RendezvousServer",
    "- RelayServer: $RelayServer",
    "- ApiServer: $ApiServer",
    "- ServerKey: $ServerKey",
    "- SigningPublicKey: $PublicKey",
    "- BuiltClientWithSigningKey: $BuildClient",
    "- UsedExistingBuildWithMatchingKey: $UseExistingBuildWithMatchingKey",
    "- CustomJson: $jsonPath",
    "- CustomTxt: $customTxtPath",
    "- PackageZip: $packageZip",
    "",
    "Runtime requirement:",
    "The packaged executable must be built with:",
    "`$env:KQ_CUSTOM_CLIENT_PUBKEY = '$PublicKey'"
)
[System.IO.File]::WriteAllLines(
    (Join-Path $workspace "summary.md"),
    [string[]]$summary,
    (New-Object System.Text.UTF8Encoding($false))
)

Get-Item $packageZip | Select-Object FullName, Length, LastWriteTime
