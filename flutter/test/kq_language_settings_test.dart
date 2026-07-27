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
}
