import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ReplayKit publishes capture and remote-view states separately', () {
    final handler =
        File('ios/KQScreenBroadcast/SampleHandler.swift').readAsStringSync();
    final bridge =
        File('ios/KQScreenBroadcast/KQBroadcastBridge.h').readAsStringSync();
    final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(handler, contains('kq_broadcast_transport_state'));
    expect(handler, contains('kq_broadcast_remote_view_available'));
    expect(handler, contains('kq_broadcast_remote_viewer_count'));
    expect(handler, contains('kq_ios_broadcast_push_bgra'));
    expect(handler, contains('kq_ios_broadcast_push_audio_f32'));
    expect(handler, contains('kq_ios_broadcast_active_viewer_count'));
    expect(bridge, contains('kq_ios_broadcast_active_viewer_count'));
    expect(handler, contains('kq_ios_broadcast_start'));
    expect(handler, contains('CMSampleBufferCopyPCMDataIntoAudioBufferList'));
    expect(handler, contains('AVAudioConverter'));
    expect(
      handler,
      contains(
        'let inputFormat = AVAudioFormat(cmAudioFormatDescription: description)',
      ),
    );
    expect(
      handler,
      isNot(
        contains(
          'let inputFormat = AVAudioFormat(cmAudioFormatDescription: description) else',
        ),
      ),
    );
    expect(
        handler,
        contains(
            'defaults.set(audioForwardingActive, forKey: "kq_broadcast_audio_supported")'));
    expect(handler, isNot(contains('capture_only')));
    expect(
      handler,
      isNot(contains(
          'defaults.set(false, forKey: "kq_broadcast_remote_view_available")')),
    );
    expect(delegate, contains('"transportState"'));
    expect(delegate, contains('"remoteViewAvailable"'));
    expect(delegate, contains('"remoteViewerCount"'));
    expect(delegate, contains('"viewOnly": true'));
    expect(delegate, contains('"errorCode"'));
  });

  test('iOS starts rendezvous registration when the broadcast starts', () {
    final handler =
        File('ios/KQScreenBroadcast/SampleHandler.swift').readAsStringSync();
    final broadcastStart = handler.indexOf('override func broadcastStarted');
    final broadcastPause = handler.indexOf('override func broadcastPaused');

    expect(broadcastStart, greaterThanOrEqualTo(0));
    expect(broadcastPause, greaterThan(broadcastStart));

    final startHandler = handler.substring(broadcastStart, broadcastPause);
    expect(startHandler, contains('state: "starting"'));
    expect(startHandler, contains('guard startTransportIfNeeded() else'));
    expect(startHandler, contains('transportState: "registering"'));
    expect(handler, contains('private func startTransportIfNeeded() -> Bool'));
    expect(handler, contains('finishBroadcastWithError'));
  });

  test('iOS shares a durable broadcast status between the app and extension',
      () {
    final handler =
        File('ios/KQScreenBroadcast/SampleHandler.swift').readAsStringSync();
    final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(handler, contains('kq-broadcast-status.json'));
    expect(handler, contains('options: .atomic'));
    expect(delegate, contains('kq-broadcast-status.json'));
    expect(delegate, contains('loadBroadcastStatusFile'));
  });

  test('iOS converts ReplayKit video buffers to BGRA before sending frames',
      () {
    final handler =
        File('ios/KQScreenBroadcast/SampleHandler.swift').readAsStringSync();

    expect(handler, contains('import CoreImage'));
    expect(handler, contains('private func bgraPixelBuffer'));
    expect(handler, contains('CIContext'));
    expect(handler, contains('kCVPixelFormatType_32BGRA'));
    expect(handler, isNot(contains('unsupported_pixel_format')));
  });

  test('iOS displays one canonical ID while the broadcast runs', () {
    final config = File('../libs/hbb_common/src/config.rs').readAsStringSync();
    final native = File('../src/ios_broadcast.rs').readAsStringSync();
    final handler =
        File('ios/KQScreenBroadcast/SampleHandler.swift').readAsStringSync();
    final bridge =
        File('ios/KQScreenBroadcast/KQBroadcastBridge.h').readAsStringSync();
    final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final page = File('lib/mobile/pages/server_page.dart').readAsStringSync();

    expect(native, contains('kq_ios_broadcast_copy_device_id'));
    expect(bridge, contains('kq_ios_broadcast_copy_device_id'));
    expect(handler, contains('kq_broadcast_device_id'));
    expect(delegate, contains('"deviceId"'));
    expect(page, contains('bool _broadcastRegistrationReady'));
    expect(page, contains('showDeviceId: registrationReady'));
    expect(config, contains('fn parse_ios_shared_device_id'));
    expect(
        page, contains('final displayedDeviceId = model.serverId.value.text;'));
    expect(page, contains('Do not copy the extension telemetry ID'));
    expect(page, isNot(contains('registeredDeviceId:')));
    expect(page, isNot(contains('sync_ios_canonical_device_id')));
    expect(page, isNot(contains('serverIdOverride')));
  });

  test('iOS keeps one persistent ID when the main app and extension restart',
      () {
    final config = File('../libs/hbb_common/src/config.rs').readAsStringSync();
    final rendezvous = File('../src/rendezvous_mediator.rs').readAsStringSync();
    final ffi = File('../src/flutter_ffi.rs').readAsStringSync();
    final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(config, contains('const IOS_SHARED_DEVICE_ID_FILE'));
    expect(config, contains('fn get_or_create_ios_shared_device_id'));
    expect(config, contains('fn set_ios_shared_device_id'));
    expect(config, contains('get_or_create_ios_shared_device_id(&config.id)'));
    expect(config, contains('update_ios_identity_snapshot_id(id)'));
    expect(config, contains('Refused to change the iOS ID'));
    expect(config, contains('const IOS_IDENTITY_SNAPSHOT_FILE'));
    expect(config, contains('fn ensure_ios_identity'));
    expect(config, contains('fn write_ios_identity_snapshot'));
    expect(config, contains('file.sync_all()?'));
    expect(config, contains('apply_durable_ios_identity(&latest, &mut merged)'));
    expect(config, contains('fn sync_ios_shared_device_id'));
    expect(ffi, contains('config::Config::sync_ios_shared_device_id();'));
    expect(delegate, contains('sharedDeviceIdFileName'));
    expect(delegate, contains('sharedDeviceIdentityFileName'));
    expect(delegate, contains('registeredDeviceIdentityFileName'));
    expect(delegate, contains('synchronizeSharedIdentityFiles'));
    expect(
      config.indexOf('get_or_create_ios_shared_device_id(&config.id)'),
      lessThan(config.indexOf('if !id_valid {')),
    );
    final iosMismatchStart = rendezvous.indexOf(
        '#[cfg(target_os = "ios")]\n    async fn handle_uuid_mismatch');
    final androidMismatchStart = rendezvous.indexOf(
        '#[cfg(target_os = "android")]\n    async fn handle_uuid_mismatch');
    final otherPlatformMismatchStart = rendezvous.indexOf(
        '#[cfg(not(any(target_os = "android", target_os = "ios")))]\n'
        '    async fn handle_uuid_mismatch');
    expect(iosMismatchStart, greaterThanOrEqualTo(0));
    expect(androidMismatchStart, greaterThan(iosMismatchStart));
    expect(otherPlatformMismatchStart, greaterThan(androidMismatchStart));
    final iosMismatch =
        rendezvous.substring(iosMismatchStart, androidMismatchStart);
    expect(iosMismatch, isNot(contains('Config::recover_ios_id_after_uuid_mismatch')));
    expect(iosMismatch, contains('Config::has_confirmed_ios_identity()'));
    expect(iosMismatch, contains('Config::rotate_unconfirmed_ios_id()'));
    expect(iosMismatch, contains('IOS_MAX_UNCONFIRMED_ID_COLLISIONS'));
    expect(iosMismatch, contains('self.register_pk(socket).await'));
    expect(iosMismatch, contains('The fixed iOS identity was rejected'));
    expect(iosMismatch, contains('NEEDS_DEPLOY.store(true'));
  });

  test('iOS binds the App Group before starting global Rust events', () {
    final nativeModel = File('lib/models/native_model.dart').readAsStringSync();
    final prepareConfig = nativeModel.indexOf('prepare_broadcast_config_dir');
    final bindAppGroup = nativeModel.indexOf('mainGetDataDirIos(appDir: _dir)');
    final initialize = nativeModel.indexOf('await _ffiBind.mainInit(');
    final startEvents = nativeModel.indexOf('_startListenEvent(_ffiBind)');

    expect(prepareConfig, greaterThanOrEqualTo(0));
    expect(bindAppGroup, greaterThan(prepareConfig));
    expect(initialize, greaterThan(bindAppGroup));
    expect(startEvents, greaterThan(initialize));
  });

  test('iOS registers its native channel after Flutter launch is ready', () {
    final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final launchStart = delegate.indexOf('override func application(');
    final channelStart = delegate.indexOf(
      'private func registerNativeChannel',
      launchStart,
    );
    final launchBody = delegate.substring(launchStart, channelStart);

    expect(launchBody, contains('let launched = super.application('));
    expect(
      launchBody.indexOf('registerNativeChannel()'),
      greaterThan(launchBody.indexOf('let launched = super.application(')),
    );
    expect(
        delegate, contains('private var nativeChannel: FlutterMethodChannel?'));
    expect(delegate, contains('guard nativeChannel == nil else'));
    expect(delegate, contains('retryCount < 20'));
    expect(delegate, contains('self?.registerNativeChannel('));
  });

  test('iOS broadcast bridges voice invitations through App Group storage', () {
    final serverConnection =
        File('../src/server/connection.rs').readAsStringSync();
    final voiceBridge = File('../src/ios_voice_call.rs').readAsStringSync();
    final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final serverPage =
        File('lib/mobile/pages/server_page.dart').readAsStringSync();
    final remotePage =
        File('lib/mobile/pages/remote_page.dart').readAsStringSync();
    final desktopToolbar =
        File('lib/desktop/widgets/remote_toolbar.dart').readAsStringSync();

    expect(serverConnection, contains('publish_incoming_voice_call'));
    expect(serverConnection, contains('take_voice_call_response'));
    expect(serverConnection, contains('append_playback_audio'));
    expect(voiceBridge, contains('REQUEST_FILE_NAME'));
    expect(voiceBridge, contains('RESPONSE_FILE_NAME'));
    expect(voiceBridge, contains('MAX_AUDIO_FILE_BYTES'));
    expect(delegate, contains('get_pending_ios_voice_call'));
    expect(delegate, contains('respond_to_ios_voice_call'));
    expect(delegate, contains('startIOSVoicePlayback'));
    expect(delegate, contains('startIOSVoiceCallInvitationMonitor'));
    expect(delegate, contains('monitorIOSVoiceCallInvitation'));
    expect(serverPage, isNot(contains('_checkPendingIOSVoiceCall')));
    expect(remotePage,
        isNot(contains('gFFI.ffiModel.pi.platform != kPeerPlatformIOS')));
    expect(
        desktopToolbar,
        isNot(contains(
            'if (widget.ffi.ffiModel.pi.platform != kPeerPlatformIOS)')));
  });

  test(
      'iOS voice calls return host microphone audio and expose a hangup action',
      () {
    final serverConnection =
        File('../src/server/connection.rs').readAsStringSync();
    final voiceBridge = File('../src/ios_voice_call.rs').readAsStringSync();
    final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final serverPage =
        File('lib/mobile/pages/server_page.dart').readAsStringSync();
    final ffi = File('../src/flutter_ffi.rs').readAsStringSync();
    final broadcast = File('../src/ios_broadcast.rs').readAsStringSync();
    final handler =
        File('ios/KQScreenBroadcast/SampleHandler.swift').readAsStringSync();
    final bridge =
        File('ios/KQScreenBroadcast/KQBroadcastBridge.h').readAsStringSync();
    final info = File('ios/Runner/Info.plist').readAsStringSync();
    final extensionInfo =
        File('ios/KQScreenBroadcast/Info.plist').readAsStringSync();

    expect(serverConnection, contains('send_ios_host_voice_call_audio'));
    expect(serverConnection, contains('take_host_voice_call_audio'));
    expect(serverConnection, contains('take_host_voice_call_close'));
    expect(voiceBridge, contains('send_host_voice_call_audio'));
    expect(voiceBridge, contains('HOST_CAPTURE_DIRECTORY_NAME'));
    expect(voiceBridge, contains('push_broadcast_host_voice_audio'));
    expect(voiceBridge, contains('request_host_voice_call_close'));
    expect(broadcast, contains('kq_ios_broadcast_push_voice_audio_f32'));
    expect(handler, contains('case .audioMic:'));
    expect(handler, contains('submitMicrophoneAudio(sampleBuffer)'));
    expect(handler, contains('"lastMicAudioAt": lastMicAudioAt'));
    expect(serverPage, contains('系统直播面板打开麦克风'));
    expect(handler, contains('kq_ios_broadcast_push_voice_audio_f32'));
    expect(bridge, contains('kq_ios_broadcast_push_voice_audio_f32'));
    expect(delegate, contains('kq_ios_host_voice_call_audio'));
    expect(delegate, contains('picker.showsMicrophoneButton = true'));
    expect(delegate, contains('get_ios_voice_call_state'));
    expect(delegate, contains('end_ios_voice_call'));
    expect(serverPage, contains('_refreshIOSVoiceCallState'));
    expect(serverPage, contains('_endIOSVoiceCall'));
    expect(ffi, contains('kq_ios_host_voice_call_end'));
    expect(info, contains('<string>audio</string>'));
    expect(extensionInfo, contains('NSMicrophoneUsageDescription'));
    expect(serverConnection, contains('iOS host sent voice audio frame'));
  });

  test('iOS advertises its displayed ID as a registered device', () {
    final defaults = File('../src/common.rs').readAsStringSync();
    final rendezvous = File('../src/rendezvous_mediator.rs').readAsStringSync();

    expect(
      defaults,
      contains(
        RegExp(
          r'#\[cfg\(any\(target_os = "android", target_os = "ios"\)\)\]\s*'
          r'let register_device = "Y";',
        ),
      ),
    );
    expect(
      defaults,
      contains(
        RegExp(
          r'#\[cfg\(not\(any\(target_os = "android", target_os = "ios"\)\)\)\]\s*'
          r'let register_device = "N";',
        ),
      ),
    );
    expect(
      rendezvous,
      contains('no_register_device: Config::no_register_device()'),
    );
    expect(
      rendezvous,
      isNot(contains(
          'let requires_pk_confirmation = !Config::no_register_device()')),
    );
    expect(rendezvous, isNot(contains('clear_ios_uuid_mismatch_recovery')));
  });

  test(
      'iOS broadcast requires a fresh successful rendezvous response before ready',
      () {
    final native = File('../src/ios_broadcast.rs').readAsStringSync();
    final rendezvous = File('../src/rendezvous_mediator.rs').readAsStringSync();
    final handler =
        File('ios/KQScreenBroadcast/SampleHandler.swift').readAsStringSync();
    final bridge =
        File('ios/KQScreenBroadcast/KQBroadcastBridge.h').readAsStringSync();
    final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    final broadcastStart = native.indexOf('kq_ios_broadcast_start');
    final registrationState = native.indexOf(
      'pub extern "C" fn kq_ios_broadcast_registration_state',
    );
    final startBody = native.substring(broadcastStart, registrationState);
    expect(startBody, isNot(contains('Config::set_key_confirmed(false);')));
    expect(native, contains('IOS_RENDEZVOUS_LAST_RESPONSE_MS'));
    expect(native, contains('IOS_PEER_REGISTERED'));
    expect(native, contains('REGISTRATION_RESPONSE_STALE_MS'));
    expect(
        native,
        contains(
            'const REGISTRATION_RESPONSE_STALE_MS: i64 = hbb_common::config::REG_INTERVAL * 3;'));
    expect(
        rendezvous, contains('fn mark_ios_rendezvous_response_received()'));
    expect(
        rendezvous,
        contains(
            'Some(rendezvous_message::Union::RegisterPeerResponse(rpr))'));
    expect(rendezvous, contains('IOS_PEER_REGISTERED'));
    expect(
        rendezvous, contains('mark_ios_rendezvous_response_received();'));
    expect(
      rendezvous,
      contains('IOS_RENDEZVOUS_LAST_RESPONSE_MS'),
    );
    expect(
      native,
      contains(
          'pub extern "C" fn kq_ios_broadcast_registration_state() -> i32'),
    );
    expect(bridge, contains('kq_ios_broadcast_registration_state'));
    expect(handler, contains('kq_ios_broadcast_registration_state()'));
    expect(handler, contains('kq_broadcast_registration_state'));
    expect(handler, contains('kq_ios_broadcast_registration_rejection()'));
    expect(handler, contains('kq_broadcast_registration_rejection'));
    expect(delegate, contains('"registrationState"'));
    expect(delegate, contains('"registrationRejection"'));
  });

  test('iOS registers the broadcast ID immediately after key confirmation', () {
    final rendezvous = File('../src/rendezvous_mediator.rs').readAsStringSync();
    final registrationStart = rendezvous.indexOf(
      'Ok(register_pk_response::Result::OK) => {',
    );
    final registrationEnd = rendezvous.indexOf(
      'Ok(register_pk_response::Result::UUID_MISMATCH)',
      registrationStart,
    );

    expect(registrationStart, greaterThanOrEqualTo(0));
    expect(registrationEnd, greaterThan(registrationStart));
    final registrationSuccess =
        rendezvous.substring(registrationStart, registrationEnd);
    expect(registrationSuccess, contains('self.register_peer(sink).await?;'));
  });

  test('iOS broadcast always merges legacy rendezvous configuration', () {
    final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final migrationStart =
        delegate.indexOf('private func prepareBroadcastConfigDirectory');
    final migrationEnd = delegate.indexOf(
        'private func migrateBroadcastConfiguration', migrationStart);

    expect(migrationStart, greaterThanOrEqualTo(0));
    expect(migrationEnd, greaterThan(migrationStart));

    final preparation = delegate.substring(migrationStart, migrationEnd);
    expect(preparation, contains('try migrateBroadcastConfiguration('));
    expect(preparation, isNot(contains('existing.isEmpty')));
  });

  test('iOS migration unifies legacy App Group config profiles once', () {
    final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final migrationStart =
        delegate.indexOf('private func migrateBroadcastConfiguration');
    final migrationEnd =
        delegate.indexOf('public func dummyMethodToEnforceBundling');

    expect(migrationStart, greaterThanOrEqualTo(0));
    expect(migrationEnd, greaterThan(migrationStart));

    final migration = delegate.substring(migrationStart, migrationEnd);
    expect(migration, contains('let canonicalConfig'));
    expect(migration, contains('configProfileMigrationMarkerFileName'));
    expect(migration, contains('defaultConfigFileName'));
    expect(migration, contains('defaultConfig2FileName'));
    expect(migration, contains('Unified iOS config profile'));
    expect(migration, contains('BroadcastConfigSource'));
    expect(migration, contains('first(where: { candidate in'));
    expect(migration, contains('broadcastUuidFileName'));
    expect(migration, isNot(contains('credentialConfigFileNames')));
  });

  test('iOS broadcast seeds temporary password from shared config', () {
    final native = File('../src/ios_broadcast.rs').readAsStringSync();
    final start = native.indexOf('pub extern "C" fn kq_ios_broadcast_start');
    final stop =
        native.indexOf('pub extern "C" fn kq_ios_broadcast_registration_state');

    expect(start, greaterThanOrEqualTo(0));
    expect(stop, greaterThan(start));

    final startBody = native.substring(start, stop);
    expect(native, contains('fn seed_temporary_password_from_config()'));
    expect(startBody, contains('seed_temporary_password_from_config();'));
    expect(
      native,
      contains('hbb_common::password_security::set_temporary_password'),
    );
  });

  test('mobile temporary password is persisted for the iOS extension', () {
    final uiInterface = File('../src/ui_interface.rs').readAsStringSync();

    expect(uiInterface, contains('fn persist_mobile_temporary_password'));
    expect(
      uiInterface,
      contains('fn refresh_mobile_password_credentials_if_needed'),
    );
    expect(uiInterface, contains('Config::set_option("temporary-password"'));
    expect(uiInterface, contains('persist_mobile_temporary_password(&value);'));
    expect(uiInterface,
        contains('persist_mobile_temporary_password(&temporary_password());'));
    expect(
      uiInterface,
      contains(
          'password_security::reload_current_password_credentials_from_config();'),
    );
  });

  test('iOS broadcast snapshots verification codes before sending its salt',
      () {
    final config = File('../libs/hbb_common/src/config.rs').readAsStringSync();
    final passwordSecurity =
        File('../libs/hbb_common/src/password_security.rs').readAsStringSync();
    final connection = File('../src/server/connection.rs').readAsStringSync();
    final start = connection.indexOf('pub async fn start(');
    final validateStart = connection.indexOf('fn validate_password(');
    final validateEnd =
        connection.indexOf('fn is_recent_session', validateStart);

    expect(start, greaterThanOrEqualTo(0));
    expect(validateStart, greaterThanOrEqualTo(0));
    expect(validateEnd, greaterThan(validateStart));
    final validateBody = connection.substring(validateStart, validateEnd);

    expect(config, contains('pub fn reload_password_credentials_from_file'));
    expect(config, contains('OPTION_TEMPORARY_PASSWORD'));
    expect(config, contains('OPTION_KQ_DAILY_PASSWORD'));
    expect(config, contains('OPTION_KQ_DAILY_PASSWORD_DATE'));
    expect(config, contains('OPTION_VERIFICATION_METHOD'));
    expect(passwordSecurity,
        contains('pub fn reload_current_password_credentials_from_config'));
    expect(passwordSecurity,
        contains('pub fn snapshot_current_password_credentials_from_config'));
    expect(passwordSecurity, contains('pub struct IosPasswordCredentials'));
    expect(passwordSecurity, contains('fn normalize_ios_verification_code'));
    expect(passwordSecurity, contains('KQ_IOS_VERIFICATION_CODE_LEN'));
    expect(
        connection.substring(start, validateStart),
        contains(
            'password::snapshot_current_password_credentials_from_config();'));
    expect(validateBody, contains('return self.validate_ios_password'));
    expect(connection,
        contains('ios_password_credentials: password::IosPasswordCredentials'));
  });

  test('iOS uses one canonical App Group configuration identity', () {
    final native = File('../src/ios_broadcast.rs').readAsStringSync();
    final handler =
        File('ios/KQScreenBroadcast/SampleHandler.swift').readAsStringSync();
    final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(native, contains('let config_path = Config::file();'));
    expect(native, contains('return ERR_CONFIG_MISSING;'));
    expect(native, isNot(contains('config_names = ["RustDesk.toml"')));
    expect(handler, contains('private let configFileName = "鲲穹远程桌面.toml"'));
    expect(handler, isNot(contains('let configFiles = ["RustDesk.toml"')));
    expect(delegate,
        contains('private let broadcastConfigFileName = "鲲穹远程桌面.toml"'));
    expect(delegate,
        contains('private let defaultConfigFileName = "鲲穹远程桌面_default.toml"'));
    expect(delegate, contains('configProfileMigrationMarkerFileName'));
    expect(delegate, isNot(contains('credentialConfigFileNames')));
  });

  test('iOS fixes the config profile name after loading custom client data',
      () {
    final common = File('../src/common.rs').readAsStringSync();

    expect(
        common,
        contains(
            'The main app and ReplayKit extension are separate executables.'));
    expect(common, contains('#[cfg(target_os = "ios")]'));
    expect(
        common,
        contains(
            '*config::APP_NAME.write().unwrap() = KQ_APP_NAME.to_owned();'));
  });

  test('iOS UI keeps the broadcast entry compact and user-facing', () {
    final page = File('lib/mobile/pages/server_page.dart').readAsStringSync();

    expect(page, contains("invokeMethod<bool>('show_broadcast_picker')"));
    expect(
        page,
        contains(
            "invokeMethod<Map<dynamic, dynamic>>('get_broadcast_status')"));
    expect(page, contains('Timer.periodic'));
    expect(page, contains('等待系统确认'));
    expect(page, contains('可连接'));
    expect(page, contains("zhCn: '开启直播'"));
    expect(page, contains('屏幕共享启动失败'));
    expect(page, contains('_broadcastFailureText'));
    expect(page, isNot(contains('打开系统广播')));
    expect(page, isNot(contains('电脑和手机连接方式')));
    expect(page, isNot(contains('采集状态')));
    expect(page, isNot(contains('视频帧')));
    expect(page, isNot(contains('传输模式')));
    expect(page, isNot(contains('当前版本先验证采集链路')));
  });

  test('iOS broadcast keeps the standard device credentials card', () {
    final page = File('lib/mobile/pages/server_page.dart').readAsStringSync();
    final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final iosStart = page
        .indexOf('if (mobilePlatformCapabilities.canHostViewOnlyBroadcast)');
    final iosEnd = page.indexOf('    checkService();', iosStart);
    final broadcastStart =
        page.indexOf('class _IOSScreenShareBroadcastMvpState');
    final broadcastEnd =
        page.indexOf('class _IOSScreenShareUnavailable', broadcastStart);

    expect(iosStart, greaterThanOrEqualTo(0));
    expect(iosEnd, greaterThan(iosStart));
    expect(broadcastStart, greaterThanOrEqualTo(0));
    expect(broadcastEnd, greaterThan(broadcastStart));

    final iosBranch = page.substring(iosStart, iosEnd);
    final broadcastPage = page.substring(broadcastStart, broadcastEnd);
    expect(iosBranch, contains('ChangeNotifierProvider.value'));
    expect(iosBranch, contains('child: const _IOSScreenShareBroadcastMvp()'));
    expect(broadcastPage, contains('ServerInfo('));
    expect(broadcastPage, contains('connectionStatusTextOverride'));
    expect(broadcastPage, contains('_connectionAvailabilityText'));
    expect(broadcastPage, contains('sharingActionLabel:'));
    expect(broadcastPage, contains('onSharingAction:'));
    expect(broadcastPage, isNot(contains('addPostFrameCallback')));
    expect(
        broadcastPage, isNot(contains('_broadcastPickerPresentedThisSession')));
    expect(broadcastPage, isNot(contains('_openBroadcastPickerOnFirstEntry')));
    expect(broadcastPage, isNot(contains('PaddingCard(')));
    expect(delegate,
        contains('private var broadcastPicker: RPSystemBroadcastPickerView?'));
    expect(delegate, contains('broadcastPicker = picker'));
    expect(delegate, contains('DispatchQueue.main.asyncAfter'));
  });

  test('iOS broadcast emits native lifecycle diagnostics', () {
    final handler =
        File('ios/KQScreenBroadcast/SampleHandler.swift').readAsStringSync();

    expect(handler, contains('private func kqBroadcastLog('));
    expect(handler, contains('KQIOSDiagnostics.log('));
    expect(handler, contains('kqBroadcastLog("broadcast started"'));
    expect(handler, contains('kqBroadcastLog("app group is unavailable"'));
    expect(handler, contains('"broadcast transport start completed"'));
  });

  test('iOS main app and broadcast extension share the same native UUID', () {
    final common = File('../libs/hbb_common/src/lib.rs').readAsStringSync();
    final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final handler =
        File('ios/KQScreenBroadcast/SampleHandler.swift').readAsStringSync();

    expect(common, contains('fn get_ios_shared_uuid()'));
    expect(common, contains('kq-ios-device-uuid'));
    expect(common, contains('Config::get_existing_key_pair()'));
    expect(delegate, contains('remoteLink-config'));
    expect(handler, contains('remoteLink-config'));
  });

  test(
      'iOS password checks tolerate legacy keypair encryption and rotate visibly',
      () {
    final passwordSecurity =
        File('../libs/hbb_common/src/password_security.rs').readAsStringSync();
    final connection = File('../src/server/connection.rs').readAsStringSync();

    expect(passwordSecurity, contains('#[cfg(not(target_os = "android"))]'));
    expect(passwordSecurity, contains('Config::get_existing_key_pair()'));
    expect(connection, contains('Config::set_option('));
    expect(connection, contains('keys::OPTION_TEMPORARY_PASSWORD.to_owned()'));
    expect(connection, contains('fn rotate_temporary_password'));
    expect(connection, contains('successful one-time use'));
  });

  test(
      'iOS discards unreadable verification ciphertext and exposes its outcome',
      () {
    final config = File('../libs/hbb_common/src/config.rs').readAsStringSync();
    final native = File('../src/ios_broadcast.rs').readAsStringSync();
    final handler =
        File('ios/KQScreenBroadcast/SampleHandler.swift').readAsStringSync();
    final bridge =
        File('ios/KQScreenBroadcast/KQBroadcastBridge.h').readAsStringSync();

    expect(config, contains('VERIFICATION_CODE_OPTION_KEYS'));
    expect(config,
        contains('Discarded unreadable legacy iOS verification setting'));
    expect(config, contains('#[cfg(not(target_os = "ios"))]'));
    expect(native, contains('kq_ios_broadcast_last_auth_result'));
    expect(native, contains('AUTH_RESULT_REJECTED'));
    expect(handler, contains('"lastAuthResult": authenticationResult()'));
    expect(bridge, contains('kq_ios_broadcast_last_auth_result'));
  });
}
