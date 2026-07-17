import 'dart:io';

import 'package:flutter_hbb/mobile/ios_membership_payment_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS only enables direct Alipay in an explicitly internal build', () {
    expect(
      KqIosMembershipPaymentPolicy.routeFor(
        isIOS: true,
        internalDirectPaymentEnabled: false,
      ),
      KqIosMembershipPaymentRoute.appleInAppPurchaseRequired,
    );
    expect(
      KqIosMembershipPaymentPolicy.routeFor(
        isIOS: true,
        internalDirectPaymentEnabled: true,
      ),
      KqIosMembershipPaymentRoute.externalPayment,
    );
    expect(
      KqIosMembershipPaymentPolicy.routeFor(
        isIOS: false,
        internalDirectPaymentEnabled: false,
      ),
      KqIosMembershipPaymentRoute.externalPayment,
    );
  });

  test('iOS account page uses the explicit membership payment policy', () {
    final page = File('lib/mobile/pages/account_page.dart').readAsStringSync();

    expect(page, contains('ios_membership_payment_policy.dart'));
    expect(
        page, contains('KqIosMembershipPaymentPolicy.routeFor(isIOS: isIOS)'));
    expect(page, contains('appleInAppPurchaseRequired'));
  });

  test('iOS readiness gate runs compliance and purchase tests', () {
    final script =
        File('../scripts/test-kq-ios-code-readiness.ps1').readAsStringSync();

    expect(script, contains('test/kq_ios_privacy_policy_test.dart'));
    expect(script, contains('test/kq_account_deletion_test.dart'));
    expect(script, contains('test/kq_ios_in_app_purchase_test.dart'));
    expect(script, contains('test/kq_ios_release_policy_test.dart'));
  });

  test('GitHub iOS preflight uses the locked Flutter 3.44 toolchain', () {
    final workflow =
        File('../.github/workflows/ios-preflight.yml').readAsStringSync();

    expect(workflow, contains('FLUTTER_VERSION: "3.44.5"'));
    expect(workflow, isNot(contains('Patch Flutter 3.24 dependency constraints')));
    expect(workflow,
        isNot(contains('flutter_3.24.4_dropdown_menu_enableFilter.diff')));
    expect('extended_text: 14.0.0'.allMatches(workflow), isEmpty);
  });

  test(
      'GitHub iOS preflight does not require artifact storage for bridge handoff',
      () {
    final workflow =
        File('../.github/workflows/ios-preflight.yml').readAsStringSync();

    expect(workflow, isNot(contains('actions/upload-artifact@v4')));
    expect(workflow, isNot(contains('actions/download-artifact@v4')));
    expect(workflow, contains('Verify generated bridge files are committed'));
    expect(workflow, contains('git diff --exit-code --'));
    expect(workflow, contains('require_committed_symbol'));
    expect(workflow, contains('git grep -q --'));
    expect(workflow, isNot(contains('git show "HEAD:\${file#./}" | grep -q')));
    expect(workflow, contains('kq_ios_broadcast_start'));
  });

  test('iOS preflight pages use Flutter 3.44 Color APIs', () {
    for (final path in <String>[
      'lib/mobile/pages/account_deletion_page.dart',
      'lib/mobile/pages/ios_membership_purchase_page.dart',
      'lib/mobile/pages/privacy_policy_page.dart',
    ]) {
      final source = File(path).readAsStringSync();

      expect(source, isNot(contains('withOpacity(')));
      expect(source, contains('withValues(alpha:'));
    }
  });

  test('shared theme uses ThemeData material theme data classes', () {
    final common = File('lib/common.dart').readAsStringSync();

    expect(
      'dialogTheme: DialogThemeData('.allMatches(common),
      hasLength(2),
    );
    expect(
      'tabBarTheme: const TabBarThemeData('.allMatches(common),
      hasLength(2),
    );
    expect(common, isNot(contains('dialogTheme: DialogTheme(')));
    expect(common, isNot(contains('tabBarTheme: const TabBarTheme(')));
  });

  test('phone registration remains shared by Android and iOS', () {
    final oauth = File('lib/common/kq_oauth_io.dart').readAsStringSync();
    final login = File('lib/common/widgets/login.dart').readAsStringSync();

    expect(oauth, contains('static Future<LoginResponse> registerWithPhone'));
    expect(login, contains('KqOauth.registerWithPhone('));
    expect(login, isNot(contains('isIOS && !canRegisterWithPhone')));
  });

  test('iOS declares its app-group UserDefaults privacy reasons', () {
    final manifest = File('ios/Runner/PrivacyInfo.xcprivacy');
    final extensionManifest =
        File('ios/KQScreenBroadcast/PrivacyInfo.xcprivacy');

    expect(manifest.existsSync(), isTrue);
    final content = manifest.readAsStringSync();
    expect(content, contains('NSPrivacyAccessedAPICategoryUserDefaults'));
    expect(content, contains('CA92.1'));
    expect(content, contains('1C8F.1'));
    expect(extensionManifest.existsSync(), isTrue);
    expect(extensionManifest.readAsStringSync(), contains('1C8F.1'));
    final project =
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    expect(
        project,
        contains(
            'A1B2C3D40000000000000014 /* PrivacyInfo.xcprivacy in Resources */'));
    expect(
        project,
        contains(
            'A1B2C3D40000000000000016 /* PrivacyInfo.xcprivacy in Resources */'));
    expect(project, contains('A1B2C3D40000000000000018 /* Resources */'));
  });

  test('screen broadcast does not advertise unsupported audio or a viewer', () {
    final handler =
        File('ios/KQScreenBroadcast/SampleHandler.swift').readAsStringSync();
    final page = File('lib/mobile/pages/server_page.dart').readAsStringSync();
    final info = File('ios/Runner/Info.plist').readAsStringSync();

    expect(handler, contains('kq_broadcast_audio_supported'));
    expect(
        handler,
        contains(
            'defaults.set(false, forKey: "kq_broadcast_remote_view_available")'));
    expect(page, contains("_status['audioSupported']"));
    expect(page, contains('共享已启动，等待其他设备连接'));
    expect(page, isNot(contains('应用音频帧')));
    expect(page, isNot(contains('麦克风音频帧')));
    expect(info, contains('用于远程协助过程中的语音通话。'));
    expect(info, isNot(contains('屏幕共享音频')));
  });

  test('iOS ReplayKit frames keep YUV conversion available to video encoding',
      () {
    final converter =
        File('../libs/scrap/src/common/convert.rs').readAsStringSync();
    final frame = File('../libs/scrap/src/common/mod.rs').readAsStringSync();

    expect(converter, contains('pub fn convert_to_yuv('));
    expect(
      converter,
      isNot(
        contains(
          RegExp(
              r'#\[cfg\(not\(target_os = "ios"\)\)\]\s*pub fn convert_to_yuv'),
        ),
      ),
    );
    expect(frame,
        contains('convert_to_yuv(&pixelbuffer, yuvfmt, yuv, mid_data)?'));
  });

  test('iOS Rust host keeps mobile-safe server symbols available', () {
    final platform = File('../src/platform/mod.rs').readAsStringSync();
    final flutter = File('../src/flutter.rs').readAsStringSync();
    final uiCm = File('../src/ui_cm_interface.rs').readAsStringSync();
    final sync = File('../src/hbbs_http/sync.rs').readAsStringSync();
    final rendezvous =
        File('../src/rendezvous_mediator.rs').readAsStringSync();
    final connection = File('../src/server/connection.rs').readAsStringSync();
    final video = File('../src/server/video_service.rs').readAsStringSync();
    final converter =
        File('../libs/scrap/src/common/convert.rs').readAsStringSync();
    final session =
        File('../src/ui_session_interface.rs').readAsStringSync();
    final ipc = File('../src/ipc.rs').readAsStringSync();

    expect(
      platform,
      contains(RegExp(
          r'#\[cfg\(target_os = "ios"\)\]\s*(?:#\[derive\([^\n]+\)\]\s*)?pub struct WakeLock')),
    );
    expect(
      flutter,
      contains(RegExp(
          r'#\[cfg\(target_os = "android"\)\]\s*pub fn start_channel')),
    );
    expect(
      uiCm,
      contains(RegExp(
          r'#\[cfg\(target_os = "ios"\)\]\s*pub fn check_file_count_limit')),
    );
    expect(
      sync,
      contains(RegExp(
          r'#\[cfg\(target_os = "ios"\)\]\s*pub fn signal_receiver')),
    );
    expect(
      sync,
      contains(RegExp(r'#\[cfg\(target_os = "ios"\)\]\s*pub fn is_pro')),
    );
    expect(
      rendezvous,
      contains(RegExp(
          r'#\[cfg\(target_os = "android"\)\]\s*let start_lan_listening')),
    );
    expect(
      rendezvous,
      contains(RegExp(
          r'#\[cfg\(not\(target_os = "ios"\)\)\]\s*scrap::codec::test_av1\(\);')),
    );
    expect(
      connection,
      contains(RegExp(
          r'#\[cfg\(target_os = "ios"\)\][\s\S]{0,240}pi\.platform = "iOS"')),
    );
    expect(
      connection,
      contains(RegExp(
          r'#\[cfg\(target_os = "android"\)\]\s*use crate::flutter::connection_manager::start_channel;')),
    );
    expect(
      video,
      contains(RegExp(
          r'#\[cfg\(not\(any\(target_os = "android", target_os = "ios"\)\)\)\]\s*resolutions: Some')),
    );
    expect(
      converter,
      isNot(contains(RegExp(
          r'#\[cfg\(not\(target_os = "ios"\)\)\]\s*pub fn convert\('))),
    );
    expect(
      session,
      contains(RegExp(
          r'#\[cfg\(target_os = "ios"\)\]\s*fn create_ios_text_clipboard_msg')),
    );
    expect(
      ipc,
      contains(RegExp(
          r'#\[cfg\(not\(any\(target_os = "android", target_os = "ios"\)\)\)\]\s*crate::server::input_service::fix_key_down_timeout_at_exit')),
    );
  });
}
