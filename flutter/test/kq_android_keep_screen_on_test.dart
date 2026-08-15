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

  test(
      'Android wake lock uses the app channel instead of mismatched plugin API',
      () {
    final common = File('lib/common.dart').readAsStringSync();
    final wakelockManager = _section(
      common,
      'class WakelockManager {',
      '\n}\n\n/// call this to reload current window.',
    );
    final activity = File(
      'android/app/src/main/kotlin/com/carriez/flutter_hbb/MainActivity.kt',
    ).readAsStringSync();

    expect(wakelockManager, contains('if (isAndroid) {'));
    expect(
      wakelockManager,
      contains('gFFI.invokeMethod("set_keep_screen_on", enabled)'),
    );
    expect(
      wakelockManager,
      contains('WakelockPlus.toggle(enable: enabled)'),
      reason: 'Non-Android platforms must keep their existing plugin path.',
    );
    expect(activity, contains('"set_keep_screen_on" ->'));
    expect(
        activity, contains('WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON'));
  });

  test('Android outgoing keep-awake setting applies during active sessions',
      () {
    final common = File('lib/common.dart').readAsStringSync();
    final settings =
        File('lib/mobile/pages/settings_page.dart').readAsStringSync();
    final wakelockManager = _section(
      common,
      'class WakelockManager {',
      '\n}\n\n/// call this to reload current window.',
    );

    expect(wakelockManager, contains('_outgoingKeys'));
    expect(wakelockManager, contains('refreshOutgoingPreference()'));
    expect(
      settings,
      contains('WakelockManager.refreshOutgoingPreference();'),
    );
  });

  test('Android start on boot accepts vendor quick boot broadcast', () {
    final receiver = File(
      'android/app/src/main/kotlin/com/carriez/flutter_hbb/BootReceiver.kt',
    ).readAsStringSync();

    expect(receiver, contains('"android.intent.action.QUICKBOOT_POWERON"'));
  });

  test('Android start-on-boot state reflects every required permission', () {
    final settings =
        File('lib/mobile/pages/settings_page.dart').readAsStringSync();
    final canStartOnBoot = _section(
      settings,
      '  Future<bool> canStartOnBoot() async {',
      '\n  defaultDisplaySection() {',
    );

    expect(
      canStartOnBoot,
      matches(
        RegExp(
          r'AndroidPermissionManager\.check\(\s*'
          r'kRequestIgnoreBatteryOptimizations\s*\)',
        ),
      ),
    );
    expect(
      canStartOnBoot,
      contains('AndroidPermissionManager.check(kSystemAlertWindow)'),
    );
    expect(canStartOnBoot, isNot(contains('_hasIgnoreBattery &&')));
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
