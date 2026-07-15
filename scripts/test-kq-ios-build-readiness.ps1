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

    $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ($content -notmatch $Pattern) {
        throw $Message
    }
}

function Assert-NotContains {
    param(
        [string]$Path,
        [string]$Pattern,
        [string]$Message
    )

    $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ($content -match $Pattern) {
        throw $Message
    }
}

$podfile = Join-Path $Root 'flutter/ios/Podfile'
$infoPlist = Join-Path $Root 'flutter/ios/Runner/Info.plist'
$exportOptions = Join-Path $Root 'flutter/ios/exportOptions.plist'
$codemagic = Join-Path $Root 'codemagic.yaml'
$buildScript = Join-Path $Root 'flutter/build_ios.sh'
$buildDoc = Join-Path $Root 'docs/ios-build.md'

Assert-Contains `
    -Path $podfile `
    -Pattern "platform :ios, '13\.0'[\s\S]*IPHONEOS_DEPLOYMENT_TARGET.*kq_ios_deployment_target" `
    -Message 'iOS Podfile must keep every pod on the iOS 13 deployment target.'

Assert-Contains `
    -Path $infoPlist `
    -Pattern 'NSLocalNetworkUsageDescription[\s\S]*NSMicrophoneUsageDescription[\s\S]*NSPhotoLibraryUsageDescription[\s\S]*NSPhotoLibraryAddUsageDescription' `
    -Message 'iOS Info.plist must include user-facing local network, microphone, and photo read/write permission descriptions.'

Assert-Contains `
    -Path $exportOptions `
    -Pattern '<key>com\.kunqiong\.remotelink</key>[\s\S]*<key>com\.kunqiong\.remotelink\.broadcast</key>' `
    -Message 'Ad Hoc export options must provide profiles for both the app and ReplayKit extension.'

Assert-Contains `
    -Path $codemagic `
    -Pattern '(?s)(flutter:\s*3\.44\.5.*){2}' `
    -Message 'Both iOS Codemagic workflows must use the repository-tested Flutter 3.44.5 toolchain.'

Assert-Contains `
    -Path $buildScript `
    -Pattern 'FLUTTER_BUILD_NUMBER:-4073[\s\S]*cargo build --features flutter --release --target "\$CARGO_TARGET" --lib[\s\S]*flutter build ios[\s\S]*--no-codesign' `
    -Message 'iOS build script must build the Rust library before producing the unsigned Flutter app.'

Assert-Contains `
    -Path $codemagic `
    -Pattern '(?s)(FLUTTER_BUILD_NUMBER:\s*4073.*){2}' `
    -Message 'Both Codemagic iOS workflows must use build number 4073, matching build_ios.sh.'

Assert-Contains `
    -Path $buildDoc `
    -Pattern 'Flutter 3\.44\.5[\s\S]*com\.kunqiong\.remotelink\.broadcast[\s\S]*group\.com\.kunqiong\.remotelink' `
    -Message 'iOS build documentation must record the pinned Flutter version, extension Bundle ID, and App Group.'

Assert-Contains `
    -Path $codemagic `
    -Pattern 'xcrun altool --upload-app -f "\$CM_BUILD_DIR/flutter/build/ios/ipa/KQRemoteLink\.ipa" -t ios[\s\S]*--apiKey "\$APP_STORE_CONNECT_KEY_IDENTIFIER"[\s\S]*--apiIssuer "\$APP_STORE_CONNECT_ISSUER_ID"' `
    -Message 'Codemagic must upload the IPA with altool upload-app syntax and its App Store Connect API key.'

Assert-NotContains `
    -Path $codemagic `
    -Pattern '--upload-package|--apple-id|--bundle-id|--bundle-short-version-string|--bundle-version|--asc-public-id' `
    -Message 'Codemagic must not pass unsupported package metadata flags to altool.'

Write-Host 'KQ iOS build readiness checks passed'
