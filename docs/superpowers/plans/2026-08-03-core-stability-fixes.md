# Core Stability Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement and verify the approved core connection, quality, membership, input, and voice-call fixes.

**Architecture:** Keep platform boundaries intact. iOS voice responses stay in the native App Group bridge, KQ video quality stays in the existing per-session `OptionMessage` and Rust `VideoQoS` path, and Flutter only controls receiver-side policy. UI-only removals do not alter legacy protocol compatibility.

**Tech Stack:** Flutter/Dart, Rust/Tokio, Swift AppDelegate, protobuf-generated Rust bridge, Flutter source-contract tests.

---

### Task 1: Add failing regression contracts

**Files:**
- Modify: `flutter/test/kq_ios_broadcast_status_contract_test.dart`
- Modify: `flutter/test/kq_ios_mobile_connection_test.dart`
- Modify: `flutter/test/kq_remote_video_render_test.dart`
- Modify: `flutter/test/kq_ios_membership_quality_test.dart`
- Create: `flutter/test/kq_core_stability_contract_test.dart`

- [ ] **Step 1: Add contracts for native iOS voice response, nonfatal KQ first-frame timeout, no standard-tier blur, exact-case desktop password, lifetime copy, foreground membership refresh, and absent block-input menu.**
- [ ] **Step 2: Run the focused tests and confirm they fail for the current implementation.**

Run from `/Users/m4_txx/remoteLink/flutter`:

```bash
flutter test test/kq_core_stability_contract_test.dart test/kq_ios_mobile_connection_test.dart test/kq_remote_video_render_test.dart test/kq_ios_membership_quality_test.dart
```

Expected: failures identify the current iOS CM voice path, 15-second close, blur fallback, lowercasing, subscription copy, missing global refresh, and block-input menu.

### Task 2: Fix iOS voice response routing

**Files:**
- Modify: `flutter/lib/models/server_model.dart`
- Modify: `flutter/lib/mobile/pages/server_page.dart`
- Modify: `flutter/ios/Runner/AppDelegate.swift` only if the bridge contract needs a small shared helper

- [ ] **Step 1: Route iOS accept/reject through `respond_to_ios_voice_call` using the pending App Group request ID.**
- [ ] **Step 2: Route iOS stop through `end_ios_voice_call`; preserve CM IPC on Android/desktop.**
- [ ] **Step 3: Return a visible failure state when the native request is stale instead of silently leaving the invitation active.**
- [ ] **Step 4: Run the voice contract tests.**

### Task 3: Make first-frame timeout recoverable

**Files:**
- Modify: `flutter/lib/models/model.dart`
- Modify: `flutter/lib/models/connection_failure_presentation.dart` if a new safe waiting message is needed
- Modify: `flutter/test/kq_ios_mobile_connection_test.dart`

- [ ] **Step 1: Replace the KQ desktop 15-second close branch with a waiting/retry dialog that keeps the session alive.**
- [ ] **Step 2: Keep explicit cancel and retry actions wired to the existing close/reconnect paths.**
- [ ] **Step 3: Run the connection tests and verify ordinary hard failures still close correctly.**

### Task 4: Remove receiver-side blur and verify runtime quality path

**Files:**
- Modify: `flutter/lib/mobile/pages/remote_page.dart`
- Modify: `flutter/lib/utils/image.dart` only if the now-unused blur parameter has no other callers
- Modify: `src/server/video_qos.rs` only if the focused Rust test shows per-session KQ height is not preserved
- Modify: `flutter/test/kq_remote_video_render_test.dart`
- Modify: `flutter/test/kq_ios_membership_quality_test.dart`

- [ ] **Step 1: Remove artificial standard-tier blur and retain real `OptionMessage` quality/FPS negotiation.**
- [ ] **Step 2: Add/adjust Rust coverage for 480p and 1080p encoded dimensions without changing remote display configuration.**
- [ ] **Step 3: Run Flutter and Rust focused quality tests.**

### Task 5: Fix input fidelity and product copy

**Files:**
- Modify: `flutter/lib/desktop/pages/connection_page.dart`
- Modify: `flutter/lib/mobile/pages/ios_membership_purchase_page.dart`
- Modify: `flutter/test/kq_core_stability_contract_test.dart`

- [ ] **Step 1: Pass the desktop password exactly as entered and remove only the lowercasing transformation.**
- [ ] **Step 2: Make lifetime products show one-time permanent entitlement copy while subscription products retain auto-renewal terms.**
- [ ] **Step 3: Run the focused Flutter tests.**

### Task 6: Add controlled foreground membership refresh and remove menu action

**Files:**
- Modify: `flutter/lib/main.dart`
- Modify: `flutter/lib/models/user_model.dart` only for a small public refresh guard/helper if needed
- Modify: `flutter/lib/common/widgets/toolbar.dart`
- Modify: `flutter/test/kq_core_stability_contract_test.dart`

- [ ] **Step 1: Refresh membership after app resume and on a bounded periodic timer while a user is logged in.**
- [ ] **Step 2: Cancel the timer on app disposal and preserve active membership on transient refresh failures.**
- [ ] **Step 3: Remove the Windows block-input menu entry and its UI-only state lookup.**
- [ ] **Step 4: Run focused tests and lint/format checks.**

### Task 7: Full verification and handoff

**Files:**
- No source changes unless verification exposes a regression.

- [ ] **Step 1: Run focused Flutter tests and all relevant Rust checks.**
- [ ] **Step 2: Run `git diff --check` and inspect `git diff --stat` plus `git status --short`.**
- [ ] **Step 3: Report exact pass/fail evidence and any real-device/TestFlight checks that cannot be completed locally.**
