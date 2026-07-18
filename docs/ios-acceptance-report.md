# iOS Acceptance Report

## Build Information

- App version: 1.4.6
- TestFlight build number: Codemagic `BUILD_NUMBER` (do not reuse `4073`)
- Bundle ID: `com.kunqiong.remotelink`
- ReplayKit extension: `com.kunqiong.remotelink.broadcast`
- Minimum iOS version: 13.0
- Latest checked unsigned preflight: GitHub macOS no-codesign IPA build passed on 2026-07-16; no signed IPA or TestFlight record is available

## Automated Code Checks

Run from the repository root on Windows or macOS:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/test-kq-ios-code-readiness.ps1
```

- [x] Static iOS project and permission checks pass
- [x] Flutter iOS regression tests pass
- [x] Full Flutter iOS readiness suite passes
- [x] Rust receiver quality test passes
- [x] Rust `flutter` feature compiles
- [x] Changed Dart files have no analyzer errors
- [x] TestFlight release configuration validator rejects missing, insecure, direct-payment, and missing-route settings
- [x] TestFlight workflow injects privacy, deletion, and StoreKit verification Dart defines and uses an increasing build number
- [x] Manual connection-manager demo is isolated from the automated test suite

## Required macOS Build Checks

- [ ] `flutter/build_ios.sh` produces an unsigned Runner app
- [ ] Codemagic unsigned workflow produces `Runner.app`
- [ ] Distribution certificate and provisioning profiles are valid
- [ ] Signed workflow produces one IPA with the expected version/build number
- [ ] TestFlight upload succeeds

## Required Device Checks

Record device model and iOS version for every result.

- [ ] iPhone login, navigation, and safe-area layout
- [ ] iPad login, navigation, split layout, and rotation
- [ ] Remote connection success, cancellation, timeout, and readable failure copy
- [ ] First video frame, background/resume, rotation, and reconnect
- [ ] Touch, drag, long press, scroll, pinch, soft keyboard, hardware keyboard
- [ ] Magic Mouse click and double-click without duplicate input
- [ ] Basic profile requests 720p / 30 FPS without artificial blur or black screen
- [ ] Member profile requests 1080p / 60 FPS with visibly higher quality
- [ ] Microphone permission, voice call start/end, rejection, busy, and timeout copy
- [ ] File transfer, Files App import, incoming clipboard, and foreground outgoing text clipboard
- [ ] ReplayKit picker, capture status, frame counters, pause/resume, and stop behavior
- [ ] Remote viewer receives ReplayKit video and application audio through direct and relay connections on physical devices
- [ ] Microphone stays on the separate voice-call path without duplicated audio or echo

## Release Preconditions

- iOS uses the same Kunqiong login, SMS login, password reset, registration, and
  session flow as Android. The identity account is owned by
  `api-web.kunqiongai.com`, not the project-side `server/` database.
- The iOS app does not expose WeChat, Alipay, QR-code, or payment-URI membership
  checkout. Configure StoreKit products and server-side transaction verification
  before enabling an iPhone membership purchase flow.
- [ ] The identity service must provide an authenticated account-deletion endpoint
  that revokes sessions and permanently deletes the external account. Deleting
  only `server/` mirror data is not an account deletion and must not be presented
  as one in the app.
- [ ] Deploy authenticated JSON `POST` endpoints for account deletion and Apple
  transaction verification. On 2026-07-17, the previously documented
  `api-web.kunqiongai.com` paths both returned HTTP `404` to a harmless
  unauthenticated `POST`, so they are not release-ready endpoints.
- [ ] Configure every active StoreKit product in App Store Connect, map it in
  `KQ_IOS_IAP_PRODUCTS`, and verify that the server validates Apple transaction
  data before changing membership rights.
- [ ] Confirm the App Store privacy labels and the export-compliance answer for
  `ITSAppUsesNonExemptEncryption`; this cannot be inferred safely from source
  code alone.

## Result

- Tester: Codex code readiness checks
- Date: 2026-07-17
- Devices:
- Overall result: iOS client code, unsigned macOS CI compilation, permissions, privacy manifest, StoreKit UI, and release guards are ready for the next stage. The product is not yet eligible for TestFlight or App Store submission.
- Blocking issues: The identity-service deletion API and Apple transaction-verification API are not deployed at the configured paths. The TestFlight workflow now fails before compilation rather than producing a broken IPA. Final confirmation still requires a signed Archive plus iPhone/iPad tests for ReplayKit, remote video, input, files, voice, account deletion, and StoreKit Sandbox purchases.
- Non-blocking issues:
