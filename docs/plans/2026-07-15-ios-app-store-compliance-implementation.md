# iOS App Store Compliance Adaptation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Complete every App Store-compliant iOS adaptation that can be implemented in this repository and expose unsupported or externally blocked capabilities accurately.

**Architecture:** Centralize platform capability decisions in a pure Dart policy, add foreground clipboard synchronization through the existing session protocol, harden file transfer and iOS lifecycle behavior, and turn ReplayKit status into an explicit view-only upload contract. Android behavior remains unchanged.

**Tech Stack:** Flutter/Dart, Swift/ReplayKit, Rust remote session FFI, PowerShell static checks, Flutter tests.

---

### Task 1: Central iOS capability policy

**Files:**
- Create: `flutter/lib/models/mobile_platform_capability_policy.dart`
- Modify: `flutter/lib/mobile/pages/settings_page.dart`
- Modify: `flutter/lib/mobile/pages/server_page.dart`
- Test: `flutter/test/kq_ios_platform_capability_test.dart`

1. Write failing policy tests for controller, view-only host, overlay, boot,
   accessibility, persistent background, voice, files, and clipboard.
2. Run the test and confirm the missing policy failure.
3. Implement the immutable capability policy and replace direct platform gates.
4. Verify that Android controls remain available and iOS-only unsupported
   controls are omitted.

### Task 2: Foreground text clipboard synchronization

**Files:**
- Modify: `src/client.rs`
- Modify: `src/ui_session_interface.rs`
- Modify: `src/flutter_ffi.rs`
- Modify: `flutter/lib/mobile/pages/remote_page.dart`
- Test: `flutter/test/kq_ios_clipboard_sync_test.dart`

1. Write a failing test for active-app, changed, non-empty text clipboard sync.
2. Add a session FFI operation that sends the existing clipboard message type.
3. Read Flutter clipboard text on resume and explicit sync, deduplicate it, and
   keep Android's native clipboard implementation unchanged.
4. Run Flutter and Rust regression tests.

### Task 3: iOS file transfer contract

**Files:**
- Modify: `flutter/lib/mobile/pages/connection_page.dart`
- Modify: `flutter/lib/desktop/pages/file_manager_page.dart` only if shared behavior requires it
- Test: `flutter/test/kq_ios_file_transfer_test.dart`

1. Test that iOS exposes file transfer through the system document workflow.
2. Ensure selected files are copied into an accessible sandbox URL before Rust
   starts transfer and that cancellation has readable copy.
3. Preserve desktop and Android paths.

### Task 4: ReplayKit view-only upload contract

**Files:**
- Create: `flutter/ios/KQScreenBroadcast/BroadcastUploadConfiguration.swift`
- Modify: `flutter/ios/KQScreenBroadcast/SampleHandler.swift`
- Modify: `flutter/ios/Runner/AppDelegate.swift`
- Modify: `flutter/lib/mobile/pages/server_page.dart`
- Test: `scripts/test-kq-ios-broadcast-extension.ps1`
- Test: `flutter/test/kq_ios_platform_capability_test.dart`

1. Add failing static checks for view-only metadata, upload configuration,
   explicit missing-transport failure, retry-safe state, and no control claim.
2. Implement App Group configuration/status exchange and frame-upload protocol
   abstraction without inventing a backend endpoint.
3. Display capture-only versus upload-ready state accurately in Flutter.
4. Document the server contract needed to make remote viewing operational.

### Task 5: Final code readiness

**Files:**
- Modify: `scripts/test-kq-ios-code-readiness.ps1`
- Modify: `docs/ios-acceptance-report.md`

1. Add all new tests to the one-click check.
2. Run changed-file Dart analysis through an ASCII path mapping.
3. Run Flutter tests, Rust tests, static iOS checks, and `git diff --check`.
4. Record macOS/Xcode, backend transport, TestFlight, and physical-device gates
   as pending rather than complete.
