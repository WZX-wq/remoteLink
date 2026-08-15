import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  test(
      'Android permission request creates its waiter before invoking native code',
      () {
    final common = _read('lib/common.dart');
    final requestStart =
        common.indexOf('static Future<bool> request(String type)');
    final requestEnd = common.indexOf('\n  static complete(', requestStart);
    expect(requestStart, greaterThanOrEqualTo(0));
    expect(requestEnd, greaterThan(requestStart));
    final request = common.substring(requestStart, requestEnd);

    expect(
        request.indexOf('_completer = Completer<bool>();'),
        lessThan(
            request.indexOf('gFFI.invokeMethod("request_permission", type)')));
    expect(request, contains('Duration(seconds: 30)'));
  });

  test('Android native permission callback reports both grant and denial', () {
    final common = _read(
      'android/app/src/main/kotlin/com/carriez/flutter_hbb/common.kt',
    );
    final callbackStart = common.indexOf('fun requestPermission(');
    final callbackEnd = common.indexOf('\n}\n\nfun startAction', callbackStart);
    expect(callbackStart, greaterThanOrEqualTo(0));
    expect(callbackEnd, greaterThan(callbackStart));
    final callback = common.substring(callbackStart, callbackEnd);

    expect(callback, contains('"result" to all'));
    expect(callback, contains('Handler(Looper.getMainLooper())'));
    expect(callback, isNot(contains('if (all)')));
  });

  test('Android voice capture only reports connected after recording starts',
      () {
    final audio = _read(
      'android/app/src/main/kotlin/com/carriez/flutter_hbb/AudioRecordHandle.kt',
    );
    final activity = _read(
      'android/app/src/main/kotlin/com/carriez/flutter_hbb/MainActivity.kt',
    );
    final chatModel = _read('lib/models/chat_model.dart');

    expect(audio, contains('audioRecordStat = true'));
    expect(audio, contains('audioRecorder!!.recordingState'));
    expect(audio, contains('AudioRecord.RECORDSTATE_RECORDING'));
    expect(activity, contains('ensureRecordAudioPermission { granted ->'));
    expect(activity, contains('result.success(false)'));
    expect(activity, contains('isAudioStart = ok'));
    expect(chatModel,
        contains('final started = await parent.target?.invokeMethod('));
    expect(chatModel, contains("'on_voice_call_started'"));
    expect(
      chatModel.indexOf('_voiceCallStatus.value = VoiceCallStatus.connected;'),
      greaterThan(chatModel.indexOf("'on_voice_call_started'")),
    );
  });

  test('Android privacy stays in-app while iOS keeps the public policy action',
      () {
    final page = _read('lib/mobile/pages/privacy_policy_page.dart');
    final settings = _read('lib/mobile/pages/settings_page.dart');

    expect(
        page, contains('onOpenPublicPolicy: isIOS ? _openPublicPolicy : null'));
    expect(settings, contains('PrivacyPolicyPage'));
    expect(settings, contains('if (isAndroid)'));
    expect(settings, contains("launchUrlString('https://kunqiongai.com/')"));
  });

  test('Android update card opens the service-provided URL', () {
    final page = _read('lib/mobile/pages/connection_page.dart');
    final updateStart = page.indexOf('Widget _buildUpdateUI(String updateUrl)');
    final updateEnd =
        page.indexOf('\n  Widget _buildConnectPanel', updateStart);
    expect(updateStart, greaterThanOrEqualTo(0));
    expect(updateEnd, greaterThan(updateStart));
    final update = page.substring(updateStart, updateEnd);

    expect(update, contains('if (isAndroid)'));
    expect(update, contains('Uri.tryParse(updateUrl.trim())'));
    expect(update, contains("Uri.parse('https://kunqiongai.com/')"));
  });

  test('Android account notifications open the real notification center', () {
    final page = _read('lib/mobile/pages/account_page.dart');
    expect(page, contains('AndroidNotificationCenterPage'));
    expect(page, contains('mobileUnreadSum'));
    expect(page, contains('onNotificationTap: isAndroid'));
    expect(page, contains("showToast(_mineText('No notifications'))"));
  });

  test('Android WOL is implemented and does not keep the empty stub', () {
    final lan = _read('../src/lan.rs');
    final ffi = _read('../src/flutter_ffi.rs');
    final peerCard = _read('lib/common/widgets/peer_card.dart');
    expect(lan, contains('send_wol_android'));
    expect(lan, contains('wol::send_wol'));
    expect(lan, isNot(contains('pub fn send_wol(_id: String) {}')));
    expect(ffi, contains('pub fn main_wol(id: String) -> bool'));
    expect(peerCard, contains('final sent = await bind.mainWol(id: id)'));
  });
}
