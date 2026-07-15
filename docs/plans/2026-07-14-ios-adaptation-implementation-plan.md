# KQ Remote Link iOS Adaptation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deliver a testable iOS client that can sign in, connect to remote computers, display and control the remote desktop, apply membership quality tiers, and produce a signed TestFlight build.

**Architecture:** Reuse the existing Flutter mobile UI and Rust remote-control core. Keep iOS-only behavior in small Dart platform guards and Swift method-channel or ReplayKit components, while preserving Android and desktop behavior.

**Tech Stack:** Flutter 3.44.5, Dart 3.12, Rust, flutter_rust_bridge, Swift, ReplayKit, CocoaPods, Xcode, Codemagic.

---

### Task 1: Establish a repeatable iOS build baseline

**Files:**
- Modify: `flutter/ios/exportOptions.plist`
- Modify: `codemagic.yaml`
- Modify: `docs/ios-build.md`
- Modify: `scripts/test-kq-ios-rust-linkage.ps1`
- Create: `scripts/test-kq-ios-build-readiness.ps1`

1. Run all iOS PowerShell checks and record the failing assertions.
2. Pin Codemagic to the Flutter version represented by the current lockfile.
3. Configure signing profiles for both Runner and the ReplayKit extension.
4. Verify Bundle IDs, App Group, iOS 13 deployment target, native Rust linkage, and build documentation.
5. Run the four existing iOS checks plus the new build-readiness check.

### Task 2: Complete the iOS mobile shell and connection flow

**Files:**
- Modify: `flutter/lib/mobile/pages/home_page.dart`
- Modify: `flutter/lib/mobile/pages/connection_page.dart`
- Test: `scripts/test-kq-ios-mobile-ui.ps1`
- Test: focused Flutter widget tests under `flutter/test/`

1. Keep the iOS connection field empty on first entry without changing Android restore behavior.
2. Verify login, remote ID, password, connecting, timeout, failure, success, and disconnect states.
3. Ensure all user-facing failures are clear Chinese text and do not expose internal error names.
4. Run focused widget tests and static iOS mobile checks.

### Task 3: Validate remote video and first-frame behavior

**Files:**
- Modify: `flutter/lib/mobile/pages/remote_page.dart`
- Modify: `flutter/lib/models/model.dart`
- Modify: iOS codec and bridge files only when runtime evidence requires it
- Test: add focused rendering-policy tests under `flutter/test/`

1. Add a test for the iOS renderer selection and first-frame state.
2. Verify VP9/H.264 decoder fallback on a physical iPhone and iPad.
3. Verify portrait, landscape, fit, scale, reconnect, and foreground-resume behavior.
4. Capture diagnostics for any black, gray, or frozen frame before changing codecs.

### Task 4: Complete touch, keyboard, and remote toolbar support

**Files:**
- Modify: `flutter/lib/models/input_model.dart`
- Modify: `flutter/lib/common/widgets/remote_input.dart`
- Modify: `flutter/lib/mobile/pages/remote_page.dart`
- Test: focused input and toolbar tests under `flutter/test/`

1. Cover tap, drag, long press, scroll, pinch zoom, mouse mode, soft keyboard, hardware keyboard, and special keys.
2. Preserve existing Magic Mouse duplicate-event filtering.
3. Verify disconnect, keyboard, pointer mode, quality, voice, and more actions.

### Task 5: Complete permissions and membership quality tiers

**Files:**
- Modify: `flutter/ios/Runner/Info.plist`
- Modify: `flutter/lib/mobile/pages/account_page.dart`
- Modify: shared remote-quality policy files
- Test: membership and quality policy tests under `flutter/test/`

1. Verify local network, microphone, camera/photo, and file permission flows.
2. Keep free users on the standard stream policy and allow members to select the high-definition policy.
3. Test the actual receiver-side stream parameters, not only labels or visual overlays.

### Task 6: Complete voice, files, clipboard, and ReplayKit scope

**Files:**
- Modify: voice, file-transfer, clipboard, and iOS method-channel files as identified by CodeGraph
- Test: `scripts/test-kq-ios-payment.ps1`
- Test: `scripts/test-kq-ios-broadcast-extension.ps1`

1. Verify voice permission, start, stop, peer rejection, and readable failure messages.
2. Verify supported file and clipboard directions; hide or explain unsupported operations.
3. Treat ReplayKit screen capture as a separately tested capability from outgoing remote control.

### Task 7: Build, sign, and complete device acceptance

**Files:**
- Modify: `codemagic.yaml` only for evidence-backed build fixes
- Modify: `docs/ios-build.md`
- Create: final iOS acceptance report under `docs/`

1. Run the unsigned Codemagic workflow.
2. Fix any Rust, CocoaPods, Xcode, or extension embedding failure using the complete build log.
3. Run the signed TestFlight workflow with profiles for both Bundle IDs and the shared App Group.
4. Test iPhone and iPad across supported iOS versions.
5. Record passed scenarios, remaining limitations, IPA version, build number, and TestFlight status.
