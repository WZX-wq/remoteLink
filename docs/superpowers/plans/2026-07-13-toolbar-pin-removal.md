# Remote Toolbar Pin Removal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the redundant remote-toolbar pin control and ensure old persisted pin state can no longer disable toolbar auto-collapse.

**Architecture:** Keep toolbar visibility controlled only by `collapse`, pointer location, and drag state. Extract the auto-collapse predicate into the existing toolbar visibility policy so the behavior can be tested without constructing the full remote session UI.

**Tech Stack:** Flutter 3.24.5, Dart, GetX observables, Flutter tests, PowerShell build scripts, Inno Setup

---

### Task 1: Add failing regression coverage

**Files:**
- Modify: `flutter/test/kq_remote_video_render_test.dart`
- Test: `flutter/test/kq_remote_video_render_test.dart`

- [ ] **Step 1: Add policy and source-contract tests**

Add tests which call the desired predicate and reject all pin-control paths:

```dart
test('remote toolbar auto-collapse depends only on active UI state', () {
  expect(
    shouldAutoCollapseRemoteToolbar(
      isExpanded: true,
      isCursorOverImage: true,
      isDragging: false,
    ),
    isTrue,
  );
  expect(
    shouldAutoCollapseRemoteToolbar(
      isExpanded: false,
      isCursorOverImage: true,
      isDragging: false,
    ),
    isFalse,
  );
  expect(
    shouldAutoCollapseRemoteToolbar(
      isExpanded: true,
      isCursorOverImage: false,
      isDragging: false,
    ),
    isFalse,
  );
  expect(
    shouldAutoCollapseRemoteToolbar(
      isExpanded: true,
      isCursorOverImage: true,
      isDragging: true,
    ),
    isFalse,
  );
});

test('remote toolbar has no pin control or persisted pin state', () {
  final source =
      File('lib/desktop/widgets/remote_toolbar.dart').readAsStringSync();
  expect(source, isNot(contains('class _PinMenu')));
  expect(source, isNot(contains('toolbarItems.add(_PinMenu')));
  expect(source, isNot(contains('kOptionRemoteMenubarState')));
  expect(source, isNot(contains('switchPin')));
});
```

- [ ] **Step 2: Run the tests and observe RED**

Run:

```powershell
D:\tools\flutter-3.24.5\bin\flutter.bat test test\kq_remote_video_render_test.dart
```

Expected: FAIL because `shouldAutoCollapseRemoteToolbar` does not exist and the pin source paths are still present.

### Task 2: Remove pin state and use the policy predicate

**Files:**
- Modify: `flutter/lib/models/remote_toolbar_visibility_policy.dart`
- Modify: `flutter/lib/desktop/widgets/remote_toolbar.dart`
- Test: `flutter/test/kq_remote_video_render_test.dart`

- [ ] **Step 1: Add the auto-collapse predicate**

Add to `remote_toolbar_visibility_policy.dart`:

```dart
bool shouldAutoCollapseRemoteToolbar({
  required bool isExpanded,
  required bool isCursorOverImage,
  required bool isDragging,
}) {
  return isExpanded && isCursorOverImage && !isDragging;
}
```

- [ ] **Step 2: Remove the pin implementation**

In `remote_toolbar.dart`:

- Remove `_pin`, its constructor loading logic, `pin`, `switchPin`, `setPin`, and `_savePin` from `ToolbarState`.
- Remove the `_PinMenu` widget class.
- Remove `toolbarItems.add(_PinMenu(state: widget.state));`.
- Replace `_debouncerHideProc` with:

```dart
void _debouncerHideProc(int value) {
  if (shouldAutoCollapseRemoteToolbar(
    isExpanded: collapse.isFalse,
    isCursorOverImage: _isCursorOverImage,
    isDragging: _dragging.isTrue,
  )) {
    collapse.value = true;
  }
}
```

Do not remove `dart:convert`; the file still uses `jsonDecode` for monitor and input-source data.

- [ ] **Step 3: Format changed Dart files**

Run:

```powershell
D:\tools\flutter-3.24.5\bin\dart.bat format lib\models\remote_toolbar_visibility_policy.dart lib\desktop\widgets\remote_toolbar.dart test\kq_remote_video_render_test.dart
```

- [ ] **Step 4: Run the tests and observe GREEN**

Run:

```powershell
D:\tools\flutter-3.24.5\bin\flutter.bat test test\kq_remote_video_render_test.dart
```

Expected: all remote-video and toolbar regression tests pass.

### Task 3: Build and verify the stable Windows installer

**Files:**
- Replace: `dist/Kunqiong-Remote-Desktop-Setup.exe`
- Replace: `dist/Kunqiong-Remote-Desktop-Setup.exe.sha256`

- [ ] **Step 1: Build Windows native code, Flutter UI, and installer**

Run:

```powershell
.\scripts\build-kq-apps.ps1 -Target Windows -FlutterSdk D:\tools\flutter-3.24.5 -WindowsCargoFeatures 'flutter,hwcodec,vram' -SkipFlutterPubGet -UpdateStableNames
```

Expected: Rust native build, Flutter Windows build, and Inno Setup compilation succeed. If the known child-shell `Get-FileHash` lookup fails after Inno reports success, manually copy the generated timestamped installer over the stable name and regenerate its SHA256 file.

- [ ] **Step 2: Verify the installer and cleanup**

Confirm the stable installer exists, its SHA256 file matches, its associated icon matches the built `rustdesk.exe`, and no timestamped installer/build directory remains under `dist`.

- [ ] **Step 3: Run final source checks**

Run:

```powershell
git diff --check
rg -n "class _PinMenu|toolbarItems\.add\(_PinMenu|kOptionRemoteMenubarState|switchPin" flutter\lib\desktop\widgets\remote_toolbar.dart
```

Expected: `git diff --check` succeeds and `rg` returns no matches.
