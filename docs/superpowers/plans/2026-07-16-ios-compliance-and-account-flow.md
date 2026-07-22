# iOS Compliance and Account Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the iOS client expose an in-app privacy policy, declare the data it collects, provide a real account-deletion client flow, and replace the current iOS payment placeholder with a StoreKit client flow that is safe when server configuration is absent.

**Architecture:** Keep legal text and policy URLs in a small, testable Dart policy module. Put account deletion and App Store purchase protocol code behind dedicated services so `account_page.dart` only owns navigation and user interaction. Both remote services must fail closed when their configured server endpoint is absent or rejects the request; no local membership unlock or local-only account deletion is allowed.

**Tech Stack:** Flutter/Dart, `in_app_purchase`, iOS `PrivacyInfo.xcprivacy`, App Store Connect, existing Kunqiong HTTP API.

---

### Task 1: Add a single-source privacy policy and internal viewer

**Files:**
- Create: `flutter/lib/mobile/privacy/kq_privacy_policy.dart`
- Create: `flutter/lib/mobile/pages/privacy_policy_page.dart`
- Modify: `flutter/lib/mobile/pages/account_page.dart`
- Test: `flutter/test/kq_ios_privacy_policy_test.dart`

- [ ] **Step 1: Write the failing policy and page-source tests**

```dart
test('privacy policy has a public URL configuration and complete in-app sections', () {
  expect(KqPrivacyPolicy.publicUrl, isNotEmpty);
  expect(KqPrivacyPolicy.sections, hasLength(greaterThanOrEqualTo(5)));
  expect(KqPrivacyPolicy.sections.map((item) => item.title), contains('Data we collect'));
});

test('personal center exposes the privacy policy route', () {
  final source = File('lib/mobile/pages/account_page.dart').readAsStringSync();
  expect(source, contains('PrivacyPolicyPage'));
});
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `flutter test test/kq_ios_privacy_policy_test.dart`

Expected: FAIL because the policy module and viewer do not exist.

- [ ] **Step 3: Implement the policy module and viewer**

```dart
class KqPrivacyPolicy {
  static const publicUrl = String.fromEnvironment(
    'KQ_PRIVACY_POLICY_URL',
    defaultValue: 'https://kunqiongai.com/privacy',
  );
  static const sections = <KqPrivacyPolicySection>[/* Chinese/English policy sections */];
}
```

Render every section in a `Scaffold` with `_KqDetailHeader`, a readable `ListView`, and an optional external-link action. Add a `Privacy policy` row in `_PersonalCenterPage`; it pushes the viewer without opening a browser.

- [ ] **Step 4: Run the focused test**

Run: `flutter test test/kq_ios_privacy_policy_test.dart`

Expected: PASS.

### Task 2: Declare app-collected privacy data accurately

**Files:**
- Modify: `flutter/ios/Runner/PrivacyInfo.xcprivacy`
- Modify: `flutter/ios/KQScreenBroadcast/PrivacyInfo.xcprivacy`
- Modify: `flutter/test/kq_ios_release_policy_test.dart`
- Test: `flutter/test/kq_ios_privacy_policy_test.dart`

- [ ] **Step 1: Add failing manifest assertions**

```dart
expect(manifest, contains('NSPrivacyCollectedDataTypePhoneNumber'));
expect(manifest, contains('NSPrivacyCollectedDataTypeUserID'));
expect(manifest, contains('NSPrivacyCollectedDataTypeOtherUserContent'));
expect(manifest, contains('NSPrivacyCollectedDataTypePurposeAppFunctionality'));
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `flutter test test/kq_ios_release_policy_test.dart test/kq_ios_privacy_policy_test.dart`

Expected: FAIL because the app manifest currently declares no collected data.

- [ ] **Step 3: Update only the app manifest for app-owned data**

Add a four-key dictionary for each of `PhoneNumber`, `UserID`, `OtherUserContent`, and `PurchaseHistory` when StoreKit support is added. Set `Linked` true, `Tracking` false, and the purpose to `AppFunctionality`. Preserve the existing UserDefaults reasons. Keep the broadcast extension manifest limited to its own App Group access because it does not independently upload account data.

- [ ] **Step 4: Run the focused test**

Run: `flutter test test/kq_ios_release_policy_test.dart test/kq_ios_privacy_policy_test.dart`

Expected: PASS.

### Task 3: Add a deletion API contract and a safe account-deletion UI

**Files:**
- Create: `flutter/lib/common/kq_account_deletion.dart`
- Modify: `flutter/lib/mobile/pages/account_page.dart`
- Modify: `flutter/lib/models/user_model.dart`
- Create: `docs/ios-account-deletion-api.md`
- Test: `flutter/test/kq_account_deletion_test.dart`

- [ ] **Step 1: Write failing service and UI contract tests**

```dart
test('account deletion refuses to run without an authenticated token', () async {
  await expectLater(api.requestDeletion(token: ''), throwsA(isA<KqAccountDeletionException>()));
});

test('personal center provides a destructive deletion action', () {
  final source = File('lib/mobile/pages/account_page.dart').readAsStringSync();
  expect(source, contains('Delete account'));
  expect(source, contains('KqAccountDeletionApi'));
});
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `flutter test test/kq_account_deletion_test.dart`

Expected: FAIL because no account-deletion service exists.

- [ ] **Step 3: Implement the client contract**

```dart
const _deleteUrl = String.fromEnvironment('KQ_ACCOUNT_DELETE_URL');

Future<KqAccountDeletionResult> requestDeletion({required String token}) async {
  if (token.trim().isEmpty) throw KqAccountDeletionException('Please log in first.');
  if (_deleteUrl.trim().isEmpty) throw KqAccountDeletionException('Account deletion is not configured on the server.');
  // POST JSON {"confirmation":"DELETE"}; accept only a 2xx success response.
}
```

Provide a destructive action in personal center. Require the user to type `DELETE`, explain that it removes the account and app data but does not cancel an Apple subscription, request the endpoint, then call `gFFI.userModel.logOut()` only after a successful server response. Document the request/response contract, authentication header, replay/idempotency expectation, and retention notice in `docs/ios-account-deletion-api.md`.

- [ ] **Step 4: Run the focused test**

Run: `flutter test test/kq_account_deletion_test.dart`

Expected: PASS.

### Task 4: Add a StoreKit client with server-side entitlement verification

**Files:**
- Modify: `flutter/pubspec.yaml`
- Create: `flutter/lib/mobile/kq_ios_in_app_purchase.dart`
- Modify: `flutter/lib/mobile/ios_membership_payment_policy.dart`
- Modify: `flutter/lib/mobile/pages/account_page.dart`
- Create: `docs/ios-in-app-purchase-api.md`
- Test: `flutter/test/kq_ios_in_app_purchase_test.dart`

- [ ] **Step 1: Write failing configuration and purchase-flow tests**

```dart
test('iOS purchase config maps every server membership package to one StoreKit product', () {
  expect(KqIosInAppPurchaseConfig.fromEnvironment().isConfigured, isTrue);
});

test('iOS policy directs App Store builds to StoreKit instead of an external URL', () {
  expect(KqIosMembershipPaymentPolicy.routeFor(isIOS: true),
      KqIosMembershipPaymentRoute.appleInAppPurchaseRequired);
});
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `flutter test test/kq_ios_in_app_purchase_test.dart`

Expected: FAIL because no StoreKit service/configuration exists.

- [ ] **Step 3: Add the package and configuration**

Add `in_app_purchase` using `flutter pub add in_app_purchase`. Parse `KQ_IOS_IAP_PRODUCTS` as JSON object `{ "server-package-id": "apple.product.id" }` and require `KQ_IOS_IAP_VERIFY_URL`. Do not hard-code product IDs, receipts, Apple credentials, or payment secrets.

- [ ] **Step 4: Implement purchase and restore handling**

```dart
final details = await InAppPurchase.instance.queryProductDetails(productIds);
await InAppPurchase.instance.buyNonConsumable(
  purchaseParam: PurchaseParam(productDetails: product),
);
```

Listen to the purchase stream, submit the StoreKit verification payload and mapped server package ID to `KQ_IOS_IAP_VERIFY_URL`, refresh membership only after server confirmation, and call `completePurchase` in a `finally` block. Add a visible `Restore purchases` action. When configuration is absent, show a Chinese user-facing configuration error and never launch Alipay/WeChat from an App Store iOS build.

- [ ] **Step 5: Run the focused test**

Run: `flutter test test/kq_ios_in_app_purchase_test.dart`

Expected: PASS.

### Task 5: Wire the new tests into the iOS readiness gate and align documentation

**Files:**
- Modify: `scripts/test-kq-ios-code-readiness.ps1`
- Modify: `docs/KQ_REMOTE_LINK_DEPLOYMENT_GUIDE.md`
- Modify: `docs/ios-external-integration-requirements.md`
- Test: `flutter/test/kq_ios_release_policy_test.dart`

- [ ] **Step 1: Add new test paths to the readiness script**

```powershell
'test/kq_ios_privacy_policy_test.dart',
'test/kq_account_deletion_test.dart',
'test/kq_ios_in_app_purchase_test.dart',
'test/kq_ios_release_policy_test.dart'
```

- [ ] **Step 2: Align iOS payment documentation**

State that external Alipay/WeChat is restricted to explicitly marked internal Ad Hoc builds, while App Store/TestFlight builds use StoreKit and server verification. State that privacy policy needs both App-internal access and a public App Store Connect URL.

- [ ] **Step 3: Run the complete code readiness gate**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-kq-ios-code-readiness.ps1`

Expected: all PowerShell, Flutter, and Rust checks pass.

### Task 6: Perform the release-only checks outside this repository

**Files:**
- Reference: `docs/ios-account-deletion-api.md`
- Reference: `docs/ios-in-app-purchase-api.md`
- Reference: `codemagic.yaml`

- [ ] **Step 1: Configure App Store Connect products**

Create one non-consumable or subscription product per member package, set matching IDs in `KQ_IOS_IAP_PRODUCTS`, and make the products available for review.

- [ ] **Step 2: Deploy the two backend endpoints**

Deploy authenticated account deletion and StoreKit verification endpoints matching the new API documents. Verify both using a test account before enabling them in a release build.

- [ ] **Step 3: Publish the exact privacy text at the configured URL**

Host the same policy text supplied in the in-app page at `KQ_PRIVACY_POLICY_URL`, then enter that public URL and the actual data-handling answers in App Store Connect.

- [ ] **Step 4: Run a macOS Archive and true-device test**

Archive the iOS app, inspect Xcode Privacy Report, test purchase/restore/deletion on an iPhone with a sandbox Apple ID, and upload the verified IPA to TestFlight.

## Self-review

- The plan covers the approved internal privacy page, mandatory privacy metadata, account deletion, StoreKit replacement, documentation, and regression gate.
- No client action grants membership or deletes an account without a successful server response.
- Product IDs, verification URL, public privacy URL, and server deletion URL are build configuration, not source secrets.
- The dirty working tree is intentionally not committed by this plan; commit selection requires a separate review of pre-existing changes.
