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

  test('iOS UI reports real view-only transport without internal errors', () {
    final page = File('lib/mobile/pages/server_page.dart').readAsStringSync();

    expect(page, contains("_status['remoteViewAvailable']"));
    expect(page, contains("_status['remoteViewerCount']"));
    expect(page, contains("_status['errorCode']"));
    expect(page, contains('共享已启动，等待其他设备连接'));
    expect(page, contains('已有设备正在观看'));
    expect(page, isNot(contains('可以连接观看')));
    expect(page, contains('仅支持观看'));
    expect(page, contains('打开系统广播面板'));
    expect(page, contains('正在传输画面和应用声音'));
    expect(page, isNot(contains('远程观看服务尚未接入')));
    expect(page, isNot(contains('Service not connected')));
    expect(page, isNot(contains('capture_only')));
    expect(page, isNot(contains('当前版本先验证采集链路')));
    expect(page, isNot(contains('开始屏幕共享')));
  });
}
