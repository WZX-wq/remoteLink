param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'

function Assert-PathExists {
    param(
        [string]$Path,
        [string]$Message
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw $Message
    }
}

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

$extensionDir = Join-Path $Root 'flutter/ios/KQScreenBroadcast'
$sampleHandler = Join-Path $extensionDir 'SampleHandler.swift'
$broadcastBridge = Join-Path $extensionDir 'KQBroadcastBridge.h'
$extensionInfo = Join-Path $extensionDir 'Info.plist'
$extensionEntitlements = Join-Path $extensionDir 'KQScreenBroadcast.entitlements'
$runnerEntitlements = Join-Path $Root 'flutter/ios/Runner/Runner.entitlements'
$appDelegate = Join-Path $Root 'flutter/ios/Runner/AppDelegate.swift'
$iosProject = Join-Path $Root 'flutter/ios/Runner.xcodeproj/project.pbxproj'
$serverPage = Join-Path $Root 'flutter/lib/mobile/pages/server_page.dart'
$nativeModel = Join-Path $Root 'flutter/lib/models/native_model.dart'
$rustBroadcast = Join-Path $Root 'src/ios_broadcast.rs'
$iosCapture = Join-Path $Root 'libs/scrap/src/common/ios.rs'
$codemagic = Join-Path $Root 'codemagic.yaml'

Assert-PathExists `
    -Path $sampleHandler `
    -Message 'iOS broadcast extension must include SampleHandler.swift.'

Assert-PathExists `
    -Path $broadcastBridge `
    -Message 'iOS broadcast extension must include its Rust C ABI header.'

Assert-PathExists `
    -Path $iosCapture `
    -Message 'iOS ReplayKit capture must provide a frame-backed Scrap capturer.'

Assert-PathExists `
    -Path $extensionInfo `
    -Message 'iOS broadcast extension must include Info.plist.'

Assert-PathExists `
    -Path $extensionEntitlements `
    -Message 'iOS broadcast extension must include its own entitlements file.'

Assert-Contains `
    -Path $extensionInfo `
    -Pattern 'com\.apple\.broadcast-services-upload' `
    -Message 'Broadcast extension Info.plist must use the broadcast upload extension point.'

Assert-Contains `
    -Path $extensionInfo `
    -Pattern 'NSExtensionPrincipalClass[\s\S]*RPBroadcastProcessMode[\s\S]*RPBroadcastProcessModeSampleBuffer' `
    -Message 'Broadcast extension must receive ReplayKit sample buffers.'

Assert-NotContains `
    -Path $extensionInfo `
    -Pattern 'NSExtensionAttributes[\s\S]*RPBroadcastProcessMode' `
    -Message 'Broadcast extension must keep RPBroadcastProcessMode directly under NSExtension for current App Store Connect validation.'

Assert-Contains `
    -Path $sampleHandler `
    -Pattern 'class SampleHandler:\s*RPBroadcastSampleHandler' `
    -Message 'Broadcast extension must implement RPBroadcastSampleHandler.'

Assert-Contains `
    -Path $sampleHandler `
    -Pattern 'processSampleBuffer\([\s\S]*_ sampleBuffer: CMSampleBuffer,[\s\S]*with sampleBufferType: RPSampleBufferType[\s\S]*\)' `
    -Message 'Broadcast extension must process ReplayKit sample buffers.'

Assert-Contains `
    -Path $sampleHandler `
    -Pattern 'appGroupId\s*=\s*"group\.com\.kunqiong\.remotelink"[\s\S]*UserDefaults\(suiteName:\s*appGroupId\)' `
    -Message 'Broadcast extension must publish status through the shared App Group container.'

Assert-Contains `
    -Path $sampleHandler `
    -Pattern 'CVPixelBufferGetWidth|CVPixelBufferGetHeight' `
    -Message 'Broadcast extension must record video frame dimensions for first-frame diagnostics.'

Assert-Contains `
    -Path $sampleHandler `
    -Pattern 'CVPixelBufferLockBaseAddress[\s\S]*kq_ios_broadcast_push_bgra' `
    -Message 'Broadcast extension must submit locked ReplayKit BGRA frames to Rust.'

Assert-Contains `
    -Path $sampleHandler `
    -Pattern 'CVPixelBufferUnlockBaseAddress' `
    -Message 'Broadcast extension must unlock ReplayKit pixel buffers after submission.'

Assert-Contains `
    -Path $sampleHandler `
    -Pattern 'maxLongEdge\s*=\s*1920[\s\S]*vImageScale_ARGB8888[\s\S]*targetWidth -= targetWidth % 2' `
    -Message 'Broadcast extension must bound ReplayKit resolution and keep encoder dimensions even.'

Assert-Contains `
    -Path $sampleHandler `
    -Pattern 'kq_ios_broadcast_start' `
    -Message 'Broadcast extension must start the Rust host after its first frame.'

Assert-Contains `
    -Path $sampleHandler `
    -Pattern 'kq_ios_broadcast_pause[\s\S]*kq_ios_broadcast_resume[\s\S]*kq_ios_broadcast_stop' `
    -Message 'Broadcast extension must forward pause, resume, and stop to the Rust host.'

Assert-Contains `
    -Path $sampleHandler `
    -Pattern 'kq_broadcast_transport_state[\s\S]*kq_broadcast_remote_view_available[\s\S]*kq_broadcast_view_only' `
    -Message 'Broadcast extension must publish capture transport and view-only capability separately.'

Assert-Contains `
    -Path $runnerEntitlements `
    -Pattern 'group\.com\.kunqiong\.remotelink' `
    -Message 'Runner target must enable the shared App Group.'

Assert-Contains `
    -Path $extensionEntitlements `
    -Pattern 'group\.com\.kunqiong\.remotelink' `
    -Message 'Broadcast extension target must enable the shared App Group.'

Assert-Contains `
    -Path $appDelegate `
    -Pattern 'import ReplayKit' `
    -Message 'Runner AppDelegate must import ReplayKit to show the broadcast picker.'

Assert-Contains `
    -Path $appDelegate `
    -Pattern 'case "show_broadcast_picker"' `
    -Message 'Runner AppDelegate must expose a native broadcast picker method.'

Assert-Contains `
    -Path $appDelegate `
    -Pattern 'case "get_broadcast_status"' `
    -Message 'Runner AppDelegate must expose a native broadcast status method.'

Assert-Contains `
    -Path $appDelegate `
    -Pattern 'case "prepare_broadcast_config_dir"' `
    -Message 'Runner must prepare the shared App Group configuration directory.'

Assert-Contains `
    -Path $appDelegate `
    -Pattern 'containerURL\([\s\S]*forSecurityApplicationGroupIdentifier:\s*broadcastAppGroupId' `
    -Message 'Runner shared configuration must use the broadcast App Group container.'

Assert-Contains `
    -Path $nativeModel `
    -Pattern "invokeMethod<String>[\s\S]*'prepare_broadcast_config_dir'" `
    -Message 'Flutter must initialize Rust from the shared broadcast configuration directory.'

Assert-Contains `
    -Path $appDelegate `
    -Pattern '"transportState"[\s\S]*"remoteViewAvailable"[\s\S]*"viewOnly"' `
    -Message 'Runner must return capture transport readiness without treating frame capture as remote viewing.'

Assert-Contains `
    -Path $appDelegate `
    -Pattern 'RPSystemBroadcastPickerView' `
    -Message 'Runner AppDelegate must use RPSystemBroadcastPickerView.'

Assert-Contains `
    -Path $appDelegate `
    -Pattern 'broadcastExtensionBundleId\s*=\s*"com\.kunqiong\.remotelink\.broadcast"[\s\S]*preferredExtension\s*=\s*broadcastExtensionBundleId' `
    -Message 'Broadcast picker must prefer the KQ broadcast extension bundle id.'

Assert-Contains `
    -Path $serverPage `
    -Pattern 'class _IOSScreenShareBroadcastMvp extends StatefulWidget' `
    -Message 'iOS Share screen page must render the ReplayKit MVP screen.'

Assert-Contains `
    -Path $serverPage `
    -Pattern "invokeMethod<.*>\('show_broadcast_picker'\)|invokeMethod\('show_broadcast_picker'\)" `
    -Message 'iOS Share screen page must call the native broadcast picker.'

Assert-Contains `
    -Path $serverPage `
    -Pattern "invokeMethod<.*>\('get_broadcast_status'\)|invokeMethod\('get_broadcast_status'\)" `
    -Message 'iOS Share screen page must read broadcast extension status.'

Assert-Contains `
    -Path $serverPage `
    -Pattern "remoteViewAvailable" `
    -Message 'iOS broadcast page must read remote viewing availability separately from capture state.'

Assert-NotContains `
    -Path $serverPage `
    -Pattern 'Service not connected|remote viewing service is not connected|远程观看服务尚未接入|capture_only' `
    -Message 'iOS broadcast page must not describe the implemented transport as capture-only or unavailable.'

Assert-Contains `
    -Path $serverPage `
    -Pattern 'Sharing started, waiting for another device' `
    -Message 'iOS broadcast page must distinguish a ready transport from an actual remote viewer.'

Assert-Contains `
    -Path $serverPage `
    -Pattern 'view-only' `
    -Message 'iOS broadcast page must state that the shared screen is view-only.'

Assert-Contains `
    -Path $serverPage `
    -Pattern "audioSupported" `
    -Message 'iOS broadcast page must expose whether broadcast audio is actually supported.'

Assert-NotContains `
    -Path $serverPage `
    -Pattern 'Available to view|App audio frames|Mic audio frames' `
    -Message 'iOS broadcast page must not advertise an unverified viewer or unsupported broadcast audio.'

Assert-NotContains `
    -Path $serverPage `
    -Pattern 'return const _IOSScreenShareUnavailable\(\);' `
    -Message 'iOS Share screen page must no longer stop at the unavailable placeholder.'

Assert-Contains `
    -Path $iosProject `
    -Pattern '/\* KQScreenBroadcast \*/ = \{[\s\S]*isa = PBXNativeTarget;' `
    -Message 'Xcode project must include the KQScreenBroadcast target.'

Assert-Contains `
    -Path $iosProject `
    -Pattern 'com\.apple\.product-type\.app-extension' `
    -Message 'Xcode project must include an app extension product type.'

Assert-Contains `
    -Path $iosProject `
    -Pattern 'PRODUCT_BUNDLE_IDENTIFIER = com\.kunqiong\.remotelink\.broadcast;' `
    -Message 'Broadcast extension target must use the expected bundle id.'

Assert-Contains `
    -Path $iosProject `
    -Pattern 'CODE_SIGN_ENTITLEMENTS = KQScreenBroadcast/KQScreenBroadcast\.entitlements;' `
    -Message 'Broadcast extension target must use its entitlements file.'

Assert-Contains `
    -Path $iosProject `
    -Pattern 'Embed App Extensions' `
    -Message 'Runner target must embed the broadcast extension.'

Assert-Contains `
    -Path $iosProject `
    -Pattern 'liblibrustdesk\.a in Frameworks[\s\S]*A1B2C3D4000000000000000A /\* Frameworks \*/' `
    -Message 'Broadcast extension target must link the Rust static library.'

Assert-Contains `
    -Path $rustBroadcast `
    -Pattern 'kq_ios_broadcast_start[\s\S]*kq_ios_broadcast_push_bgra[\s\S]*kq_ios_broadcast_stop' `
    -Message 'Rust must export the ReplayKit host lifecycle and frame submission ABI.'

Assert-Contains `
    -Path $iosCapture `
    -Pattern 'frame\.width\(\) != self\.display\.width\(\) \|\| frame\.height\(\) != self\.display\.height\(\)[\s\S]*io::ErrorKind::Interrupted' `
    -Message 'ReplayKit orientation changes must interrupt the old capturer before it encodes a frame with stale dimensions.'

Assert-Contains `
    -Path $codemagic `
    -Pattern 'EXTENSION_BUNDLE_ID:\s*com\.kunqiong\.remotelink\.broadcast' `
    -Message 'Codemagic must know the broadcast extension bundle id.'

Assert-Contains `
    -Path $codemagic `
    -Pattern 'fetch-signing-files "\$EXTENSION_BUNDLE_ID"[\s\S]*--type IOS_APP_STORE' `
    -Message 'Codemagic must fetch an App Store provisioning profile for the broadcast extension.'

Write-Host 'KQ iOS broadcast extension checks passed'
