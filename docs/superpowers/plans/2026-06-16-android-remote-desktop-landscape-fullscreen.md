# Android Remote Desktop Landscape Fullscreen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make phone-to-PC remote sessions default to landscape fullscreen.

**Architecture:** Add small helper methods in the existing mobile remote page. Use Flutter `SystemChrome` APIs so the behavior is scoped to this page and can be restored in `dispose`.

**Tech Stack:** Flutter/Dart, existing PowerShell release checks.

---

### Task 1: Regression Checks

**Files:**
- Modify: `scripts/test-kq-release.ps1`

- [ ] Add `Test-KqAndroidRemoteDesktopLandscapeFullscreen`.
- [ ] Require a desktop-peer helper using Windows/macOS/Linux platform constants.
- [ ] Require `SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight])`.
- [ ] Require orientation reset in `dispose`.
- [ ] Run `scripts\test-kq-release.ps1 -NoReport`; expected before implementation: the new checks fail.

### Task 2: Remote Page Behavior

**Files:**
- Modify: `flutter/lib/mobile/pages/remote_page.dart`

- [ ] Add `_shouldUseDesktopPeerLandscapeFullscreen`.
- [ ] Add `_applyDesktopPeerLandscapeFullscreen`.
- [ ] Call the helper after peer info is ready in the first-image callback.
- [ ] Restore orientation and system overlays in `dispose`.

### Task 3: Verification And Package

**Files:**
- Verify: `flutter/lib/mobile/pages/remote_page.dart`
- Verify: `scripts/test-kq-release.ps1`

- [ ] Run `dart format`.
- [ ] Run targeted Flutter analysis.
- [ ] Run `scripts\test-kq-release.ps1 -NoReport`.
- [ ] Build Android APK with next build number.
- [ ] Install on MuMu and confirm version/startup.
