param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'

function Assert-Contains {
    param(
        [string]$Content,
        [string]$Pattern,
        [string]$Message
    )

    if ($Content -notmatch $Pattern) {
        throw $Message
    }
}

$workflowPath = Join-Path $Root '.github/workflows/ios-testflight-build.yml'
if (-not (Test-Path -LiteralPath $workflowPath)) {
    throw 'GitHub TestFlight workflow is missing.'
}

$content = Get-Content -LiteralPath $workflowPath -Raw -Encoding UTF8

Assert-Contains $content 'push:[\s\S]*branches:[\s\S]*- main' `
    'TestFlight workflow must build from pushes to main.'
Assert-Contains $content 'workflow_dispatch:' `
    'TestFlight workflow must support a manual run.'
Assert-Contains $content 'skip_endpoint_probe:[\s\S]*type:\s*boolean' `
    'TestFlight workflow must expose endpoint probing as an explicit manual boolean input.'
Assert-Contains $content 'KQ_SKIP_ENDPOINT_PROBE:\s*\$\{\{ inputs\.skip_endpoint_probe \}\}' `
    'TestFlight workflow must pass the manual endpoint probe choice to the validator.'
Assert-Contains $content 'runs-on:\s*macos-latest' `
    'TestFlight workflow must run on macOS.'
Assert-Contains $content 'IOS_DISTRIBUTION_CERTIFICATE_BASE64:\s*\$\{\{ secrets\.IOS_DISTRIBUTION_CERTIFICATE_BASE64 \}\}' `
    'TestFlight workflow must import an Apple Distribution certificate from a secret.'
Assert-Contains $content 'IOS_MAIN_APPSTORE_PROFILE_BASE64:\s*\$\{\{ secrets\.IOS_MAIN_APPSTORE_PROFILE_BASE64 \}\}' `
    'TestFlight workflow must import the main App Store provisioning profile from a secret.'
Assert-Contains $content 'IOS_BROADCAST_APPSTORE_PROFILE_BASE64:\s*\$\{\{ secrets\.IOS_BROADCAST_APPSTORE_PROFILE_BASE64 \}\}' `
    'TestFlight workflow must import the broadcast App Store provisioning profile from a secret.'
Assert-Contains $content 'get_task_allow[^\n]*true' `
    'TestFlight workflow must inspect the get-task-allow entitlement.'
Assert-Contains $content 'get_task_allow\"?\s*=\s*\"true\"' `
    'TestFlight workflow must reject development provisioning profiles.'
Assert-Contains $content '"method": "app-store"' `
    'TestFlight workflow must export an App Store IPA.'
Assert-Contains $content '"signingStyle": "manual"' `
    'TestFlight workflow must export with explicit signing settings.'
Assert-Contains $content 'apple-actions/upload-testflight-build@v4' `
    'TestFlight workflow must upload through the Apple-maintained action.'
Assert-Contains $content 'issuer-id:\s*\$\{\{ secrets\.APPSTORE_ISSUER_ID \}\}' `
    'TestFlight workflow must use the App Store Connect issuer secret.'
Assert-Contains $content 'api-key-id:\s*\$\{\{ secrets\.APPSTORE_API_KEY_ID \}\}' `
    'TestFlight workflow must use the App Store Connect API key ID secret.'
Assert-Contains $content 'api-private-key:\s*\$\{\{ secrets\.APPSTORE_API_PRIVATE_KEY \}\}' `
    'TestFlight workflow must use the App Store Connect private key secret.'
Assert-Contains $content "wait-for-processing:\s*'false'" `
    'TestFlight workflow must not fail the upload after Apple accepts the IPA but delays build processing visibility.'
Assert-Contains $content 'GITHUB_RUN_ID[\s\S]*GITHUB_RUN_ATTEMPT' `
    'TestFlight workflow must generate a unique build number for reruns.'
Assert-Contains $content 'KQ_IOS_INTERNAL_DIRECT_PAYMENT:\s*"false"' `
    'TestFlight workflow must keep direct iOS payment disabled.'
Assert-Contains $content 'scripts/prepare_ios_release_config.py' `
    'TestFlight workflow must validate release URLs and StoreKit product mapping.'

foreach ($localSigningFile in @(
        'CERTIFICATE_PASSWORD.txt',
        'RemoteLink-Apple-Development.p12',
        'RemoteLink-Development.mobileprovision',
        'RemoteLink-Broadcast-Development.mobileprovision')) {
    if ($content -match [regex]::Escape($localSigningFile)) {
        throw "TestFlight workflow must not reference local signing file $localSigningFile."
    }
}

Write-Host 'KQ iOS TestFlight workflow checks passed'
