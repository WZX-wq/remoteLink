import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile remote session does not expose privacy mode', () {
    final toolbar = File('lib/common/widgets/toolbar.dart').readAsStringSync();
    final remotePage =
        File('lib/mobile/pages/remote_page.dart').readAsStringSync();
    final server = File('../src/server/connection.rs').readAsStringSync();
    final privacy = File('../src/privacy_mode.rs').readAsStringSync();

    expect(remotePage, isNot(contains('toolbarPrivacyMode(')));
    expect(remotePage, isNot(contains('setPrivacyModeDialog(')));
    expect(remotePage, isNot(contains("translate('Privacy mode')")));
    expect(toolbar, contains('List<TToggleMenu> toolbarPrivacyMode'));
    expect(server, contains('"supported_privacy_mode_impl"'));
    expect(privacy, contains('win_topmost_window::is_runtime_available()'));
  });

  test('mobile more actions do not expose the iOS recording no-op', () {
    final toolbar = File('lib/common/widgets/toolbar.dart').readAsStringSync();
    final model = File('lib/models/model.dart').readAsStringSync();

    expect(model, contains('if (isIOS) return;'));
    expect(toolbar, contains('if (!isIOS &&'));
  });
}
