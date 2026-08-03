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

  test('mobile account header shows the full username without ellipsis', () {
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
    expect(
      home,
      contains(
          'title: isLogin ? user.userName.value.trim() : translate(\'Login\')'),
    );
    expect(
        home, isNot(contains('title: isLogin ? _kqPrivacyAccountLabel(user)')));
    expect(home, contains('subtitle: isLogin'));
    expect(home, contains('? null'));
    expect(header, contains('final String? subtitle;'));
    expect(
        header, contains('if (subtitle != null && subtitle!.isNotEmpty) ...['));

    final titleStart = header.indexOf('Text(\n                      title,');
    final titleEnd = header.indexOf('const SizedBox(height: 6),', titleStart);
    expect(titleStart, greaterThanOrEqualTo(0));
    expect(titleEnd, greaterThan(titleStart));
    final title = header.substring(titleStart, titleEnd);
    expect(title, contains('maxLines: 2'));
    expect(title, contains('overflow: TextOverflow.visible'));
    expect(title, isNot(contains('TextOverflow.ellipsis')));
  });

  test('contact us opens the customer service page', () {
    final source = _readAccountPage();

    expect(source, contains(
        "const _kqContactUsUrl = 'https://www.kunqiongai.com/custom/';"));
    expect(source, contains('launchUrl(Uri.parse(_kqContactUsUrl))'));
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

  test('account page refreshes server membership while it is visible', () {
    final source = _readAccountPage();
    final stateStart = source.indexOf('class _AccountPageState');
    final stateEnd =
        source.indexOf('  Future<void> _saveRemotePerformance', stateStart);
    expect(stateStart, greaterThanOrEqualTo(0));
    expect(stateEnd, greaterThan(stateStart));
    final state = source.substring(stateStart, stateEnd);

    expect(state, contains('with WidgetsBindingObserver'));
    expect(state, contains('WidgetsBinding.instance.addObserver(this)'));
    expect(state, contains('WidgetsBinding.instance.removeObserver(this)'));
    expect(state, contains('Timer.periodic(const Duration(seconds: 30)'));
    expect(state, contains('didChangeAppLifecycleState'));
    expect(state, contains('AppLifecycleState.resumed'));
    expect(state, contains('_refreshMemberEntitlementFromServer'));
    expect(state, contains('await user.refreshMembership('));
    expect(state, contains('showError: false, keepExistingOnFailure: true'));
  });
}
