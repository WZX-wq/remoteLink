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

$mobileHomePage = Join-Path $Root 'flutter/lib/mobile/pages/home_page.dart'
$mobileConnectionPage = Join-Path $Root 'flutter/lib/mobile/pages/connection_page.dart'
$mobileRemotePage = Join-Path $Root 'flutter/lib/mobile/pages/remote_page.dart'
$mobileServerPage = Join-Path $Root 'flutter/lib/mobile/pages/server_page.dart'
$common = Join-Path $Root 'flutter/lib/common.dart'
$connectionModel = Join-Path $Root 'flutter/lib/models/model.dart'
$connectionFailurePresentation = Join-Path $Root 'flutter/lib/models/connection_failure_presentation.dart'
$videoRenderPolicy = Join-Path $Root 'flutter/lib/models/video_render_policy.dart'
$mobileCapabilityPolicy = Join-Path $Root 'flutter/lib/models/mobile_platform_capability_policy.dart'
$nativeModel = Join-Path $Root 'flutter/lib/models/native_model.dart'
$iosProject = Join-Path $Root 'flutter/ios/Runner.xcodeproj/project.pbxproj'

Assert-Contains `
    -Path $mobileHomePage `
    -Pattern 'if \(!bind\.isOutgoingOnly\(\)\) \{[\s\S]*_pages\.add\(ServerPage\(\)\);[\s\S]*\}' `
    -Message 'iOS mobile home must include the Share screen tab when incoming control is allowed.'

Assert-NotContains `
    -Path $mobileHomePage `
    -Pattern 'isAndroid\s*&&\s*!bind\.isOutgoingOnly\(\)' `
    -Message 'Share screen tab must not be gated to Android only.'

Assert-Contains `
    -Path $mobileConnectionPage `
    -Pattern 'Future<void> _restoreLastConnection\(\) async \{[\s\S]*if \(isIOS\) return;[\s\S]*mainGetLastRemoteId\(' `
    -Message 'iOS connection page must start with an empty remote ID while Android may restore its last successful connection.'

Assert-Contains `
    -Path $mobileHomePage `
    -Pattern 'bottomNavigationBar:\s*MobileBottomNavigationSafeArea\([\s\S]*isIOS:\s*isIOS,[\s\S]*margin:\s*const EdgeInsets\.fromLTRB\(14,\s*0,\s*14,\s*0\)' `
    -Message 'Mobile bottom navigation must use the tested iOS safe-area helper.'

Assert-Contains `
    -Path $mobileRemotePage `
    -Pattern "showLoading\(translate\('Connecting\.\.\.'\),\s*onCancel:\s*closeConnection\)" `
    -Message 'Mobile remote route must expose a cancellable connecting state.'

Assert-Contains `
    -Path $mobileRemotePage `
    -Pattern 'onPressed:\s*\(\) => clientClose\(sessionId, gFFI\)' `
    -Message 'Mobile remote route must expose an explicit disconnect action.'

Assert-Contains `
    -Path $connectionFailurePresentation `
    -Pattern 'class KqConnectionFailureCopy[\s\S]*bool shouldCloseKqConnectionFailure\([\s\S]*KqConnectionFailureCopy presentKqConnectionFailure\(' `
    -Message 'KQ connection failures must use the pure bilingual presentation helper.'

Assert-Contains `
    -Path $connectionModel `
    -Pattern 'shouldCloseKqConnectionFailure\([\s\S]*isMobilePlatform:\s*isMobile[\s\S]*isIOSPlatform:\s*isIOS[\s\S]*final isKqIOS[\s\S]*if \(isKqIOS\) \{[\s\S]*final navigator = failedRoute\?\.navigator \?\? globalKey\.currentState;[\s\S]*removeRegisteredMobileRemoteRoute\([\s\S]*stateGlobal\.isInMainPage = true;[\s\S]*showToast\(reason' `
    -Message 'KQ mobile connection errors must remove the registered remote route and show sanitized copy on HomePage.'

Assert-Contains `
    -Path $connectionModel `
    -Pattern 'Route<dynamic>\? mobileRemoteRoute;' `
    -Message 'FFI must retain the exact mobile remote route for failure cleanup.'

Assert-Contains `
    -Path $common `
    -Pattern 'final remoteRoute = MaterialPageRoute[\s\S]*gFFI\.mobileRemoteRoute = remoteRoute;[\s\S]*Navigator\.push(?:<void>)?\(context, remoteRoute\)' `
    -Message 'The mobile connection flow must register the exact remote route before pushing it.'

Assert-NotContains `
    -Path $connectionModel `
    -Pattern 'if \(isKqIOS\) \{[\s\S]*navigator\.pop\(\);[\s\S]*if \(isKqDesktop\)' `
    -Message 'Mobile failure cleanup must not pop whichever route happens to be on top.'

Assert-Contains `
    -Path $connectionModel `
    -Pattern "type == 'kq-network-diagnostics'[\s\S]*if \(isIOS && !isWeb\)[\s\S]*_notifyConnectionFailureAndClose\('error', 'Connection Error', text\)[\s\S]*showKqNetworkDiagnosticsDialog" `
    -Message 'Mobile network diagnostics must use sanitized failure copy instead of the desktop technical panel.'

Assert-Contains `
    -Path $videoRenderPolicy `
    -Pattern 'bool shouldDeferSoftwareFirstFrameUntilPaint\([\s\S]*isWindowsPlatform \|\| isIOSPlatform[\s\S]*waitingForFirstImage[\s\S]*!hasPaintedFrame' `
    -Message 'iOS software video must keep the connection overlay until a frame is actually painted.'

Assert-Contains `
    -Path $connectionModel `
    -Pattern 'shouldDeferSoftwareFirstFrameUntilPaint\([\s\S]*isIOSPlatform:\s*isIOS[\s\S]*first-frame-ui-deferred-until-paint' `
    -Message 'The RGBA event path must defer iOS first-frame completion to the mobile canvas.'

Assert-Contains `
    -Path $mobileRemotePage `
    -Pattern 'void _handleIOSSoftwarePaint\(ImageModel model\)[\s\S]*model\.markFramePainted\(display\)[\s\S]*onEvent2UIRgba\(updateCanvasLayout:\s*false\)' `
    -Message 'The iOS remote canvas must finalize the first frame only after paint.'

Assert-Contains `
    -Path $mobileRemotePage `
    -Pattern 'void _scheduleOrientationRefresh\(Orientation orientation\)[\s\S]*orientation-changed' `
    -Message 'The iOS remote canvas must refresh after orientation changes.'

Assert-Contains `
    -Path $mobileRemotePage `
    -Pattern "bool _wasBackgrounded = false;[\s\S]*_refreshIOSRemoteVideo\('app-resumed'\)[\s\S]*return SizedBox\.expand\(" `
    -Message 'The iOS remote canvas must fill its viewport and recover after returning from background.'

Assert-Contains `
    -Path $mobileCapabilityPolicy `
    -Pattern 'static const ios = MobilePlatformCapabilities\([\s\S]*canHostViewOnlyBroadcast:\s*true,[\s\S]*canReceiveRemoteInput:\s*false' `
    -Message 'iOS capability policy must allow ReplayKit broadcast without Android-style remote input.'

Assert-Contains `
    -Path $mobileServerPage `
    -Pattern 'if \(mobilePlatformCapabilities\.canHostViewOnlyBroadcast\) \{[\s\S]*return const _IOSScreenShareBroadcastMvp\(\);[\s\S]*\}' `
    -Message 'iOS Share screen page must show the ReplayKit broadcast MVP instead of Android service controls.'

Assert-Contains `
    -Path $mobileServerPage `
    -Pattern 'if \(mobilePlatformCapabilities\.canReceiveRemoteInput\) \{[\s\S]*gFFI\.serverModel\.checkAndroidPermission\(\);[\s\S]*\}' `
    -Message 'Android permission checks must be guarded by the remote-input platform capability.'

Assert-Contains `
    -Path $mobileServerPage `
    -Pattern 'class _IOSScreenShareBroadcastMvp extends StatefulWidget' `
    -Message 'iOS Share screen page must have a dedicated ReplayKit broadcast MVP widget.'

Assert-Contains `
    -Path $mobileServerPage `
    -Pattern "invokeMethod<.*>\('show_broadcast_picker'\)|invokeMethod\('show_broadcast_picker'\)" `
    -Message 'iOS Share screen page must open the native ReplayKit broadcast picker.'

Assert-Contains `
    -Path $mobileServerPage `
    -Pattern 'void checkService\(\) async \{[\s\S]*if \(!isAndroid\) return;[\s\S]*gFFI\.invokeMethod\("check_service"\);' `
    -Message 'checkService must not run Android service checks on iOS.'

Assert-Contains `
    -Path $nativeModel `
    -Pattern 'invokeMethod\(String method, \[dynamic arguments\]\) async \{[\s\S]*if \(!isAndroid\) return Future<bool>\(\(\) => false\);' `
    -Message 'The Android server-control MethodChannel path must remain Android-only; iOS ReplayKit uses its own native channel calls.'

Assert-Contains `
    -Path $iosProject `
    -Pattern 'com\.apple\.product-type\.app-extension' `
    -Message 'The iOS project must contain the ReplayKit broadcast upload extension target.'

Write-Host 'KQ iOS mobile UI checks passed'
