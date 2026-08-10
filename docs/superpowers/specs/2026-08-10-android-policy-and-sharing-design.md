# Android Policy And Screen Sharing Design

## Goal

Android builds must not display Apple, App Store, StoreKit, or Apple
subscription-management wording. Account deletion remains available on Android.
The Android Share screen must focus on the minimum steps required to share a
screen, leaving optional capabilities discoverable without prompting for all of
their permissions.

## Scope

The change covers the mobile account-deletion page, the in-app privacy-policy
content, the public privacy-policy endpoint, and the Android Share screen. It
does not change iOS StoreKit purchase behavior, account-deletion API behavior,
remote-session protocols, or Android permission implementations.

## Platform-Specific Policy Content

`KqPrivacyPolicy` will expose sections selected for the current platform rather
than one static list. Android receives a generic Membership and payments
section describing entitlement processing without naming a payment provider.
iOS receives the existing Apple In-App Purchase and subscription-cancellation
disclosure.

The account-deletion warning follows the same rule. Both platforms explain that
deleting an account clears applicable account data. Only iOS additionally
explains that account deletion does not cancel an Apple auto-renewing
subscription.

The public policy endpoint will select its membership disclosure from an
explicit `platform` query parameter. The app opens the public URL with either
`platform=android` or `platform=ios`. Missing or unrecognised values receive
the generic disclosure, preventing Apple wording from being exposed by default.

## Android Share Screen

The Android screen keeps one primary setup/action for starting screen sharing.
It combines the existing service-not-running and screen-capture readiness
states instead of presenting duplicate setup cards.

Remote input remains a separate, clearly optional action because it requires a
different system permission and changes the session capability. File transfer,
application audio, and clipboard sharing move below a collapsed More sharing
features control. Each optional feature requests only its own permission when
the user enables it. The bulk action that serially requests all five permission
types is removed.

Connection state stays visible in a compact status area. Existing settings that
disable or fix options continue to govern which controls are shown.

## Error Handling

If a user declines screen-capture or remote-input permission, the page remains
usable and identifies that capability as unavailable. Declining an optional
feature permission does not block screen sharing. The account-deletion request
and the privacy-policy URL retain their current fallback behavior.

## Verification

Tests will first assert that Android account-deletion and policy content omit
Apple terms while iOS retains its required disclosure. A server test will
exercise Android, iOS, and unrecognised public-policy platform values. A mobile
Share-page regression test will assert the essential-first hierarchy and the
absence of the bulk permission action. Targeted Flutter and server tests, a
source scan of Android-reachable mobile UI, formatting, and a release APK build
will provide final verification.
