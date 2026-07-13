# Remove Remote Toolbar Pin Control

## Goal

Remove the redundant remote-toolbar pin control and its persisted state so the toolbar has one predictable visibility model.

## Behavior

- The expanded remote toolbar no longer renders the Pin Toolbar / Unpin Toolbar button.
- The toolbar keeps the existing manual expand/collapse `V` control.
- When expanded and the pointer is over the remote image, the toolbar automatically collapses after five seconds.
- Previously persisted `pin` values are ignored, so an old pinned setting cannot disable auto-collapse after upgrading.

## Implementation Scope

- Remove the pin observable, persistence methods, and local-option parsing from `ToolbarState`.
- Remove `_PinMenu` and stop adding it to the toolbar item list.
- Make the auto-hide condition independent of pin state.
- Do not change the remote video renderer, toolbar overlay structure, or Android UI.

## Verification

- Add a regression test that confirms the toolbar source contains no pin menu or pin persistence path.
- Add a policy-level test confirming auto-hide remains eligible while expanded, over the image, and not dragging.
- Run the existing remote-video regression test suite and build the Windows installer under the stable filename.
