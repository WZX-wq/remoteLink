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
$mobileServerPage = Join-Path $Root 'flutter/lib/mobile/pages/server_page.dart'
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

Assert-NotContains `
    -Path $mobileConnectionPage `
    -Pattern 'mainGetLastRemoteId\(' `
    -Message 'Mobile connection page must start with an empty remote ID field instead of auto-filling the last remote ID.'

Assert-Contains `
    -Path $mobileServerPage `
    -Pattern 'if \(isAndroid\) \{[\s\S]*gFFI\.serverModel\.checkAndroidPermission\(\);[\s\S]*\}' `
    -Message 'iOS Share screen page must not invoke Android permission checks.'

Assert-Contains `
    -Path $mobileServerPage `
    -Pattern 'if \(isIOS\) \{[\s\S]*return const _IOSScreenShareBroadcastMvp\(\);[\s\S]*\}' `
    -Message 'iOS Share screen page must show the ReplayKit broadcast MVP instead of Android service controls.'

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
