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
    final source = File('lib/mobile/pages/remote_page.dart').readAsStringSync();
    expect(source, contains("MethodChannel('mChannel')"));
    expect(source, contains("'request_microphone_permission'"));
    expect(source, contains('isIOS || (isAndroid && isSupportVoiceCall)'));
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

  test('iOS voice call responder confirms microphone access before accepting',
      () {
    final native = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final page = File('lib/mobile/pages/server_page.dart').readAsStringSync();
    final responseStart = native.indexOf('private func respondToIOSVoiceCall');
    final responseEnd = native.indexOf('private func getIOSVoiceCallState');

    expect(responseStart, greaterThanOrEqualTo(0));
    expect(responseEnd, greaterThan(responseStart));
    expect(
      native.substring(responseStart, responseEnd),
      contains('withMicrophonePermission'),
    );
    expect(native, contains('startIOSVoiceCallInvitationMonitor'));
    expect(native, contains('monitorIOSVoiceCallInvitation'));
    expect(page, isNot(contains('_checkPendingIOSVoiceCall')));
  });

  test('iOS recovers its invitation state when an alert cannot be shown', () {
    final native = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final monitorStart =
        native.indexOf('@objc private func monitorIOSVoiceCallInvitation');
    final presenterStart =
        native.indexOf('private func voiceInvitationPresenter');

    expect(monitorStart, greaterThanOrEqualTo(0));
    expect(presenterStart, greaterThan(monitorStart));
    final monitor = native.substring(monitorStart, presenterStart);
    expect(monitor, contains('!isPendingIOSVoiceCallRequest(requestId)'));
    expect(monitor, contains('Failed to present iOS voice call invitation'));
    expect(monitor, contains('Timed out presenting iOS voice call invitation'));
  });

  test('iOS accepts independently of fallback capture and keeps two-way audio',
      () {
    final native = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final responseStart =
        native.indexOf('private func finishIOSVoiceCallResponse');
    final responseEnd = native.indexOf('private func getIOSVoiceCallState');
    final playbackStart = native.indexOf('private func startIOSVoicePlayback');
    final playbackEnd = native.indexOf('private func stopIOSVoicePlayback()');

    expect(responseStart, greaterThanOrEqualTo(0));
    expect(responseEnd, greaterThan(responseStart));
    final response = native.substring(responseStart, responseEnd);
    expect(response, contains('startIOSBroadcastHostVoiceCapture()'));
    expect(response, contains('"accepted": accepted'));
    expect(response, isNot(contains('"accepted": responseAccepted')));
    expect(
        response,
        contains(
            'iOS host recorder unavailable; using ReplayKit microphone'));
    expect(playbackStart, greaterThanOrEqualTo(0));
    expect(playbackEnd, greaterThan(playbackStart));
    final playback = native.substring(playbackStart, playbackEnd);
    expect(playback, contains('stopCapture: false'));
    expect(playback, contains('.playAndRecord'));
    expect(playback, contains('.voiceChat'));
    expect(native, contains('picker.showsMicrophoneButton = true'));
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
    final fileManager =
        File('lib/mobile/pages/file_manager_page.dart').readAsStringSync();
    expect(connection, contains('isFileTransfer: true'));
    expect(connection, isNot(contains('isAndroid && isFileTransfer')));
    expect(model, contains('Clipboard.setData('));
    expect(fileManager, contains('widget.selectMode.value ='));
    expect(fileManager, contains('_selectedItems.add(entries[index])'));
  });
}
