# iOS ReplayKit Remote Viewing Design

## Goal

Allow another remoteLink client to watch an iPhone or iPad screen while the
user explicitly runs the ReplayKit broadcast extension. The iOS device remains
view-only: remote keyboard, pointer, touch injection, clipboard hosting, file
hosting, and unattended background control are not exposed.

## Process Boundary

ReplayKit delivers screen frames to `KQScreenBroadcast`, not to the containing
Runner process. Runner can be suspended after the broadcast starts, so the
extension owns the complete sending path:

1. Runner stores remoteLink configuration in the shared App Group directory.
2. `SampleHandler` locks each ReplayKit `CVPixelBuffer` and submits its BGRA
   bytes through a small C ABI.
3. Rust copies the newest frame into a bounded single-frame mailbox. Replacing
   an unread frame is intentional so slow networks increase frame drops rather
   than extension memory usage or latency.
4. The iOS `scrap::Capturer` reads the mailbox and feeds the existing VP8/VP9
   encoder, video service, rendezvous registration, relay, and client decoder.
5. The extension publishes capture, transport, frame, peer, and error state in
   App Group defaults so Runner can show user-readable status.

## Shared Configuration

Runner asks the native iOS layer for the App Group container before Rust
initialization and uses that directory as `Config::APP_DIR`. On first launch
after this change, native code copies the previous Documents configuration to
the App Group when the destination is empty. Both processes therefore use the
same device ID, rendezvous servers, key pair, temporary password state, and
permanent password without inventing a second identity.

## Lifecycle

The extension waits for the first valid video frame before starting the Rust
host. This guarantees a non-zero display size before encoder creation. Pause
stops accepting frames but keeps transport state explicit. Resume accepts new
frames and requests a video refresh. Finish clears the mailbox and asks the
rendezvous mediator to stop the mobile service.

The C ABI is idempotent: repeated start, pause, resume, and stop calls do not
start duplicate host threads. Invalid dimensions, stride, null pointers, or
oversized frames are rejected and surfaced as a stable error code.

## Failure Handling

The extension never reports remote viewing as available merely because local
capture works. Status progresses through `starting`, `registering`, `ready`,
`streaming`, `paused`, `stopped`, or `failed`. Runner maps internal details to
plain Chinese text while retaining a diagnostic error code for support logs.

## Verification

Windows can verify the frame mailbox, C ABI contract, source guards, project
linkage, Flutter status model, and the `aarch64-apple-ios` Rust build. Final
acceptance still requires Xcode and two physical devices: one iPhone/iPad
broadcasting and one Android/Windows/iOS client viewing through direct and
relay connections.
