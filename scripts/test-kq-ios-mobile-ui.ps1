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

Write-Host 'KQ iOS mobile UI checks passed'
