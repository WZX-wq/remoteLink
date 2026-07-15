# iOS ReplayKit Remote Viewing Implementation Plan

**Goal:** Connect the ReplayKit broadcast upload extension to the existing
remoteLink host video protocol so another device can watch the iOS screen.

**Architecture:** Add a tested latest-frame mailbox to `scrap`, provide an iOS
BGRA capturer and display implementation, enable the mobile server/rendezvous
modules on iOS, expose a small C ABI to Swift, share configuration through the
App Group, and link the existing Rust static library into the extension.

**Tech Stack:** Rust, libvpx, remoteLink rendezvous/relay protocol, Swift,
ReplayKit, CoreVideo, Flutter method channels, Xcode project configuration.

---

### Task 1: External frame mailbox

**Files:**
- Create: `libs/scrap/src/external_frame.rs`
- Modify: `libs/scrap/src/lib.rs`

1. Test valid BGRA submission, invalid dimensions/stride/data length, latest
   frame replacement, sequence numbers, clear, and size metadata.
2. Implement an owned one-frame mailbox with bounded allocation.
3. Run `cargo test -p scrap external_frame`.

### Task 2: iOS scrap capture source

**Files:**
- Create: `libs/scrap/src/common/ios.rs`
- Modify: `libs/scrap/src/common/mod.rs`

1. Add an iOS `Display`, `Capturer`, and `PixelBuffer` backed by the mailbox.
2. Enable `Frame`, `TraitCapturer::frame`, conversion, and camera fallback on
   iOS without affecting Android or desktop implementations.
3. Cross-check `scrap` for `aarch64-apple-ios`.

### Task 3: iOS host server bridge

**Files:**
- Modify: `src/lib.rs`
- Modify: `src/server.rs`
- Modify: `src/server/connection.rs`
- Modify: `src/rendezvous_mediator.rs`
- Create: `src/ios_broadcast.rs`

1. Compile server, rendezvous, and IPC modules on iOS using mobile/view-only
   guards.
2. Register display/video services while keeping input and clipboard disabled.
3. Export start, push BGRA, pause/resume, stop, status, and error C functions.
4. Make lifecycle calls idempotent and keep only one host thread.

### Task 4: App Group and ReplayKit integration

**Files:**
- Create: `flutter/ios/KQScreenBroadcast/KQBroadcastBridge.h`
- Modify: `flutter/ios/KQScreenBroadcast/SampleHandler.swift`
- Modify: `flutter/ios/Runner/AppDelegate.swift`
- Modify: `flutter/ios/Runner/Runner-Bridging-Header.h`
- Modify: `flutter/lib/models/native_model.dart`
- Modify: `flutter/ios/Runner.xcodeproj/project.pbxproj`
- Modify: `flutter/build_ios.sh`

1. Migrate and return the shared App Group configuration directory.
2. Start transport on the first valid frame and submit locked BGRA buffers.
3. Publish accurate transport state and user-readable diagnostics.
4. Link Rust and required system frameworks into the extension target.

### Task 5: Regression and device readiness

**Files:**
- Modify: `scripts/test-kq-ios-broadcast-extension.ps1`
- Modify: `scripts/test-kq-ios-rust-linkage.ps1`
- Modify: `scripts/test-kq-ios-build-readiness.ps1`
- Modify: `docs/ios-acceptance-report.md`

1. Add static assertions for the bridge, frame submission, shared config, view-
   only policy, extension linkage, and non-capture-only status.
2. Run focused Rust and Flutter tests, then full test suites.
3. Run the iOS target build and all PowerShell readiness checks.
4. Record physical-device direct/relay viewing as the final external gate.
