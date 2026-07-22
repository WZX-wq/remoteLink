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

  test('TestFlight workflow validates and injects release-only iOS settings',
      () {
    final workflow = File('../codemagic.yaml').readAsStringSync();
    final validator = File('../scripts/prepare_ios_release_config.py');
    final preflight =
        File('../.github/workflows/ios-preflight.yml').readAsStringSync();
    final testFlightStart = workflow.indexOf('kq-remote-link-ios-testflight:');
    final unsignedWorkflow = workflow.substring(0, testFlightStart);
    final testFlightWorkflow = workflow.substring(testFlightStart);

    expect(validator.existsSync(), isTrue);
    expect(testFlightWorkflow,
        contains('Validate iOS App Store release configuration'));
    expect(testFlightWorkflow, contains('prepare_ios_release_config.py'));
    expect(unsignedWorkflow,
        isNot(contains('Validate iOS App Store release configuration')));
    expect(testFlightWorkflow, contains(r'--build-number "$BUILD_NUMBER"'));
    expect(
        testFlightWorkflow,
        contains(
            r'--dart-define=KQ_PRIVACY_POLICY_URL="$KQ_PRIVACY_POLICY_URL"'));
    expect(
        testFlightWorkflow,
        contains(
            r'--dart-define=KQ_ACCOUNT_DELETE_URL="$KQ_ACCOUNT_DELETE_URL"'));
    expect(testFlightWorkflow,
        contains(r'--dart-define=KQ_IOS_IAP_PRODUCTS="$KQ_IOS_IAP_PRODUCTS"'));
    expect(
        testFlightWorkflow,
        contains(
            r'--dart-define=KQ_IOS_IAP_VERIFY_URL="$KQ_IOS_IAP_VERIFY_URL"'));
    expect(preflight, contains('test_ios_release_config.py'));
  });

  test('TestFlight workflow uses Codemagic publishing instead of altool', () {
    final workflow = File('../codemagic.yaml').readAsStringSync();
    final testFlightWorkflow =
        workflow.substring(workflow.indexOf('kq-remote-link-ios-testflight:'));

    expect(
      testFlightWorkflow,
      contains(
        '--custom-export-options=\''
        '{"testFlightInternalTestingOnly": true}'
        '\'',
      ),
    );
    expect(testFlightWorkflow, contains('publishing:'));
    expect(testFlightWorkflow, contains('app_store_connect:'));
    expect(testFlightWorkflow,
        contains('api_key: \$APP_STORE_CONNECT_PRIVATE_KEY'));
    expect(
      testFlightWorkflow,
      contains('key_id: \$APP_STORE_CONNECT_KEY_IDENTIFIER'),
    );
    expect(testFlightWorkflow,
        contains('issuer_id: \$APP_STORE_CONNECT_ISSUER_ID'));
    expect(testFlightWorkflow, isNot(contains('xcrun altool')));
  });

  test('GitHub iOS preflight uses the locked Flutter 3.44 toolchain', () {
    final workflow =
        File('../.github/workflows/ios-preflight.yml').readAsStringSync();

    expect(workflow, contains('FLUTTER_VERSION: "3.44.5"'));
    expect(
        workflow, isNot(contains('Patch Flutter 3.24 dependency constraints')));
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

  test('iOS preflight pages remain compatible with shared Flutter 3.24 builds',
      () {
    for (final path in <String>[
      'lib/mobile/pages/account_deletion_page.dart',
      'lib/mobile/pages/ios_membership_purchase_page.dart',
      'lib/mobile/pages/privacy_policy_page.dart',
    ]) {
      final source = File(path).readAsStringSync();

      expect(source, isNot(contains('withValues(')));
      expect(source, contains('withOpacity('));
    }
  });

  test('shared theme avoids version-specific dialog and tab theme data classes',
      () {
    final common = File('lib/common.dart').readAsStringSync();

    expect(common, isNot(contains('DialogThemeData(')));
    expect(common, isNot(contains('TabBarThemeData(')));
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

  test(
      'screen broadcast forwards application audio and reports verified viewers',
      () {
    final handler =
        File('ios/KQScreenBroadcast/SampleHandler.swift').readAsStringSync();
    final page = File('lib/mobile/pages/server_page.dart').readAsStringSync();
    final info = File('ios/Runner/Info.plist').readAsStringSync();

    expect(handler, contains('kq_broadcast_audio_supported'));
    expect(handler, contains('case .audioApp:'));
    expect(handler, contains('CMSampleBufferCopyPCMDataIntoAudioBufferList'));
    expect(handler, contains('kq_ios_broadcast_push_audio_f32'));
    expect(handler, contains('kq_ios_broadcast_active_viewer_count'));
    expect(handler, contains('kq_broadcast_remote_viewer_count'));
    expect(
      handler,
      isNot(contains(
          'defaults.set(false, forKey: "kq_broadcast_remote_view_available")')),
    );
    expect(
        handler,
        contains(
            'defaults.set(audioForwardingActive, forKey: "kq_broadcast_audio_supported")'));
    expect(page, contains("_status['audioSupported']"));
    expect(page, contains('共享已启动，等待其他设备连接'));
    expect(page, contains('已有设备正在观看'));
    expect(page, contains('正在传输画面和应用声音'));
    expect(page, isNot(contains('当前屏幕共享仅传输画面。')));
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

  test('iOS native bridges pass C size values as UInt', () {
    final handler =
        File('ios/KQScreenBroadcast/SampleHandler.swift').readAsStringSync();
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(handler, contains('UInt(max(0, buffer.count - 1))'));
    expect(handler, contains('UInt(stride * height)'));
    expect(handler, contains('UInt(width)'));
    expect(handler, contains('UInt(height)'));
    expect(handler, contains('UInt(stride)'));
    expect(handler, contains('UInt(targetLength)'));
    expect(handler, contains('UInt(target.width)'));
    expect(handler, contains('UInt(target.height)'));
    expect(handler, contains('UInt(targetStride)'));
    expect(appDelegate, contains('UInt(sessionPointer.count)'));
    expect(appDelegate, contains('UInt(framePointer.count)'));
  });

  test('iOS project lets CocoaPods link Flutter plugin frameworks', () {
    final project =
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();

    expect(project, contains(r'$(inherited)'));
    expect(project, contains('liblibrustdesk.a'));
    for (final framework in <String>[
      'DKImagePickerController',
      'DKPhotoGallery',
      'MTBBarcodeScanner',
      'SDWebImage',
      'SwiftyGif',
      'device_info_plus',
      'file_picker',
      'flutter_keyboard_visibility',
      'image_picker_ios',
      'package_info_plus',
      'path_provider_foundation',
      'qr_code_scanner',
      'sqflite',
      'uni_links',
      'url_launcher_ios',
      'video_player_avfoundation',
      'wakelock_plus',
    ]) {
      final xcodeFramework =
          '${String.fromCharCode(92)}"$framework${String.fromCharCode(92)}"';
      expect(project, isNot(contains(xcodeFramework)));
    }
  });

  test('iOS Rust host keeps mobile-safe server symbols available', () {
    final platform = File('../src/platform/mod.rs').readAsStringSync();
    final flutter = File('../src/flutter.rs').readAsStringSync();
    final uiCm = File('../src/ui_cm_interface.rs').readAsStringSync();
    final sync = File('../src/hbbs_http/sync.rs').readAsStringSync();
    final rendezvous = File('../src/rendezvous_mediator.rs').readAsStringSync();
    final connection = File('../src/server/connection.rs').readAsStringSync();
    final video = File('../src/server/video_service.rs').readAsStringSync();
    final converter =
        File('../libs/scrap/src/common/convert.rs').readAsStringSync();
    final session = File('../src/ui_session_interface.rs').readAsStringSync();
    final ipc = File('../src/ipc.rs').readAsStringSync();

    expect(
      platform,
      contains(RegExp(
          r'#\[cfg\(target_os = "ios"\)\]\s*(?:#\[derive\([^\n]+\)\]\s*)?pub struct WakeLock')),
    );
    expect(
      flutter,
      contains(
          RegExp(r'#\[cfg\(target_os = "android"\)\]\s*pub fn start_channel')),
    );
    expect(
      uiCm,
      contains(RegExp(
          r'#\[cfg\(target_os = "ios"\)\]\s*pub fn check_file_count_limit')),
    );
    expect(
      sync,
      contains(
          RegExp(r'#\[cfg\(target_os = "ios"\)\]\s*pub fn signal_receiver')),
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
      isNot(contains(
          RegExp(r'#\[cfg\(not\(target_os = "ios"\)\)\]\s*pub fn convert\('))),
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
