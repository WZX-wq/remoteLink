import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _sourceSection(
  String source, {
  required String start,
  required String end,
}) {
  final startIndex = source.indexOf(start);
  expect(startIndex, greaterThanOrEqualTo(0), reason: 'Missing start: $start');

  final endIndex = source.indexOf(end, startIndex + start.length);
  expect(endIndex, greaterThan(startIndex), reason: 'Missing end: $end');
  return source.substring(startIndex, endIndex);
}

int _countMatches(String source, RegExp pattern) {
  return pattern.allMatches(source).length;
}

int _requiredIndex(String source, String value) {
  final index = source.indexOf(value);
  expect(index, greaterThanOrEqualTo(0), reason: 'Missing text: $value');
  return index;
}

void main() {
  test('Android screen sharing setup card has one focused action', () {
    final source = File('lib/mobile/pages/server_page.dart').readAsStringSync();
    final card = _sourceSection(
      source,
      start: 'class ScreenShareSetupCard extends StatelessWidget {',
      end: 'class ScamWarningDialog extends StatefulWidget {',
    );

    expect(_countMatches(card, RegExp(r'FilledButton\.icon\s*\(')), 1);
    expect(card, contains("zhCn: '共享屏幕'"));
    expect(card, contains("zhCn: '开始共享屏幕'"));
    expect(
        _countMatches(
            card, RegExp(r'showScamWarning\s*\(context,\s*serverModel\)')),
        1);
    expect(_countMatches(card, RegExp(r'serverModel\.toggleService')), 1);
    expect(_countMatches(card, RegExp(r'show-scam-warning')), 1);
    expect(card, isNot(contains('_runAllPermissionSteps')));

    final onPressed = _sourceSection(
      card,
      start: 'onPressed: () {',
      end: '\n              ),',
    );
    expect(
      RegExp(
        r'if\s*\(\s*gFFI\.userModel\.userName\.value\.isEmpty\s*&&\s*'
        r'bind\.mainGetLocalOption\(key:\s*"show-scam-warning"\)\s*!=\s*"N"\s*\)',
      ).hasMatch(onPressed),
      isTrue,
    );
    final scamWarning =
        _requiredIndex(onPressed, 'showScamWarning(context, serverModel);');
    final elseBranch = _requiredIndex(onPressed, '} else {');
    final toggleService =
        _requiredIndex(onPressed, 'serverModel.toggleService();');
    expect(scamWarning, lessThan(elseBranch));
    expect(elseBranch, lessThan(toggleService));
  });

  test('Android server page isolates the reference layout from iOS', () {
    final source = File('lib/mobile/pages/server_page.dart').readAsStringSync();
    final build = _sourceSection(
      source,
      start: '  @override\n  Widget build(BuildContext context) {\n'
          '    if (mobilePlatformCapabilities.canHostViewOnlyBroadcast) {',
      end: 'void checkService() async {',
    );

    final iosBranch = _requiredIndex(
        build, 'mobilePlatformCapabilities.canHostViewOnlyBroadcast');
    final androidBranch = _requiredIndex(build, 'if (isAndroid) {');
    final serviceCheck = _requiredIndex(build, 'checkService();');
    final androidList = _requiredIndex(build, 'ListView(');
    expect(iosBranch, lessThan(androidBranch));
    expect(androidBranch, lessThan(serviceCheck));
    expect(serviceCheck, lessThan(androidList));
    expect(build, contains('const _IOSScreenShareBroadcastMvp()'));
    expect(build, contains('const _AndroidScreenSharePage()'));
    expect(
        _countMatches(build, RegExp(r'\b_AndroidScreenSharePage\s*\(\)')), 1);
    expect(_countMatches(build, RegExp(r'\bServerInfo\s*\(\)')), 1);
    expect(_countMatches(build, RegExp(r'\bScreenShareSetupCard\s*\(\)')), 1);
    expect(_countMatches(build, RegExp(r'\bConnectionManager\s*\(\)')), 1);
    expect(_countMatches(build, RegExp(r'\bPermissionChecker\s*\(\)')), 1);
  });

  test(
      'Android reference page keeps the supplied visual hierarchy and real actions',
      () {
    final source = File('lib/mobile/pages/server_page.dart').readAsStringSync();
    final page = _sourceSection(
      source,
      start: 'class _AndroidScreenSharePage extends StatelessWidget {',
      end: 'class ScamWarningDialog extends StatefulWidget {',
    );

    for (final className in [
      '_AndroidShareHeader',
      '_AndroidShareHero',
      '_AndroidCurrentConnectionCard',
      '_AndroidShareSectionTitle',
      '_AndroidPermissionCard',
      '_AndroidPermissionList',
      '_AndroidPermissionItem',
      '_AndroidPermissionStatePill',
    ]) {
      expect(page, contains('class $className'));
    }

    for (final text in [
      "zhCn: '共享屏幕'",
      "zhCn: '开始共享屏幕'",
      "zhCn: '当前连接'",
      "zhCn: '未连接'",
      "zhCn: '远程控制'",
      "zhCn: '更多共享功能'",
      "zhCn: '去开启'",
    ]) {
      expect(page, contains(text), reason: 'Missing reference copy: $text');
    }

    expect(page, contains('LinearGradient('));
    expect(page, contains('Color(0xFF3C73F6)'));
    expect(page, contains('Color(0xFF43A8F7)'));
    expect(page, contains('CustomPaint('));
    expect(page, contains('Icons.play_arrow_rounded'));
    expect(page, contains('Icons.open_in_new_rounded'));
    expect(page, contains('Divider('));

    for (final callback in [
      'serverModel.toggleService',
      'serverModel.toggleInput',
      'serverModel.toggleFile',
      'serverModel.toggleAudio',
      'serverModel.toggleClipboard',
    ]) {
      expect(page, contains(callback),
          reason: 'Missing real callback: $callback');
    }
    expect(page, contains('showScamWarning(context, serverModel)'));
    expect(_countMatches(page, RegExp(r'_PermissionGuideData\s*\(')), 4);

    final header = _sourceSection(
      page,
      start: 'class _AndroidShareHeader extends StatelessWidget {',
      end: 'class _AndroidShareHero extends StatelessWidget {',
    );
    expect(header, isNot(contains('最近连接')));
    expect(header, isNot(contains('Recent connections')));
    expect(header, isNot(contains('IconButton(')));
  });

  test('Android share page uses compact geometry and themed system bars', () {
    final source = File('lib/mobile/pages/server_page.dart').readAsStringSync();
    final page = _sourceSection(
      source,
      start: 'class _AndroidScreenSharePage extends StatelessWidget {',
      end: 'class ScamWarningDialog extends StatefulWidget {',
    );
    final hero = _sourceSection(
      page,
      start: 'class _AndroidShareHero extends StatelessWidget {',
      end: 'class _AndroidShareWavePainter extends CustomPainter {',
    );
    final item = _sourceSection(
      page,
      start: 'class _AndroidPermissionItem extends StatelessWidget {',
      end: 'class _AndroidPermissionStatePill extends StatelessWidget {',
    );
    final connection = _sourceSection(
      page,
      start: 'class _AndroidCurrentConnectionCard extends StatelessWidget {',
      end: 'class _AndroidConnectionStatePill extends StatelessWidget {',
    );
    final permissionCard = _sourceSection(
      page,
      start: 'class _AndroidPermissionCard extends StatelessWidget {',
      end: 'class _AndroidPermissionList extends StatelessWidget {',
    );

    expect(page, contains('AnnotatedRegion<SystemUiOverlayStyle>('));
    expect(page, contains('statusBarColor: q.surface'));
    expect(page, contains('systemNavigationBarColor: q.surface'));
    expect(hero, contains('height: 96'));
    expect(hero, isNot(contains('height: 152')));
    expect(item, contains('Padding('));
    expect(item, isNot(contains('height: 62')));
    expect(item, isNot(contains('width: 88')));
    expect(item, contains('child: Text('));
    expect(item, isNot(contains('item.description')));
    expect(connection, contains('mainAxisSize: MainAxisSize.min'));
    expect(connection, contains('mainAxisAlignment: MainAxisAlignment.center'));
    expect(hero, isNot(contains('boxShadow:')));
    expect(connection, isNot(contains('boxShadow:')));
    expect(permissionCard, isNot(contains('boxShadow:')));
    expect(item, isNot(contains('elevation: item.enabled ? 2 : 0')));
  });

  test('Android share descriptions wrap and system bars use the page color',
      () {
    final source = File('lib/mobile/pages/server_page.dart').readAsStringSync();
    final connection = _sourceSection(
      source,
      start: 'class _AndroidCurrentConnectionCard extends StatelessWidget {',
      end: 'class _AndroidConnectionStatePill extends StatelessWidget {',
    );
    final item = _sourceSection(
      source,
      start: 'class _AndroidPermissionItem extends StatelessWidget {',
      end: 'class _AndroidPermissionStatePill extends StatelessWidget {',
    );
    final lightTheme =
        File('android/app/src/main/res/values/styles.xml').readAsStringSync();
    final darkTheme = File('android/app/src/main/res/values-night/styles.xml')
        .readAsStringSync();

    expect(connection, contains('BoxConstraints(minHeight: 84)'));
    expect(connection, isNot(contains('height: 72')));
    expect(
      RegExp(
        r"zhCn: '暂无正在连接的设备，收到连接请求后会在这里显示。',[\\s\\S]{0,300}"
        r'maxLines:',
      ).hasMatch(connection),
      isFalse,
    );
    expect(item, contains('Padding('));
    expect(item, isNot(contains('height: 62')));
    expect(
      RegExp(r'Text\(\s*item\.description,\s*maxLines:').hasMatch(item),
      isFalse,
    );
    expect(
      RegExp(r'Text\(\s*item\.description,[\s\S]{0,240}'
              r'overflow: TextOverflow\.ellipsis')
          .hasMatch(item),
      isFalse,
    );

    for (final theme in [lightTheme, darkTheme]) {
      expect(theme,
          contains('<item name="android:statusBarColor">#EFF8FF</item>'));
      expect(theme,
          contains('<item name="android:navigationBarColor">#EFF8FF</item>'));
      expect(theme,
          contains('<item name="android:windowLightStatusBar">true</item>'));
    }
  });

  test('Android share uses a compact connection row and title-only permissions',
      () {
    final source = File('lib/mobile/pages/server_page.dart').readAsStringSync();
    final page = _sourceSection(
      source,
      start: 'class _AndroidScreenSharePage extends StatelessWidget {',
      end: 'class ScamWarningDialog extends StatefulWidget {',
    );
    final item = _sourceSection(
      page,
      start: 'class _AndroidPermissionItem extends StatelessWidget {',
      end: 'class _AndroidPermissionStatePill extends StatelessWidget {',
    );

    expect(page, contains('const _AndroidCurrentConnectionsCard()'));
    expect(page, isNot(contains('const ConnectionManager()')));
    expect(page, contains('class _AndroidCurrentConnectionsCard'));
    expect(page, contains('class _AndroidConnectionRow'));
    expect(item, isNot(contains('item.description')));
    expect(item, contains('padding: const EdgeInsets.symmetric(vertical: 8)'));
  });

  test('Android controlled side can end an active voice call', () {
    final source = File('lib/mobile/pages/server_page.dart').readAsStringSync();
    final row = _sourceSection(
      source,
      start: 'class _AndroidConnectionRow extends StatelessWidget {',
      end: 'class _AndroidConnectionStatePill extends StatelessWidget {',
    );

    expect(row, contains('if (client.inVoiceCall)'));
    expect(row, contains('gFFI.serverModel.closeVoiceCall(client)'));
    expect(row, contains("zhCn: '挂断语音'"));
  });

  test('Android input permission guidance uses structured modern actions', () {
    final source = File('lib/models/server_model.dart').readAsStringSync();
    final dialog = _sourceSection(
      source,
      start: 'showInputWarnAlert(FFI ffi) {',
      end: '\n}',
    );

    expect(dialog, contains('androidTitleIcon:'));
    expect(dialog, contains('androidSubtitle:'));
    expect(source, contains('class _AndroidPermissionStep'));
    expect(source, contains('class _AndroidPermissionNotice'));
    expect(dialog, contains('AndroidDialogActionRole.primary'));
    expect(dialog, contains('AndroidDialogActionRole.secondary'));
    expect(dialog, contains('AndroidDialogActionRole.cancel'));
    expect(dialog, contains('kActionAccessibilitySettings'));
    expect(dialog, contains('kActionApplicationDetailsSettings'));
  });

  test('Android scam warning uses the focused shell and keeps safety flow', () {
    final source = File('lib/mobile/pages/server_page.dart').readAsStringSync();
    final warning = _sourceSection(
      source,
      start: 'class ScamWarningDialogState extends State<ScamWarningDialog> {',
      end: 'class ServerInfo extends StatelessWidget {',
    );

    expect(warning, contains('if (isAndroid)'));
    expect(warning, contains('CustomAlertDialog('));
    expect(warning, contains('androidTitleIcon:'));
    expect(warning, contains('AndroidDialogActionRole.primary'));
    expect(warning, contains('AndroidDialogActionRole.cancel'));
    expect(warning, contains('_countdown > 0'));
    expect(warning, contains('_serverModel.toggleService()'));
    expect(warning, contains('show-scam-warning'));
    expect(warning, contains('AlertDialog('),
        reason: 'Non-Android platforms must retain their legacy warning');
  });

  test('Android device card uses compact geometry without resizing iOS', () {
    final source = File('lib/mobile/pages/server_page.dart').readAsStringSync();
    final serverInfo = _sourceSection(
      source,
      start: 'class ServerInfo extends StatelessWidget {',
      end: 'class _DevicePasswordTile extends StatefulWidget {',
    );
    final deviceId = _sourceSection(
      source,
      start: 'class _DeviceSecretTile extends StatelessWidget {',
      end: 'class _PermissionCheckerState extends State<PermissionChecker> {',
    );

    expect(serverInfo, contains('final compact = isAndroid;'));
    expect(serverInfo, contains('const EdgeInsets.fromLTRB(12, 10, 12, 10)'));
    expect(serverInfo, contains('compact: compact,'));
    expect(deviceId, contains('final bool compact;'));
    expect(deviceId, contains('width: compact ? 34 : 38'));
    expect(deviceId, contains('width: compact ? 36 : 42'));
    expect(deviceId, contains('height: compact ? 36 : 42'));
  });

  test('Android notification cancellation always completes its method call',
      () {
    final activity = File(
      'android/app/src/main/kotlin/com/carriez/flutter_hbb/MainActivity.kt',
    ).readAsStringSync();
    final start = activity.indexOf('"cancel_notification" -> {');
    final end = activity.indexOf('"enable_soft_keyboard" -> {', start);

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final handler = activity.substring(start, end);
    final canceled = handler.indexOf('mainService?.cancelNotification(id)');
    final completed = handler.indexOf('result.success(true)', canceled);
    expect(canceled, greaterThanOrEqualTo(0));
    expect(completed, greaterThan(canceled));
    expect(handler.substring(canceled, completed), isNot(contains('} else {')));
  });

  test('Android permission controls remain independent and collapsed', () {
    final source = File('lib/mobile/pages/server_page.dart').readAsStringSync();
    final permissionChecker = _sourceSection(
      source,
      start: 'class _PermissionCheckerState extends State<PermissionChecker> {',
      end: 'class _PermissionGuideData {',
    );
    final build = _sourceSection(
      permissionChecker,
      start: '  @override\n  Widget build(BuildContext context) {',
      end: '\n}',
    );
    final optionalFeatures = _sourceSection(
      build,
      start: 'final optionalFeatures = [',
      end: '];\n    return PaddingCard(',
    );
    final optionalRender = _sourceSection(
      build,
      start: 'if (_showOptionalFeatures) ...[',
      end: '\n          ],\n        ]));',
    );
    final inputRender =
        RegExp(r'_PermissionGuideItem\s*\(item:\s*inputControl\)');
    final guideItemRender = RegExp(r'_PermissionGuideItem\s*\(');
    final optionalItemsRender =
        RegExp(r'\.\.\.\s*optionalFeatures\.map\s*\(\s*\(item\)\s*=>');
    final optionalFeatureContracts = <String, RegExp>{
      'fileTransfer': RegExp(
        r'_PermissionGuideData\(\s*'
        r'title:\s*translate\("Transfer file"\),[\s\S]*?'
        r'onPressed:\s*serverModel\.toggleFile,',
      ),
      'audioCapture': RegExp(
        r'_PermissionGuideData\(\s*'
        r'title:\s*translate\("Audio Capture"\),[\s\S]*?'
        r'onPressed:\s*serverModel\.toggleAudio,',
      ),
      'clipboard': RegExp(
        r'_PermissionGuideData\(\s*'
        r'title:\s*translate\("Enable clipboard"\),[\s\S]*?'
        r'onPressed:\s*serverModel\.toggleClipboard,',
      ),
    };

    expect(build, isNot(contains('Screen Capture')));
    expect(build, isNot(contains('_runAllPermissionSteps')));
    expect(build, isNot(contains('kq_mobile_enable_missing_permissions')));
    expect(build, isNot(contains('_PermissionProgressHeader(')));

    final inputItem =
        _requiredIndex(build, '_PermissionGuideItem(item: inputControl)');
    final optionalGate = _requiredIndex(build, 'if (_showOptionalFeatures)');
    expect(inputItem, lessThan(optionalGate));
    final beforeOptionalRender = build.substring(0, optionalGate);
    final afterOptionalRender =
        build.substring(optionalGate + optionalRender.length);
    expect(_countMatches(beforeOptionalRender, inputRender), 1);
    expect(_countMatches(beforeOptionalRender, guideItemRender), 1);
    expect(_countMatches(beforeOptionalRender, optionalItemsRender), 0);
    expect(_countMatches(optionalRender, optionalItemsRender), 1);
    expect(_countMatches(optionalRender, inputRender), 0);
    expect(_countMatches(afterOptionalRender, inputRender), 0);
    expect(_countMatches(afterOptionalRender, optionalItemsRender), 0);
    expect(_countMatches(afterOptionalRender, guideItemRender), 0);
    expect(_countMatches(build, inputRender), 1);

    expect(optionalFeatures, isNot(contains('inputControl')));
    expect(
        _countMatches(optionalFeatures, RegExp(r'_PermissionGuideData\(')), 3);
    for (final entry in optionalFeatureContracts.entries) {
      expect(_countMatches(optionalFeatures, entry.value), 1,
          reason: 'Expected exactly one ${entry.key} optional item');
    }

    final inputToggleHelper = _sourceSection(
      permissionChecker,
      start:
          'Future<void> _toggleInputControl(ServerModel serverModel) async {',
      end: '  @override\n',
    );
    expect(
        _countMatches(inputToggleHelper, RegExp(r'serverModel\.toggleInput\b')),
        1);
    final serverModelToggleCalls = RegExp(r'serverModel\.toggle[A-Z]\w*\b')
        .allMatches(permissionChecker)
        .map((match) => match.group(0)!)
        .toList();
    expect(
      serverModelToggleCalls,
      unorderedEquals([
        'serverModel.toggleInput',
        'serverModel.toggleFile',
        'serverModel.toggleAudio',
        'serverModel.toggleClipboard',
      ]),
    );

    expect(optionalRender, contains('...optionalFeatures.map('));
    expect(optionalRender,
        contains('_PermissionGuideItem(item: item).marginOnly(top: 10)'));
    expect(build, contains('final hasAudioPermission = androidVersion >= 30;'));
    expect(optionalFeatures, isNot(contains('permissionChangeLocked')));
    expect(optionalFeatures, contains('enabled: hasAudioPermission'));
    expect(optionalRender, isNot(contains('_PermissionNotice(')));
    expect(permissionChecker, isNot(contains('permissionChangeLocked')));
    expect(permissionChecker,
        isNot(contains('kOptionEnablePermChangeInAcceptWindow')));

    for (final forbidden in [
      'mediaOk',
      'serverModel.toggleService',
      'showScamWarning',
      'Screen Capture',
      'ScreenShareSetupCard',
      '_runAllPermissionSteps',
      'kq_mobile_enable_missing_permissions',
    ]) {
      expect(permissionChecker, isNot(contains(forbidden)),
          reason: 'Unexpected PermissionChecker path: $forbidden');
    }
  });

  test('obsolete Android permission progress controls are removed', () {
    final source = File('lib/mobile/pages/server_page.dart').readAsStringSync();

    expect(source, isNot(contains('class _PermissionProgressHeader')));
    expect(source, isNot(contains('class _PermissionDetailsToggle')));
    expect(source, contains('class _PermissionGuideItem'));
    expect(source, contains('class _PermissionStatePill'));
  });

  test('Android live permission changes reach active sessions', () {
    final ffi = File('../src/flutter_ffi.rs').readAsStringSync();
    final connection = File('../src/server/connection.rs').readAsStringSync();
    final cm = File('../src/ui_cm_interface.rs').readAsStringSync();
    final page = File('lib/mobile/pages/server_page.dart').readAsStringSync();
    final serverModel = File('lib/models/server_model.dart').readAsStringSync();
    final androidPage = _sourceSection(
      page,
      start: 'class _AndroidScreenSharePage extends StatelessWidget {',
      end: 'class _AndroidShareHeader extends StatelessWidget {',
    );

    expect(ffi, contains('fn android_live_permission_name'));
    expect(ffi, contains('Some("audio")'));
    expect(ffi, contains('Some("file")'));
    expect(ffi, contains('Some("clipboard")'));
    expect(ffi, contains('Some("keyboard")'));
    expect(ffi, contains('broadcast_android_permission_change(&key, &value);'));
    expect(ffi, contains('broadcast_android_permission_changes(&map);'));
    expect(ffi, isNot(contains('blocked main_set_option by policy')));
    expect(ffi, isNot(contains('blocked main_set_options item by policy')));
    expect(cm, isNot(contains('blocked cm switch_permission_all by policy')));
    expect(connection, contains('} else if &name == "audio" {'));
    expect(connection, contains('} else if &name == "file" {'));
    expect(connection, contains('} else if &name == "clipboard" {'));
    expect(androidPage, isNot(contains('permissionChangeLocked')));
    expect(androidPage, contains('enabled: hasAudioPermission,'));
    expect(serverModel, isNot(contains('showClientsMayNotBeChangedAlert')));
  });
}
