# Mobile Keyboard Side Rail Layout

## Goal

Keep the mobile remote-session side rail stable and usable when the software keyboard opens, including access to the More and Hide actions.

## Root Cause

Android declares `adjustResize`, and the remote page's `Scaffold` currently uses the default `resizeToAvoidBottomInset: true`. Opening the software keyboard therefore reduces the body height. The side rail is a fixed-size `Column` positioned only from the top, so its lower actions are clipped when the resized body becomes shorter. Floating keyboards are not consistently reported by the keyboard-visibility plugin, which makes the existing conditional rail hiding unreliable.

## Behavior

- The remote video scene and right-side action rail keep their full safe-area layout when the software keyboard opens.
- The software keyboard overlays the video scene instead of resizing it.
- The right-side action rail remains visible while the keyboard is active.
- More and Hide remain reachable.
- On short landscape screens, the rail scrolls vertically instead of overflowing or clipping.
- Closing the keyboard, hiding the rail, and all existing rail actions retain their current behavior.

## Implementation

- Set `resizeToAvoidBottomInset: false` on the mobile remote page `Scaffold`.
- Stop using keyboard visibility as a reason to return `Offstage` from `_remoteSideActionRail()`.
- Compute the rail's maximum height from the full `MediaQuery` height minus safe-area padding and existing top/bottom gaps.
- Wrap the rail controls in a vertical `SingleChildScrollView` inside that maximum-height constraint.
- Do not change `openKeyboard()`, text input handling, video rendering, stream quality, or the desktop toolbar.

## Verification

- Add a regression test that requires `resizeToAvoidBottomInset: false` on the mobile remote page.
- Add a source/layout contract that the rail is not hidden by `keyboardIsVisible` and uses a bounded vertical scroll view.
- Run the complete remote-video regression test file.
- Build Android and overwrite `dist/Kunqiong-Remote-Desktop.apk` and its SHA256 file without leaving timestamped APKs.
- Verify the APK contains the current Dart AOT library and Rust native library.
