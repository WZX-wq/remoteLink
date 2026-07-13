# 720p gray-screen handoff (2026-07-11)

## Project

- Repository: `D:\demo\远程桌面\remoteLink`
- Branch/HEAD: `main`, `a275403 chore: add production env file`
- The worktree is heavily modified and contains unrelated user work. Do not reset, clean, checkout, or revert broad file sets.
- Latest screenshot: `C:\Users\admin\AppData\Local\Temp\codex-clipboard-91b2e180-6714-4fb0-b8a6-fad19ecc8037.png`

## Unresolved behavior

The controller connects successfully to peer `494994239`, but the remote-video area is uniformly gray when the account profile is 720p standard quality.

Reproduction paths reported by the user:

1. Select 720p in My Account, then connect: connection succeeds but the video area is gray.
2. Select 1080p and connect: remote picture is visible.
3. Start in 1080p, switch to 720p, then repeatedly collapse/expand the top toolbar with the V button: the video area becomes gray.

Product requirements:

- 720p/1080p are video-quality profiles, not controlled-side display resolutions.
- Never change the controlled computer's screen resolution.
- Both profiles should use the same connection/decode/render architecture.
- Standard quality may use a lower stream quality value so the video is softer; HD should remain clearer.
- Collapsing/expanding the toolbar must not reset or cover the video.

## Latest package is definitely installed

Installed files match the final Release artifacts, so do not attribute this run to an old installer:

- `C:\Program Files\KQRemoteLink\rustdesk.exe`
  - SHA256 `0972C8D800E0212D9F9395727FE32F1FC521FC5ADF1940A6937ED41C332F3472`
  - file version `1.4.6+2067`
- `C:\Program Files\KQRemoteLink\librustdesk.dll`
  - SHA256 `F176D7751945FDD6B503CFDDFE1002B2219AFCCCD241000FABDDDE43474960A7`
- `C:\Program Files\KQRemoteLink\data\app.so`
  - SHA256 `3D83E2DD00827BF0D0DD279766EA5E207FB0564E859D5493707414D8C94C03E4`
- Installer: `D:\demo\远程桌面\remoteLink\dist\Kunqiong-Remote-Desktop-Setup.exe`
  - product version `2026.07.11.1534`
  - SHA256 `3CF9DC8E27226BE9249E5339D9D994DE6B9876F67AB50C7872A45844A25F92FB`

Only the controller needs this UI/composition fix. The controlled side already sends valid frames and is not the current blocker.

## Decisive evidence from the failed 720p run

Log: `C:\Users\admin\AppData\Roaming\鲲穹远程桌面\log\rustdesk_rCURRENT.log`

Current persisted settings are also confirmed:

- `鲲穹远程桌面_local.toml`: `kq_remote_resolution_tier = '720p'`
- `鲲穹远程桌面_local.toml`: `kq_remote_fps_tier = '60'`
- `鲲穹远程桌面_default.toml`: `custom-fps = '60'`
- `鲲穹远程桌面_default.toml`: `custom_image_quality = '150'`

The failed session is healthy through the Flutter canvas:

- Line 49: first encoded VP9 keyframe received.
- Line 55: VP9 decoder created successfully.
- Line 56: first 1920x1080 RGBA frame queued, 8,294,400 bytes, alpha range 255..255, first pixel is non-gray content.
- Line 57: decoded frame submitted to the renderer with `pixelbuffer=true`.
- Lines 59-60: Dart receives the buffer and creates/updates a 1920x1080 `ui.Image`.
- Lines 61-62: `canvas-draw-image` runs with a visible paint area of 1284x709.
- Line 88: selected custom FPS is 60.
- Many subsequent `dart-frame-received` and `dart-image-updated` events continue.
- Toolbar toggles are logged around lines 385, 395, 439, and 446, while frame/image updates continue after every toggle.
- There is no decoder failure, empty frame, alpha failure, or stopped stream.

Conclusion: network, peer capture, codec, FPS, decoding, RGBA conversion, Dart buffer transfer, and canvas drawing are working. The gray output occurs after `canvas-draw-image`, in the Flutter widget/layer/window composition path.

## Most likely remaining cause

The only remote-video rendering branch that still depends on the selected 720p/1080p profile is:

- `flutter/lib/models/remote_video_quality_policy.dart`
  - `KqRemoteQualityPresentation`
  - HD returns `child` directly.
  - Standard wraps `child` in a `Stack` with a full-size `ColoredBox` overlay.
- `flutter/lib/desktop/pages/remote_page.dart`
  - `_applyKqRemoteQualityPresentation()` wraps both texture and software-paint video widgets.
  - It reads `gFFI.userModel.remoteResolutionSelection` and is applied in both major layout branches.

This wrapper is currently the only profile-specific difference after stream/decode. Even though the overlay opacity is only 0.045 and its widget test passes, the test uses a simple `ColoredBox`; it does not exercise the real Windows AOT `ui.Image`/`CustomPaint`/window composition. Therefore that test does not rule out a real composition failure.

## Changes already attempted

- 720p and 1080p now both request custom image quality `150`.
- Both profiles now use 60 FPS.
- Rust clamps old persisted/dynamic 30 FPS values to 60.
- Codec selection is the same; failed run used VP9 successfully.
- KQ Windows currently uses the software pixel-buffer renderer for diagnostics.
- Remote display resolution changes were removed/skipped.
- V-button handling was changed to visibility-only behavior.
- Extensive stage logging was added from encoded frame through canvas paint.
- Unit/widget tests pass, but the real two-PC Windows failure remains.

Do not spend another iteration changing FPS, codec, peer display resolution, installer version, or connection timeout unless new evidence contradicts the log above.

## Required next diagnostic/fix sequence

1. First make a minimal diagnostic build where `_applyKqRemoteQualityPresentation(Widget child)` returns `child` unconditionally for KQ. Remove/bypass `KqRemoteQualityPresentation` entirely. Do not add any blur/filter/overlay yet.
2. Build and test both exact cases: direct 720p connection; 1080p connection -> switch to 720p -> repeatedly click V.
3. If video becomes visible, the wrapper is confirmed as the cause. Delete the overlay approach permanently.
4. Differentiate quality through the existing stream-quality number only, using the same pipeline (for example standard 80-100 and HD 150). This changes video compression quality, not the controlled-side screen resolution.
5. If the no-wrapper build is still gray, add a `RepaintBoundary` around the final video surface and capture it with `toImage()` after `canvas-draw-image`. Compare sampled pixels from the Flutter capture with an OS screenshot:
   - Flutter capture has content but OS window is gray: Windows/Flutter compositor or another native/window layer is covering it.
   - Flutter capture is gray: inspect ancestors, clipping, opacity, placeholder/background widgets, and paint bounds.
6. Add an actual Windows integration/repaint test. The existing red `ColoredBox` widget test is not sufficient.

## Relevant files

- `flutter/lib/desktop/pages/remote_page.dart`
- `flutter/lib/models/remote_video_quality_policy.dart`
- `flutter/lib/models/video_render_policy.dart`
- `flutter/lib/models/desktop_render_texture.dart`
- `flutter/lib/desktop/widgets/remote_toolbar.dart`
- `flutter/lib/models/user_model.dart`
- `flutter/test/kq_remote_video_render_test.dart`
- `src/client.rs`
- `src/client/io_loop.rs`
- `src/flutter.rs`
- `src/ui_interface.rs`
- `src/ui_session_interface.rs`

## Verification/build commands

```powershell
cd D:\demo\远程桌面\remoteLink

D:\tools\flutter-3.24.5\bin\flutter.bat test .\flutter\test\kq_remote_video_render_test.dart
cargo test --features flutter --lib kq_remote_video_quality_tests -- --nocapture

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-kq-apps.ps1 `
  -Target Windows `
  -FlutterSdk 'D:\tools\flutter-3.24.5' `
  -ForceWindowsNative `
  -Offline
```

Do not report the issue fixed only because tests pass. Acceptance requires the user to confirm both real two-PC reproduction paths.
