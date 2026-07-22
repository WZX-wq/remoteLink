# iOS Completion Hardening Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Close the remaining iOS development gaps without breaking the established Windows and Android build toolchains.

**Architecture:** Keep the shared Flutter source compatible with the existing Flutter 3.24 build workflows. Expose the iOS broadcast viewer count from the Rust server through the existing C bridge to the ReplayKit extension. Process Apple server notifications only after resolving the referenced transaction through the App Store Server API, then update the local membership record owned by the verified subscription owner.

**Tech Stack:** Flutter/Dart, Swift ReplayKit, Rust FFI, Node.js/Express, MySQL, node:test, cargo test.

---

### Task 1: Restore shared Flutter toolchain compatibility

**Status:** Implemented. Dart formatting and analysis pass; focused Flutter test must be rerun in CI or on macOS because the local Flutter SDK lock is held by another process.

**Files:**
- Modify: `flutter/lib/common.dart`
- Modify: `flutter/lib/mobile/pages/account_deletion_page.dart`
- Modify: `flutter/lib/mobile/pages/ios_membership_purchase_page.dart`
- Modify: `flutter/lib/mobile/pages/privacy_policy_page.dart`
- Test: `flutter/test/kq_ios_release_policy_test.dart`

1. Replace Flutter 3.44-only color and theme data APIs in shared imports.
2. Run the focused release-policy test.

### Task 2: Publish actual ReplayKit viewer state

**Status:** Implemented. Rust broadcast-state and frame-mailbox tests pass; Flutter contract test is pending the same CI/macOS rerun.

**Files:**
- Modify: `src/server.rs`
- Modify: `src/ios_broadcast.rs`
- Modify: `flutter/ios/KQScreenBroadcast/KQBroadcastBridge.h`
- Modify: `flutter/ios/KQScreenBroadcast/SampleHandler.swift`
- Modify: `flutter/lib/mobile/pages/server_page.dart`
- Test: `flutter/test/kq_ios_broadcast_status_contract_test.dart`

1. Add a Rust active connection count API scoped to the active iOS broadcast service.
2. Publish the count through the C bridge and App Group status.
3. Show connected versus waiting status in the Flutter page.
4. Run focused Rust and Flutter contract tests.

### Task 3: Process Apple membership lifecycle notifications

**Status:** Implemented and covered by Node tests. Deployment must still configure the public Apple notification URL and production credentials.

**Files:**
- Modify: `server/src/apple-iap.js`
- Modify: `server/src/index.js`
- Create: `server/src/apple-notifications.js`
- Create: `server/test/apple-notifications.test.js`

1. Decode only enough notification data to locate a transaction, then verify it again against the Apple Server API.
2. Resolve the subscription owner and stored package before changing local membership data.
3. Apply renewals idempotently and revoke only the matching Apple order before recalculating local entitlement.
4. Run Node tests for transaction parsing and notification handling.

### Task 4: Complete mobile paused-transfer controls

**Status:** Implemented. Static source coverage and Dart analysis pass; focused Flutter test is pending the CI/macOS rerun.

**Files:**
- Modify: `flutter/lib/mobile/pages/file_manager_page.dart`
- Create: `flutter/test/kq_mobile_file_transfer_pause_test.dart`

1. Render a paused transfer state with resume and cancel controls.
2. Run the focused widget/source contract test.

### Task 5: Verify and document remaining external release prerequisites

**Status:** Completed. The acceptance report leaves external identity deletion, signing, StoreKit setup, deployment, and device acceptance explicitly pending.

**Files:**
- Modify: `docs/ios-acceptance-report.md`

1. Record the completed code items.
2. Leave the external identity-account deletion API, signed archive, StoreKit product setup, and physical-device testing explicitly pending.
