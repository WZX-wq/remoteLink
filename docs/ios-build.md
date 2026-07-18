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
are configured.

Before the `kq-remote-link-ios-testflight` workflow is run, configure these
non-secret values in its Codemagic environment group. They are compiled into
the signed IPA as Dart defines, but Apple credentials and server verification
secrets must remain only in Codemagic/App Store Connect:

```text
KQ_PRIVACY_POLICY_URL=https://remotelink.kunqiongai.com/kq-api/privacy
KQ_ACCOUNT_DELETE_URL=https://remotelink.kunqiongai.com/kq-api/api/auth/account/delete
KQ_IOS_IAP_PRODUCTS={"1":"com.kunqiong.remotelink.member.monthly"}
KQ_IOS_IAP_VERIFY_URL=https://remotelink.kunqiongai.com/kq-api/api/membership/apple/verify
```

Map every active server membership package to its matching App Store Connect
product ID. The signed workflow rejects missing or non-HTTPS values and rejects
`KQ_IOS_INTERNAL_DIRECT_PAYMENT=true`, so an App Store/TestFlight IPA cannot
accidentally expose the internal Alipay flow. It uses Codemagic's increasing
`BUILD_NUMBER` for `CFBundleVersion`; do not reuse a fixed TestFlight build
number. Before compiling, the workflow sends an unauthenticated JSON `POST`
probe to the deletion and transaction-verification URLs. A deployed route must
answer `200`, `400`, `401`, `403`, or `422`; `404`, a wrong method, or a server
error stops the build. Codemagic then publishes the IPA with its App Store
Connect publishing configuration and API-key credentials; the first app record
and its required App Store metadata must already exist in App Store Connect.
