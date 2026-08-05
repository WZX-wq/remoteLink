import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _section(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  final endIndex = source.indexOf(end, startIndex + start.length);
  expect(startIndex, greaterThanOrEqualTo(0), reason: 'Missing start: $start');
  expect(endIndex, greaterThan(startIndex), reason: 'Missing end: $end');
  return source.substring(startIndex, endIndex);
}

void main() {
  test('mobile language picker avoids the status bar and uses compact rows',
      () {
    final settings =
        File('lib/mobile/pages/settings_page.dart').readAsStringSync();
    final dialog = _section(
      settings,
      'void showLanguageSettings(OverlayDialogManager dialogManager) async',
      'String _kqNormalizeMobileLang(String value)',
    );

    expect(dialog, contains('SafeArea('));
    expect(dialog, contains('MediaQuery.sizeOf(context).height'));
    expect(dialog, contains('ListView.builder('));
    expect(dialog, contains('_KqLanguageOptionTile('));
    expect(dialog, isNot(contains('getRadio(Text(kqLanguageDisplayName')));
  });

  test('mobile language picker splits the Chinese hint out of the main label',
      () {
    final common = File('lib/common.dart').readAsStringSync();
    final settings =
        File('lib/mobile/pages/settings_page.dart').readAsStringSync();

    expect(common, contains('kqLanguageDisplayParts'));
    expect(common, contains('String? subtitle'));
    expect(settings, contains('kqLanguageDisplayParts('));
  });

  test('critical mobile flows route visible labels through language helpers',
      () {
    final connection =
        File('lib/mobile/pages/connection_page.dart').readAsStringSync();
    final membership = File('lib/mobile/pages/ios_membership_purchase_page.dart')
        .readAsStringSync();
    final deletion =
        File('lib/mobile/pages/account_deletion_page.dart').readAsStringSync();
    final server = File('lib/mobile/pages/server_page.dart').readAsStringSync();
    final settings =
        File('lib/mobile/pages/settings_page.dart').readAsStringSync();
    final privacy =
        File('lib/mobile/pages/privacy_policy_page.dart').readAsStringSync();

    expect(connection, contains("translate('Connect')"));
    expect(membership, contains('String _text(String zh, String en)'));
    expect(deletion, contains('String _text(String zh, String en)'));
    expect(server, contains("kqLocaleText(zhCn: '结束语音通话'"));
    expect(settings, contains("title: _settingsText('Keep screen on')"));
    expect(privacy, contains("tooltip: translate('Open public policy')"));
  });

  test('account-route pages translate non-Chinese copy through the language table',
      () {
    final deletion =
        File('lib/mobile/pages/account_deletion_page.dart').readAsStringSync();
    final policy =
        File('lib/mobile/privacy/kq_privacy_policy.dart').readAsStringSync();

    expect(deletion, contains('kqUiPrefersChinese() ? zh : translate(en)'));
    expect(policy, contains('titleZh : translate(titleEn)'));
    expect(policy, contains('paragraphsEn.map(translate).toList()'));
  });
}
