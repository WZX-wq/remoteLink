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

$accountPage = Join-Path $Root 'flutter/lib/mobile/pages/account_page.dart'
$appDelegate = Join-Path $Root 'flutter/ios/Runner/AppDelegate.swift'
$infoPlist = Join-Path $Root 'flutter/ios/Runner/Info.plist'

Assert-Contains `
    -Path $accountPage `
    -Pattern 'if \(isAndroid \|\| isIOS\) \{[\s\S]*AndroidChannel\.kOpenAlipayHtml' `
    -Message 'iOS Alipay HTML checkout must use the native payment channel instead of url_launcher data HTML.'

Assert-Contains `
    -Path $accountPage `
    -Pattern 'if \(isAndroid \|\| isIOS\) \{[\s\S]*AndroidChannel\.kOpenPaymentUri' `
    -Message 'iOS payment URI launch must use the native payment channel.'

Assert-Contains `
    -Path $appDelegate `
    -Pattern 'import WebKit[\s\S]*FlutterMethodChannel\(name: "mChannel"[\s\S]*open_alipay_html[\s\S]*open_payment_uri' `
    -Message 'iOS AppDelegate must register the payment MethodChannel handlers.'

Assert-Contains `
    -Path $appDelegate `
    -Pattern 'WKNavigationDelegate[\s\S]*loadHTMLString[\s\S]*UIApplication\.shared\.open' `
    -Message 'iOS Alipay HTML checkout must load the cashier form in WKWebView and hand off custom schemes to Alipay.'

Assert-Contains `
    -Path $infoPlist `
    -Pattern '<key>LSApplicationQueriesSchemes</key>[\s\S]*<string>alipays</string>[\s\S]*<string>alipayqr</string>[\s\S]*<string>alipay</string>' `
    -Message 'iOS Info.plist must whitelist Alipay URL schemes.'

Assert-Contains `
    -Path $accountPage `
    -Pattern 'Alipay is not installed\. Please install Alipay and try again\.' `
    -Message 'iOS Alipay unavailable state must tell the user to install Alipay instead of showing a QR fallback.'

Assert-Contains `
    -Path $accountPage `
    -Pattern 'isMobileAlipayUnavailable\s*=\s*launchState == _KqPaymentLaunchState\.unavailable[\s\S]*payType == 2[\s\S]*\(isAndroid \|\| isIOS\)' `
    -Message 'Mobile Alipay unavailable state must be detected as a missing-app terminal state.'

Assert-Contains `
    -Path $accountPage `
    -Pattern 'shouldShowQrFallback\s*=\s*launchState == _KqPaymentLaunchState\.unavailable &&[\s\S]*!isMobileAlipayUnavailable' `
    -Message 'Mobile Alipay unavailable state must cancel the payment instead of enabling QR fallback.'

Assert-Contains `
    -Path $accountPage `
    -Pattern 'order\s*=\s*shouldShowQrFallback \|\|[\s\S]*launchState == _KqPaymentLaunchState\.opened[\s\S]*\? nextOrder[\s\S]*: null' `
    -Message 'iOS unavailable Alipay orders must not be retained for the QR order panel.'

Assert-NotContains `
    -Path $accountPage `
    -Pattern 'showQrFallback\s*=\s*launchState == _KqPaymentLaunchState\.unavailable;' `
    -Message 'Payment unavailable must not unconditionally show the QR fallback.'

Write-Host 'KQ iOS payment checks passed'
