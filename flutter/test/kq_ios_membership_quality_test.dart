import 'dart:io';

import 'package:flutter_hbb/models/remote_video_quality_policy.dart';
import 'package:flutter_hbb/models/user_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('basic and member receiver profiles have distinct real parameters', () {
    expect(kqStandardRemoteStreamQuality, 100);
    expect(kqHighDefinitionRemoteStreamQuality, 150);
    expect(UserModel.freeMaxFps, 30);
    expect(UserModel.memberDefaultFps, 60);
    expect(kqStandardRemoteBlurSigma, 0);
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

  test('mobile account displays the parameters that the receiver requests', () {
    final source =
        File('lib/mobile/pages/account_page.dart').readAsStringSync();
    expect(source, contains("label: '720p / 30 FPS'"));
    expect(source, contains("label: '1080p / 60 FPS'"));
    expect(source, contains('UserModel.freeMaxFps'));
    expect(source, contains('UserModel.memberDefaultFps'));
  });

  test('membership card localizes the free and member quality message', () {
    final source =
        File('lib/mobile/pages/account_page.dart').readAsStringSync();
    const key = 'Basic uses 720p / 30 FPS. Membership unlocks 1080p / 60 FPS.';
    final cardTextOffset = source.indexOf("'$key'");
    expect(cardTextOffset, greaterThanOrEqualTo(0));
    expect(
      source.substring(cardTextOffset - 80, cardTextOffset + key.length + 4),
      contains('_mineText('),
    );
    expect(source, contains('基础版使用 720p / 30 FPS，会员可使用 1080p / 60 FPS。'));
    expect(source, contains('基礎版使用 720p / 30 FPS，會員可使用 1080p / 60 FPS。'));
    expect(source, contains("'Upgrade Kunqiong Membership': '开通鲲穹会员'"));
    expect(source, contains("'Membership benefits unlocked': '会员权益已开通'"));
    expect(source, contains("'Membership valid until': '会员有效期至'"));

    final bannerStart = source.indexOf('class _MembershipBanner');
    final bannerEnd = source.indexOf('String _priceLabel', bannerStart);
    final banner = source.substring(bannerStart, bannerEnd);
    expect(banner, contains("_mineText('Membership benefits unlocked')"));
    expect(banner, contains("_mineText('Upgrade Kunqiong Membership')"));
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
