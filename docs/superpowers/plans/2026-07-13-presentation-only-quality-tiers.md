# Presentation-Only Remote Quality Tiers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore reliable first-frame delivery and distinguish standard quality with a sigma 0.6 client-side blur on Windows and Android.

**Architecture:** Revert the failed encoder-dimension experiment so both tiers use the original stream pipeline at quality 150 and 60 FPS. Apply Windows blur with the existing widget-level presentation component and Android blur inside the existing `ImagePainter` paint operation, never around the Android `CustomPaint` widget.

**Tech Stack:** Flutter/Dart, Dart `ui.ImageFilter`, Rust, Flutter tests, Cargo tests, PowerShell packaging.

---

### Task 1: Restore The Original Encoding Pipeline

**Files:**
- Modify: `src/server/video_qos.rs`
- Modify: `src/server/video_service.rs`
- Modify: `libs/scrap/src/bindings/yuv_ffi.h`
- Modify: `libs/scrap/src/common/convert.rs`
- Modify: `libs/scrap/src/common/mod.rs`
- Modify: `libs/scrap/examples/benchmark.rs`
- Test: `flutter/test/kq_remote_video_render_test.dart`

- [ ] **Step 1: Add failing source-contract assertions**

Assert that the server files contain no `KqVideoTier`, `kq_encoded_dimensions`, `ARGBScale`, `convert_to_yuv_with_scale`, or `KQ video encoder switch` symbols. Assert that `Frame::to` retains its original four arguments.

- [ ] **Step 2: Run the Flutter regression and verify failure**

Run: `D:\tools\flutter-3.24.5\bin\flutter.bat test test\kq_remote_video_render_test.dart`

Expected: FAIL because the failed encoder-size experiment is still present.

- [ ] **Step 3: Remove the encoder-size experiment**

Restore the original `VideoQoS` user data, `video_service` encoder configuration, `check_qos`, `convert_to_yuv`, `Frame::to`, benchmark calls, and libyuv header list. Preserve unrelated existing code and the custom quality/FPS policy.

- [ ] **Step 4: Run Rust compilation and Flutter regression**

Run:

```powershell
cargo test --features flutter kq_remote_video_quality_tests --lib -- --nocapture
D:\tools\flutter-3.24.5\bin\flutter.bat test test\kq_remote_video_render_test.dart
```

Expected: PASS and no encoder-size symbols remain.

### Task 2: Restore Unified Stream Quality And Windows Blur

**Files:**
- Modify: `src/client.rs`
- Modify: `flutter/lib/models/remote_video_quality_policy.dart`
- Create: `flutter/lib/common/widgets/kq_remote_quality_presentation.dart`
- Modify: `flutter/lib/desktop/pages/remote_page.dart`
- Test: `flutter/test/kq_remote_video_render_test.dart`

- [ ] **Step 1: Change tests to the unified quality and Windows presentation contract**

Assert standard and HD quality are both `150`. Add widget tests proving standard creates exactly one `ImageFiltered` with sigma `0.6`, HD creates none, and the component contains no `Stack`, `ColoredBox`, or `BackdropFilter`.

- [ ] **Step 2: Run Flutter and Rust tests and verify failure**

Expected: Flutter fails because the component is absent; Rust fails because standard quality is still `25`.

- [ ] **Step 3: Implement unified quality and Windows blur**

Set both Dart and Rust constants to `150`. Restore `kqStandardRemoteBlurSigma = 0.6`, create `KqRemoteQualityPresentation`, and return it from desktop `_applyKqRemoteQualityPresentation` around only the video child.

- [ ] **Step 4: Run focused tests**

Expected: quality and Windows presentation tests PASS.

### Task 3: Blur Android Inside The Existing Painter

**Files:**
- Modify: `flutter/lib/utils/image.dart`
- Modify: `flutter/lib/mobile/pages/remote_page.dart`
- Test: `flutter/test/kq_remote_video_render_test.dart`

- [ ] **Step 1: Write failing painter and integration tests**

Render a colored `ui.Image` through `ImagePainter(blurSigma: 0.6)` into a picture, decode the output bytes, and assert visible non-transparent pixels remain. Assert mobile `ImagePaint` passes the standard sigma to `ImagePainter` but contains no widget-level `ImageFiltered`, `BackdropFilter`, or `KqRemoteQualityPresentation`.

- [ ] **Step 2: Run the Flutter test and verify failure**

Expected: FAIL because `ImagePainter` has no `blurSigma` argument.

- [ ] **Step 3: Add painter-level blur**

Add nullable/default-zero `blurSigma` to `ImagePainter`. Before `canvas.drawImage`, set:

```dart
if (blurSigma > 0) {
  paint.imageFilter = ui.ImageFilter.blur(
    sigmaX: blurSigma,
    sigmaY: blurSigma,
    tileMode: ui.TileMode.clamp,
  );
}
```

In mobile `ImagePaint`, pass `kqStandardRemoteBlurSigma` only when `remoteCustomQualitySelection` represents the standard account tier; otherwise pass zero. Cursor painters keep the default zero.

- [ ] **Step 4: Run Flutter regressions**

Expected: the blurred painter remains nonblank and all remote-video tests PASS.

### Task 4: Verify And Rebuild Stable Packages

**Files:**
- Modify: `dist/Kunqiong-Remote-Desktop-Setup.exe`
- Modify: `dist/Kunqiong-Remote-Desktop-Setup.exe.sha256`
- Modify: `dist/Kunqiong-Remote-Desktop.apk`
- Modify: `dist/Kunqiong-Remote-Desktop.apk.sha256`

- [ ] **Step 1: Run fresh source verification**

Run Flutter remote-video tests, the Rust quality test, `git diff --check`, and source scans proving no encoder-size experiment or Android widget filter remains.

- [ ] **Step 2: Build Windows and Android with fresh native libraries**

Run `scripts/build-kq-apps.ps1` for Windows with `'flutter,hwcodec,vram'` and for Android without native-skip flags.

- [ ] **Step 3: Overwrite stable names and remove duplicates**

Update the two stable packages and SHA256 files. Delete timestamped package/build artifacts only after resolving each target inside `dist`.

- [ ] **Step 4: Verify final payloads**

Confirm the Windows installer icon matches `rustdesk.exe`, APK `librustdesk.so` matches the new arm64 library, SHA files match, and timestamped duplicate count is zero.

- [ ] **Step 5: Device acceptance**

Install both stable packages and test direct 720p first-frame delivery, direct 1080p, switching both ways, Windows toolbar expand/collapse, Android side controls, and absence of waiting, black, or gray screens.
