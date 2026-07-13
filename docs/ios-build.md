# iOS Build Readiness

This project can be edited on Windows, but iOS compilation, signing, TestFlight,
and App Store upload require macOS with Xcode.

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
BUILD_MODE=ipa FLUTTER_BUILD_NAME=1.4.6 FLUTTER_BUILD_NUMBER=2067 ./build_ios.sh
```

Signing requirements:

- Apple Developer Program membership
- App Store Connect app for `com.kunqiong.remotelink`
- Bundle ID and provisioning profile for `com.kunqiong.remotelink`
- Bundle ID and provisioning profile for `com.kunqiong.remotelink.broadcast`
- App Group capability for both targets: `group.com.kunqiong.remotelink`

## CI

`codemagic.yaml` already contains two iOS workflows:

- `kq-remote-link-ios-nosign`: unsigned iOS app build
- `kq-remote-link-ios-testflight`: signed IPA and App Store Connect upload

Use the no-sign workflow first to verify native dependencies and Xcode project
health before configuring App Store signing credentials.
