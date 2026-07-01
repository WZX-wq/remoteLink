param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'

function Assert-Contains {
    param(
        [string]$Path,
        [string]$Pattern,
        [string]$Message
    )

    $content = Get-Content -LiteralPath $Path -Raw
    if ($content -notmatch $Pattern) {
        throw $Message
    }
}

$buildRs = Join-Path $Root 'libs/scrap/build.rs'
$modRs = Join-Path $Root 'libs/scrap/src/common/mod.rs'
$codecRs = Join-Path $Root 'libs/scrap/src/common/codec.rs'

Assert-Contains `
    -Path $buildRs `
    -Pattern 'kq-ios-no-aom-linkage[\s\S]*if target_os != "ios" \{[\s\S]*gen_vcpkg_package\("aom"' `
    -Message 'iOS Rust build must not link libaom/aom_codec objects.'

Assert-Contains `
    -Path $modRs `
    -Pattern '#\[cfg\(not\(target_os = "ios"\)\)\]\s*pub mod aom;' `
    -Message 'AOM module must be cfg-gated out of iOS builds.'

Assert-Contains `
    -Path $codecRs `
    -Pattern '#\[cfg\(not\(target_os = "ios"\)\)\]\s*use crate::aom' `
    -Message 'codec.rs must not import AOM on iOS.'

Assert-Contains `
    -Path $codecRs `
    -Pattern 'fn av1_enabled\(\) -> bool \{[\s\S]*!cfg!\(target_os = "ios"\)' `
    -Message 'AV1 support must be disabled on iOS when AOM is not linked.'

Write-Host 'KQ iOS Rust linkage checks passed'
