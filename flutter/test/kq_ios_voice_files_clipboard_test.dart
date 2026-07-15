import 'dart:io';

import 'package:flutter_hbb/models/mobile_voice_call_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('voice close reasons are presented in readable Chinese', () {
    expect(mobileVoiceCallClosedMessage('End connection'), isNull);
    expect(mobileVoiceCallClosedMessage(''), isNull);
    expect(
      mobileVoiceCallClosedMessage('voice call closed by peer'),
      '对方已结束语音通话',
    );
    expect(
      mobileVoiceCallClosedMessage('rejected by peer'),
      '对方拒绝了语音通话',
    );
    expect(
      mobileVoiceCallClosedMessage('peer is busy'),
      '对方正在通话中，请稍后重试',
    );
    expect(
      mobileVoiceCallClosedMessage('request timeout'),
      '对方未接听，请稍后重试',
    );
    expect(
      mobileVoiceCallClosedMessage('microphone permission denied'),
      '无法使用麦克风，请检查系统权限后重试',
    );
    expect(
      mobileVoiceCallClosedMessage('failed to start voice call'),
      '语音通话未能开始，请稍后重试',
    );
  });

  test('iOS remote page requests microphone permission before calling', () {
    final source =
        File('lib/mobile/pages/remote_page.dart').readAsStringSync();
    expect(source, contains("MethodChannel('mChannel')"));
    expect(source, contains("'request_microphone_permission'"));
    expect(source,
        contains('isIOS || (isAndroid && isSupportVoiceCall)'));
    expect(
      source.indexOf('await _ensureMobileVoicePermission()'),
      lessThan(source.indexOf('bind.sessionRequestVoiceCall')),
    );
  });

  test('iOS native channel exposes microphone authorization', () {
    final source = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(source, contains('import AVFoundation'));
    expect(source, contains('case "request_microphone_permission"'));
    expect(source, contains('requestRecordPermission'));
    expect(source, contains('case "start_ios_voice_capture"'));
    expect(source, contains('case "stop_ios_voice_capture"'));
    expect(source, contains('kq_ios_voice_call_audio('));
    expect(source, contains('voiceAudioQueue.async'));
    expect(source, isNot(contains('NSLock()')));
  });

  test('Rust reports voice start failure, rejection, and remote hangup', () {
    final source = File('../src/client/io_loop.rs').readAsStringSync();
    expect(source, contains('"Failed to start voice call"'));
    expect(source, contains('"Voice call rejected by peer"'));
    expect(source, contains('"Voice call closed by peer"'));
    expect(
      source.indexOf('self.start_voice_call()'),
      lessThan(source.indexOf('self.handler.on_voice_call_started()')),
    );
  });

  test('iOS keeps file transfer and incoming clipboard paths available', () {
    final connection =
        File('lib/mobile/pages/connection_page.dart').readAsStringSync();
    final model = File('lib/models/model.dart').readAsStringSync();
    expect(connection, contains('isFileTransfer: true'));
    expect(connection, isNot(contains('isAndroid && isFileTransfer')));
    expect(model, contains('Clipboard.setData('));
  });
}
