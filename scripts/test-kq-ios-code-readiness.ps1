param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'

$staticChecks = @(
    'test-kq-ios-build-readiness.ps1',
    'test-kq-ios-rust-linkage.ps1',
    'test-kq-ios-mobile-ui.ps1',
    'test-kq-ios-payment.ps1',
    'test-kq-ios-broadcast-extension.ps1'
)

foreach ($check in $staticChecks) {
    Write-Host "Running $check"
    & (Join-Path $PSScriptRoot $check) -Root $Root
}

$python = Get-Command python -ErrorAction Stop
Write-Host 'Running test_ios_release_config.py'
& $python.Source (Join-Path $PSScriptRoot 'test_ios_release_config.py')
if ($LASTEXITCODE -ne 0) {
    throw 'iOS App Store release configuration tests failed.'
}

$flutterRoot = Join-Path $Root 'flutter'
Push-Location $flutterRoot
try {
    & flutter test `
        test/kq_remote_video_render_test.dart `
        test/kq_ios_mobile_connection_test.dart `
        test/kq_ios_video_render_test.dart `
        test/kq_ios_input_toolbar_test.dart `
        test/kq_ios_membership_quality_test.dart `
        test/kq_ios_voice_files_clipboard_test.dart `
        test/kq_ios_platform_capability_test.dart `
        test/kq_ios_foreground_clipboard_test.dart `
        test/kq_ios_file_transfer_test.dart `
        test/kq_ios_broadcast_status_contract_test.dart `
        test/kq_ios_privacy_policy_test.dart `
        test/kq_account_deletion_test.dart `
        test/kq_ios_in_app_purchase_test.dart `
        test/kq_ios_release_policy_test.dart `
        test/member_session_state_test.dart
    if ($LASTEXITCODE -ne 0) {
        throw 'iOS Flutter regression tests failed.'
    }
} finally {
    Pop-Location
}

Push-Location $Root
try {
    & cargo test -p scrap external_frame
    if ($LASTEXITCODE -ne 0) {
        throw 'iOS ReplayKit frame mailbox Rust tests failed.'
    }

    & cargo test kq_remote_video_quality_tests --lib
    if ($LASTEXITCODE -ne 0) {
        throw 'iOS receiver quality Rust test failed.'
    }
} finally {
    Pop-Location
}

Write-Host 'KQ iOS code readiness checks passed'
