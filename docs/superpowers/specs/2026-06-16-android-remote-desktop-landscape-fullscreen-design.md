# Android Remote Desktop Landscape Fullscreen Design

## Goal

When a phone controls a desktop computer, the remote page should default to landscape and fullscreen.

## Scope

- Applies to mobile controller remote sessions where the peer platform is Windows, macOS, or Linux.
- Does not force landscape when controlling an Android peer.
- Restores the app's normal system orientation and system overlays after leaving the remote page.

## Behavior

- On remote-page entry, keep the existing immersive fullscreen behavior.
- After peer information is available and the peer is a desktop platform, lock orientation to `landscapeLeft` and `landscapeRight`, then keep system overlays hidden.
- When the page is disposed, clear the orientation preference and restore system overlays.

## Verification

`scripts/test-kq-release.ps1` must assert that the mobile remote page has a desktop-peer helper, applies landscape orientations for desktop peers, does not apply the lock for Android peers, and restores orientation on dispose.
