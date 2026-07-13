# True Remote Video Tiers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Encode standard sessions at no more than 1280x720 and HD sessions at no more than 1920x1080 without changing the controlled display or either client's presentation path.

**Architecture:** Preserve the selected product tier separately from adaptive bitrate in `VideoQoS`, then derive an even, aspect-ratio-preserving encoder size from that tier. Scale CPU pixel buffers with libyuv before the existing YUV conversion and skip VRAM texture input only when scaling is required; decoder output continues to be drawn into the original remote display rectangle.

**Tech Stack:** Rust, libyuv, RustDesk `scrap` encoders, Flutter/Dart regression tests, Cargo tests, PowerShell packaging.

---

### Task 1: Persist The Selected Video Tier In QoS

**Files:**
- Modify: `src/server/video_qos.rs`

- [ ] **Step 1: Write failing tier-selection tests**

Add tests that feed packed KQ custom qualities (`25 << 8` and `150 << 8`) into `VideoQoS::user_image_quality` and assert that `selected_video_tier()` returns `Standard` and `HighDefinition`. Add a non-KQ/default assertion for `Original`.

- [ ] **Step 2: Run the focused tests and verify failure**

Run: `cargo test --features flutter video_qos::tests::kq_selected_video_tier --lib -- --nocapture`

Expected: FAIL because `KqVideoTier` and `selected_video_tier()` do not exist.

- [ ] **Step 3: Implement tier state independent of adaptive ratio**

Add:

```rust
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum KqVideoTier {
    Standard,
    HighDefinition,
    #[default]
    Original,
}
```

Store `(timestamp, KqVideoTier)` beside each user's selected `Quality`. For the KQ app, map custom quality `25` to `Standard` and `150` to `HighDefinition`; otherwise retain `Original`. Select the most recently updated tier using the same timestamp ordering as `latest_quality()`.

- [ ] **Step 4: Run focused QoS tests**

Run: `cargo test --features flutter video_qos::tests --lib -- --nocapture`

Expected: PASS with standard and HD tier state unaffected by adaptive bitrate changes.

### Task 2: Calculate Stable Encoder Dimensions

**Files:**
- Modify: `src/server/video_service.rs`

- [ ] **Step 1: Write failing dimension tests**

Add table tests for `kq_encoded_dimensions(width, height, tier)` covering:

```rust
(1920, 1080, Standard)       => (1280, 720)
(1920, 1080, HighDefinition) => (1920, 1080)
(3840, 2160, HighDefinition) => (1920, 1080)
(3440, 1440, Standard)       => (1280, 534)
(1080, 1920, Standard)       => (404, 720)
(1279, 719, Standard)        => (1278, 718)
(800, 600, Standard)         => (800, 600)
(1920, 1080, Original)       => (1920, 1080)
```

- [ ] **Step 2: Run focused dimension tests and verify failure**

Run: `cargo test --features flutter video_service::tests::kq_encoded_dimensions --lib -- --nocapture`

Expected: FAIL because the helper does not exist.

- [ ] **Step 3: Implement the pure dimension helper**

Calculate `scale = min(max_width / width, max_height / height, 1.0)`, floor both scaled dimensions to even positive values, and return the source dimensions unchanged for `Original`. Avoid floating-point overflow by converting source values to `f64` only after validating non-zero input.

- [ ] **Step 4: Run focused dimension tests**

Run: `cargo test --features flutter video_service::tests::kq_encoded_dimensions --lib -- --nocapture`

Expected: PASS for landscape, portrait, ultrawide, odd, small, 1080p, and 4K cases.

### Task 3: Scale Pixel Buffers Before YUV Conversion

**Files:**
- Modify: `libs/scrap/src/bindings/yuv_ffi.h`
- Modify: `libs/scrap/src/common/convert.rs`
- Modify: `libs/scrap/src/common/mod.rs`
- Modify: `src/server/video_service.rs`

- [ ] **Step 1: Add failing conversion tests**

Create synthetic BGRA buffers and verify conversion from 1920x1080 input into 1280x720 I420, NV12, and I444 output layouts. Assert successful conversion and exact minimum plane-buffer lengths; add a no-scaling case that preserves the existing output.

- [ ] **Step 2: Run scrap conversion tests and verify failure**

Run: `cargo test -p scrap convert::tests -- --nocapture`

Expected: FAIL with the current `src rect > dst rect` error.

- [ ] **Step 3: Bind and implement libyuv scaling**

Include `libyuv/scale_argb.h` in `yuv_ffi.h`. Extend `Frame::to` and `convert_to_yuv` with a reusable scale buffer. When source dimensions exceed `EncodeYuvFormat`, normalize RGB565 to four-channel ARGB, call `ARGBScale(..., kFilterBilinear)`, then pass the scaled BGRA/RGBA bytes through the existing I420/NV12/I444 conversion branches. Do not allocate a new scale buffer for every frame.

- [ ] **Step 4: Run conversion and scrap tests**

Run: `cargo test -p scrap convert::tests -- --nocapture`

Expected: PASS for all three encoder pixel layouts and the unchanged no-scale path.

### Task 4: Configure And Restart Encoders At Tier Dimensions

**Files:**
- Modify: `src/server/video_service.rs`
- Modify: `src/server/video_qos.rs`

- [ ] **Step 1: Write failing encoder-policy tests**

Assert that scaling-required configurations use the calculated dimensions for VPX, AOM, and hardware-RAM config variants and cannot select VRAM texture input. Assert that an in-session tier change produces the existing `SWITCH` signal before applying a bitrate-only update.

- [ ] **Step 2: Run focused policy tests and verify failure**

Run: `cargo test --features flutter video_service::tests::kq_encoder_tier --lib -- --nocapture`

Expected: FAIL because encoder configuration still uses capture width and height.

- [ ] **Step 3: Apply tier dimensions to encoder setup**

Read `selected_video_tier()` with the initial ratio, pass it into `setup_encoder` and `get_encoder_config`, and use calculated dimensions in VPX, AOM, and HWRAM configurations. Skip VRAM selection only when target dimensions differ from capture dimensions. Allocate and reuse the new scaling buffer in the frame loop.

- [ ] **Step 4: Restart when a tier crosses dimensions**

After `check_qos` reads the current selected tier, compare its desired dimensions with `encoder.yuvfmt()`. Return `SWITCH` on a mismatch so the existing outer service loop rebuilds the encoder and sends a fresh key frame. Keep `set_quality` for ratio changes that do not alter dimensions.

- [ ] **Step 5: Add installed-build diagnostics**

Log selected tier, source dimensions, encoded dimensions, negotiated codec, quality ratio, and CPU-scaling state immediately after encoder creation.

- [ ] **Step 6: Run focused and full Rust tests**

Run:

```powershell
cargo test --features flutter video_qos::tests --lib -- --nocapture
cargo test --features flutter video_service::tests --lib -- --nocapture
cargo test --features flutter kq_remote_video_quality_tests --lib -- --nocapture
```

Expected: all tests PASS.

### Task 5: Remove Presentation-Only Quality Differences

**Files:**
- Modify: `flutter/lib/desktop/pages/remote_page.dart`
- Modify: `flutter/lib/models/remote_video_quality_policy.dart`
- Modify: `flutter/test/kq_remote_video_render_test.dart`
- Delete: `flutter/lib/common/widgets/kq_remote_quality_presentation.dart`

- [ ] **Step 1: Change Flutter regression expectations first**

Assert that desktop `_applyKqRemoteQualityPresentation` returns `child`, Android `ImagePaint` contains neither `ImageFiltered` nor `KqRemoteQualityPresentation`, quality values remain `25` and `150`, and neither tier calls `sessionChangeResolution`.

- [ ] **Step 2: Run the Flutter regression and verify failure**

Run: `D:\tools\flutter-3.24.5\bin\flutter.bat test test\kq_remote_video_render_test.dart`

Expected: FAIL because desktop still wraps standard video with the temporary blur component.

- [ ] **Step 3: Remove the temporary presentation component**

Return `child` directly on desktop, remove the component import and file, and remove the obsolete blur sigma constant. Do not alter Android `CustomPaint`.

- [ ] **Step 4: Run Flutter remote-video tests**

Run: `D:\tools\flutter-3.24.5\bin\flutter.bat test test\kq_remote_video_render_test.dart`

Expected: PASS with identical client presentation paths.

### Task 6: Verify And Package Stable Artifacts

**Files:**
- Modify: `dist/Kunqiong-Remote-Desktop-Setup.exe`
- Modify: `dist/Kunqiong-Remote-Desktop-Setup.exe.sha256`
- Modify: `dist/Kunqiong-Remote-Desktop.apk`
- Modify: `dist/Kunqiong-Remote-Desktop.apk.sha256`

- [ ] **Step 1: Run full regression suites**

Run the complete Flutter test suite used by `kq_remote_video_render_test.dart`, the focused Rust tests above, and `git diff --check`.

Expected: all tests PASS and no whitespace errors.

- [ ] **Step 2: Build Windows and Android native artifacts**

Run the repository `scripts/build-kq-apps.ps1` workflow for Windows with `flutter,hwcodec,vram` and Android with the existing arm64 native prerequisites. Do not skip native Rust builds because the tier and scaling logic lives in Rust.

- [ ] **Step 3: Overwrite stable package names**

Copy successful outputs to `dist/Kunqiong-Remote-Desktop-Setup.exe` and `dist/Kunqiong-Remote-Desktop.apk`, regenerate their `.sha256` files, and remove timestamped APK/EXE duplicates only after verifying every deletion target resolves inside `dist`.

- [ ] **Step 4: Inspect final payloads**

Verify the Windows installer embeds the current executable and icon, the APK contains the newly built `arm64-v8a/librustdesk.so`, and no timestamped installer duplicates remain.

- [ ] **Step 5: Report device acceptance steps**

Install both stable packages and test direct 720p, direct 1080p, live switching in both directions, repeated toolbar expand/collapse, readable standard text, visibly sharper HD text, correct pointer/touch coordinates, and absence of black or gray screens.
