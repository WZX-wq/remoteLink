import 'dart:io';

import 'package:flutter_hbb/models/remote_video_quality_policy.dart';
import 'package:flutter_hbb/models/user_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('basic and member receiver profiles have distinct real parameters', () {
    expect(kqStandardRemoteStreamQuality, 35);
    expect(kqHighDefinitionRemoteStreamQuality, 150);
    expect(kqRemoteMaxFrameHeight(highDefinition: false), 480);
    expect(kqRemoteMaxFrameHeight(highDefinition: true), 1080);
    expect(UserModel.freeMaxFps, 30);
    expect(UserModel.memberDefaultFps, 60);
    expect(kqStandardRemoteMaxFrameHeight, 480);
  });

  test('Rust connection option message uses the selected tier parameters', () {
    final source = File('../src/client.rs').readAsStringSync();
    final start = source.indexOf('fn get_option_message(');
    final end = source.indexOf('pub fn get_supported_decoding', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final optionMessage = source.substring(start, end);

    expect(optionMessage, contains('kq_remote_custom_image_quality() << 8'));
    expect(optionMessage, contains('let custom_fps = kq_remote_fps();'));
    expect(optionMessage, contains('msg.custom_fps = custom_fps;'));
  });

  test('account quality profile is pushed to the active session', () {
    final source = File('lib/models/user_model.dart').readAsStringSync();
    final start = source.indexOf('Future<void> setRemotePerformanceProfile');
    final end = source.indexOf('Future<void> _setMemberStatus', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final setter = source.substring(start, end);

    expect(setter, contains('final sessionId = parent.target?.sessionId;'));
    expect(setter, contains('sessionSetImageQuality('));
    expect(setter, contains('value: kRemoteImageQualityCustom'));
    expect(setter, contains('sessionSetCustomImageQuality('));
    expect(setter, contains('value: customQuality'));
    expect(setter, contains('sessionSetCustomFps('));
    expect(setter, contains('fps: normalizedFps'));
  });

  test('mobile account displays the parameters that the receiver requests', () {
    final source =
        File('lib/mobile/pages/account_page.dart').readAsStringSync();
    expect(source, contains("label: _mineText('SD / 30 FPS')"));
    expect(source, contains("label: _mineText('1080p HD / 60 FPS')"));
    expect(source, contains('UserModel.freeMaxFps'));
    expect(source, contains('UserModel.memberDefaultFps'));
  });

  test('membership card localizes the free and member quality message', () {
    final source =
        File('lib/mobile/pages/account_page.dart').readAsStringSync();
    const key = 'Basic uses SD / 30 FPS. Membership unlocks 1080p HD / 60 FPS.';
    final cardTextOffset = source.indexOf("'$key'");
    expect(cardTextOffset, greaterThanOrEqualTo(0));
    expect(
      source.substring(cardTextOffset - 80, cardTextOffset + key.length + 4),
      contains('_mineText('),
    );
    expect(source, contains('基础版使用标清 / 30 FPS，会员可使用 1080p 高清 / 60 FPS。'));
    expect(source, contains('基礎版使用標清 / 30 FPS，會員可使用 1080p 高畫質 / 60 FPS。'));
    expect(source, contains("'Upgrade Kunqiong Membership': '开通鲲穹会员'"));
    expect(source, contains("'Membership benefits unlocked': '会员权益已开通'"));

    final bannerStart = source.indexOf('class _MembershipBanner');
    final bannerEnd = source.indexOf('String _priceLabel', bannerStart);
    final banner = source.substring(bannerStart, bannerEnd);
    expect(banner, contains("_mineText('Membership benefits unlocked')"));
    expect(banner, isNot(contains("_mineText('Membership benefits active')")));
    expect(banner, contains("_mineText('Upgrade Kunqiong Membership')"));
    expect(banner, contains('Semantics('));
    expect(banner, contains('button: true'));
    expect(banner, contains('InkWell('));
    expect(banner, contains('onTap: onPrimaryTap'));
    expect(banner, isNot(contains('FilledButton(')));
    expect(banner, isNot(contains('TextButton.icon(')));
    expect(banner, isNot(contains('onRefreshTap')));
    expect(source, isNot(contains('onRefreshTap: isLogin')));
    final paymentStart = source.indexOf('void startPolling');
    final paymentEnd =
        source.indexOf('void startPaymentLaunchWatchdog', paymentStart);
    expect(paymentStart, greaterThanOrEqualTo(0));
    expect(paymentEnd, greaterThan(paymentStart));
    final paymentFlow = source.substring(paymentStart, paymentEnd);
    expect(paymentFlow, isNot(contains('Membership benefits active')));
    expect(banner, isNot(contains('Membership valid until')));
  });

  test('quality update toast uses a readable high contrast style', () {
    final common = File('lib/common.dart').readAsStringSync();
    final toastStart = common.indexOf('void showToast(String text');
    final toastEnd = common.indexOf('// TODO', toastStart);
    expect(toastStart, greaterThanOrEqualTo(0));
    expect(toastEnd, greaterThan(toastStart));
    final toast = common.substring(toastStart, toastEnd);

    expect(toast, contains('maxWidth:'));
    expect(toast, contains('FontWeight.w700'));
    expect(toast, contains('fontSize: isMobile ? 14 : 16'));
    expect(toast, contains('BoxShadow('));
    expect(common, contains('toastBg: const Color(0xE6000000)'));
    expect(common, contains('toastText: Colors.white'));
    expect(common, isNot(contains('toastBg: Colors.black.withOpacity(0.6)')));
  });

  test('iOS declares all native permission descriptions used by the app', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    for (final key in <String>[
      'NSCameraUsageDescription',
      'NSLocalNetworkUsageDescription',
      'NSMicrophoneUsageDescription',
      'NSPhotoLibraryUsageDescription',
      'NSPhotoLibraryAddUsageDescription',
    ]) {
      expect(plist, contains('<key>$key</key>'));
    }
  });
}
