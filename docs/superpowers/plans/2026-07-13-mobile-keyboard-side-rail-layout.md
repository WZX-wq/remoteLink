# Mobile Keyboard Side Rail Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent the mobile software keyboard from resizing and clipping the remote-session right action rail.

**Architecture:** Add a small pure layout policy that computes the rail's maximum height from full viewport size and safe-area padding only. The mobile remote page disables Scaffold keyboard resizing, keeps the rail visible during keyboard input, and places its controls in a bounded vertical scroll view.

**Tech Stack:** Flutter 3.24.5, Dart, Android, Flutter tests, PowerShell build scripts

---

### Task 1: Add failing mobile layout regression tests

**Files:**
- Modify: `flutter/test/kq_remote_video_render_test.dart`
- Test: `flutter/test/kq_remote_video_render_test.dart`

- [ ] **Step 1: Import the desired mobile layout policy and add tests**

Add:

```dart
import 'package:flutter_hbb/models/mobile_remote_layout_policy.dart';
```

Add policy and source-contract tests:

```dart
test('mobile side rail height ignores keyboard view insets', () {
  expect(
    mobileRemoteSideRailMaxHeight(
      viewportHeight: 720,
      safeTop: 24,
      safeBottom: 16,
    ),
    648,
  );
});

test('mobile keyboard does not resize or hide the side action rail', () {
  final source =
      File('lib/mobile/pages/remote_page.dart').readAsStringSync();
  expect(source, contains('resizeToAvoidBottomInset: false'));

  final railStart = source.indexOf('  Widget _remoteSideActionRail()');
  final railEnd = source.indexOf(
    '  Widget _remoteSideActionButton(',
    railStart,
  );
  expect(railStart, greaterThanOrEqualTo(0));
  expect(railEnd, greaterThan(railStart));

  final railSource = source.substring(railStart, railEnd);
  expect(railSource, isNot(contains('keyboardIsVisible ||')));
  expect(railSource, contains('mobileRemoteSideRailMaxHeight('));
  expect(railSource, contains('SingleChildScrollView('));
});
```

- [ ] **Step 2: Run tests and observe RED**

Run:

```powershell
D:\tools\flutter-3.24.5\bin\flutter.bat test test\kq_remote_video_render_test.dart
```

Expected: FAIL because `mobile_remote_layout_policy.dart` does not exist and the mobile page still uses the default Scaffold resize behavior.

### Task 2: Stabilize the remote page and bound the side rail

**Files:**
- Create: `flutter/lib/models/mobile_remote_layout_policy.dart`
- Modify: `flutter/lib/mobile/pages/remote_page.dart`
- Test: `flutter/test/kq_remote_video_render_test.dart`

- [ ] **Step 1: Implement the pure height policy**

Create:

```dart
const double kMobileRemoteSideRailTopGap = 24;
const double kMobileRemoteSideRailBottomGap = 8;

double mobileRemoteSideRailMaxHeight({
  required double viewportHeight,
  required double safeTop,
  required double safeBottom,
}) {
  final available = viewportHeight -
      safeTop -
      safeBottom -
      kMobileRemoteSideRailTopGap -
      kMobileRemoteSideRailBottomGap;
  return available > 0 ? available : 0;
}
```

- [ ] **Step 2: Disable Scaffold keyboard resizing**

Add the policy import to `mobile/pages/remote_page.dart`, then set:

```dart
child: Scaffold(
  resizeToAvoidBottomInset: false,
```

- [ ] **Step 3: Keep and constrain the rail**

In `_remoteSideActionRail()`:

- Remove `keyboardIsVisible` and its offstage condition.
- Calculate `mediaQuery`, `railTop`, and `railMaxHeight` from the new policy.
- Keep the existing `right: 12` position.
- Wrap the existing `Material` with `ConstrainedBox(constraints: BoxConstraints(maxHeight: railMaxHeight))`.
- Replace the outer padding/column with:

```dart
SingleChildScrollView(
  padding: const EdgeInsets.symmetric(vertical: 4),
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: controls,
  ),
)
```

Set `clipBehavior: Clip.antiAlias` on the rail `Material` so scrolling content stays inside its rounded boundary.

- [ ] **Step 4: Format changed Dart files**

Run:

```powershell
D:\tools\flutter-3.24.5\bin\dart.bat format lib\models\mobile_remote_layout_policy.dart lib\mobile\pages\remote_page.dart test\kq_remote_video_render_test.dart
```

- [ ] **Step 5: Run tests and observe GREEN**

Run:

```powershell
D:\tools\flutter-3.24.5\bin\flutter.bat test test\kq_remote_video_render_test.dart
```

Expected: all remote-video and mobile-layout regression tests pass.

### Task 3: Build and verify the stable Android APK

**Files:**
- Replace: `dist/Kunqiong-Remote-Desktop.apk`
- Replace: `dist/Kunqiong-Remote-Desktop.apk.sha256`

- [ ] **Step 1: Build Android**

Run:

```powershell
.\scripts\build-kq-apps.ps1 -Target Android -FlutterSdk D:\tools\flutter-3.24.5 -SkipFlutterPubGet -UpdateStableNames
```

Expected: Android arm64 native build and Flutter release APK build succeed, then the stable APK and SHA256 file are overwritten.

- [ ] **Step 2: Verify package contents and cleanup**

Extract `lib/arm64-v8a/librustdesk.so` and `lib/arm64-v8a/libapp.so` from the stable APK. Verify their SHA256 hashes match the current Android native and Dart AOT build outputs. Confirm the SHA256 sidecar matches and no timestamped APK remains.

- [ ] **Step 3: Run final checks**

Run:

```powershell
git diff --check
```

Expected: no whitespace errors.
