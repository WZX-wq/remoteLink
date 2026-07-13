# Remote Quality Separation Design

## Goal

Make the product-facing 720p standard tier visibly different from the 1080p HD tier without changing the controlled computer's display resolution or the stable video rendering path.

## Design

- Keep both tiers on the same 60 FPS connection, codec, decode, RGBA/texture, and Flutter presentation pipeline.
- Set the 720p standard custom image quality to `25`, which maps to a `0.5` bitrate ratio and matches the built-in low-quality ratio.
- Keep the 1080p HD custom image quality at `150`, which maps to a `3.0` bitrate ratio.
- Do not add blur filters, overlays, alternate texture paths, or display-resolution changes.
- Keep the Windows toolbar overlay gray-screen fix unchanged.

At an actual 1920x1080 source size, the existing bitrate table yields approximately 1.0 Mbps for standard quality and 6.2 Mbps for HD before adaptive network reductions. The sixfold target difference should be visible in text edges and motion while retaining a usable standard tier.

## Verification

- Flutter policy test asserts `25` and `150`, equal 60 FPS, and no mapping to remote display resolution.
- Rust client test asserts the same tier values and ordering.
- Rebuild Windows and Android native libraries so packaged binaries contain the new constants.
- Verify the Windows installer payload DLL and Android APK native library match the newly built artifacts.
