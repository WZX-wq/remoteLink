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

  test('mobile more actions do not expose block user input', () {
    final toolbar = File('lib/common/widgets/toolbar.dart').readAsStringSync();
    final start = toolbar.indexOf('// blockUserInput');
    final end = toolbar.indexOf('// switchSides', start);

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final blockInputMenu = toolbar.substring(start, end);

    expect(blockInputMenu, contains('!isMobile'));
    expect(blockInputMenu, contains('pi.sasEnabled'));
    expect(blockInputMenu,
        isNot(contains('blockInput.value = !blockInput.value')));
  });

  test('block input access denied uses user-facing guidance', () {
    final client = File('../src/client/io_loop.rs').readAsStringSync();
    final cn = File('../src/lang/cn.rs').readAsStringSync();

    expect(client, contains('block_input_failure_text'));
    expect(client, contains('block-input-admin-required-tip'));
    expect(client, contains('os error 1460'));
    expect(cn, contains('block-input-admin-required-tip'));
  });

  test('Windows block input is proxied through the interactive service', () {
    final ipc = File('../src/ipc.rs').readAsStringSync();
    final portable =
        File('../src/server/portable_service.rs').readAsStringSync();
    final windows = File('../src/platform/windows.rs').readAsStringSync();

    expect(ipc, contains('BlockInput((u64, bool))'));
    expect(ipc, contains('BlockInputResult((u64, bool, String))'));
    expect(portable, contains('DataPortableService::BlockInput(('));
    expect(portable, contains('BlockInputResult((request_id, ok, msg))'));
    expect(portable, contains('pub fn block_input(v: bool)'));
    expect(windows, contains('fn block_input_direct'));
    expect(windows, contains('portable_service::client::block_input'));
  });
}
