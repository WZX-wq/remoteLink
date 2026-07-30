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

  test('mobile account header shows only the masked username', () {
    final source = _readAccountPage();
    final homeStart = source.indexOf('return ListView(');
    final homeEnd = source.indexOf('class _MineToolbar', homeStart);
    final headerStart = source.indexOf('class _ProfileHeader');
    final headerEnd = source.indexOf('class _MembershipBanner', headerStart);
    expect(homeStart, greaterThanOrEqualTo(0));
    expect(homeEnd, greaterThan(homeStart));
    expect(headerStart, greaterThanOrEqualTo(0));
    expect(headerEnd, greaterThan(headerStart));

    final home = source.substring(homeStart, homeEnd);
    final header = source.substring(headerStart, headerEnd);
    expect(home, contains('title: isLogin ? _kqPrivacyAccountLabel(user)'));
    expect(home, isNot(contains('_kqPrivacyDisplayName(user)')));
    expect(home, contains('subtitle: isLogin'));
    expect(home, contains('? null'));
    expect(header, contains('final String? subtitle;'));
    expect(
        header, contains('if (subtitle != null && subtitle!.isNotEmpty) ...['));
  });

  test('membership banner shows the current account expiry without raw data',
      () {
    final source = _readAccountPage();
    final bannerStart = source.indexOf('class _MembershipBanner');
    final bannerEnd = source.indexOf('String _priceLabel', bannerStart);
    expect(bannerStart, greaterThanOrEqualTo(0));
    expect(bannerEnd, greaterThan(bannerStart));
    final banner = source.substring(bannerStart, bannerEnd);

    expect(banner, isNot(contains("_mineText('Membership benefits active')")));
    expect(source, contains('expireAt: user.memberExpireAt.value'));
    expect(banner, contains('_membershipExpiryLabel(expireAt)'));
    expect(source, contains('String? _membershipExpiryLabel(String value)'));
    expect(source, contains("_mineText('Membership valid until')"));
    expect(source, contains("_mineText('Unlimited')"));
  });
}
