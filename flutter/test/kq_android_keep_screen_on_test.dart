import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _section(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  final endIndex = source.indexOf(end, startIndex + start.length);
  expect(startIndex, greaterThanOrEqualTo(0));
  expect(endIndex, greaterThan(startIndex));
  return source.substring(startIndex, endIndex);
}

void main() {
  test(
      'Android keep-screen-on selector remains available without a floating window',
      () {
    final settings =
        File('lib/mobile/pages/settings_page.dart').readAsStringSync();
    final keepScreenOn = _section(
      settings,
      "title: _settingsText('Keep screen on'),",
      'final disabledSettings = bind.isDisableSettings();',
    );

    expect(keepScreenOn, contains('getter: () => _keepScreenOnToOption('));
    expect(
      keepScreenOn,
      contains('bind.mainGetLocalOption(key: kOptionKeepScreenOn)'),
    );
    expect(
      keepScreenOn,
      contains('asyncSetter: isOptionFixed(kOptionKeepScreenOn)'),
    );
    expect(keepScreenOn, isNot(contains('_floatingWindowDisabled')));
  });

  test('Android keep-screen-on behavior is independent of overlay permission',
      () {
    final serverModel = File('lib/models/server_model.dart').readAsStringSync();
    final update = _section(
      serverModel,
      'void androidUpdatekeepScreenOn() {',
      '\n}\n\nenum ClientType',
    );

    expect(
      update,
      contains(
          'optionToKeepScreenOn(bind.mainGetLocalOption(key: kOptionKeepScreenOn))'),
    );
    expect(update, isNot(contains('kOptionDisableFloatingWindow')));
    expect(update, isNot(contains('kSystemAlertWindow')));
  });

  test('Android controlled-session wake lock ignores disconnected clients', () {
    final serverModel = File('lib/models/server_model.dart').readAsStringSync();
    final update = _section(
      serverModel,
      'void androidUpdatekeepScreenOn() {',
      '\n}\n\nenum ClientType',
    );

    expect(update, contains('_clients.any((client) => !client.disconnected)'));
    expect(update, isNot(contains('_clients.map((e) => !e.disconnected)')));
  });

  test('Android wake locks keep independent mobile activities awake', () {
    final common = File('lib/common.dart').readAsStringSync();
    final wakelockManager = _section(
      common,
      'class WakelockManager {',
      '\n}\n\n/// call this to reload current window.',
    );

    expect(
      wakelockManager,
      contains('if (isDesktop || isAndroid) {\n      _enabledKeys.add(key);'),
    );
    expect(
      wakelockManager,
      contains(
          'if (isDesktop || isAndroid) {\n      _enabledKeys.remove(key);'),
    );
  });

  test('mobile interactive callbacks are never empty', () {
    final callback = RegExp(
      r'(?:onPressed|onTap|onChanged|onToggle)\s*:\s*(?:\([^)]*\)\s*)?(?:async\s*)?(?:=>\s*)?\{\s*\}',
      multiLine: true,
    );
    final mobileFiles = Directory('lib/mobile')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in mobileFiles) {
      expect(
        callback.hasMatch(file.readAsStringSync()),
        isFalse,
        reason: '${file.path} contains an empty mobile interaction callback',
      );
    }
  });
}
