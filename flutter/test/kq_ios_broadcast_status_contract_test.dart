import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ReplayKit publishes capture and remote-view states separately', () {
    final handler =
        File('ios/KQScreenBroadcast/SampleHandler.swift').readAsStringSync();
    final bridge =
        File('ios/KQScreenBroadcast/KQBroadcastBridge.h').readAsStringSync();
    final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(handler, contains('kq_broadcast_transport_state'));
    expect(handler, contains('kq_broadcast_remote_view_available'));
    expect(handler, contains('kq_broadcast_remote_viewer_count'));
    expect(handler, contains('kq_ios_broadcast_push_bgra'));
    expect(handler, contains('kq_ios_broadcast_push_audio_f32'));
    expect(handler, contains('kq_ios_broadcast_active_viewer_count'));
    expect(bridge, contains('kq_ios_broadcast_active_viewer_count'));
    expect(handler, contains('kq_ios_broadcast_start'));
    expect(handler, contains('CMSampleBufferCopyPCMDataIntoAudioBufferList'));
    expect(handler, contains('AVAudioConverter'));
    expect(
      handler,
      contains(
        'let inputFormat = AVAudioFormat(cmAudioFormatDescription: description)',
      ),
    );
    expect(
      handler,
      isNot(
        contains(
          'let inputFormat = AVAudioFormat(cmAudioFormatDescription: description) else',
        ),
      ),
    );
    expect(
        handler,
        contains(
            'defaults.set(audioForwardingActive, forKey: "kq_broadcast_audio_supported")'));
    expect(handler, isNot(contains('capture_only')));
    expect(
      handler,
      isNot(contains(
          'defaults.set(false, forKey: "kq_broadcast_remote_view_available")')),
    );
    expect(delegate, contains('"transportState"'));
    expect(delegate, contains('"remoteViewAvailable"'));
    expect(delegate, contains('"remoteViewerCount"'));
    expect(delegate, contains('"viewOnly": true'));
    expect(delegate, contains('"errorCode"'));
  });

  test('iOS starts rendezvous registration when the broadcast starts', () {
    final handler =
        File('ios/KQScreenBroadcast/SampleHandler.swift').readAsStringSync();
    final broadcastStart = handler.indexOf('override func broadcastStarted');
    final broadcastPause = handler.indexOf('override func broadcastPaused');

    expect(broadcastStart, greaterThanOrEqualTo(0));
    expect(broadcastPause, greaterThan(broadcastStart));

    final startHandler = handler.substring(broadcastStart, broadcastPause);
    expect(startHandler, contains('guard startTransportIfNeeded() else'));
    expect(startHandler, contains('transportState: "registering"'));
    expect(handler, contains('private func startTransportIfNeeded() -> Bool'));
  });

  test('iOS broadcast requires a fresh rendezvous confirmation before ready',
      () {
    final native = File('../src/ios_broadcast.rs').readAsStringSync();
    final handler =
        File('ios/KQScreenBroadcast/SampleHandler.swift').readAsStringSync();
    final bridge =
        File('ios/KQScreenBroadcast/KQBroadcastBridge.h').readAsStringSync();
    final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(native, contains('Config::set_key_confirmed(false);'));
    expect(
      native,
      contains(
          'pub extern "C" fn kq_ios_broadcast_registration_state() -> i32'),
    );
    expect(bridge, contains('kq_ios_broadcast_registration_state'));
    expect(handler, contains('kq_ios_broadcast_registration_state()'));
    expect(handler, contains('kq_broadcast_registration_state'));
    expect(delegate, contains('"registrationState"'));
  });

  test('iOS UI keeps the broadcast entry compact and user-facing', () {
    final page = File('lib/mobile/pages/server_page.dart').readAsStringSync();

    expect(page, contains("invokeMethod<bool>('show_broadcast_picker')"));
    expect(
        page,
        contains(
            "invokeMethod<Map<dynamic, dynamic>>('get_broadcast_status')"));
    expect(page, contains('Timer.periodic'));
    expect(page, contains('addPostFrameCallback'));
    expect(page, contains('_openBroadcastPickerWhenNeeded'));
    expect(page, contains('等待系统确认'));
    expect(page, contains('可连接'));
    expect(page, isNot(contains("zhCn: '启动'")));
    expect(page, isNot(contains('打开系统广播')));
    expect(page, isNot(contains('电脑和手机连接方式')));
    expect(page, isNot(contains('采集状态')));
    expect(page, isNot(contains('视频帧')));
    expect(page, isNot(contains('传输模式')));
    expect(page, isNot(contains('当前版本先验证采集链路')));
  });

  test('iOS broadcast keeps the standard device credentials card', () {
    final page = File('lib/mobile/pages/server_page.dart').readAsStringSync();
    final iosStart = page
        .indexOf('if (mobilePlatformCapabilities.canHostViewOnlyBroadcast)');
    final iosEnd = page.indexOf('    checkService();', iosStart);
    final broadcastStart =
        page.indexOf('class _IOSScreenShareBroadcastMvpState');
    final broadcastEnd =
        page.indexOf('class _IOSScreenShareUnavailable', broadcastStart);

    expect(iosStart, greaterThanOrEqualTo(0));
    expect(iosEnd, greaterThan(iosStart));
    expect(broadcastStart, greaterThanOrEqualTo(0));
    expect(broadcastEnd, greaterThan(broadcastStart));

    final iosBranch = page.substring(iosStart, iosEnd);
    final broadcastPage = page.substring(broadcastStart, broadcastEnd);
    expect(iosBranch, contains('ChangeNotifierProvider.value'));
    expect(iosBranch, contains('child: const _IOSScreenShareBroadcastMvp()'));
    expect(broadcastPage, contains('ServerInfo('));
    expect(broadcastPage, contains('connectionStatusTextOverride'));
    expect(broadcastPage, contains('_connectionAvailabilityText'));
    expect(broadcastPage, contains('屏幕共享'));
  });
}
