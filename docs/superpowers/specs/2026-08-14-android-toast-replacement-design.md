# Android Transient Notice Replacement Design

## Goal

Prevent transient notices from overlapping when Android users trigger actions repeatedly, including rapid screen-recording start and stop actions.

## Scope

- Apply replacement behavior only when `isAndroid` is true.
- Keep the existing notice appearance, text, position, and timeout values.
- Keep iOS, desktop, and web notice behavior unchanged.
- Keep the existing recording transition and publishing guards unchanged.

## Design

Add a small Android notice coordinator that owns one active dismiss callback and one expiry timer. When a new Android notice is shown, the coordinator cancels the previous timer, dismisses the previous notice, and starts the new notice timer. A stale timer must never dismiss a newer notice.

`showToast` will continue creating the existing overlay. On Android it will register the overlay with the coordinator; other platforms will retain the current independent-overlay behavior.

## Verification

- A focused test proves that a second notice dismisses the first.
- A focused test proves that the cancelled first timer cannot dismiss the second notice.
- Existing Android recording, dialog, startup, and UI tests remain passing.
- Build and inspect a release APK after tests pass.
