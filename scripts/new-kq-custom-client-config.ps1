param(
    [switch]$GenerateKeyPair,
    [string]$RendezvousServer,
    [string]$RelayServer,
    [string]$ApiServer = "",
    [string]$ServerKey,
    [string]$SecretKey,
    [string]$PublicKey,
    [string]$OutputJson = "deploy\custom-client.generated.json",
    [string]$OutputCustomTxt = "custom.txt",
    [string]$CopyToReleaseDir,
    [ValidateSet("Y", "N")]
    [string]$HideServerSettings = "Y"
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo
$signerTargetDir = Join-Path $env:TEMP "kq-custom-client-signer-target"

function Resolve-RepoPath($Path) {
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $repo $Path))
}

function Assert-NotPlaceholder($Name, $Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "$Name is required."
    }
    if ($Value -match "example\.com|PASTE_|<|>") {
        throw "$Name still looks like a placeholder: $Value"
    }
}

if ($GenerateKeyPair) {
    cargo run --quiet --target-dir $signerTargetDir --manifest-path .\tools\custom_client_signer\Cargo.toml -- gen-key
    if ($LASTEXITCODE -ne 0) {
        throw "custom_client_signer gen-key failed with exit code $LASTEXITCODE"
    }
    return
}

Assert-NotPlaceholder "RendezvousServer" $RendezvousServer
Assert-NotPlaceholder "RelayServer" $RelayServer
Assert-NotPlaceholder "ServerKey" $ServerKey
Assert-NotPlaceholder "SecretKey" $SecretKey

$jsonPath = Resolve-RepoPath $OutputJson
$customTxtPath = Resolve-RepoPath $OutputCustomTxt
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $jsonPath) | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $customTxtPath) | Out-Null

$config = [ordered]@{
    "app-name" = "KQ Remote Link"
    "default-settings" = [ordered]@{
        "custom-rendezvous-server" = $RendezvousServer
        "relay-server" = $RelayServer
        "api-server" = $ApiServer
        "key" = $ServerKey
        "hide-server-settings" = $HideServerSettings
    }
    "override-settings" = [ordered]@{
        "custom-rendezvous-server" = $RendezvousServer
        "relay-server" = $RelayServer
        "api-server" = $ApiServer
        "key" = $ServerKey
        "hide-server-settings" = $HideServerSettings
        "allow-deep-link-server-settings" = "N"
    }
}

$json = $config | ConvertTo-Json -Depth 6
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($jsonPath, "$json`n", $utf8NoBom)

cargo run --quiet --target-dir $signerTargetDir --manifest-path .\tools\custom_client_signer\Cargo.toml -- sign $jsonPath $SecretKey $customTxtPath
if ($LASTEXITCODE -ne 0) {
    throw "custom_client_signer sign failed with exit code $LASTEXITCODE"
}

if (-not (Test-Path $customTxtPath) -or (Get-Item $customTxtPath).Length -le 0) {
    throw "Signing did not create a non-empty custom.txt at $customTxtPath"
}

if ($PublicKey) {
    cargo run --quiet --target-dir $signerTargetDir --manifest-path .\tools\custom_client_signer\Cargo.toml -- verify $customTxtPath $PublicKey $jsonPath
    if ($LASTEXITCODE -ne 0) {
        throw "custom_client_signer verify failed with exit code $LASTEXITCODE"
    }
}

if ($CopyToReleaseDir) {
    $releaseDir = Resolve-RepoPath $CopyToReleaseDir
    if (-not (Test-Path (Join-Path $releaseDir "rustdesk.exe"))) {
        throw "CopyToReleaseDir must point to a release directory containing rustdesk.exe: $releaseDir"
    }
    Copy-Item -LiteralPath $customTxtPath -Destination (Join-Path $releaseDir "custom.txt") -Force
}

Write-Host "Generated JSON config: $jsonPath"
Write-Host "Generated signed custom client config: $customTxtPath"
if ($PublicKey) {
    Write-Host "Build release clients with this matching verification key:"
    Write-Host "`$env:KQ_CUSTOM_CLIENT_PUBKEY = '$PublicKey'"
} else {
    Write-Host "Reminder: rebuild the client with the public key that matches SecretKey:"
    Write-Host "`$env:KQ_CUSTOM_CLIENT_PUBKEY = '<public-key-from-gen-key>'"
}
