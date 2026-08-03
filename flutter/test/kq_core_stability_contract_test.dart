import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  test('iOS incoming voice controls use the native App Group bridge', () {
    final serverModel = _read('lib/models/server_model.dart');
    final serverPage = _read('lib/mobile/pages/server_page.dart');

    expect(serverModel, contains("'get_pending_ios_voice_call'"));
    expect(serverModel, contains("'respond_to_ios_voice_call'"));
    expect(serverModel, contains("'end_ios_voice_call'"));
    expect(serverPage, contains('voiceCallPrompt:'));
    expect(serverPage, contains('!isIOS &&'));
    expect(serverPage, contains('closeVoiceCall(client)'));
  });

  test('KQ first-frame timeout remains recoverable', () {
    final model = _read('lib/models/model.dart');
    final timer = model.substring(
      model.indexOf('waitForImageTimeoutTimer?.cancel();'),
      model.indexOf('bind.sessionOnWaitingForImageDialogShow',
          model.indexOf('waitForImageTimeoutTimer?.cancel();')),
    );

    expect(timer, contains('_showWaitingForImageTimeout'));
    expect(timer, isNot(contains('KQ_VIDEO_FIRST_FRAME_TIMEOUT')));
  });

  test('receiver renders the negotiated quality instead of artificial blur',
      () {
    final remotePage = _read('lib/mobile/pages/remote_page.dart');
    final policy = _read('lib/models/remote_video_quality_policy.dart');

    expect(policy, contains('kqStandardRemoteMaxFrameHeight = 480'));
    expect(policy, contains('kqHighDefinitionRemoteMaxFrameHeight = 1080'));
    expect(remotePage, isNot(contains('kqStandardRemoteBlurSigma')));
    expect(remotePage, isNot(contains('blurSigma: blurSigma')));
  });

  test('desktop verification code preserves exact case', () {
    final source = _read('lib/desktop/pages/connection_page.dart');
    expect(
        source, contains('final password = _passwordController.text.trim();'));
    expect(source,
        isNot(contains('_passwordController.text.trim().toLowerCase()')));
  });

  test('membership cards distinguish lifetime purchases from subscriptions',
      () {
    final source = _read('lib/mobile/pages/ios_membership_purchase_page.dart');
    expect(source, contains('memberPackage?.days'));
    expect(source, contains('一次性购买，永久有效'));
    expect(source, contains('自动续订'));
  });

  test('app-level membership refresh is lifecycle and timer driven', () {
    final source = _read('lib/main.dart');
    expect(source, contains('didChangeAppLifecycleState'));
    expect(source, contains('refreshMembership'));
    expect(source, contains('Timer.periodic'));
  });

  test('block-input action is not exposed in the toolbar menu', () {
    final toolbar = _read('lib/common/widgets/toolbar.dart');
    expect(toolbar, isNot(contains('// blockUserInput')));
    expect(toolbar, isNot(contains("'block-input'")));
  });
}
