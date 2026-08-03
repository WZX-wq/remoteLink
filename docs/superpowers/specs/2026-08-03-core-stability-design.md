# Core Stability Fixes Design

**Goal:** Make the confirmed iOS connection, voice-call, membership, quality, and desktop-input behaviors reliable for release validation.

## Scope

1. iOS incoming voice-call accept/reject and stop actions use the native App Group request/response files. Desktop and non-iOS CM IPC behavior remains unchanged.
2. A missing first video frame is a recoverable state. The KQ desktop client keeps the session open and presents retry/waiting guidance instead of closing the connection at 15 seconds.
3. KQ quality selection is session-scoped. The receiver sends the selected custom quality/FPS through the existing `OptionMessage`; the controlled endpoint applies the encoder dimensions in memory for that session and does not persist or change its display configuration. Basic uses 480p/30 FPS and membership uses 1080p/60 FPS.
4. Desktop verification-code input preserves exact user-entered case because the password hash is case-sensitive.
5. StoreKit cards describe lifetime products as one-time permanent purchases and subscription products as auto-renewing plans.
6. Membership refresh runs when the app returns to foreground and on a bounded periodic schedule while logged in. Existing membership data is retained if the refresh service is temporarily unavailable.
7. The Windows-only "Block user input" action is removed from the shared toolbar menu. Its lower-level compatibility code is retained only where required for protocol compatibility and is not exposed by this UI.

## Data Flow

- Flutter account/session state chooses a KQ tier and sends `custom_image_quality` plus `custom_fps` to the active session.
- Rust decodes the per-connection option and updates `VideoQoS` for the session. The encoder uses the effective KQ height limit at runtime. No remote `Config` write or display-resolution change is performed.
- iOS voice buttons call `respond_to_ios_voice_call` with the pending request ID and `end_ios_voice_call`; native code writes the App Group response and closes the active audio state.

## Error Handling

- Invalid/stale iOS voice request IDs return `false` and leave no active call.
- First-frame waiting is displayed as informational. The user can cancel or retry; only explicit connection errors or the existing longer connection-start failure path closes the session.
- Membership refresh failures update diagnostic state but do not downgrade an already active local membership unless the server explicitly reports inactive/expired status.

## Verification

- Add source-contract tests for the iOS voice bridge, nonfatal first-frame timeout, no blur fallback, exact-case desktop password input, StoreKit product copy, foreground membership refresh, and removed toolbar action.
- Run focused Flutter tests, Rust formatting/check/tests for changed Rust modules, `git diff --check`, and inspect the final diff/status before any commit or build.
