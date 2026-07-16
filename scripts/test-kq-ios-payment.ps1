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
$paymentPolicy = Join-Path $Root 'flutter/lib/mobile/ios_membership_payment_policy.dart'
$appDelegate = Join-Path $Root 'flutter/ios/Runner/AppDelegate.swift'
$infoPlist = Join-Path $Root 'flutter/ios/Runner/Info.plist'

Assert-Contains `
    -Path $accountPage `
    -Pattern 'KqIosMembershipPaymentPolicy\.routeFor\(isIOS: isIOS\)' `
    -Message 'The membership sheet must resolve the iOS payment policy before it creates an order.'

Assert-Contains `
    -Path $accountPage `
    -Pattern 'KqIosMembershipPaymentRoute\.appleInAppPurchaseRequired[\s\S]*return;' `
    -Message 'App Store iOS builds must stop before they create an external membership order.'

Assert-Contains `
    -Path $paymentPolicy `
    -Pattern "KQ_IOS_INTERNAL_DIRECT_PAYMENT" `
    -Message 'Direct iOS payment must require an explicit internal-build flag.'

Assert-Contains `
    -Path $paymentPolicy `
    -Pattern 'defaultValue: false' `
    -Message 'Direct iOS payment must remain disabled by default.'

Assert-NotContains `
    -Path $accountPage `
    -Pattern 'if \(isAndroid \|\| isIOS\)' `
    -Message 'iOS must not share the Android external-payment launch path.'

Assert-NotContains `
    -Path $appDelegate `
    -Pattern 'WebKit|WKNavigationDelegate|open_alipay_html|open_payment_uri|openAlipayHtml|openPaymentUri' `
    -Message 'The iOS runner must not include an external Alipay or payment-URI bridge.'

Assert-NotContains `
    -Path $infoPlist `
    -Pattern 'LSApplicationQueriesSchemes|alipays|alipayqr|weixin|wechat' `
    -Message 'The iOS bundle must not declare third-party payment URL schemes while iOS purchase is disabled.'

Write-Host 'KQ iOS payment checks passed'
