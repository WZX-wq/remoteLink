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
  test('permanent password edit dialog locks iOS mobile UI to portrait', () {
    final page = File('lib/mobile/pages/server_page.dart').readAsStringSync();
    final dialog = _section(
      page,
      'void _showMobileKqPasswordDialog(ServerModel model) {',
      'class _DeviceSecretTile',
    );

    expect(
      page,
      contains('Future<void> _setMobilePasswordDialogPortraitOrientation'),
    );
    expect(page, contains('DeviceOrientation.portraitUp'));
    expect(
      dialog,
      contains('final lockPortrait = isIOS && isPermanent;'),
    );
    expect(
      dialog,
      contains(
          'await _setMobilePasswordDialogPortraitOrientation(locked: true);'),
    );
    expect(dialog, contains('finally'));
    expect(
      dialog,
      contains(
          'await _setMobilePasswordDialogPortraitOrientation(locked: false);'),
    );
  });

  test('permanent password edit dialog keeps action buttons horizontal', () {
    final page = File('lib/mobile/pages/server_page.dart').readAsStringSync();
    final dialog = _section(
      page,
      'void _showMobileKqPasswordDialog(ServerModel model) {',
      'class _DeviceSecretTile',
    );

    expect(dialog, contains('_MobileKqPasswordDialogActions('));

    final actions = _section(
      page,
      'class _MobileKqPasswordDialogActions',
      'class _DeviceSecretTile',
    );
    expect(actions, contains('FittedBox('));
    expect(actions, contains('Row('));
    expect(actions, contains('mainAxisSize: MainAxisSize.min'));
  });

  test('password edit dialog keeps only close as a secondary header action',
      () {
    final page = File('lib/mobile/pages/server_page.dart').readAsStringSync();
    final dialog = _section(
      page,
      'void _showMobileKqPasswordDialog(ServerModel model) {',
      'class _DeviceSecretTile',
    );
    final header = _section(
      page,
      'class _MobileKqPasswordDialogHeader',
      'class _MobileKqPasswordDialogActions',
    );
    final actions = _section(
      page,
      'class _MobileKqPasswordDialogActions',
      'class _DeviceSecretTile',
    );

    expect(dialog, contains('_MobileKqPasswordDialogHeader('));
    expect(header, contains('IconButton('));
    expect(header, contains('BoxConstraints.tightFor(width: 36, height: 36)'));
    expect(dialog, isNot(contains('removePermanentPassword')));
    expect(header, isNot(contains('Icons.delete_outline_rounded')));
    expect(header, isNot(contains('PopupMenuButton')));
    expect(actions, contains('"OK"'));
    expect(actions, isNot(contains('dialogButton("Cancel"')));
    expect(actions, isNot(contains("dialogButton('随机验证码'")));
    expect(actions, isNot(contains('dialogButton(\n              "Remove"')));
  });

  test('mobile password edit dialog removes random code header action', () {
    final page = File('lib/mobile/pages/server_page.dart').readAsStringSync();
    final dialog = _section(
      page,
      'void _showMobileKqPasswordDialog(ServerModel model) {',
      'class _DeviceSecretTile',
    );
    final header = _section(
      page,
      'class _MobileKqPasswordDialogHeader',
      'class _MobileKqPasswordDialogActions',
    );

    expect(dialog, isNot(contains('canRandomGenerate')));
    expect(dialog, isNot(contains('fillRandomPassword')));
    expect(header, isNot(contains('onGeneratePassword')));
    expect(header, isNot(contains('Icons.casino_outlined')));
    expect(header, isNot(contains('随机验证码')));
  });

  test('mobile password edit dialog limits manual verification code to six',
      () {
    final page = File('lib/mobile/pages/server_page.dart').readAsStringSync();
    final dialog = _section(
      page,
      'void _showMobileKqPasswordDialog(ServerModel model) {',
      'class _DeviceSecretTile',
    );

    expect(page, contains('const _kqMobileManualVerificationCodeLength = 6;'));
    expect(
      dialog,
      contains('final maxLength = _kqMobileManualVerificationCodeLength;'),
    );
    expect(dialog, contains('LengthLimitingTextInputFormatter(maxLength)'));
    expect(dialog, isNot(contains('bind.mainMaxEncryptLen()')));
  });
}
