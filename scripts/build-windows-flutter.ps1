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

$hbbPatch = Join-Path $repo "patches\hbb_common\kq-local-changes.patch"
if (Test-Path $hbbPatch) {
    git -C libs\hbb_common apply --reverse --check $hbbPatch *> $null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "hbb_common KQ patch already applied"
    } else {
        git -C libs\hbb_common apply --check $hbbPatch
        if ($LASTEXITCODE -ne 0) {
            throw "hbb_common KQ patch check failed with exit code $LASTEXITCODE"
        }
        git -C libs\hbb_common apply $hbbPatch
        if ($LASTEXITCODE -ne 0) {
            throw "hbb_common KQ patch apply failed with exit code $LASTEXITCODE"
        }
        Write-Host "hbb_common KQ patch applied"
    }
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
