import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS voice UI is driven by native audio levels and transport frames',
      () {
    final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final handler =
        File('ios/KQScreenBroadcast/SampleHandler.swift').readAsStringSync();
    final bridge = File('../src/ios_voice_call.rs').readAsStringSync();
    final server = File('../src/server/connection.rs').readAsStringSync();
    final page = File('lib/mobile/pages/server_page.dart').readAsStringSync();

    expect(delegate, contains('get_ios_voice_call_metrics'));
    expect(delegate, contains('normalizedIOSVoiceLevel'));
    expect(delegate, contains('voicePlaybackFormat'));
    expect(delegate, contains('publishIOSVoiceOutputLevel(normalized)'));
    expect(delegate, contains('startIOSHostVoiceCaptureWhenActive'));
    expect(handler, contains('publishMicrophoneLevel'));
    expect(handler, contains('kq_ios_broadcast_voice_frames_sent'));
    expect(bridge, contains('record_host_voice_frame_sent'));
    expect(bridge, contains('record_peer_voice_frame_received'));
    expect(bridge, contains('for attempt in 0..2'));
    expect(server, contains('record_host_voice_frame_sent'));
    expect(server, contains('record_peer_voice_frame_received'));
    expect(page, contains('_IOSVoiceLevelIndicator'));
    expect(page, contains('AnimatedContainer'));
    expect(page, contains('Icons.call_end_rounded'));
  });

  test('mobile remote actions use a safe-area bottom sheet', () {
    final page = File('lib/mobile/pages/remote_page.dart').readAsStringSync();
    final start = page.indexOf('void showActions(String id) async');
    final end = page.indexOf('showChatOptions(String id) async', start);

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final actions = page.substring(start, end);
    expect(actions, contains('showModalBottomSheet<int>'));
    expect(actions, contains('useSafeArea: true'));
    expect(actions, contains('ListView.separated'));
    expect(actions, isNot(contains('showMenu(')));
  });

  test('Android remote rail uses the redesigned mobile panels', () {
    final page = File('lib/mobile/pages/remote_page.dart').readAsStringSync();
    final start = page.indexOf('Widget _remoteSideActionRail()');
    final end = page.indexOf('Widget _remoteSideActionButton(', start);

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final rail = page.substring(start, end);
    expect(rail, contains('showOptions(context, widget.id'));
    expect(rail, contains('showActions(widget.id)'));
    expect(rail, isNot(contains('if (isIOS)')));
  });

  test('mobile display settings use compact grouped controls', () {
    final page = File('lib/mobile/pages/remote_page.dart').readAsStringSync();
    final start = page.indexOf('void showOptions(');
    final end = page.indexOf('TTextMenu? getVirtualDisplayMenu', start);

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final options = page.substring(start, end);
    expect(options, contains('showModalBottomSheet<void>'));
    expect(options, contains('useSafeArea: true'));
    expect(options, contains('_RemoteOptionSegments<String>'));
    expect(options, contains('_RemoteOptionToggle'));
    expect(options, isNot(contains('CustomAlertDialog(')));
    expect(options, isNot(contains('getRadio<String>(')));
  });
}
