# Remote Quality Separation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make 720p standard quality visibly lower than 1080p HD while preserving the stable 60 FPS video and rendering pipeline.

**Architecture:** Change only the custom image quality constants consumed by Flutter settings and the Rust session option message. Keep the existing server conversion `quality * 2 / 100`, all codec/rendering decisions, and remote display resolution behavior unchanged.

**Tech Stack:** Flutter/Dart, Rust, Cargo, Flutter 3.24.5, Inno Setup, Android NDK/Gradle

---

### Task 1: Lock the new quality values with failing tests

**Files:**
- Modify: `flutter/test/kq_remote_video_render_test.dart`
- Modify: `src/client.rs`

- [ ] **Step 1: Change the Flutter expectation from 80 to 25**

```dart
expect(kqStandardRemoteStreamQuality, 25);
expect(kqHighDefinitionRemoteStreamQuality, 150);
```

- [ ] **Step 2: Change the Rust expectation from 80 to 25**

```rust
assert_eq!(kq_remote_custom_image_quality_for_tier("720p"), 25);
assert_eq!(kq_remote_custom_image_quality_for_tier("1080p"), 150);
```

- [ ] **Step 3: Run both targeted tests and verify RED**

Run:

```powershell
D:\tools\flutter-3.24.5\bin\flutter.bat test test\kq_remote_video_render_test.dart --plain-name "720p standard quality is lower than 1080p HD"
cargo test profiles_use_distinct_compression_quality --lib --features flutter
```

Expected: both fail because the implementation still returns `80` for 720p.

### Task 2: Apply the standard-quality constant

**Files:**
- Modify: `flutter/lib/models/remote_video_quality_policy.dart`
- Modify: `src/client.rs`

- [ ] **Step 1: Set the Flutter standard value**

```dart
const int kqStandardRemoteStreamQuality = 25;
const int kqHighDefinitionRemoteStreamQuality = 150;
```

- [ ] **Step 2: Set the Rust standard value**

```rust
const KQ_STANDARD_IMAGE_QUALITY: i32 = 25;
const KQ_HIGH_DEFINITION_IMAGE_QUALITY: i32 = 150;
```

- [ ] **Step 3: Run the targeted tests and verify GREEN**

Run the commands from Task 1. Expected: both pass.

### Task 3: Run regression verification

**Files:**
- Test: `flutter/test/kq_remote_video_render_test.dart`

- [ ] **Step 1: Run the full Flutter regression file**

```powershell
D:\tools\flutter-3.24.5\bin\flutter.bat test test\kq_remote_video_render_test.dart
```

Expected: all 21 tests pass, including gray-screen overlay and no-resolution-mapping checks.

- [ ] **Step 2: Confirm the server mapping remains unchanged**

```powershell
rg -n "custom_quality \* 2|sessionChangeResolution|KQ skips remote display resolution" src flutter\lib
```

Expected: quality still maps through the existing ratio calculation and KQ remote resolution changes remain blocked.

### Task 4: Build and verify Windows

**Files:**
- Output: `dist/Kunqiong-Remote-Desktop-Setup-<timestamp>.exe`

- [ ] **Step 1: Force native and Flutter Windows rebuild**

```powershell
.\scripts\build-kq-apps.ps1 -Target Windows -FlutterSdk D:\tools\flutter-3.24.5 -WindowsCargoFeatures flutter,hwcodec,vram -ForceWindowsNative -SkipFlutterPubGet -UpdateStableNames -KeepTimestampedArtifacts
```

- [ ] **Step 2: Verify Inno and payload hashes**

Run `ISCC.exe` directly if the helper's final `Get-FileHash` call fails, then compare the built `librustdesk.dll` SHA-256 with the installer payload DLL. Expected: Inno exit code 0 and matching hashes.

### Task 5: Build and verify Android

**Files:**
- Output: `dist/Kunqiong-Remote-Desktop-Android-<timestamp>.apk`

- [ ] **Step 1: Force Android native and Flutter rebuild**

```powershell
.\scripts\build-kq-apps.ps1 -Target Android -FlutterSdk D:\tools\flutter-3.24.5 -ForceAndroidNative -SkipFlutterPubGet -UpdateStableNames -KeepTimestampedArtifacts
```

- [ ] **Step 2: Verify the packaged native library**

Compare the APK `lib/arm64-v8a/librustdesk.so` SHA-256 with a freshly stripped copy of the Cargo output. Expected: hashes match.
