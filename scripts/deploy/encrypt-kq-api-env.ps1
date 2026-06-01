param(
    [Parameter(Mandatory = $true)]
    [string] $PublicKeyPath,

    [Parameter(Mandatory = $true)]
    [string] $EnvPath,

    [string] $OutputPath = "deploy\kq-api.env.enc"
)

$ErrorActionPreference = "Stop"

$openssl = (Get-Command openssl -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source)
if (-not $openssl) {
    $candidates = @(
        "E:\Git\usr\bin\openssl.exe",
        "E:\Git\mingw64\bin\openssl.exe",
        "C:\Program Files\Git\usr\bin\openssl.exe",
        "C:\Program Files\Git\mingw64\bin\openssl.exe"
    )
    $openssl = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (-not $openssl) {
    throw "openssl.exe was not found. Install Git for Windows or OpenSSL and retry."
}

$cipherPath = [System.IO.Path]::GetTempFileName()
try {
    & $openssl pkeyutl -encrypt -pubin -inkey $PublicKeyPath `
        -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 `
        -in $EnvPath -out $cipherPath
    if ($LASTEXITCODE -ne 0) {
        throw "openssl failed to encrypt $EnvPath"
    }
    $cipherBytes = [System.IO.File]::ReadAllBytes($cipherPath)
    $encoded = [Convert]::ToBase64String($cipherBytes)
    $wrapped = [regex]::Matches($encoded, ".{1,76}") | ForEach-Object { $_.Value }
    $target = if ([System.IO.Path]::IsPathRooted($OutputPath)) {
        $OutputPath
    } else {
        Join-Path (Get-Location) $OutputPath
    }
    $parent = Split-Path -Parent $target
    if ($parent) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Set-Content -LiteralPath $target -Value $wrapped -Encoding ascii
    Write-Output "Encrypted KQ API env written to $target"
} finally {
    Remove-Item -LiteralPath $cipherPath -Force -ErrorAction SilentlyContinue
}
