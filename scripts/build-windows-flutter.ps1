param(
    [switch]$SkipPortablePack
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

& "$PSScriptRoot\check-build-env.ps1"

git submodule update --init --recursive
if ($LASTEXITCODE -ne 0) {
    throw "git submodule update failed with exit code $LASTEXITCODE"
}

Push-Location flutter
flutter pub get
if ($LASTEXITCODE -ne 0) {
    throw "flutter pub get failed with exit code $LASTEXITCODE"
}
Pop-Location

$buildArgs = @("--flutter")
if ($SkipPortablePack) {
    $buildArgs += "--skip-portable-pack"
}

python .\build.py @buildArgs
if ($LASTEXITCODE -ne 0) {
    throw "build.py failed with exit code $LASTEXITCODE"
}
