# Designer Desktop UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Windows desktop Flutter UI match the designer-provided desktop prototype while preserving existing business logic.

**Architecture:** Reuse the current Flutter desktop page files and introduce a small designer-style component layer inside the same ownership boundaries. Add regression markers to the release script before UI changes, then implement page-by-page with focused Dart changes.

**Tech Stack:** Flutter/Dart desktop UI, existing RustDesk/KQ models and FFI bindings, PowerShell release regression scripts, CodeGraph CLI.

---

### Task 1: Add Regression Markers

**Files:**
- Modify: `scripts/test-kq-release.ps1`

- [ ] Add checks for designer desktop UI markers:
  - `kq-designer-desktop-shell`
  - `kq-designer-sidebar`
  - `kq-designer-header-bar`
  - `kq-designer-home-member-banner`
  - `kq-designer-local-credential-panels`
  - `kq-designer-connect-card`
  - `kq-designer-account-guest-layout`
  - `kq-designer-account-performance-right`
  - `kq-designer-settings-tabs`
  - `kq-designer-devices-page`
- [ ] Run `powershell -ExecutionPolicy Bypass -File scripts\test-kq-release.ps1 -NoReport` and verify the new checks fail before implementation.

### Task 2: Implement Designer Shell and Navigation

**Files:**
- Modify: `flutter/lib/desktop/pages/desktop_tab_page.dart`
- Modify: `flutter/lib/desktop/pages/desktop_home_page.dart`

- [ ] Add a designer-style desktop shell marker and constants for sidebar width, header height, palette, and compact card styling.
- [ ] Ensure sidebar order is `远程协助`, `设备`, `我的账户`, `设置`, footer `官网`.
- [ ] Preserve window dragging, top user entry, and existing window controls.

### Task 3: Implement Home Layout

**Files:**
- Modify: `flutter/lib/desktop/pages/desktop_home_page.dart`
- Modify if needed: `flutter/lib/common/widgets/peer_card.dart`

- [ ] Render the member banner from the prototype.
- [ ] Render local ID and verification code in one split white card.
- [ ] Keep existing one-time/daily/long-term password controls and share/copy/refresh behavior.
- [ ] Render remote ID/password/connect controls in a compact connect card.
- [ ] Render recent connections as light cards using local recent data.

### Task 4: Implement Account Layout

**Files:**
- Modify: `flutter/lib/desktop/pages/desktop_setting_page.dart`

- [ ] Logged-out page uses designer guest layout with welcome/features and login card.
- [ ] Logged-in account keeps profile, membership, account actions, and right-side remote quality/FPS settings.
- [ ] Keep quality/FPS membership gating and saved options unchanged.

### Task 5: Implement Settings Tabs

**Files:**
- Modify: `flutter/lib/desktop/pages/desktop_setting_page.dart`

- [ ] Replace the embedded settings layout with designer horizontal tabs.
- [ ] Keep existing settings groups and foldouts, but restyle cards compactly.
- [ ] Keep camera/view-camera descriptions hidden.

### Task 6: Implement Devices Page

**Files:**
- Modify: `flutter/lib/desktop/pages/desktop_home_page.dart`
- Modify if needed: `flutter/lib/desktop/pages/desktop_tab_page.dart`

- [ ] Add a designer devices page entry using existing peer/recent data.
- [ ] Do not introduce cloud overwrite of local recent history.

### Task 7: Verify and Package

**Commands:**
- `dart format <changed dart files>`
- `flutter analyze --no-fatal-infos <changed dart files>`
- `powershell -ExecutionPolicy Bypass -File scripts\test-kq-release.ps1 -NoReport`
- `powershell -ExecutionPolicy Bypass -File scripts\test-kq-oauth.ps1 -NoReport`
- `powershell -ExecutionPolicy Bypass -File scripts\verify-kq-remote-link.ps1 -SkipBuildEnvCheck`
- `cmd /c codegraph sync`
- `cmd /c codegraph status`
- `powershell -ExecutionPolicy Bypass -File scripts\new-kq-inno-installer.ps1 -OutputRoot C:\kq-remote-link-tools -InstallerName Remote-Link-v212 -Version 2026.06.27.2120 -SkipCargoBuild`

**Expected:** All checks pass and the unsigned installer is created at `C:\kq-remote-link-tools\Remote-Link-v212.exe`.
