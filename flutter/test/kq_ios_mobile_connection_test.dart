import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/mobile/widgets/mobile_bottom_navigation_safe_area.dart';
import 'package:flutter_hbb/models/connection_failure_presentation.dart';
import 'package:flutter_hbb/models/mobile_remote_route.dart';
import 'package:flutter_test/flutter_test.dart';

String _section(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  final endIndex = source.indexOf(end, startIndex + start.length);
  expect(startIndex, greaterThanOrEqualTo(0), reason: 'Missing start: $start');
  expect(endIndex, greaterThan(startIndex), reason: 'Missing end: $end');
  return source.substring(startIndex, endIndex);
}

void main() {
  testWidgets(
      'registered remote route removal preserves Home and an upper route',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const SizedBox(key: Key('home-route')),
      ),
    );

    final remoteRoute = MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'remote'),
      builder: (_) => const SizedBox(key: Key('remote-route')),
    );
    navigatorKey.currentState!.push(remoteRoute);
    await tester.pumpAndSettle();

    final upperRoute = MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'upper'),
      builder: (_) => const SizedBox(key: Key('upper-route')),
    );
    navigatorKey.currentState!.push(upperRoute);
    await tester.pumpAndSettle();

    final removed = removeRegisteredMobileRemoteRoute(
      navigator: navigatorKey.currentState!,
      route: remoteRoute,
    );
    await tester.pumpAndSettle();

    expect(removed, isTrue);
    expect(find.byKey(const Key('upper-route')), findsOneWidget);
    expect(
      find.byKey(const Key('remote-route'), skipOffstage: false),
      findsNothing,
    );
    expect(
      find.byKey(const Key('home-route'), skipOffstage: false),
      findsOneWidget,
    );

    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home-route')), findsOneWidget);
  });

  test('iOS starts with an empty remote ID while Android restore remains', () {
    final source =
        File('lib/mobile/pages/connection_page.dart').readAsStringSync();
    final restore = _section(
      source,
      '  Future<void> _restoreLastConnection() async {',
      '  void _setRemoteId(',
    );

    expect(restore, contains('if (isIOS) return;'));
    expect(restore, contains('if (!isMobile) return;'));
    expect(restore, contains('kqLastSuccessfulMobileConnectId()'));
    expect(restore, contains('bind.mainGetLastRemoteId()'));
  });

  test('outgoing connection form covers login, ID, and password gates', () {
    final source =
        File('lib/mobile/pages/connection_page.dart').readAsStringSync();
    final connect = _section(
      source,
      '  void onConnect() async {',
      '  Future<void> _restoreLastConnection() async {',
    );

    expect(connect, contains('if (!await _ensureLoggedIn()) return;'));
    expect(connect, contains('if (!_ensureRemoteId()) return;'));
    expect(connect, contains('password: _remotePassword'));
    expect(
      connect,
      contains('rememberPassword: _remotePassword.isNotEmpty'),
    );
    expect(source, contains("translate('Please enter remote ID')"));
    expect(
      source,
      contains("translate('Please login before remote connection')"),
    );
  });

  test('mobile remote route covers connecting, success, and disconnect', () {
    final remotePage =
        File('lib/mobile/pages/remote_page.dart').readAsStringSync();
    final model = File('lib/models/model.dart').readAsStringSync();

    expect(
      remotePage,
      contains(
          "showLoading(translate('Connecting...'), onCancel: closeConnection)"),
    );
    expect(
        remotePage, contains('onPressed: () => clientClose(sessionId, gFFI)'));
    expect(remotePage, contains('await gFFI.close();'));

    final firstFrame = _section(
      model,
      '    if (ffiModel.waitForFirstImage.value == true) {',
      '  /// Login with [password]',
    );
    expect(firstFrame, contains('ffiModel.waitForFirstImage.value = false;'));
    expect(firstFrame, contains('dialogManager.dismissAll();'));
    expect(firstFrame, contains('imageModel.callbacksOnFirstImage'));
  });

  test('KQ mobile failures use safe copy and close only the remote route', () {
    final common = File('lib/common.dart').readAsStringSync();
    final helper = File('lib/models/connection_failure_presentation.dart');
    final model = File('lib/models/model.dart').readAsStringSync();

    expect(
      helper.existsSync(),
      isTrue,
      reason: 'Connection failures need a pure, testable presentation helper.',
    );
    expect(
      model,
      contains('shouldCloseKqConnectionFailure('),
      reason:
          'Mobile connection errors must be intercepted before raw dialogs.',
    );
    expect(model, contains('isMobilePlatform: isMobile'));
    expect(model, contains('isIOSPlatform: isIOS'));
    expect(model, contains('Route<dynamic>? mobileRemoteRoute;'));
    expect(
      common,
      contains('gFFI.mobileRemoteRoute = remoteRoute;'),
      reason: 'The exact pushed remote route must be registered before start.',
    );
    expect(
      common,
      contains('Navigator.push<void>(context, remoteRoute)'),
    );

    final notify = _section(
      model,
      '  void _notifyConnectionFailureAndClose(',
      '  /// Show a message box with [type], [title] and [text].',
    );
    expect(notify, contains('final isKqIOS'));
    expect(
      notify,
      contains(
        'final navigator = failedRoute?.navigator ?? globalKey.currentState;',
      ),
      reason: 'Failure cleanup must use the navigator that owns the remote route.',
    );
    expect(notify, contains('removeRegisteredMobileRemoteRoute('));

    final mobileStart = notify.indexOf('if (isKqIOS) {');
    final desktopStart = notify.indexOf('if (isKqDesktop) {');
    expect(mobileStart, greaterThanOrEqualTo(0));
    expect(desktopStart, greaterThan(mobileStart));
    final mobileBranch = notify.substring(mobileStart, desktopStart);
    expect(
        mobileBranch, contains('WidgetsBinding.instance.addPostFrameCallback'));
    expect(mobileBranch, contains('showToast(reason'));
    expect(mobileBranch, contains('stateGlobal.isInMainPage = true;'));
    expect(mobileBranch, isNot(contains('closeConnection()')));
    expect(mobileBranch, isNot(contains('navigator.pop()')));
    expect(mobileBranch, isNot(contains('sessionClose(')));
    expect(mobileBranch, isNot(contains('popUntil')));
    expect(model, contains('ffiModel._connectionFailureCloseStarted = false;'));
  });

  test('KQ failure policy intercepts mobile errors without widening desktop',
      () {
    bool shouldClose({
      required String type,
      String text = 'opaque failure',
      bool isKqApp = true,
      bool isDesktopPlatform = false,
      bool isMobilePlatform = true,
      bool isIOSPlatform = true,
      bool isWebPlatform = false,
    }) {
      return shouldCloseKqConnectionFailure(
        isKqApp: isKqApp,
        isDesktopPlatform: isDesktopPlatform,
        isMobilePlatform: isMobilePlatform,
        isIOSPlatform: isIOSPlatform,
        isWebPlatform: isWebPlatform,
        type: type,
        title: 'Connection Error',
        text: text,
      );
    }

    expect(shouldClose(type: 'error'), isTrue);
    expect(
      shouldClose(type: 'error', isIOSPlatform: false),
      isFalse,
      reason: 'Android must keep its existing retry and diagnostics behavior.',
    );
    expect(shouldClose(type: 're-input-password'), isFalse);
    expect(shouldClose(type: 'error', isKqApp: false), isFalse);
    expect(shouldClose(type: 'error', isWebPlatform: true), isFalse);
    expect(
      shouldClose(
        type: 'error',
        text: 'KQ_CONNECTION_START_TIMEOUT',
        isDesktopPlatform: true,
        isMobilePlatform: false,
      ),
      isTrue,
    );
    expect(
      shouldClose(
        type: 'error',
        text: 'Failed to connect to rendezvous server',
        isDesktopPlatform: true,
        isMobilePlatform: false,
      ),
      isFalse,
      reason: 'Existing desktop multi-window failure behavior must not widen.',
    );
  });

  test('KQ failure copy removes internal markers in Chinese and English', () {
    const cases = <String, String>{
      'KQ_CONNECTION_START_TIMEOUT': '30 seconds',
      'Remote desktop is offline': 'cannot be reached',
      'Failed to connect to rendezvous server': 'temporarily unavailable',
      'Failed to connect to relay server': 'temporarily unavailable',
      'KQ_VPN_ROUTE_BLOCKED': 'VPN',
      'KQ_VIDEO_FIRST_FRAME_TIMEOUT': 'remote image',
      'Os error 10054: Connection reset': 'interrupted',
      'Connection refused': 'interrupted',
      'socket error 61': 'interrupted',
      'wrong password': 'password is incorrect',
      'opaque::internal_error(raw=7)': 'Connection failed',
    };
    const forbidden = <String>[
      'kq_connection_start_timeout',
      'kq_vpn_route_blocked',
      'kq_video_first_frame_timeout',
      'rendezvous',
      'relay server',
      'socket error',
      '10054',
      'opaque::',
      'raw=7',
    ];

    for (final entry in cases.entries) {
      final copy = presentKqConnectionFailure(entry.key);
      expect(copy.zhCn, matches(RegExp(r'[\u4e00-\u9fff]')));
      expect(copy.en, contains(entry.value));
      final visible = '${copy.zhCn}\n${copy.en}'.toLowerCase();
      for (final marker in forbidden) {
        expect(
          visible,
          isNot(contains(marker)),
          reason: 'Visible copy leaked "$marker" for ${entry.key}.',
        );
      }
    }
  });

  test('mobile network diagnostics bypass desktop-only technical details', () {
    final model = File('lib/models/model.dart').readAsStringSync();
    final handler = _section(
      model,
      '  handleMsgBox(Map<String, dynamic> evt, SessionID sessionId, String peerId) {',
      '  bool shouldShowKqConnectionDiagnostics(',
    );
    final diagnosticsStart =
        handler.indexOf("} else if (type == 'kq-network-diagnostics') {");
    final relayStart = handler.indexOf("} else if (type == 'relay-hint'", diagnosticsStart);
    expect(diagnosticsStart, greaterThanOrEqualTo(0));
    expect(relayStart, greaterThan(diagnosticsStart));

    final diagnosticsBranch = handler.substring(diagnosticsStart, relayStart);
    expect(diagnosticsBranch, contains('if (isIOS && !isWeb)'));
    expect(
      diagnosticsBranch,
      contains("_notifyConnectionFailureAndClose('error', 'Connection Error', text)"),
    );
    expect(diagnosticsBranch, contains('showKqNetworkDiagnosticsDialog('));
  });

  test('relay failure actions are localized instead of hard-coded Chinese', () {
    final model = File('lib/models/model.dart').readAsStringSync();
    final relayDialog = _section(
      model,
      '  Future<void> showRelayHintDialog(',
      '  Future<void> showKqNetworkDiagnosticsDialog(',
    );

    expect(
      relayDialog,
      matches(RegExp("zhCn:\\s*'关闭',\\s*en:\\s*'Close'")),
    );
    expect(
      relayDialog,
      matches(RegExp("zhCn:\\s*'重试',\\s*en:\\s*'Retry'")),
    );
    expect(
      relayDialog,
      matches(RegExp(
          "zhCn:\\s*'换一种连接方式',\\s*en:\\s*'Use another connection method'")),
    );
    expect(relayDialog, isNot(contains("dialogButton('关闭'")));
    expect(relayDialog, isNot(contains("dialogButton('重试'")));
  });

  test('iOS bottom navigation stays above the home indicator', () {
    final source = File('lib/mobile/pages/home_page.dart').readAsStringSync();
    final bottomNavigation = _section(
      source,
      '            bottomNavigationBar:',
      '            body: Container(',
    );

    expect(bottomNavigation, contains('MobileBottomNavigationSafeArea('));
    expect(bottomNavigation, contains('isIOS: isIOS'));
    expect(
      bottomNavigation,
      contains('margin: const EdgeInsets.fromLTRB(14, 0, 14, 0)'),
      reason: 'Platform-specific bottom spacing belongs to the safe-area helper.',
    );
  });

  testWidgets('bottom navigation helper applies iOS and Android spacing',
      (tester) async {
    Future<double> pumpAndReadBottomPadding(bool isIOS) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            padding: EdgeInsets.only(bottom: 34),
          ),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: MobileBottomNavigationSafeArea(
              isIOS: isIOS,
              child: const SizedBox(key: Key('navigation-child')),
            ),
          ),
        ),
      );
      final padding = tester.widget<Padding>(
        find.descendant(
          of: find.byType(MobileBottomNavigationSafeArea),
          matching: find.byType(Padding),
        ),
      );
      return (padding.padding as EdgeInsets).bottom;
    }

    expect(await pumpAndReadBottomPadding(true), 34);
    expect(await pumpAndReadBottomPadding(false), 14);
  });
}
