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

  test('Android server page keeps iOS early return and one primary setup state',
      () {
    final source = File('lib/mobile/pages/server_page.dart').readAsStringSync();
    final build = _sourceSection(
      source,
      start: '  @override\n  Widget build(BuildContext context) {\n'
          '    if (mobilePlatformCapabilities.canHostViewOnlyBroadcast) {',
      end: 'void checkService() async {',
    );

    final iosBranch = _requiredIndex(
        build, 'mobilePlatformCapabilities.canHostViewOnlyBroadcast');
    final serviceCheck = _requiredIndex(build, 'checkService();');
    final androidList = _requiredIndex(build, 'ListView(');
    expect(iosBranch, lessThan(serviceCheck));
    expect(serviceCheck, lessThan(androidList));
    expect(build, contains('const _IOSScreenShareBroadcastMvp()'));

    expect(
      RegExp(
        r'serverModel\.isStart\s*\?\s*ServerInfo\(\)\s*:'
        r'\s*const ScreenShareSetupCard\(\)',
      ).hasMatch(build),
      isTrue,
    );
    expect(_countMatches(build, RegExp(r'\bServerInfo\s*\(\)')), 1);
    expect(_countMatches(build, RegExp(r'\bScreenShareSetupCard\s*\(\)')), 1);
    expect(_countMatches(build, RegExp(r'\bConnectionManager\s*\(\)')), 1);
    expect(_countMatches(build, RegExp(r'\bPermissionChecker\s*\(\)')), 1);
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
    expect(optionalFeatures, contains('enabled: !permissionChangeLocked'));
    expect(optionalFeatures,
        contains('enabled: hasAudioPermission && !permissionChangeLocked'));
    expect(optionalRender, contains('if (permissionChangeLocked)'));
    expect(optionalRender, contains('_PermissionNotice('));

    final permissionPolicy = _sourceSection(
      build,
      start: 'final allowPermChangeInAcceptWindow = option2bool(',
      end: 'final inputControl = _PermissionGuideData(',
    );
    expect(permissionPolicy, contains('kOptionEnablePermChangeInAcceptWindow'));
    expect(permissionPolicy, contains('option2bool('));
    expect(
        permissionPolicy, contains('final permissionChangeLocked = isAndroid'));
    expect(permissionPolicy,
        contains('serverModel.clients.any((c) => !c.disconnected)'));
    expect(permissionPolicy, contains('!allowPermChangeInAcceptWindow'));

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
}
