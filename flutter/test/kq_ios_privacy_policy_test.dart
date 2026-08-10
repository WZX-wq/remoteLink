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
    final policyText = KqPrivacyPolicy.sections
        .expand((section) => <String>[
              ...section.paragraphsZh,
              ...section.paragraphsEn,
            ])
        .join('\n');
    expect(policyText, contains('应用声音'));
    expect(policyText, contains('application audio'));
  });

  test('membership policy and public URI select the current platform', () {
    final androidText = KqPrivacyPolicy.sectionsFor(isIOS: false)
        .expand((section) =>
            <String>[...section.paragraphsZh, ...section.paragraphsEn])
        .join('\n');
    final iosMembership = KqPrivacyPolicy.sectionsFor(isIOS: true)
        .singleWhere((section) => section.id == 'membership');

    expect(androidText, contains('适用的支付渠道'));
    expect(androidText, isNot(contains('Apple')));
    expect(iosMembership.paragraphsZh, <String>[
      'App Store 版本的会员购买和恢复购买由 Apple 的应用内购买完成。我们仅处理验证会员权益所需的交易信息。',
      '删除账号不会自动取消 Apple 订阅；如有自动续订订阅，请先在 Apple 订阅管理中取消。',
    ]);
    expect(iosMembership.paragraphsEn, <String>[
      'Membership purchase and purchase restoration in the App Store build are handled by Apple In-App Purchase. We process only the transaction information needed to verify membership entitlements.',
      'Deleting an account does not automatically cancel an Apple subscription. Cancel any auto-renewing subscription in Apple subscription management first.',
    ]);
    expect(
      KqPrivacyPolicy.publicUriFor(isIOS: false)?.queryParameters['platform'],
      'android',
    );
    expect(
      KqPrivacyPolicy.publicUriFor(isIOS: true)?.queryParameters['platform'],
      'ios',
    );
    final androidUriWithRepeatedQuery = KqPrivacyPolicy.publicUriFor(
      isIOS: false,
      baseUrl: 'https://example.test/privacy?tag=one&tag=two&platform=old',
    );
    expect(
      androidUriWithRepeatedQuery?.queryParametersAll['tag'],
      <String>['one', 'two'],
    );
    expect(
      androidUriWithRepeatedQuery?.queryParametersAll['platform'],
      <String>['android'],
    );
    expect(
      KqPrivacyPolicy.publicUriFor(
        isIOS: false,
        baseUrl: 'https://[invalid',
      ),
      isNull,
    );
    expect(
      KqPrivacyPolicy.publicUriFor(
        isIOS: false,
        baseUrl: '/privacy',
      ),
      isNull,
    );
  });

  test('public privacy policy targets the Remote Link API', () {
    expect(
      KqPrivacyPolicy.publicUrl,
      contains('remotelink.kunqiongai.com/kq-api/privacy'),
    );
  });

  test('personal center exposes the internal privacy policy page', () {
    final page = File('lib/mobile/pages/account_page.dart').readAsStringSync();

    expect(page, contains('PrivacyPolicyPage'));
    expect(page, contains('Privacy policy'));
  });

  test('privacy page skips launch when the public policy URI is invalid', () {
    final page =
        File('lib/mobile/pages/privacy_policy_page.dart').readAsStringSync();

    expect(page, contains('if (uri == null) return;'));
  });

  test('Runner privacy manifest declares app-owned collected data', () {
    final manifest =
        File('ios/Runner/PrivacyInfo.xcprivacy').readAsStringSync();
    final extensionManifest =
        File('ios/KQScreenBroadcast/PrivacyInfo.xcprivacy').readAsStringSync();

    expect(manifest, contains('NSPrivacyCollectedDataTypePhoneNumber'));
    expect(manifest, contains('NSPrivacyCollectedDataTypeUserID'));
    expect(manifest, contains('NSPrivacyCollectedDataTypeOtherUserContent'));
    expect(manifest, contains('NSPrivacyCollectedDataTypeAudioData'));
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
    expect(
      extensionManifest,
      contains('NSPrivacyCollectedDataTypeAudioData'),
    );
  });

  test('iOS membership purchase footer uses the iOS public policy URI', () {
    final source = File(
      'lib/mobile/pages/ios_membership_purchase_page.dart',
    ).readAsStringSync();

    expect(
      source,
      contains('KqPrivacyPolicy.publicUriFor(isIOS: true)'),
    );
    expect(
      source,
      isNot(contains('_openLegalUrl(KqPrivacyPolicy.publicUrl)')),
    );
  });
}
