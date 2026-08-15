import 'dart:io';

import 'package:flutter_hbb/models/remote_id_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('remote ID validation rejects malformed IDs before connecting', () {
    expect(isValidKqRemoteIdentifierFormat('1234567890'), isTrue);
    expect(isValidKqRemoteIdentifierFormat('device_01'), isTrue);
    expect(isValidKqRemoteIdentifierFormat('12345'), isFalse);
    expect(isValidKqRemoteIdentifierFormat('bad id'), isFalse);
    expect(isValidKqRemoteIdentifierFormat('@@@'), isFalse);
    expect(isValidKqRemoteIdentifierFormat('1234567890/r'), isTrue);
    expect(
      isValidKqRemoteIdentifierFormat('1234567890@relay.example.com:21117'),
      isTrue,
    );
  });

  test('online lookup is only used for rendezvous IDs', () {
    expect(kqRemoteIdentifierSupportsOnlineLookup('1234567890'), isTrue);
    expect(kqRemoteIdentifierSupportsOnlineLookup('device_01'), isTrue);
    expect(
        kqRemoteIdentifierSupportsOnlineLookup('192.168.1.2:21118'), isFalse);
    expect(
      kqRemoteIdentifierSupportsOnlineLookup('1234567890@server.example.com'),
      isFalse,
    );
  });

  test('lookup timeout does not block the native rendezvous connection', () {
    final source =
        File('lib/mobile/pages/connection_page.dart').readAsStringSync();
    expect(source, contains('if (online == false)'));
    expect(
        source, isNot(contains('if (online == null && supportsOnlineLookup)')));
    expect(source, isNot(contains('暂时无法核验识别码')));
  });

  test('mobile remote controls use one integrated mouse in both modes', () {
    final source = File('lib/mobile/pages/remote_page.dart').readAsStringSync();
    expect(source, contains('paints.add(FloatingMouse('));
    expect(source, isNot(contains('FloatingMouseWidgets(')));
    expect(source, isNot(contains('floating_mouse_widgets.dart')));
  });

  test(
      'mobile keyboard keeps a right-side hide action above the system keyboard',
      () {
    final source = File('lib/mobile/pages/remote_page.dart').readAsStringSync();

    expect(source, contains('void _hideSoftKeyboard()'));
    expect(source, contains('if (_softKeyboardActive) {'));
    expect(source, contains('icon: Icons.keyboard_hide'));
    expect(source,
        contains("label: kqLocaleText(zhCn: '收起键盘', en: 'Hide keyboard')"));
    expect(source, contains('bottom: keyboardInset + 12'));
    expect(source, contains('onPressed: _hideSoftKeyboard'));
    expect(
        source,
        contains(
            "SystemChannels.textInput.invokeMethod<void>('TextInput.hide')"));
  });

  test('auto disconnect settings explain the ten-minute minimum', () {
    final mobile =
        File('lib/mobile/pages/settings_page.dart').readAsStringSync();
    final desktop =
        File('lib/desktop/pages/desktop_setting_page.dart').readAsStringSync();
    final common = File('lib/common.dart').readAsStringSync();
    final dialog = File('lib/common/widgets/dialog.dart').readAsStringSync();

    expect(mobile, contains('autoDisconnectTimeoutSummaryText'));
    expect(mobile, contains('BoxFit.scaleDown'));
    expect(mobile, isNot(contains("} min'")));
    expect(desktop, contains('autoDisconnectTimeoutRangeText'));
    expect(common, contains('kAutoDisconnectTimeoutMinimumMinutes'));
    expect(common, contains('kAutoDisconnectTimeoutMaximumMinutes'));
    expect(common, contains('isAutoDisconnectTimeoutInRange'));
    expect(common, contains('normalizeAutoDisconnectTimeout'));
    expect(dialog, contains('isAutoDisconnectTimeoutInRange'));
    expect(dialog, contains('autoDisconnectTimeoutBoundsText'));
    expect(desktop, contains('isAutoDisconnectTimeoutInRange'));
    expect(desktop, contains('LengthLimitingTextInputFormatter(5)'));
  });

  test('visible action affordances do not use empty callbacks', () {
    final popupMenu =
        File('lib/desktop/widgets/popup_menu.dart').readAsStringSync();
    final peerCard =
        File('lib/common/widgets/peer_card.dart').readAsStringSync();
    final addressBook =
        File('lib/common/widgets/address_book.dart').readAsStringSync();
    final settings =
        File('lib/desktop/pages/desktop_setting_page.dart').readAsStringSync();

    expect(popupMenu, isNot(contains('onPressed: () {}')));
    expect(peerCard, contains('onTap: onTap'));
    expect(peerCard, contains('onTapDown: onTapDown'));
    expect(addressBook, contains('onTap: () => _showMenu(menuPos)'));
    expect(peerCard, contains('onTap: () => _showPeerMenu(peer.id)'));
    expect(settings, isNot(contains("keys: const ['auto']")));
  });

  test('desktop consumer assistance shares do not include credentials', () {
    String shareBody(String source, String nextMethod) {
      final start = source.indexOf('Future<void> _copyRemoteAssistShare');
      final end = source.indexOf(nextMethod, start);
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      return source.substring(start, end);
    }

    final home =
        File('lib/desktop/pages/desktop_home_page.dart').readAsStringSync();
    final settings =
        File('lib/desktop/pages/desktop_setting_page.dart').readAsStringSync();
    final homeShare = shareBody(home, 'String _kqPasswordKindLabel');
    final settingsShare =
        shareBody(settings, 'String _settingsPasswordKindLabel');

    for (final share in [homeShare, settingsShare]) {
      expect(share, contains('Device ID'));
      expect(share, contains('separately through a trusted channel'));
      expect(share, isNot(contains(r'$password')));
      expect(share, isNot(contains('base64UrlEncode')));
      expect(share, isNot(contains('_buildKqInviteLink')));
    }
  });

  test('desktop consumer settings exclude administrator-only controls', () {
    final settings =
        File('lib/desktop/pages/desktop_setting_page.dart').readAsStringSync();
    final permissionsStart = settings.indexOf('Widget permissions(context)');
    final permissionsEnd =
        settings.indexOf('Widget more(BuildContext context)', permissionsStart);
    final advancedStart =
        settings.indexOf('Widget _advancedNetworkReferenceCard');
    final advancedEnd =
        settings.indexOf('Widget network(BuildContext context)', advancedStart);

    expect(permissionsStart, greaterThanOrEqualTo(0));
    expect(permissionsEnd, greaterThan(permissionsStart));
    expect(advancedStart, greaterThanOrEqualTo(0));
    expect(advancedEnd, greaterThan(advancedStart));

    final permissions = settings.substring(permissionsStart, permissionsEnd);
    final advancedNetwork = settings.substring(advancedStart, advancedEnd);
    expect(permissions, isNot(contains('Enable terminal')));
    expect(permissions, isNot(contains('Enable TCP tunneling')));
    expect(permissions,
        isNot(contains('Enable remote configuration modification')));
    expect(advancedNetwork, contains('kOptionHideWebSocketSetting'));
  });

  test('mobile virtual mouse does not paint a duplicate local cursor', () {
    final remotePage =
        File('lib/mobile/pages/remote_page.dart').readAsStringSync();
    final floatingMouse =
        File('lib/mobile/widgets/floating_mouse.dart').readAsStringSync();

    expect(remotePage, contains('paints.add(CursorPaint(widget.id))'));
    expect(remotePage, contains('paints.add(FloatingMouse('));
    expect(floatingMouse, isNot(contains('class CursorPaint')));
    expect(floatingMouse, isNot(contains('_cursorPaintKey')));
  });

  test('remote cursor switch controls its mobile paint layer immediately', () {
    final remotePage =
        File('lib/mobile/pages/remote_page.dart').readAsStringSync();
    final toolbar = File('lib/common/widgets/toolbar.dart').readAsStringSync();

    expect(remotePage, contains('ShowRemoteCursorState.find(widget.id).value'));
    expect(remotePage, contains('? CursorPaint(widget.id)'));
    expect(remotePage, contains(': const SizedBox.shrink()'));
    expect(
        toolbar, contains('bool supportsRemoteCursorBroadcast(PeerInfo pi)'));
    expect(toolbar, contains('pi.platform != kPeerPlatformIOS'));
  });

  test('true color option is only shown for the supported VP9 codec', () {
    final toolbar = File('lib/common/widgets/toolbar.dart').readAsStringSync();
    expect(toolbar, contains('codec_format == "VP9"'));
    expect(toolbar, isNot(contains('codec_format == "AV1"')));
  });

  test('Android codec selection preserves the user preferred codec', () {
    final toolbar = File('lib/common/widgets/toolbar.dart').readAsStringSync();
    final client = File('../src/client.rs').readAsStringSync();
    final start = client.indexOf('pub fn get_supported_decoding(&self)');
    final end =
        client.indexOf('fn kq_force_h264_recording_supported_decoding', start);

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final supportedDecoding = client.substring(start, end);

    expect(toolbar, contains('name: kOptionCodecPreference, value: value'));
    expect(toolbar, contains('bind.sessionChangePreferCodec'));
    expect(supportedDecoding, contains('Some(&self.id)'));
    expect(supportedDecoding, contains('decoding.ability_av1 = 0;'));
    expect(
      supportedDecoding,
      contains('Self::apply_kq_default_codec_preference(&mut decoding);'),
    );
    expect(
      client,
      contains('#[cfg(target_os = "android")]\n'
          '    fn apply_kq_default_codec_preference'),
    );
    expect(
      client,
      contains('#[cfg(not(target_os = "android"))]\n'
          '    fn apply_kq_default_codec_preference'),
    );
  });

  test('Android hides AV1 while preserving it for other platforms', () {
    final toolbar = File('lib/common/widgets/toolbar.dart').readAsStringSync();
    final settings =
        File('lib/mobile/pages/settings_page.dart').readAsStringSync();

    expect(
      toolbar,
      contains("if (!isAndroid && codecs[1]) radio('AV1', 'av1', codecs[1])"),
    );
    expect(
      settings,
      contains("if (!isAndroid) _RadioEntry('AV1', 'av1')"),
    );
    expect(toolbar, contains("if (isAndroid && groupValue == 'av1')"));
    expect(
      toolbar,
      contains("name: kOptionCodecPreference, value: 'auto'"),
    );
    expect(settings, contains("if (isAndroid && value == 'av1')"));
  });

  test('Android hides the unreachable terminal extra keys setting', () {
    final settings =
        File('lib/mobile/pages/settings_page.dart').readAsStringSync();
    final labelIndex = settings.indexOf("'Show terminal extra keys'");

    expect(labelIndex, greaterThanOrEqualTo(0));
    final conditionStart = settings.lastIndexOf('if (', labelIndex);
    expect(conditionStart, greaterThanOrEqualTo(0));
    expect(
      settings.substring(conditionStart, labelIndex),
      contains('!isAndroid'),
    );
    expect(
      RegExp(
        r'mainSetLocalBoolOption\(\s*kOptionEnableShowTerminalExtraKeys, v\)',
      ).hasMatch(settings),
      isTrue,
      reason: 'Other platforms must retain the working terminal preference',
    );
  });

  test('Android view mode blocks every remote input sender', () {
    final inputModel = File('lib/models/input_model.dart').readAsStringSync();
    final remotePage =
        File('lib/mobile/pages/remote_page.dart').readAsStringSync();
    final toolbar = File('lib/common/widgets/toolbar.dart').readAsStringSync();

    expect(inputModel, contains('bool get _isAndroidInputBlocked'));
    for (final signature in [
      'void newKeyboardMode(',
      'void inputRawKey(',
      'void inputKey(',
      'Future<void> scroll(',
      'Future<void> _sendScrollMouseEvent(',
      'Future<void> sendMouse(',
      'Future<void> moveMouse(',
      'Future<void> sendMobileRelativeMouseMove(',
      'void handlePointerEvent(',
      'void onPointHoverImage(',
      'void onPointDownImage(',
      'void onPointUpImage(',
      'void onPointMoveImage(',
    ]) {
      final start = inputModel.indexOf(signature);
      expect(start, greaterThanOrEqualTo(0), reason: 'Missing $signature');
      final body = inputModel.substring(start, start + 500);
      expect(body, contains('if (_isAndroidInputBlocked) return;'),
          reason: '$signature must enforce Android view mode');
    }
    final handleMouseStart =
        inputModel.indexOf('Map<String, dynamic>? handleMouse(');
    expect(handleMouseStart, greaterThanOrEqualTo(0));
    expect(
      inputModel.substring(handleMouseStart, handleMouseStart + 500),
      contains('if (_isAndroidInputBlocked) return null;'),
    );
    expect(
      remotePage,
      contains('if (isAndroid && gFFI.ffiModel.viewOnly) return;'),
    );
    final panZoomEndStart = inputModel.indexOf('void onPointerPanZoomEnd(');
    expect(panZoomEndStart, greaterThanOrEqualTo(0));
    expect(
      inputModel.substring(panZoomEndStart, panZoomEndStart + 300),
      contains('if (_isAndroidInputBlocked) return;'),
    );
    expect(toolbar, contains('(!isAndroid || !ffiModel.viewOnly)'));
  });

  test('Android view mode hides remote system action entry points', () {
    final inputModel = File('lib/models/input_model.dart').readAsStringSync();
    final remotePage =
        File('lib/mobile/pages/remote_page.dart').readAsStringSync();
    final toolbar = File('lib/common/widgets/toolbar.dart').readAsStringSync();

    expect(
      toolbar,
      contains('final androidViewOnly = isAndroid && ffiModel.viewOnly;'),
    );
    for (final action in [
      "translate('Request Elevation')",
      "translate(pi.isHeadless ? 'OS Account' : 'OS Password')",
      "translate('Restart remote device')",
    ]) {
      final actionIndex = toolbar.indexOf(action);
      expect(actionIndex, greaterThanOrEqualTo(0), reason: 'Missing $action');
      final conditionStart = toolbar.lastIndexOf('if (', actionIndex);
      expect(conditionStart, greaterThanOrEqualTo(0));
      expect(
        toolbar.substring(conditionStart, actionIndex),
        contains('!androidViewOnly'),
        reason: '$action must be hidden in Android view mode',
      );
    }

    final mobileActionsStart =
        remotePage.indexOf('List<TTextMenu> _getMobileActionMenus()');
    expect(mobileActionsStart, greaterThanOrEqualTo(0));
    expect(
      remotePage.substring(mobileActionsStart, mobileActionsStart + 400),
      contains('if (isAndroid && gFFI.ffiModel.viewOnly) return [];'),
    );
    final openKeyboardStart = remotePage.indexOf('void openKeyboard()');
    expect(openKeyboardStart, greaterThanOrEqualTo(0));
    expect(
      remotePage.substring(openKeyboardStart, openKeyboardStart + 250),
      contains('if (isAndroid && gFFI.ffiModel.viewOnly) return;'),
    );
    expect(inputModel, contains('bool get _isAndroidInputBlocked'));
  });

  test('Android applies the effective reverse mouse wheel preference once', () {
    final session = File('../src/ui_session_interface.rs').readAsStringSync();
    final inputModel = File('lib/models/input_model.dart').readAsStringSync();

    expect(inputModel, contains('_sendScrollMouseEvent('));
    expect(inputModel, isNot(contains('_kqAndroidReverseMouseWheel')));
    expect(inputModel,
        contains('bind.sessionGetReverseMouseWheelSync(sessionId: sessionId)'));
    expect(inputModel,
        contains('bind.mainGetUserDefaultOption(key: kKeyReverseMouseWheel)'));
    expect(
      session,
      contains('#[cfg(not(any(target_os = "android", target_os = "ios")))]\n'
          '    fn get_scroll_xy'),
    );
  });

  test('Android resumes remote audio playback when mute is disabled', () {
    final client = File('../src/client.rs').readAsStringSync();
    final formatStart = client.indexOf('pub fn handle_format(&mut self');
    final frameStart = client.indexOf('pub fn handle_frame(&mut self');
    final ioLoop = File('../src/client/io_loop.rs').readAsStringSync();

    expect(formatStart, greaterThanOrEqualTo(0));
    expect(frameStart, greaterThan(formatStart));
    final handleFormat = client.substring(formatStart, frameStart);
    expect(handleFormat, contains('AudioDecoder::new'));
    expect(handleFormat, contains('allow_err!(self.start_audio(f));'));
    expect(handleFormat,
        isNot(contains('KQ Android skips remote audio playback')));
    expect(
        ioLoop, contains('!self.handler.lc.read().unwrap().disable_audio.v'));
  });

  test('mobile view-only changes synchronize through the shared session path',
      () {
    final flutter = File('../src/flutter.rs').readAsStringSync();
    final syncStart = flutter.indexOf('pub fn try_sync_peer_option(');
    final syncEnd = flutter.indexOf(
        'pub(super) fn session_update_virtual_display', syncStart);

    expect(syncStart, greaterThanOrEqualTo(0));
    expect(syncEnd, greaterThan(syncStart));
    final sync = flutter.substring(syncStart, syncEnd);
    expect(sync, contains('if key == "view-only" {'));
    expect(
        sync,
        isNot(contains(
            '#[cfg(not(any(target_os = "android", target_os = "ios")))]')));
    expect(sync, contains('session.push_event("sync_peer_option"'));
  });

  test('mobile display options refresh after changing view-only mode', () {
    final page = File('lib/mobile/pages/remote_page.dart').readAsStringSync();
    final toolbar = File('lib/common/widgets/toolbar.dart').readAsStringSync();
    final optionsStart = page.indexOf('void showOptions(');
    final optionsEnd = page.indexOf('class _RemoteOptionSection', optionsStart);

    expect(optionsStart, greaterThanOrEqualTo(0));
    expect(optionsEnd, greaterThan(optionsStart));
    final options = page.substring(optionsStart, optionsEnd);
    expect(options, contains('Future<void> refreshToggleMenus() async {'));
    expect(options, contains('await refreshToggleMenus();'));
    expect(toolbar, contains('ffiModel.setViewOnly(id, value);'));
    expect(toolbar, contains('await bind.sessionToggleOption('));
  });

  test('mobile display switches wait for their native action before reloading',
      () {
    final page = File('lib/mobile/pages/remote_page.dart').readAsStringSync();
    final optionsStart = page.indexOf('void showOptions(');
    final optionsEnd = page.indexOf('class _RemoteOptionSection', optionsStart);

    expect(optionsStart, greaterThanOrEqualTo(0));
    expect(optionsEnd, greaterThan(optionsStart));
    final options = page.substring(optionsStart, optionsEnd);
    expect(options, contains('await onChanged?.call(value);'));
    expect(
        options,
        isNot(contains(
            'onChanged?.call(value);\n                                      unawaited(refreshToggleMenus());')));
  });

  test('mobile screen settings initialize and identify cursor switches', () {
    final page = File('lib/mobile/pages/remote_page.dart').readAsStringSync();
    final toolbar = File('lib/common/widgets/toolbar.dart').readAsStringSync();

    expect(page, contains("arg: 'show-remote-cursor'"));
    expect(page, contains('ShowRemoteCursorState.find(widget.id).value ='));
    expect(page, contains("ValueKey('cursor-\${cursorToggles[index].id}')"));
    expect(page, contains("'display-\${displayToggles[index].id}'"));
    expect(
        toolbar, contains('final FutureOr<void> Function(bool?)? onChanged;'));
    expect(toolbar, contains("id: 'show-remote-cursor'"));
    expect(toolbar, contains("id: 'show-quality-monitor'"));
  });

  test('mobile long labels use adaptive navigation and membership layout', () {
    final home = File('lib/mobile/pages/home_page.dart').readAsStringSync();
    final account =
        File('lib/mobile/pages/account_page.dart').readAsStringSync();
    expect(home, contains('NavigationDestinationLabelBehavior.alwaysShow'));
    expect(account, contains('maxLines: 2'));
    expect(account, contains('width: double.infinity'));
  });

  test('connection-end notes are audit-only while manual peer notes remain',
      () {
    final dialog = File('lib/common/widgets/dialog.dart').readAsStringSync();
    final settings =
        File('lib/mobile/pages/settings_page.dart').readAsStringSync();
    final peerCard =
        File('lib/common/widgets/peer_card.dart').readAsStringSync();

    expect(dialog, contains('final hasAuditContext ='));
    expect(dialog, contains('hasAuditContext &&'));
    expect(dialog, isNot(contains('supportsLocalMobileNote')));
    expect(dialog, isNot(contains('bind.mainSetPeerAlias(id: ffi.id')));
    expect(settings, isNot(contains('_allowAskForNoteAtEndOfConnection')));
    expect(settings, isNot(contains('note-at-conn-end-tip')));
    expect(peerCard, contains("translate('Edit note')"));
    expect(peerCard, contains('bind.mainSetPeerAlias'));
  });

  test(
      'mobile peer timeout gives the first session packet the normal grace period',
      () {
    final ioLoop = File('../src/client/io_loop.rs').readAsStringSync();
    expect(ioLoop, contains('KQ_MOBILE_PEER_TIMEOUT'));
    expect(ioLoop, contains('KQ_MOBILE_INITIAL_PEER_TIMEOUT'));
    expect(ioLoop, contains('Duration::from_secs(5)'));
    expect(
        ioLoop,
        contains(
            'kq_mobile_peer_timed_out(received, last_recv_time.elapsed())'));
  });

  test('iOS broadcast registration has a visible timeout state', () {
    final rust = File('../src/ios_broadcast.rs').readAsStringSync();
    final swift =
        File('ios/KQScreenBroadcast/SampleHandler.swift').readAsStringSync();
    final page = File('lib/mobile/pages/server_page.dart').readAsStringSync();
    expect(rust, contains('REGISTRATION_TIMEOUT_MS: i64 = 30_000'));
    expect(rust, contains('REGISTRATION_TIMED_OUT'));
    expect(swift, contains('server_registration_timeout'));
    expect(page, contains('设备接入服务超时'));
  });

  test('idle remote video does not force a remote capture restart', () {
    final ioLoop = File('../src/client/io_loop.rs').readAsStringSync();
    expect(ioLoop, isNot(contains('KQ_STALLED_VIDEO_REFRESH_TICKS')));
    expect(ioLoop, isNot(contains('kq_refresh_stalled_zero_fps_displays')));
    expect(
        ioLoop, isNot(contains('KQ video idle/stalled; refreshing display')));
  });

  test('iOS viewport changes repaint locally without restarting remote capture',
      () {
    final remotePage =
        File('lib/mobile/pages/remote_page.dart').readAsStringSync();
    final refreshStart = remotePage.indexOf('void _refreshIOSRemoteVideo');
    final refreshEnd =
        remotePage.indexOf('void _scheduleOrientationRefresh', refreshStart);
    final refresh = remotePage.substring(refreshStart, refreshEnd);

    expect(refreshStart, greaterThanOrEqualTo(0));
    expect(refreshEnd, greaterThan(refreshStart));
    expect(refresh, contains('gFFI.imageModel.requestRepaint()'));
    expect(refresh, isNot(contains('sessionRefreshVideo')));
  });

  test(
      'Windows portable capture refresh forces the service to recreate with GDI',
      () {
    final portable =
        File('../src/server/portable_service.rs').readAsStringSync();
    final videoService =
        File('../src/server/video_service.rs').readAsStringSync();

    expect(portable, contains('force_gdi: bool'));
    expect(portable, contains('force_gdi: true'));
    expect(portable, contains('KQ portable capture: forcing GDI recreation'));
    expect(portable,
        contains('KQ portable capture: recreated capture with forced GDI'));

    final refreshStart =
        videoService.indexOf('if refresh_requested && vs.source.is_monitor()');
    final refreshEnd = videoService.indexOf('let mut video_qos', refreshStart);
    final refresh = videoService.substring(refreshStart, refreshEnd);
    expect(refreshStart, greaterThanOrEqualTo(0));
    expect(refreshEnd, greaterThan(refreshStart));
    expect(refresh, contains('c.set_gdi()'));
    expect(refresh, isNot(contains('!c.is_gdi()')));
  });

  test('Windows main-window close keeps the portable service alive', () {
    final tabbar =
        File('lib/desktop/widgets/tabbar_widget.dart').readAsStringSync();
    final connection =
        File('lib/desktop/pages/connection_page.dart').readAsStringSync();

    expect(tabbar,
        contains('mainWindowClose() async => await windowManager.hide()'));
    expect(connection, isNot(contains('bind.mainOnMainWindowClose();')));
  });

  test('Windows video recovery logs every refresh boundary', () {
    final connection = File('../src/server/connection.rs').readAsStringSync();
    final videoService =
        File('../src/server/video_service.rs').readAsStringSync();
    final portable =
        File('../src/server/portable_service.rs').readAsStringSync();

    expect(connection, contains('KQ video refresh command received'));
    expect(videoService, contains('KQ video refresh requested:'));
    expect(videoService, contains('KQ video refresh recovery:'));
    expect(portable, contains('KQ portable capture: forcing GDI recreation'));
    expect(
        portable,
        contains(
            'KQ portable capture: forced recreation produced first frame'));
  });

  test('quality monitor does not show fake zero delay for stalled video', () {
    final model = File('lib/models/model.dart').readAsStringSync();
    final overlay = File('lib/common/widgets/overlay.dart').readAsStringSync();
    expect(model, contains('hasActiveVideoFrames'));
    expect(model, contains('displayDelay'));
    expect(overlay, contains('qualityMonitorModel.data.displayDelay'));
    expect(overlay, isNot(contains('let delay be 0 if fps is 0')));
  });
}
