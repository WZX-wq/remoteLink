# Remove Mobile Block User Input Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the Block user input action from mobile remote-session menus while preserving desktop and protocol compatibility.

**Architecture:** Keep the shared Flutter toolbar implementation and gate the existing Windows block-input menu item with `!isMobile`. Preserve all Rust, Windows service, desktop UI, translation, and protocol code.

**Tech Stack:** Flutter/Dart, Flutter test, Xcode iOS archive, App Store Connect upload.

---

### Task 1: Lock the mobile visibility contract

**Files:**
- Modify: `flutter/test/kq_mobile_privacy_capability_test.dart`

- [ ] **Step 1: Replace the capability test with a failing mobile visibility test**

```dart
test('mobile more actions do not expose block user input', () {
  final toolbar = File('lib/common/widgets/toolbar.dart').readAsStringSync();
  final start = toolbar.indexOf('// blockUserInput');
  final end = toolbar.indexOf('// switchSides', start);

  expect(start, greaterThanOrEqualTo(0));
  expect(end, greaterThan(start));
  final blockInputMenu = toolbar.substring(start, end);

  expect(blockInputMenu, contains('!isMobile'));
  expect(blockInputMenu, isNot(contains('blockInput.value = !blockInput.value')));
});
```

- [ ] **Step 2: Run the focused test and verify RED**

Run: `/Users/m4_txx/.local/flutter/3.44.5/bin/flutter test test/kq_mobile_privacy_capability_test.dart`

Expected: FAIL because the current block-input menu condition does not contain `!isMobile`.

### Task 2: Hide block input on mobile

**Files:**
- Modify: `flutter/lib/common/widgets/toolbar.dart:262-278`

- [ ] **Step 1: Add the mobile exclusion to the existing condition**

```dart
if (isDefaultConn &&
    !isMobile &&
    ffi.ffiModel.keyboard &&
    ffi.ffiModel.permissions['block_input'] != false &&
    pi.platform == kPeerPlatformWindows &&
    pi.sasEnabled) {
```

- [ ] **Step 2: Run the focused test and verify GREEN**

Run: `/Users/m4_txx/.local/flutter/3.44.5/bin/flutter test test/kq_mobile_privacy_capability_test.dart`

Expected: all tests pass.

- [ ] **Step 3: Run formatting and static diff checks**

Run: `/Users/m4_txx/.local/flutter/3.44.5/bin/dart format --output=none --set-exit-if-changed flutter/lib/common/widgets/toolbar.dart flutter/test/kq_mobile_privacy_capability_test.dart`

Run: `git diff --check`

Expected: both commands exit successfully.

- [ ] **Step 4: Commit the focused implementation**

```bash
git add flutter/lib/common/widgets/toolbar.dart flutter/test/kq_mobile_privacy_capability_test.dart docs/superpowers/plans/2026-07-31-remove-mobile-block-input.md
git commit -m "fix(mobile): remove block input action"
```

### Task 3: Build and upload TestFlight

**Files:**
- Verify: `flutter/ios/build/ios/ipa-3008970547863-*/鲲穹远程桌面.ipa`

- [ ] **Step 1: Confirm no heavy build or upload process is already running**

Run: `ps -axo pid=,rss=,command= | rg '(flutter|xcodebuild|cargo|rustc|altool)' | rg -v 'rg '`

Expected: no active build or upload process.

- [ ] **Step 2: Incrementally build and upload the Dart-only change**

Run: `XCODE_JOBS=2 CARGO_BUILD_JOBS=2 scripts/kq_ios_testflight_fast.sh --mode dart --build-number 3008970547863`

Expected: archive/export succeeds and App Store Connect reports upload success.

- [ ] **Step 3: Verify the exported IPA and App Store Connect state**

Inspect the IPA `Info.plist` and confirm `CFBundleShortVersionString=1.4.6` and `CFBundleVersion=3008970547863`. Query App Store Connect and confirm the build reaches `VALID`.

- [ ] **Step 4: Confirm process cleanup and repository state**

Run: `ps -axo pid=,rss=,command= | rg '(flutter|xcodebuild|cargo|rustc|altool)' | rg -v 'rg '`

Run: `git status --short --branch`

Expected: no heavy process remains; pre-existing untracked artifacts remain untouched.
