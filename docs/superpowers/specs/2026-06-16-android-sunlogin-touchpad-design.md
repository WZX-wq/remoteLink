# Android Sunlogin Touchpad Design

## Goal

Android controlling a desktop peer should use Sunlogin-style touchpad semantics in touch mode.

## Scope

- Applies to Android/iOS mobile controller touch mode when the peer is not Android.
- Does not change controlling an Android peer.
- Does not change desktop pointer input, relative mouse mode, rendezvous, or audio behavior.

## Mapping

- One-finger slide moves the remote cursor only.
- One-finger tap sends left click.
- One-finger double tap sends double left click.
- Long press sends right click.
- Double-tap and hold drag sends left-button drag.
- Existing pinch/canvas gestures remain unchanged unless they conflict with the above.

## Verification

`scripts/test-kq-release.ps1` must assert that touch-mode one-finger pan no longer sends implicit left down/up for desktop peers, and that hold-drag remains the explicit left-drag path.
