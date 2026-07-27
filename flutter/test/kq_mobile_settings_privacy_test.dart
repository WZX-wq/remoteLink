import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

String _section(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  final endIndex = source.indexOf(end, startIndex + start.length);
  expect(startIndex, greaterThanOrEqualTo(0), reason: 'Missing $start');
  expect(endIndex, greaterThan(startIndex), reason: 'Missing $end');
  return source.substring(startIndex, endIndex);
}

void main() {
  test('mobile settings omit advanced network configuration surfaces', () {
    final source = _read('lib/mobile/pages/settings_page.dart');
    final account = _read('lib/mobile/pages/account_page.dart');

    expect(source, isNot(contains('kqMobileSettingsGroupConnectionNetwork')));
    expect(source, isNot(contains("showServerSettings(gFFI.dialogManager")));
    expect(source, isNot(contains('changeSocks5Proxy();')));
    expect(source, isNot(contains("Text(_settingsText('Use WebSocket'))")));
    expect(source, isNot(contains("Text(_settingsText('ID/Relay Server'))")));
    expect(
        source, isNot(contains("Text(_settingsText('Socks5/Http(s) Proxy'))")));
    expect(
        source, isNot(contains("Text(_settingsText(\"Direct IP Access\"))")));
    expect(source, isNot(contains("Text(_settingsText('Adaptive bitrate'))")));
    expect(account, isNot(contains('kqMobileSettingsGroupConnectionNetwork')));
    expect(account, isNot(contains("'Mobile device management':")));
  });

  test('mobile server settings protect existing server values by default', () {
    final source = _read('lib/mobile/widgets/dialog.dart');
    final entryPoint = _section(
      source,
      'void showServerSettings(',
      'String _managedServerSummary()',
    );
    final summaryGuard = _section(
      source,
      'bool _serverSettingsUsesManagedSummary',
      'ServerConfig _editableServerConfig',
    );
    final dialog = _section(
      source,
      'void showServerSettingsWithValue',
      'void setPrivacyModeDialog',
    );

    expect(entryPoint, contains('protectExistingValues: true'));
    expect(summaryGuard,
        contains('protectExistingValues && _hasServerConfigValue'));
    expect(dialog, contains('protectExistingValues: protectExistingValues'));
    expect(dialog, contains('final keyObscure = true.obs;'));
    expect(dialog, contains('obscureText: keyObscure.value'));
    expect(dialog, contains('Icons.visibility_off'));
  });

  test('server configuration export is not printed to debug logs', () {
    final source = _read('lib/common/widgets/setting_widgets.dart');

    expect(source, isNot(contains('ServerConfig export:')));
    expect(source, contains('Clipboard.setData(ClipboardData(text: text))'));
  });
}
