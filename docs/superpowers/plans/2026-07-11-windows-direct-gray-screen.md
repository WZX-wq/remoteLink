# Windows Direct-Connection Gray Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent the KQ Windows remote-desktop startup lifecycle from placing full-screen global Overlay entries above the first software-rendered video frame.

**Architecture:** Keep 720p and 1080p on the existing shared VP9 → RGBA → `ui.Image` → `CustomPaint` pipeline. Suppress only the KQ Windows desktop connection/waiting overlays, retain first-frame timeout handling, and finalize first-frame state directly after canvas paint without swapping repaint boundaries or broadly dismissing global dialogs.

**Tech Stack:** Flutter/Dart, Flutter tests, Windows Flutter build, Inno Setup.

---

### Task 1: Lock the startup-overlay policy

**Files:**
- Modify: `flutter/lib/models/video_render_policy.dart`
- Modify: `flutter/test/kq_remote_video_render_test.dart`

- [ ] Add a failing test proving KQ Windows desktop returns false while other apps/platforms return true.
- [ ] Run `flutter test test/kq_remote_video_render_test.dart` and confirm the missing policy fails.
- [ ] Implement `shouldShowRemoteConnectionOverlay` as a pure boolean policy.
- [ ] Run the focused test again.

### Task 2: Remove global startup overlays from KQ Windows sessions

**Files:**
- Modify: `flutter/lib/desktop/pages/remote_page.dart`
- Modify: `flutter/lib/models/model.dart`
- Modify: `flutter/test/kq_remote_video_render_test.dart`

- [ ] Add source-level assertions for guarded Connecting and waiting-for-image overlays.
- [ ] Confirm those assertions fail before implementation.
- [ ] Guard `showLoading('Connecting...')` with the policy.
- [ ] Guard only the waiting dialog insertion; retain retry and 15-second timeout timers.
- [ ] On KQ Windows, clear only the waiting tag instead of calling `dismissAll()`.
- [ ] Run the focused test.

### Task 3: Remove the ineffective scene-boundary workaround

**Files:**
- Modify: `flutter/lib/desktop/pages/remote_page.dart`
- Delete: `flutter/lib/desktop/widgets/first_frame_presentation.dart`
- Modify: `flutter/test/kq_remote_video_render_test.dart`

- [ ] Replace boundary/capture tests with direct first-paint finalization assertions.
- [ ] Confirm the new assertions fail while the boundary remains.
- [ ] Remove the boundary key, capture helpers, wrapper, and callback.
- [ ] Keep `markFramePainted`, then await `widget.ffi.onEvent2UIRgba()` after the first paint.
- [ ] Delete the obsolete helper and run focused tests/analyze.

### Task 4: Build and verify the installer

**Files:**
- Build output: `flutter/build/windows/x64/runner/Release/`
- Installer: `dist/Kunqiong-Remote-Desktop-Setup.exe`

- [ ] Build Windows release with the repository's established command.
- [ ] Run `scripts/new-kq-inno-installer.ps1`.
- [ ] Record path, size, timestamp, and SHA-256.
- [ ] Require real tests: direct account 720p; then 1080p to 720p plus repeated top-V toggles.

Do not change the controlled-side resolution, FPS, codec, or runtime version.
