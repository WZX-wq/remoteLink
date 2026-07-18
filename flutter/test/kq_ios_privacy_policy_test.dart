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

  test('public privacy policy is hosted by the Remote Link API', () {
    final server = File('../server/src/index.js').readAsStringSync();

    expect(
      KqPrivacyPolicy.publicUrl,
      contains('remotelink.kunqiongai.com/kq-api/privacy'),
    );
    expect(server, contains('function privacyPolicyPage()'));
    expect(server, contains("app.get(['/privacy', '/api/privacy']"));
    expect(server, contains('鲲穹远程桌面隐私政策'));
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
