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
$codemagicYaml = Join-Path $Root 'codemagic.yaml'
$iosTriplet = Join-Path $Root 'res/vcpkg/triplets/arm64-ios.cmake'
$verifyVcpkg = Join-Path $Root 'scripts/ci/verify-ios-vcpkg-libraries.sh'

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

Assert-Contains `
    -Path $iosTriplet `
    -Pattern 'VCPKG_CMAKE_SYSTEM_NAME iOS[\s\S]*VCPKG_OSX_SYSROOT iphoneos[\s\S]*VCPKG_OSX_ARCHITECTURES arm64' `
    -Message 'Codemagic must use a project-owned iPhoneOS vcpkg triplet.'

Assert-Contains `
    -Path $codemagicYaml `
    -Pattern '--overlay-triplets "\$VCPKG_OVERLAY_TRIPLETS"[\s\S]*verify-ios-vcpkg-libraries\.sh' `
    -Message 'Codemagic must install with the iOS overlay triplet and verify native vcpkg libraries before Rust linking.'

Assert-Contains `
    -Path $codemagicYaml `
    -Pattern 'set -euo pipefail[\s\S]*"libvpx:\$VCPKG_TRIPLET"[\s\S]*"libyuv:\$VCPKG_TRIPLET"' `
    -Message 'Codemagic iOS vcpkg step must install only target libvpx/libyuv instead of the full manifest host dependency graph.'

Assert-Contains `
    -Path $verifyVcpkg `
    -Pattern 'platform MACOS[\s\S]*exit 1' `
    -Message 'iOS vcpkg verification must fail early if libyuv contains macOS objects.'

Assert-Contains `
    -Path $verifyVcpkg `
    -Pattern 'libyuv\.a" ''convert_argb\\\.cc\\\.o\$''' `
    -Message 'iOS vcpkg verification must inspect the libyuv object that failed in Codemagic.'

Write-Host 'KQ iOS Rust linkage checks passed'
