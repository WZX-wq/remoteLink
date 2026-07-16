import 'dart:io';

import 'package:flutter_hbb/mobile/privacy/kq_privacy_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('privacy policy has a public URL configuration and complete sections',
      () {
    expect(KqPrivacyPolicy.publicUrl, startsWith('https://'));
    expect(KqPrivacyPolicy.sections, hasLength(greaterThanOrEqualTo(5)));
    expect(
      KqPrivacyPolicy.sections.map((section) => section.id),
      containsAll(<String>[
        'data-collection',
        'data-use',
        'data-sharing',
        'retention-deletion',
        'contact',
      ]),
    );
  });

  test('personal center exposes the internal privacy policy page', () {
    final page = File('lib/mobile/pages/account_page.dart').readAsStringSync();

    expect(page, contains('PrivacyPolicyPage'));
    expect(page, contains('Privacy policy'));
  });

  test('Runner privacy manifest declares app-owned collected data', () {
    final manifest =
        File('ios/Runner/PrivacyInfo.xcprivacy').readAsStringSync();
    final extensionManifest =
        File('ios/KQScreenBroadcast/PrivacyInfo.xcprivacy').readAsStringSync();

    expect(manifest, contains('NSPrivacyCollectedDataTypePhoneNumber'));
    expect(manifest, contains('NSPrivacyCollectedDataTypeUserID'));
    expect(manifest, contains('NSPrivacyCollectedDataTypeOtherUserContent'));
    expect(manifest, contains('NSPrivacyCollectedDataTypePurchaseHistory'));
    expect(
      manifest,
      contains('NSPrivacyCollectedDataTypePurposeAppFunctionality'),
    );
    expect(
      extensionManifest,
      isNot(contains('NSPrivacyCollectedDataTypePhoneNumber')),
    );
    expect(
      extensionManifest,
      contains('NSPrivacyCollectedDataTypeOtherUserContent'),
    );
  });
}
