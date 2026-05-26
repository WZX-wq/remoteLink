param(
    [string]$OutputRoot = "C:\kq-remote-link-tools",
    [string]$Name = "KQ-Remote-Link-hbbs-key-$(Get-Date -Format 'yyyyMMdd-HHmm')"
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

$targetDir = Join-Path $env:TEMP "kq-custom-client-signer-target"
$output = cargo run --quiet --target-dir $targetDir --manifest-path .\tools\custom_client_signer\Cargo.toml -- gen-key 2>&1
if ($LASTEXITCODE -ne 0) {
    $output | Out-String | Write-Host
    throw "custom_client_signer gen-key failed with exit code $LASTEXITCODE"
}

$text = $output | Out-String
if ($text -notmatch "public-key=(\S+)") {
    throw "Generated key output did not include public-key."
}
$publicKey = $Matches[1]
if ($text -notmatch "secret-key=(\S+)") {
    throw "Generated key output did not include secret-key."
}
$secretKey = $Matches[1]

$publicBytes = [Convert]::FromBase64String($publicKey)
$secretBytes = [Convert]::FromBase64String($secretKey)
if ($publicBytes.Length -ne 32) {
    throw "Expected 32-byte hbbs public key, got $($publicBytes.Length)."
}
if ($secretBytes.Length -ne 64) {
    throw "Expected 64-byte hbbs secret key, got $($secretBytes.Length)."
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$outPath = Join-Path $OutputRoot "$Name.txt"
$lines = @(
    "# KQ Remote Link hbbs/hbbr key pair",
    "",
    "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "",
    "Use the public key as the client ServerKey:",
    $publicKey,
    "",
    "Set these Gitea/runner environment values for deployment:",
    "KQ_HBBS_PUBLIC_KEY=$publicKey",
    "KQ_HBBS_SECRET_KEY=$secretKey",
    "",
    "Do not commit the secret key."
)
[System.IO.File]::WriteAllLines($outPath, [string[]]$lines, (New-Object System.Text.UTF8Encoding($false)))

[PSCustomObject]@{
    PublicKey = $publicKey
    SecretKeyFile = $outPath
}
