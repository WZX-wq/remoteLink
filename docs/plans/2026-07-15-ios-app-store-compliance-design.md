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
foreground. The extension therefore needs a real upload transport and cannot
depend on the Runner process polling App Group files. The current repository
contains no server endpoint or protocol that accepts ReplayKit frames and maps
them to an existing remoteLink device session. This change will define and test
the extension-side transport contract, status/error reporting, and view-only
capability metadata. Enabling real remote viewing still requires the matching
server transport to be supplied and then verified on macOS and physical iOS
devices.

## Error Handling And Verification

Unsupported capabilities are represented by a pure platform capability policy
so UI code cannot accidentally re-enable Android controls on iOS. Clipboard
sync is foreground-only and ignores empty or unchanged values. File transfer
continues through the iOS sandbox and system document picker. ReplayKit status
distinguishes capture-only, upload-ready, uploading, failed, and stopped states
using user-readable copy. Automated tests cover policy decisions and static
native integration; Xcode compilation, upload transport integration, and
device acceptance remain explicit external gates.
