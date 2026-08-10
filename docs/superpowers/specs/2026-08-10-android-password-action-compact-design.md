# Android Password Action Compact Layout

## Scope

Adjust only the Android presentation of the mobile device password tile. Keep
the password type, password value, and four existing actions unchanged.

## Layout

- Render each Android action button at 32 by 32 logical pixels.
- Use a 4 pixel gap between Android action buttons.
- Keep a minimum 108 pixel Android text region for the password type and code.
- Scale the password type label down when necessary instead of ellipsizing it,
  so the Chinese one-time-password label remains complete on narrow screens.

## Platform Isolation

The compact dimensions and non-ellipsizing label behavior are passed as an
Android-only layout mode. iOS retains the existing 40 pixel buttons, 6 pixel
gaps, and current label behavior.

## Verification

Add source-level regression assertions for the Android-only mode, then run the
focused test, the full Flutter test suite, static analysis, diff checks, and a
signed release APK build. Verify the generated APK independently.
