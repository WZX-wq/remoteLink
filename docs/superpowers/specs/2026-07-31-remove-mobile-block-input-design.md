# Remove Mobile Block User Input

## Goal

Remove the "Block user input" action from the mobile remote-session More menu so users cannot invoke an unreliable Windows-only operation from iOS or Android.

## Scope

- Remove the mobile menu item and its callback from the shared Flutter toolbar.
- Keep the Rust protocol, Windows implementation, desktop UI, translations, and compatibility handling unchanged.
- Keep the surrounding More menu actions and layout unchanged.

## Verification

- Add a source contract test proving the mobile More menu no longer contains the block-input action.
- Run the focused Flutter toolbar/privacy tests.
- Run static checks, build a new incremental iOS release IPA, verify its bundle version, and upload it to TestFlight.

## Non-Goals

- Removing block-input support from desktop clients or the Windows service.
- Changing remote-control permissions or protocol messages.
- Refactoring unrelated toolbar actions.
