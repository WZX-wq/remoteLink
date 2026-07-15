# iOS Acceptance Report

## Build Information

- App version: 1.4.6
- Build number: 4073
- Bundle ID: `com.kunqiong.remotelink`
- ReplayKit extension: `com.kunqiong.remotelink.broadcast`
- Minimum iOS version: 13.0
- Test build URL or artifact: Not provided

## Automated Code Checks

Run from the repository root on Windows or macOS:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/test-kq-ios-code-readiness.ps1
```

- [x] Static iOS project and permission checks pass
- [x] Flutter iOS regression tests pass
- [x] Full Flutter test suite passes (110 tests)
- [x] Rust receiver quality test passes
- [x] Rust `flutter` feature compiles
- [x] Changed Dart files have no analyzer errors
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
- [ ] ReplayKit picker, capture status, frame counters, and stop behavior
- [ ] Remote viewer receives ReplayKit video through direct and relay connections on physical devices

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

## Result

- Tester: Codex code readiness checks
- Date: 2026-07-15
- Devices:
- Overall result: Repository transport code and Windows-verifiable checks passed; macOS build and physical-device acceptance remain pending
- Blocking issues: The ReplayKit extension now submits BGRA frames directly to the existing Rust encoder, rendezvous, relay, and remote viewer protocol. A frame-size change interrupts the old encoder before it receives mismatched ReplayKit frames. Final confirmation requires an Xcode build and two physical devices because Windows does not provide the iPhoneOS SDK or ReplayKit runtime. App Store release also requires StoreKit membership configuration and a real account-deletion API from the external identity service.
- Non-blocking issues:
