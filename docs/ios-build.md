# iOS Build Readiness

This project can be edited on Windows, but iOS compilation, signing, TestFlight,
and App Store upload require macOS with Xcode.

## Pinned Toolchain

- Flutter 3.44.5
- Dart 3.12.x (bundled with Flutter)
- Rust 1.75 with target `aarch64-apple-ios`
- iOS deployment target 13.0

Use the pinned Flutter release for local Mac and Codemagic builds. Running an
older Flutter version against the current `pubspec.lock` is unsupported.

## Current iOS Structure

- Flutter app: `flutter/`
- iOS Xcode workspace: `flutter/ios/Runner.xcworkspace`
- Main app target: `Runner`
- Broadcast extension target: `KQScreenBroadcast`
- Main bundle id: `com.kunqiong.remotelink`
- Broadcast extension bundle id: `com.kunqiong.remotelink.broadcast`
- App Group: `group.com.kunqiong.remotelink`
- Minimum iOS version: `13.0`

## What Can Be Done On Windows

Run from `flutter/`:

```bash
flutter pub get
flutter analyze
```

Windows cannot run `pod install`, `flutter build ios`, Xcode signing, or
TestFlight upload.

## Unsigned Cloud Mac Build

Use a macOS builder with Flutter, Xcode, CocoaPods, Rust, and the iOS Rust target.

```bash
cd flutter
BUILD_MODE=ios ./build_ios.sh
```

The script runs:

- `flutter pub get`
- `pod install`
- `cargo build --features flutter --release --target aarch64-apple-ios --lib`
- `flutter build ios --release --no-codesign`

## Signed IPA Build

After Apple Developer signing is configured on the Mac builder:

```bash
cd flutter
BUILD_MODE=ipa FLUTTER_BUILD_NAME=1.4.6 FLUTTER_BUILD_NUMBER=4073 ./build_ios.sh
```

Signing requirements:

- Apple Developer Program membership
- App Store Connect app for `com.kunqiong.remotelink`
- Bundle ID and provisioning profile for `com.kunqiong.remotelink`
- Bundle ID and provisioning profile for `com.kunqiong.remotelink.broadcast`
- App Group capability for both targets: `group.com.kunqiong.remotelink`

Ad Hoc export also requires both provisioning profiles. The checked-in
`flutter/ios/exportOptions.plist` contains entries for the Runner app and the
ReplayKit extension; update the profile names there if your Apple account does
not use `match AdHoc ...` names.

The Runner app and `KQScreenBroadcast` extension both link
`target/aarch64-apple-ios/release/liblibrustdesk.a`. Keep the Rust build before
`flutter build ios` or `flutter build ipa`; otherwise the extension link phase
cannot resolve the ReplayKit host bridge. Runner migrates the existing
remoteLink configuration into the shared App Group `remoteLink-config`
directory on first launch, so the app and extension use one device ID,
password, key pair, and rendezvous configuration.

## CI

`codemagic.yaml` already contains two iOS workflows:

- `kq-remote-link-ios-nosign`: unsigned iOS app build
- `kq-remote-link-ios-testflight`: signed IPA and App Store Connect upload

Use the no-sign workflow first to verify native dependencies and Xcode project
health before configuring App Store signing credentials.

## App Store Release Boundaries

The iOS build keeps the existing Android-compatible Kunqiong login and account
registration flow. The account itself is managed by `api-web.kunqiongai.com`.
Before App Store submission, that identity service must expose an authenticated
account-deletion API that revokes sessions and permanently removes the external
account. The project-side `server/` database only stores synchronized device,
history, and membership mirror data; deleting it alone is not sufficient.

iOS intentionally does not expose WeChat, Alipay, QR-code, or payment-URI
membership checkout. Enable membership purchase only after Apple StoreKit
product identifiers, purchase handling, and server-side transaction verification
are configured. The Codemagic signed workflow uploads its IPA with `xcrun
altool --upload-app -f ... -t ios` and App Store Connect API-key credentials.
