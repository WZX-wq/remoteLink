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
    -Pattern 'Future<void> _openMembershipSheet\(\) async \{[\s\S]*if \(isIOS\) \{[\s\S]*Membership purchase is being prepared for iPhone\.[\s\S]*return;' `
    -Message 'iOS must stop before it creates an external membership order or opens a third-party payment app.'

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
