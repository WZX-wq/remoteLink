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
$extensionInfo = Join-Path $extensionDir 'Info.plist'
$extensionEntitlements = Join-Path $extensionDir 'KQScreenBroadcast.entitlements'
$runnerEntitlements = Join-Path $Root 'flutter/ios/Runner/Runner.entitlements'
$appDelegate = Join-Path $Root 'flutter/ios/Runner/AppDelegate.swift'
$iosProject = Join-Path $Root 'flutter/ios/Runner.xcodeproj/project.pbxproj'
$serverPage = Join-Path $Root 'flutter/lib/mobile/pages/server_page.dart'
$codemagic = Join-Path $Root 'codemagic.yaml'

Assert-PathExists `
    -Path $sampleHandler `
    -Message 'iOS broadcast extension must include SampleHandler.swift.'

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
    -Path $codemagic `
    -Pattern 'EXTENSION_BUNDLE_ID:\s*com\.kunqiong\.remotelink\.broadcast' `
    -Message 'Codemagic must know the broadcast extension bundle id.'

Assert-Contains `
    -Path $codemagic `
    -Pattern 'fetch-signing-files "\$EXTENSION_BUNDLE_ID"[\s\S]*--type IOS_APP_STORE' `
    -Message 'Codemagic must fetch an App Store provisioning profile for the broadcast extension.'

Write-Host 'KQ iOS broadcast extension checks passed'
