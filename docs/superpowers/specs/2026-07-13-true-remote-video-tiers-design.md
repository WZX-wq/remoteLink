# True Remote Video Tiers Design

## Goal

Make the mobile 720p and 1080p tiers visibly different by changing the encoded
pixel dimensions, while keeping the controlled computer's display resolution,
input coordinates, connection path, decoder path, and Flutter presentation path
unchanged.

## Selected Approach

Scale captured pixels before encoding:

- Standard tier: maximum encoded size `1280x720`.
- HD tier: maximum encoded size `1920x1080`.
- Preserve the source aspect ratio.
- Round output width and height down to positive even values required by YUV
  4:2:0 encoders.
- Never upscale a source that is already smaller than the tier limit.
- Keep the existing custom quality values (`25` for standard and `150` for HD)
  and the shared 60 FPS policy.

This produces a real pixel-count difference. It does not use a Flutter blur,
overlay, opacity layer, remote resolution command, or a different client-side
renderer.

## Alternatives Considered

1. Lower bitrate only. This is the current behavior. VP9 preserves static desktop
   text efficiently, so the difference is often not visible on a small phone.
2. Blur or pixelate in Flutter. This can make the difference obvious, but the
   Android `CustomPaint` surface already produced a black video area when wrapped
   by `ImageFiltered`, so this approach is rejected.
3. Change the controlled monitor to 1280x720. This visibly changes the stream but
   disrupts the remote machine and violates the product requirement, so it is
   rejected.

## Server Video Pipeline

Add a pure helper that calculates the encoded dimensions from source width,
source height, and the selected quality tier. The helper is shared by encoder
configuration and the frame conversion path.

For standard or HD sources larger than their tier limit:

1. Capture the desktop at its real dimensions.
2. Scale the pixel buffer with libyuv using bilinear filtering.
3. Convert the scaled buffer to the encoder's requested I420, NV12, or I444
   layout.
4. Configure VP8, VP9, AV1, and hardware-RAM encoders with the same scaled width
   and height.
5. Disable the VRAM texture-input encoder only when scaling is required, because
   its input texture size is tied to the captured surface. Continue using the
   existing encoder negotiation and hardware-RAM path where supported.

When no scaling is required, preserve the existing zero-copy and conversion
behavior.

## Tier Changes During A Session

The video loop compares the desired tier dimensions with the active encoder
dimensions after quality updates. If they differ, it requests the existing
encoder switch/restart flow and emits a new key frame. A bitrate-only adjustment
within the same dimensions continues to use `set_quality` without restarting.

The current service uses one encoder per display for all viewers. This design
retains that ownership model: the latest selected quality remains the active
display stream policy, matching the current QoS behavior.

## Client Display And Input Mapping

Do not modify `DisplayInfo`, `SwitchDisplay`, or the controlled monitor. The
client learns the decoded frame size from the video bitstream and draws that
image into the existing display rectangle. Pointer and touch input continue to
map against the controlled display's real dimensions, so scaling the encoded
image does not shift click coordinates.

Android `ImagePaint` must continue to return its normal `CustomPaint` subtree
without `ImageFiltered` or `KqRemoteQualityPresentation`.

## Diagnostics

Log one line when an encoder is created or restarted with:

- selected tier;
- source dimensions;
- encoded dimensions;
- codec;
- quality ratio;
- whether CPU scaling is active.

This makes installed-device verification possible without inferring behavior
from the product label.

## Verification

- Unit-test dimension calculation for 16:9, ultrawide, portrait, odd-sized,
  smaller-than-limit, 720p, 1080p, and 4K sources.
- Unit-test that standard and HD produce different dimensions for a 1080p source.
- Unit-test that scaling never changes the controlled display dimensions.
- Test libyuv scaling and conversion buffer sizes for I420, NV12, and I444.
- Keep the existing Flutter tests proving Android has no presentation filter and
  both tiers use the same display widget path.
- Run the existing Rust quality test and Flutter remote-video regression suite.
- Build Android and Windows packages under the stable filenames only.
- Device acceptance: connect directly in 720p, connect directly in 1080p, switch
  both directions while connected, verify readable standard text, visibly sharper
  HD text, correct mouse/touch coordinates, and no black or gray screen.

## Non-Goals

- Changing the controlled computer's display mode.
- Adding a client-side blur or overlay.
- Changing FPS, membership rules, codec preference, or remote-control input
  behavior.
