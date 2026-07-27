import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _section(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  final endIndex = source.indexOf(end, startIndex + start.length);
  expect(startIndex, greaterThanOrEqualTo(0), reason: 'Missing start: $start');
  expect(endIndex, greaterThan(startIndex), reason: 'Missing end: $end');
  return source.substring(startIndex, endIndex);
}

void main() {
  test('iOS broadcast picker waits for layout before triggering system UI', () {
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final method = _section(
      appDelegate,
      'private func showBroadcastPicker(result: @escaping FlutterResult) {',
      'private func getBroadcastStatus(result: @escaping FlutterResult) {',
    );

    expect(method, contains('DispatchQueue.main.async'));
    expect(method, contains('layoutIfNeeded()'));
    expect(method, contains('findBroadcastPickerButton'));
    expect(method, contains('sendActions(for: .allTouchEvents)'));
    expect(method, contains('DispatchQueue.main.asyncAfter'));
    expect(method, isNot(contains('picker.alpha = 0.01')));
  });

  test('iOS broadcast picker reports simulator unavailability visibly', () {
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final method = _section(
      appDelegate,
      'private func showBroadcastPicker(result: @escaping FlutterResult) {',
      'private func getBroadcastStatus(result: @escaping FlutterResult) {',
    );

    expect(method, contains('#if targetEnvironment(simulator)'));
    expect(method, contains('ios_simulator_unavailable'));

    final serverPage =
        File('lib/mobile/pages/server_page.dart').readAsStringSync();
    final openPicker = _section(
      serverPage,
      'Future<void> _openBroadcastPicker() async {',
      '@override\n  Widget build(BuildContext context)',
    );
    expect(openPicker, contains('on PlatformException catch (e)'));
    expect(openPicker, contains("e.code == 'ios_simulator_unavailable'"));
    expect(openPicker, contains('iOS 模拟器不支持系统屏幕直播'));
  });

  test('iOS share screen card uses a concrete page icon', () {
    final serverPage =
        File('lib/mobile/pages/server_page.dart').readAsStringSync();
    final header = _section(
      serverPage,
      'width: 46,',
      "_DeviceSecretTile(",
    );
    final sharingButton = _section(
      serverPage,
      'SizedBox(\n              width: double.infinity,\n              height: 48,',
      'if (sharingErrorText != null)',
    );

    expect(header, contains('Icons.mobile_screen_share_rounded'));
    expect(header, contains('height: 46'));
    expect(header, isNot(contains("Image.asset('assets/logo.png'")));
    expect(sharingButton, contains('ElevatedButton.icon'));
    expect(sharingButton, contains('backgroundColor:'));
  });
}
