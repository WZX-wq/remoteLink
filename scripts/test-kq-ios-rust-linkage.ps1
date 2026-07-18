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

function Assert-GitTracks {
    param(
        [string]$RelativePath,
        [string]$Message
    )

    $null = & git -C $Root ls-files --error-unmatch $RelativePath 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw $Message
    }
}

$buildRs = Join-Path $Root 'libs/scrap/build.rs'
$modRs = Join-Path $Root 'libs/scrap/src/common/mod.rs'
$codecRs = Join-Path $Root 'libs/scrap/src/common/codec.rs'
$codemagicYaml = Join-Path $Root 'codemagic.yaml'
$iosTriplet = Join-Path $Root 'res/vcpkg/triplets/arm64-ios.cmake'
$verifyVcpkg = Join-Path $Root 'scripts/ci/verify-ios-vcpkg-libraries.sh'
$iosProject = Join-Path $Root 'flutter/ios/Runner.xcodeproj/project.pbxproj'
$iosInfoPlist = Join-Path $Root 'flutter/ios/Runner/Info.plist'
$iosExportOptions = Join-Path $Root 'flutter/ios/exportOptions.plist'
$iosBuildDoc = Join-Path $Root 'docs/ios-build.md'
$iosRunnerBridgingHeader = Join-Path $Root 'flutter/ios/Runner/Runner-Bridging-Header.h'
$iosBridgeHeader = Join-Path $Root 'flutter/ios/Runner/bridge_generated.h'
$iosBroadcastBridge = Join-Path $Root 'flutter/ios/KQScreenBroadcast/KQBroadcastBridge.h'
$iosBroadcastRust = Join-Path $Root 'src/ios_broadcast.rs'
$iosBroadcastAudio = Join-Path $Root 'src/ios_broadcast_audio.rs'
$audioServiceRs = Join-Path $Root 'src/server/audio_service.rs'
$rootLibRs = Join-Path $Root 'src/lib.rs'
$serverRs = Join-Path $Root 'src/server.rs'
$connectionRs = Join-Path $Root 'src/server/connection.rs'

Assert-Contains `
    -Path $buildRs `
    -Pattern 'kq-ios-no-aom-linkage[\s\S]*if target_os != "ios" \{[\s\S]*gen_vcpkg_package\(\s*"aom"' `
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
    -Pattern '--overlay-ports "\$VCPKG_OVERLAY_PORTS"[\s\S]*--overlay-triplets "\$VCPKG_OVERLAY_TRIPLETS"[\s\S]*verify-ios-vcpkg-libraries\.sh' `
    -Message 'Codemagic must install with project overlay ports, the iOS overlay triplet, and verify native vcpkg libraries before Rust linking.'

Assert-Contains `
    -Path $codemagicYaml `
    -Pattern 'set -euo pipefail[\s\S]*"libvpx:\$VCPKG_TRIPLET"[\s\S]*"libyuv:\$VCPKG_TRIPLET"[\s\S]*--classic' `
    -Message 'Codemagic iOS vcpkg step must use classic mode and install only target libvpx/libyuv instead of the full manifest host dependency graph.'

Assert-Contains `
    -Path $codemagicYaml `
    -Pattern '"opus:\$VCPKG_TRIPLET"[\s\S]*--classic' `
    -Message 'Codemagic iOS vcpkg step must install target opus for magnum-opus headers and static library.'

Assert-Contains `
    -Path $verifyVcpkg `
    -Pattern 'platform MACOS[\s\S]*exit 1' `
    -Message 'iOS vcpkg verification must fail early if libyuv contains macOS objects.'

Assert-Contains `
    -Path $verifyVcpkg `
    -Pattern 'libyuv\.a" ''convert_argb\\\.cc\\\.o\$''' `
    -Message 'iOS vcpkg verification must inspect the libyuv object that failed in Codemagic.'

Assert-Contains `
    -Path $verifyVcpkg `
    -Pattern 'opus/opus_multistream\.h' `
    -Message 'iOS vcpkg verification must fail early if opus headers required by magnum-opus are missing.'

Assert-Contains `
    -Path $verifyVcpkg `
    -Pattern 'libopus\.a" ''\\\.o\$''' `
    -Message 'iOS vcpkg verification must inspect libopus before Rust linking.'

Assert-Contains `
    -Path $codemagicYaml `
    -Pattern 'BUNDLE_ID:\s*com\.kunqiong\.remotelink[\s\S]*fetch-signing-files "\$BUNDLE_ID"[\s\S]*--type IOS_APP_STORE[\s\S]*publishing:\s*app_store_connect:' `
    -Message 'Codemagic TestFlight workflow must fetch App Store signing files for the registered KQ Remote Link Bundle ID before uploading its IPA.'

Assert-Contains `
    -Path $iosProject `
    -Pattern 'PRODUCT_BUNDLE_IDENTIFIER = com\.kunqiong\.remotelink;' `
    -Message 'Runner Xcode project must use the registered KQ Remote Link Bundle ID.'

Assert-Contains `
    -Path $iosInfoPlist `
    -Pattern '<string>com\.kunqiong\.remotelink</string>' `
    -Message 'Runner Info.plist URL name must match the registered KQ Remote Link Bundle ID.'

Assert-Contains `
    -Path $iosExportOptions `
    -Pattern '<key>com\.kunqiong\.remotelink</key>[\s\S]*<string>match AdHoc com\.kunqiong\.remotelink</string>' `
    -Message 'iOS export options must reference the registered KQ Remote Link Bundle ID.'

Assert-Contains `
    -Path $iosBuildDoc `
    -Pattern 'com\.kunqiong\.remotelink' `
    -Message 'iOS build documentation must show the registered KQ Remote Link Bundle ID.'

Assert-Contains `
    -Path $iosRunnerBridgingHeader `
    -Pattern '#import "bridge_generated\.h"' `
    -Message 'Runner bridging header must import the flutter_rust_bridge C header.'

Assert-Contains `
    -Path $iosBridgeHeader `
    -Pattern 'dummy_method_to_enforce_bundling[\s\S]*session_get_rgba' `
    -Message 'iOS must include the generated flutter_rust_bridge C header used by AppDelegate.swift.'

Assert-Contains `
    -Path $modRs `
    -Pattern 'target_os = "ios"[\s\S]*mod ios;[\s\S]*pub use self::ios::\*;' `
    -Message 'scrap must select the ReplayKit-backed iOS display and capturer.'

Assert-Contains `
    -Path $rootLibRs `
    -Pattern 'mod server;[\s\S]*mod rendezvous_mediator;[\s\S]*pub mod ipc;[\s\S]*target_os = "ios"[\s\S]*mod ios_broadcast;' `
    -Message 'iOS builds must include the host server, rendezvous, IPC, and ReplayKit bridge.'

Assert-Contains `
    -Path $serverRs `
    -Pattern 'server\.add_service\(Box::new\(display_service::new\(\)\)\);' `
    -Message 'iOS host mode must publish display metadata and video service state.'

Assert-Contains `
    -Path $connectionRs `
    -Pattern '#\[cfg\(target_os = "android"\)\][\s\S]*use scrap::android::\{call_main_service_key_event, call_main_service_pointer_input\};' `
    -Message 'iOS view-only hosting must not call Android remote-input services.'

Assert-Contains `
    -Path $iosBroadcastBridge `
    -Pattern 'kq_ios_broadcast_start[\s\S]*kq_ios_broadcast_push_bgra[\s\S]*kq_ios_broadcast_push_audio_f32[\s\S]*kq_ios_broadcast_stop' `
    -Message 'ReplayKit target must import the Rust host, video, and audio ABI.'

Assert-Contains `
    -Path $iosBroadcastRust `
    -Pattern 'start_server\(true\)[\s\S]*submit_bgra_frame' `
    -Message 'ReplayKit Rust bridge must start the host and feed ReplayKit frames.'

Assert-Contains `
    -Path $iosBroadcastAudio `
    -Pattern 'AUDIO_FRAME_SAMPLES[\s\S]*push_audio_samples[\s\S]*take_audio_frame' `
    -Message 'ReplayKit Rust bridge must queue application PCM for the Opus audio service.'

Assert-Contains `
    -Path $serverRs `
    -Pattern 'server\.add_service\(Box::new\(audio_service::new\(\)\)\);' `
    -Message 'iOS host mode must publish the audio service with the display service.'

Assert-Contains `
    -Path $audioServiceRs `
    -Pattern 'target_os = "ios"[\s\S]*ios_broadcast_audio::take_audio_frame' `
    -Message 'The audio service must consume ReplayKit PCM on iOS instead of opening a device input.'

Assert-Contains `
    -Path $iosBroadcastRust `
    -Pattern 'RendezvousMediator::restart' `
    -Message 'ReplayKit Rust bridge must restart or stop the existing rendezvous host safely.'

Assert-Contains `
    -Path $iosProject `
    -Pattern 'liblibrustdesk\.a in Frameworks[\s\S]*SWIFT_OBJC_BRIDGING_HEADER = KQScreenBroadcast/KQBroadcastBridge\.h;' `
    -Message 'Broadcast extension must link Rust and import its dedicated C header.'

Assert-GitTracks `
    -RelativePath 'flutter/ios/Runner/bridge_generated.h' `
    -Message 'iOS generated bridge header must be tracked so Codemagic fresh clones can build.'

Write-Host 'KQ iOS Rust linkage checks passed'
