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
$xcodeProject = Join-Path $Root 'flutter/ios/Runner.xcodeproj/project.pbxproj'
$githubWorkflow = Join-Path $Root '.github/workflows/ios-development-build.yml'
$archiveSigningConfigurator = Join-Path $Root 'scripts/configure-ios-archive-signing.py'
$gitignore = Join-Path $Root '.gitignore'

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
    -Pattern '(?s)kq-remote-link-ios-nosign:.*FLUTTER_BUILD_NUMBER:\s*4073' `
    -Message 'The unsigned Codemagic iOS workflow must keep the documented local build number.'

Assert-Contains `
    -Path $codemagic `
    -Pattern '(?s)kq-remote-link-ios-testflight:.*Build signed IPA.*--build-number "\$BUILD_NUMBER"' `
    -Message 'The TestFlight workflow must use Codemagic build numbers to avoid duplicate uploads.'

Assert-Contains `
    -Path $buildDoc `
    -Pattern 'Flutter 3\.44\.5[\s\S]*com\.kunqiong\.remotelink\.broadcast[\s\S]*group\.com\.kunqiong\.remotelink' `
    -Message 'iOS build documentation must record the pinned Flutter version, extension Bundle ID, and App Group.'

Assert-Contains `
    -Path $codemagic `
    -Pattern '(?s)publishing:\s*app_store_connect:\s*api_key:\s*\$APP_STORE_CONNECT_PRIVATE_KEY\s*key_id:\s*\$APP_STORE_CONNECT_KEY_IDENTIFIER\s*issuer_id:\s*\$APP_STORE_CONNECT_ISSUER_ID' `
    -Message 'Codemagic must publish the IPA through its App Store Connect publishing configuration.'

Assert-NotContains `
    -Path $codemagic `
    -Pattern 'xcrun altool|--upload-package|--apple-id|--bundle-short-version-string|--bundle-version|--asc-public-id' `
    -Message 'Codemagic must not use the retired altool upload path or unsupported metadata flags.'

$developmentTeamCount = [regex]::Matches(
    (Get-Content -LiteralPath $xcodeProject -Raw -Encoding UTF8),
    'DEVELOPMENT_TEAM = G4C3ADW2F4;'
).Count
if ($developmentTeamCount -ne 6) {
    throw 'All Runner and KQScreenBroadcast build configurations must use the supplied G4C3ADW2F4 development team.'
}

if (-not (Test-Path -LiteralPath $githubWorkflow)) {
    throw 'GitHub development signing workflow is missing.'
}

Assert-Contains `
    -Path $githubWorkflow `
    -Pattern 'workflow_dispatch:' `
    -Message 'GitHub development signing must be manually dispatched.'

Assert-Contains `
    -Path $githubWorkflow `
    -Pattern 'IOS_SIGNING_CERTIFICATE_BASE64' `
    -Message 'GitHub signing workflow must read the signing certificate from a secret.'

Assert-Contains `
    -Path $githubWorkflow `
    -Pattern 'IOS_SIGNING_CERTIFICATE_PASSWORD' `
    -Message 'GitHub signing workflow must read the certificate password from a secret.'

Assert-Contains `
    -Path $githubWorkflow `
    -Pattern 'IOS_MAIN_PROVISIONING_PROFILE_BASE64' `
    -Message 'GitHub signing workflow must read the main provisioning profile from a secret.'

Assert-Contains `
    -Path $githubWorkflow `
    -Pattern 'IOS_BROADCAST_PROVISIONING_PROFILE_BASE64' `
    -Message 'GitHub signing workflow must read the broadcast provisioning profile from a secret.'

Assert-Contains `
    -Path $githubWorkflow `
    -Pattern 'security create-keychain[\s\S]*security import[\s\S]*security set-key-partition-list' `
    -Message 'GitHub signing workflow must import the certificate into a temporary macOS keychain.'

Assert-Contains `
    -Path $githubWorkflow `
    -Pattern '"method": "development"[\s\S]*"signingStyle": "manual"[\s\S]*flutter build ipa --release[\s\S]*--export-options-plist' `
    -Message 'GitHub signing workflow must export a development IPA with explicit export options.'

if (-not (Test-Path -LiteralPath $archiveSigningConfigurator)) {
    throw 'The archive-signing configurator is missing.'
}

Assert-Contains `
    -Path $githubWorkflow `
    -Pattern 'Configure manual archive signing[\s\S]*configure-ios-archive-signing\.py[\s\S]*--main-profile "\$IOS_MAIN_PROFILE_NAME"[\s\S]*--broadcast-profile "\$IOS_BROADCAST_PROFILE_NAME"[\s\S]*flutter build ipa --release' `
    -Message 'GitHub signing workflow must configure both targets for manual provisioning before the archive phase.'

Assert-Contains `
    -Path $archiveSigningConfigurator `
    -Pattern 'CODE_SIGN_STYLE = Manual;[\s\S]*PROVISIONING_PROFILE_SPECIFIER' `
    -Message 'The archive-signing configurator must make Xcode use explicit provisioning profiles.'

Assert-Contains `
    -Path $githubWorkflow `
    -Pattern 'actions/upload-artifact@v4[\s\S]*\.ipa' `
    -Message 'GitHub signing workflow must upload the signed IPA artifact.'

Assert-Contains `
    -Path $githubWorkflow `
    -Pattern 'BUILD_NAME: \$\{\{ inputs\.build_name \}\}' `
    -Message 'GitHub signing workflow must pass dispatch inputs through an environment variable.'

Assert-NotContains `
    -Path $githubWorkflow `
    -Pattern '--build-name "\$\{\{ inputs\.build_name \}\}"' `
    -Message 'GitHub signing workflow must not interpolate dispatch inputs directly into a shell command.'

Assert-NotContains `
    -Path $githubWorkflow `
    -Pattern 'CERTIFICATE_PASSWORD\.txt|RemoteLink-Apple-Development\.p12|RemoteLink-Development\.mobileprovision|RemoteLink-Broadcast-Development\.mobileprovision' `
    -Message 'GitHub signing workflow must not reference local signing material files.'

Assert-Contains `
    -Path $gitignore `
    -Pattern '!/\.github/workflows/[\s\S]*\.github/workflows/\*[\s\S]*!/\.github/workflows/ios-development-build\.yml' `
    -Message 'Only the iOS development-signing workflow must be explicitly trackable.'

Write-Host 'KQ iOS build readiness checks passed'
