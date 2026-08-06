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

  test('mobile zero-fps video stall requests a stream refresh', () {
    final ioLoop = File('../src/client/io_loop.rs').readAsStringSync();
    final videoService = File('../src/server/video_service.rs').readAsStringSync();
    expect(ioLoop, contains('KQ_STALLED_VIDEO_REFRESH_TICKS'));
    expect(ioLoop, contains('kq_refresh_stalled_zero_fps_displays'));
    expect(ioLoop, contains('last_frame_instant'));
    expect(ioLoop, contains('last_seen_frame_instant'));
    expect(ioLoop, isNot(contains('KQ_STALLED_VIDEO_REFRESH_MAX_TIMES')));
    expect(ioLoop, contains('KQ video idle/stalled; refreshing display'));
    expect(ioLoop, contains('KQ_STALLED_VIDEO_CODEC_RENEGOTIATE_EVERY'));
    expect(ioLoop,
        contains('KQ video idle/stalled; renegotiating supported decodings'));
    expect(ioLoop, contains('self.kq_refresh_stalled_zero_fps_displays()'));
    expect(ioLoop, contains('v.video_sender.send(MediaData::Reset).ok();'));
    expect(videoService,
        contains('KQ video refresh recovery: forcing fresh GDI capture'));
    expect(videoService, contains('let refresh_requested = sp.is_option_true(OPTION_REFRESH);'));
  });

  test('stalled video recovery keeps the current remote session open', () {
    final ioLoop = File('../src/client/io_loop.rs').readAsStringSync();
    final recoveryStart =
        ioLoop.indexOf('fn kq_refresh_stalled_zero_fps_displays(&mut self)');
    final recoveryEnd =
        ioLoop.indexOf('fn check_view_camera_support', recoveryStart);
    final recovery = ioLoop.substring(recoveryStart, recoveryEnd);

    expect(recoveryStart, greaterThanOrEqualTo(0));
    expect(recoveryEnd, greaterThan(recoveryStart));
    expect(recovery, isNot(contains('reconnect(')));
    expect(recovery,
        isNot(contains('KQ_STALLED_VIDEO_RECONNECT_AFTER_REFRESHES')));
  });

  test('stalled video recovery falls back to legacy full-stream refresh', () {
    final ioLoop = File('../src/client/io_loop.rs').readAsStringSync();
    final recoveryStart =
        ioLoop.indexOf('fn kq_refresh_stalled_zero_fps_displays(&mut self)');
    final recoveryEnd = ioLoop.indexOf('fn check_view_camera_support', recoveryStart);
    final recovery = ioLoop.substring(recoveryStart, recoveryEnd);

    expect(recoveryStart, greaterThanOrEqualTo(0));
    expect(recoveryEnd, greaterThan(recoveryStart));
    expect(recovery, contains('client::LoginConfigHandler::refresh()'));
    expect(recovery,
        contains('KQ video idle/stalled; issuing legacy full-stream refresh'));
  });

  test('Windows portable capture refresh forces the service to recreate with GDI',
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

  test('quality monitor does not show fake zero delay for stalled video', () {
    final model = File('lib/models/model.dart').readAsStringSync();
    final overlay = File('lib/common/widgets/overlay.dart').readAsStringSync();
    expect(model, contains('hasActiveVideoFrames'));
    expect(model, contains('displayDelay'));
    expect(overlay, contains('qualityMonitorModel.data.displayDelay'));
    expect(overlay, isNot(contains('let delay be 0 if fps is 0')));
  });
}
