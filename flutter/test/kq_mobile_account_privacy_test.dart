import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _readAccountPage() =>
    File('lib/mobile/pages/account_page.dart').readAsStringSync();

void main() {
  test('mobile account surfaces mask personal account identifiers', () {
    final source = _readAccountPage();

    expect(source, contains('String _kqMaskAccountIdentifier(String value)'));
    expect(source, contains('String _kqMaskAccountPhoneNumber(String value)'));
    expect(source, contains('_kqPrivacyDisplayName(user)'));
    expect(source, contains('_kqPrivacyAccountLabel(user)'));
    expect(source, contains('_kqMaskAccountPhoneNumber('));
    expect(source, contains('_localUserPhoneNumber()'));
    expect(
      source,
      isNot(contains('title: isLogin ? user.displayNameOrUserName')),
    );
    expect(source, isNot(contains('subtitle: user.accountLabelWithHandle')));
    expect(source, isNot(contains('value: user.userName.value.trim()')));
    expect(source, isNot(contains('value: _localUserPhoneNumber()')));
  });

  test('membership banner avoids showing exact expiry date on public surface',
      () {
    final source = _readAccountPage();
    final bannerStart = source.indexOf('class _MembershipBanner');
    final bannerEnd = source.indexOf('String _priceLabel', bannerStart);
    expect(bannerStart, greaterThanOrEqualTo(0));
    expect(bannerEnd, greaterThan(bannerStart));
    final banner = source.substring(bannerStart, bannerEnd);

    expect(banner, contains("_mineText('Membership benefits active')"));
    expect(banner, isNot(contains('_formatMembershipExpireAt(expireAt)')));
    expect(banner, isNot(contains("'Membership valid until'")));
  });
}
