# Android Sunlogin Touchpad Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Android touch mode control desktop peers like Sunlogin touchpad mode.

**Architecture:** Keep the existing Flutter gesture recognizers. Change only the mobile touch-mode desktop-peer branch in `RawTouchGestureDetectorRegion`, so one-finger pan moves the cursor without mouse down/up and hold-drag is the explicit drag gesture.

**Tech Stack:** Flutter/Dart gesture handling, existing PowerShell release checks.

---

### Task 1: Regression Checks

**Files:**
- Modify: `scripts/test-kq-release.ps1`

- [ ] Add source checks that require a helper for Sunlogin touchpad mode.
- [ ] Require `onOneFingerPanStart` and `onOneFingerPanEnd` to skip implicit left down/up when the helper is active.
- [ ] Require hold-drag start/end to send explicit left down/up in touch mode.
- [ ] Run `scripts\test-kq-release.ps1 -NoReport`; expected before implementation: the new checks fail.

### Task 2: Gesture Mapping

**Files:**
- Modify: `flutter/lib/common/widgets/remote_input.dart`

- [ ] Add a helper returning true when this is a mobile controller in touch mode controlling a non-Android peer.
- [ ] In touch mode tap-up, keep the existing move-then-left-click behavior.
- [ ] In one-finger pan start/end, do not send implicit left down/up when the helper is true.
- [ ] In hold-drag start/update/end, allow the helper path to send left down, move relatively, then left up.
- [ ] Run `dart format` and targeted analysis.

### Task 3: Verification And Package

**Files:**
- Verify: `flutter/lib/common/widgets/remote_input.dart`
- Verify: `scripts/test-kq-release.ps1`

- [ ] Run PowerShell parser check for `scripts/test-kq-release.ps1`.
- [ ] Run `scripts\test-kq-release.ps1 -NoReport`.
- [ ] Build Android native library and release APK with next build number.
- [ ] Install on MuMu and smoke-test remote connection/touch behavior where feasible.
- [ ] Update Obsidian project memory with the mapping decision and deliverable.
