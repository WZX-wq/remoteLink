import 'dart:io';

import 'package:flutter_hbb/models/mobile_remote_layout_policy.dart';
import 'package:flutter_test/flutter_test.dart';

String _section(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  final endIndex = source.indexOf(end, startIndex + start.length);
  expect(startIndex, greaterThanOrEqualTo(0), reason: 'Missing $start');
  expect(endIndex, greaterThan(startIndex), reason: 'Missing $end');
  return source.substring(startIndex, endIndex);
}

void main() {
  test('Android phone-to-phone capability boundary is centralized', () {
    final policy =
        File('lib/models/mobile_remote_layout_policy.dart').readAsStringSync();

    expect(policy, contains('bool isAndroidPhoneToPhoneSession('));
    expect(policy, contains('isAndroidController && isAndroidPeer'));
    expect(
      isAndroidPhoneToPhoneSession(
        isAndroidController: true,
        isAndroidPeer: true,
      ),
      isTrue,
    );
    expect(
      isAndroidPhoneToPhoneSession(
        isAndroidController: true,
        isAndroidPeer: false,
      ),
      isFalse,
    );
    expect(
      isAndroidPhoneToPhoneSession(
        isAndroidController: false,
        isAndroidPeer: true,
      ),
      isFalse,
    );
  });

  test('Android phone-to-phone side rail hides keyboard and virtual mouse', () {
    final source = File('lib/mobile/pages/remote_page.dart').readAsStringSync();
    final rail = _section(
      source,
      'Widget _remoteSideActionRail()',
      'Widget _remoteSideActionButton(',
    );
    final body = _section(
      source,
      'Widget getBodyForMobile()',
      'Widget getBodyForDesktopWithListener()',
    );

    expect(source, contains('bool get _isAndroidPhoneToPhoneSession'));
    expect(rail, contains('if (!_isAndroidPhoneToPhoneSession)'));
    expect(body, contains('if (!_isAndroidPhoneToPhoneSession)'));
    expect(body, contains('FloatingMouse('));
  });

  test('Android phone-to-phone session cannot mount or open soft keyboard', () {
    final source = File('lib/mobile/pages/remote_page.dart').readAsStringSync();
    final openKeyboard = _section(
      source,
      'void openKeyboard()',
      'void _hideSoftKeyboard()',
    );
    final body = _section(
      source,
      'Widget getBodyForMobile()',
      'Widget getBodyForDesktopWithListener()',
    );
    final rawInput = _section(
      source,
      'Widget getRawPointerAndKeyBody(Widget child)',
      'Widget _remoteSideActionRail()',
    );
    final cursor = _section(
      source,
      'bool get showCursorPaint',
      'Widget getBodyForMobile()',
    );

    expect(
        openKeyboard, contains('if (_isAndroidPhoneToPhoneSession) return;'));
    expect(
        rawInput, contains('if (_isAndroidPhoneToPhoneSession) return child;'));
    expect(cursor, contains('!_isAndroidPhoneToPhoneSession &&'));
    expect(
      RegExp(
        r'if \(!_isAndroidPhoneToPhoneSession\)\s+SizedBox\(\s+width: 0,\s+height: 0,\s+child:',
      ).hasMatch(body),
      isTrue,
    );
  });

  test('Android phone-to-phone more menu keeps only mobile-safe actions', () {
    final source = File('lib/mobile/pages/remote_page.dart').readAsStringSync();
    final actions = _section(
      source,
      'List<TTextMenu> _getMobileActionMenus()',
      'void showActions(String id)',
    );
    final showActions = _section(
      source,
      'void showActions(String id)',
      'showChatOptions(String id)',
    );

    expect(actions, contains('if (!gFFI.ffiModel.isPeerAndroid ||'));
    expect(actions, contains('if (!_isAndroidPhoneToPhoneSession) ...['));
    expect(actions, contains("translate('Volume up')"));
    expect(actions, contains("translate('Volume down')"));
    expect(actions, contains("translate('Power')"));
    expect(actions, contains("translate('Back')"));
    expect(actions, contains("translate('Home')"));
    expect(actions, contains("translate('Apps')"));
    expect(showActions, contains('androidPhoneToPhone:'));
  });

  test('Android phone-to-phone display settings filter desktop input items',
      () {
    final toolbar = File('lib/common/widgets/toolbar.dart').readAsStringSync();
    final displayToggles = _section(
      toolbar,
      'Future<List<TToggleMenu>> toolbarDisplayToggle(',
      'var togglePrivacyModeTime',
    );
    final remotePage =
        File('lib/mobile/pages/remote_page.dart').readAsStringSync();
    final options = _section(
      remotePage,
      'void showOptions(',
      'class _RemoteOptionSection',
    );

    expect(displayToggles, contains('androidPhoneToPhone = false'));
    expect(displayToggles,
        contains('if (!androidPhoneToPhone) ...toolbarKeyboardToggles(ffi)'));
    expect(options, contains('androidPhoneToPhone: androidPhoneToPhone'));
    expect(
      options,
      contains(
        'androidPhoneToPhone\n      ? <TToggleMenu>[]\n      : await toolbarCursor',
      ),
    );
    expect(
      RegExp(r'final resolution =\s+androidPhoneToPhone \? null')
          .hasMatch(options),
      isTrue,
    );
  });

  test('Android phone-to-phone generic controls hide desktop-only actions', () {
    final toolbar = File('lib/common/widgets/toolbar.dart').readAsStringSync();
    final controls = _section(
      toolbar,
      'List<TTextMenu> toolbarControls(',
      'Future<List<TRadioMenu<String>>> toolbarViewStyle(',
    );

    expect(controls, contains('androidPhoneToPhone = false'));
    expect(
      RegExp(r'if \(!androidPhoneToPhone &&\s+isDefaultConn &&')
          .hasMatch(controls),
      isTrue,
    );
    expect(controls, contains("translate(pi.isHeadless ? 'OS Account'"));
    expect(controls, contains("translate('Insert Lock')"));
  });
}
