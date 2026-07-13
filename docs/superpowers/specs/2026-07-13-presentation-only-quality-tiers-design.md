# Presentation-Only Remote Quality Tiers Design

## Goal

Restore reliable first-frame delivery on Android and distinguish standard from
HD quality only in the client presentation layer.

## Stream Pipeline

- Remove the KQ encoder-size tier, libyuv pre-encode scaling, encoder dimension
  restart, and related diagnostics/tests introduced by the true-720p experiment.
- Restore the existing capture and encoder dimensions on every platform.
- Set both standard and HD custom stream quality to `150` at 60 FPS.
- Keep both tiers on the same codec negotiation, network transport, decoder,
  RGBA/texture, and Flutter video widget paths.
- Do not change the controlled computer's display resolution.

This returns first-frame delivery to the configuration that worked before the
encoder-size experiment.

## Windows Presentation

- Restore `KqRemoteQualityPresentation` around only the desktop video child.
- For standard quality, apply one clipped `ImageFiltered` blur with sigma `0.6`.
- For HD quality, return the video child unchanged.
- Do not add a `Stack`, colored overlay, opacity layer, or toolbar filter.

This reuses the Windows presentation behavior that was already accepted before
the true-resolution experiment.

## Android Presentation

- Keep Android `ImagePaint` as the existing `CustomPaint`; do not wrap it with
  `ImageFiltered`, `BackdropFilter`, or `KqRemoteQualityPresentation`.
- Add an optional `blurSigma` argument to `ImagePainter`, defaulting to zero.
- When `blurSigma` is positive, assign `ui.ImageFilter.blur` with sigma `0.6`
  to the `Paint` used by the existing `Canvas.drawImage` call.
- Pass sigma `0.6` only when the selected account tier is standard; pass zero
  for HD.
- Do not blur the cursor, side toolbar, dialogs, gestures, or input surfaces.

This avoids the Android black-screen path caused by filtering the entire
continuously painted widget subtree while still making the decoded image softer.

## Alternatives Rejected

1. Android `ImageFiltered` wrapper: previously produced a black video region.
2. Encoder-side downscaling: the latest installed build connected but never
   delivered the first 720p frame.
3. `FilterQuality.low` only: safe but too subtle to provide a visible product
   distinction on a phone screen.

## Verification

- A painter test renders a non-empty image with Android blur enabled and verifies
  that output pixels remain visible.
- Source integration tests verify Windows uses exactly one `ImageFiltered` for
  standard quality and Android has no widget-level image filter.
- Tests verify both stream qualities equal `150` and both tiers remain 60 FPS.
- Tests verify neither profile maps to `sessionChangeResolution`.
- Existing first-frame, gray-screen, toolbar, canvas, and texture regressions
  remain green.
- Rebuild Windows and Android native/package artifacts into stable filenames and
  remove timestamped duplicates.
- Device acceptance covers direct 720p, direct 1080p, switching both directions,
  repeated Windows toolbar expand/collapse, readable standard text, visibly
  sharper HD text, and no waiting, black, or gray screen.
