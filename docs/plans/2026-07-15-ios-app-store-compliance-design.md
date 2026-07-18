# iOS App Store Compliance Adaptation Design

## Decision

The iOS build will use only public App Store APIs. Android-only capabilities
will not be emulated with private APIs, silent audio, accessibility injection,
or background-process workarounds.

## Capability Model

The iOS app has two supported roles. As a controller, it can connect to a
desktop, display remote video, send touch and keyboard input, transfer files,
synchronize text clipboard content while the app is active, and make voice
calls. As an assisted device, it can expose a ReplayKit view-only broadcast.
It must never claim that a remote user can inject touches or control other iOS
apps. Android overlay windows, start-on-boot, accessibility control, and an
unrestricted persistent background service are unavailable on iOS and their
settings must be omitted.

## ReplayKit Boundary

`KQScreenBroadcast` is a Broadcast Upload Extension and is the only process
allowed to keep receiving screen frames after the containing app leaves the
foreground. The extension runs the existing Rust peer service in its own
process, feeds ReplayKit BGRA frames into the shared video pipeline, and
normalizes application audio to 48 kHz stereo PCM before the existing Opus
audio service sends it. App Group storage carries status and diagnostics only;
the media path does not depend on the Runner process polling files. The shared
session remains view-only because iOS does not allow remote input injection
into other apps. Final availability still requires macOS compilation and
direct/relay verification on physical iOS devices.

## Error Handling And Verification

Unsupported capabilities are represented by a pure platform capability policy
so UI code cannot accidentally re-enable Android controls on iOS. Clipboard
sync is foreground-only and ignores empty or unchanged values. File transfer
continues through the iOS sandbox and system document picker. ReplayKit status
distinguishes waiting, ready, capturing, paused, failed, and stopped states and
reports application-audio availability separately from remote-viewer presence.
Automated tests cover policy decisions, native integration, PCM queueing, and
the existing video/audio service contracts; Xcode compilation and physical
device acceptance remain explicit external gates.
