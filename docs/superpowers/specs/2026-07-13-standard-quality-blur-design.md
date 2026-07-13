# Standard Quality Blur Design

## Goal

Make the 720p standard tier visibly softer than 1080p HD without introducing platform rendering failures.

## Design

- Add a shared `KqRemoteQualityPresentation` widget that receives the active custom stream quality and the video child.
- On Windows, apply `ClipRect` and a single `ImageFiltered` Gaussian blur with sigma `0.6` only when the stream quality exactly equals the standard value `25`.
- Return the child unchanged for the HD value `150` and for unknown values.
- Keep Android `ImagePaint` completely outside `ImageFiltered`; Android standard quality is distinguished only by the existing quality value `25` because filtering its continuously painted surface produces a black video region on affected devices.
- On Windows, wrap only the desktop RawImage/Texture subtree. Cursor, mouse listener, toolbar, dialogs, and connection state remain outside the filter.
- Do not use `Stack`, `ColoredBox`, `BackdropFilter`, opacity overlays, or remote display resolution changes.
- Keep the existing `25/150` compression settings and 60 FPS behavior.

## Verification

- Widget tests prove standard quality creates exactly one `ImageFiltered`, HD creates none, sigma is `0.6`, and the presentation component contains no `Stack`, `ColoredBox`, or `BackdropFilter`.
- Source integration tests prove desktop uses the shared component and Android does not use `ImageFiltered` or `KqRemoteQualityPresentation` in `ImagePaint`.
- Existing gray-screen, first-frame, rendering, quality, and no-resolution-mapping tests continue to pass.
- Android Flutter artifacts are rebuilt into the stable APK name, and timestamped duplicate APKs are removed.
