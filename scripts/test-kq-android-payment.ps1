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
$androidCommon = Join-Path $Root 'flutter/android/app/src/main/kotlin/com/carriez/flutter_hbb/common.kt'

Assert-Contains `
    -Path $androidCommon `
    -Pattern 'const val ALIPAY_PACKAGE_NAME = "com\.eg\.android\.AlipayGphone"' `
    -Message 'Android payment code must centralize the Alipay package name.'

Assert-Contains `
    -Path $androidCommon `
    -Pattern 'fun isPackageInstalled\(context: Context, packageName: String\): Boolean[\s\S]*PackageManager\.NameNotFoundException' `
    -Message 'Android payment code must detect whether Alipay is installed before launching checkout.'

Assert-Contains `
    -Path $androidCommon `
    -Pattern 'fun isAlipayInstalled\(context: Context\): Boolean[\s\S]*isPackageInstalled\(context, ALIPAY_PACKAGE_NAME\)' `
    -Message 'Android payment code must expose an Alipay-specific installed check.'

Assert-Contains `
    -Path $androidCommon `
    -Pattern 'fun openAlipayHtmlCheckout\(context: Context, html: String\): Boolean[\s\S]*!isAlipayInstalled\(context\)[\s\S]*return false[\s\S]*AlipayCheckoutActivity' `
    -Message 'Android Alipay HTML checkout must return false before opening the transparent checkout activity when Alipay is missing.'

Assert-Contains `
    -Path $androidCommon `
    -Pattern 'fun openPaymentUri\(context: Context, uri: String\): Boolean[\s\S]*isAlipayUri[\s\S]*!isAlipayInstalled\(context\)[\s\S]*return false' `
    -Message 'Android direct Alipay URI launch must also return false when Alipay is missing.'

Assert-Contains `
    -Path $accountPage `
    -Pattern 'messageKey: \(isAndroid \|\| isIOS\)[\s\S]*Alipay is not installed\. Please install Alipay and try again\.' `
    -Message 'Mobile Alipay unavailable state must show the install-Alipay prompt on Android as well as iOS.'

Assert-Contains `
    -Path $accountPage `
    -Pattern 'isMobileAlipayUnavailable\s*=\s*launchState == _KqPaymentLaunchState\.unavailable[\s\S]*payType == 2[\s\S]*\(isAndroid \|\| isIOS\)' `
    -Message 'Flutter payment sheet must identify Android/iOS Alipay unavailable as a terminal missing-app state.'

Assert-Contains `
    -Path $accountPage `
    -Pattern 'shouldShowQrFallback\s*=\s*launchState == _KqPaymentLaunchState\.unavailable &&[\s\S]*!isMobileAlipayUnavailable' `
    -Message 'Mobile Alipay unavailable must not enable the QR fallback.'

Assert-NotContains `
    -Path $accountPage `
    -Pattern '!\(isIOS && payType == 2\)' `
    -Message 'The Alipay unavailable QR fallback guard must not be iOS-only.'

Write-Host 'KQ Android payment checks passed'
