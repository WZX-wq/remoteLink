import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common/kq_theme.dart';
import 'package:flutter_hbb/desktop/pages/desktop_home_page.dart';
import 'package:flutter_hbb/mobile/widgets/dialog.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import '../../common.dart';
import '../../common/widgets/dialog.dart';
import '../../consts.dart';
import '../../models/platform_model.dart';
import '../../models/mobile_platform_capability_policy.dart';
import '../../models/server_model.dart';
import 'page_shape.dart';

const _kqIOSBroadcastChannel = MethodChannel('mChannel');
const _kqMobileManualVerificationCodeLength = 6;

class ServerPage extends StatefulWidget implements PageShape {
  @override
  final title = translate("Share screen");

  @override
  final icon = const Icon(Icons.mobile_screen_share);

  @override
  final appBarActions = isIOS
      ? const <Widget>[]
      : (!bind.isDisableSettings() &&
              bind.mainGetBuildinOption(key: kOptionHideSecuritySetting) != 'Y')
          ? [_DropDownAction()]
          : <Widget>[];

  ServerPage({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _ServerPageState();
}

class _DropDownAction extends StatelessWidget {
  _DropDownAction();

  // should only have one action
  final actions = [
    PopupMenuButton<String>(
        tooltip: "",
        icon: const Icon(Icons.more_vert),
        itemBuilder: (context) {
          listTile(String text, bool checked) {
            return ListTile(
                title: Text(translate(text)),
                trailing: Icon(
                  Icons.check,
                  color: checked ? null : Colors.transparent,
                ));
          }

          final approveMode = gFFI.serverModel.approveMode;
          final verificationMethod = gFFI.serverModel.verificationMethod;
          final showPasswordOption = approveMode != 'click';
          final isApproveModeFixed = isOptionFixed(kOptionApproveMode);
          final isNumericOneTimePasswordFixed =
              isOptionFixed(kOptionAllowNumericOneTimePassword);
          final isAllowNumericOneTimePassword =
              gFFI.serverModel.allowNumericOneTimePassword;
          return [
            if (!isChangeIdDisabled())
              PopupMenuItem(
                enabled: gFFI.serverModel.connectStatus > 0,
                value: "changeID",
                child: Text(translate("Change ID")),
              ),
            if (!isChangeIdDisabled()) const PopupMenuDivider(),
            PopupMenuItem(
              value: 'AcceptSessionsViaPassword',
              child: listTile(
                  'Accept sessions via password', approveMode == 'password'),
              enabled: !isApproveModeFixed,
            ),
            PopupMenuItem(
              value: 'AcceptSessionsViaClick',
              child:
                  listTile('Accept sessions via click', approveMode == 'click'),
              enabled: !isApproveModeFixed,
            ),
            PopupMenuItem(
              value: "AcceptSessionsViaBoth",
              child: listTile("Accept sessions via both",
                  approveMode != 'password' && approveMode != 'click'),
              enabled: !isApproveModeFixed,
            ),
            if (showPasswordOption) const PopupMenuDivider(),
            if (showPasswordOption &&
                verificationMethod != kUseTemporaryPassword &&
                !isChangePermanentPasswordDisabled())
              PopupMenuItem(
                value: "setPermanentPassword",
                child: Text(translate("Set permanent password")),
              ),
            if (showPasswordOption &&
                verificationMethod != kUsePermanentPassword)
              PopupMenuItem(
                value: "setTemporaryPasswordLength",
                child: Text(translate("One-time password length")),
              ),
            if (showPasswordOption &&
                verificationMethod != kUsePermanentPassword)
              PopupMenuItem(
                value: "allowNumericOneTimePassword",
                child: listTile(translate("Numeric one-time password"),
                    isAllowNumericOneTimePassword),
                enabled: !isNumericOneTimePasswordFixed,
              ),
            if (showPasswordOption) const PopupMenuDivider(),
            if (showPasswordOption)
              PopupMenuItem(
                value: kUseTemporaryPassword,
                child: listTile('Use one-time password',
                    verificationMethod == kUseTemporaryPassword),
              ),
            if (showPasswordOption)
              PopupMenuItem(
                value: kUsePermanentPassword,
                child: listTile('Use permanent password',
                    verificationMethod == kUsePermanentPassword),
              ),
            if (showPasswordOption)
              PopupMenuItem(
                value: kUseBothPasswords,
                child: listTile(
                    'Use both passwords',
                    verificationMethod != kUseTemporaryPassword &&
                        verificationMethod != kUsePermanentPassword),
              ),
          ];
        },
        onSelected: (value) async {
          if (value == "changeID") {
            changeIdDialog();
          } else if (value == "setPermanentPassword") {
            setPasswordDialog();
          } else if (value == "setTemporaryPasswordLength") {
            setTemporaryPasswordLengthDialog(gFFI.dialogManager);
          } else if (value == "allowNumericOneTimePassword") {
            gFFI.serverModel.switchAllowNumericOneTimePassword();
            gFFI.serverModel.updatePasswordModel();
          } else if (value == kUsePermanentPassword ||
              value == kUseTemporaryPassword ||
              value == kUseBothPasswords) {
            callback() {
              bind.mainSetOption(key: kOptionVerificationMethod, value: value);
              gFFI.serverModel.updatePasswordModel();
            }

            if (value == kUsePermanentPassword &&
                (await bind.mainGetCommon(key: "permanent-password-set")) !=
                    "true") {
              if (isChangePermanentPasswordDisabled()) {
                callback();
                return;
              }
              setPasswordDialog(notEmptyCallback: callback);
            } else {
              callback();
            }
          } else if (value.startsWith("AcceptSessionsVia")) {
            value = value.substring("AcceptSessionsVia".length);
            if (value == "Password") {
              gFFI.serverModel.setApproveMode('password');
            } else if (value == "Click") {
              gFFI.serverModel.setApproveMode('click');
            } else {
              gFFI.serverModel.setApproveMode(defaultOptionApproveMode);
            }
          }
        })
  ];

  @override
  Widget build(BuildContext context) {
    return actions[0];
  }
}

class _ServerPageState extends State<ServerPage> with WidgetsBindingObserver {
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updateTimer = periodic_immediate(const Duration(seconds: 3), () async {
      await gFFI.serverModel.fetchID();
      await gFFI.serverModel.updatePasswordModel();
    });
    if (mobilePlatformCapabilities.canReceiveRemoteInput) {
      gFFI.serverModel.checkAndroidPermission();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed &&
        mobilePlatformCapabilities.canReceiveRemoteInput) {
      checkService();
      unawaited(gFFI.serverModel.checkAndroidPermission());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (mobilePlatformCapabilities.canHostViewOnlyBroadcast) {
      return ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: const _IOSScreenShareBroadcastMvp(),
      );
    }
    checkService();
    return ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: Consumer<ServerModel>(
            builder: (context, serverModel, child) => ListView(
                  controller: gFFI.serverModel.controller,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 22),
                  children: [
                    buildPresetPasswordWarningMobile(),
                    gFFI.serverModel.isStart
                        ? ServerInfo()
                        : ServiceNotRunningNotification(),
                    const ConnectionManager(),
                    const PermissionChecker(),
                  ],
                )));
  }
}

void checkService() async {
  if (!isAndroid) return;
  gFFI.invokeMethod("check_service");
  // for Android 10/11, request MANAGE_EXTERNAL_STORAGE permission from system setting page
  if (AndroidPermissionManager.isWaitingFile() && !gFFI.serverModel.fileOk) {
    AndroidPermissionManager.complete(kManageExternalStorage,
        await AndroidPermissionManager.check(kManageExternalStorage));
    debugPrint("file permission finished");
  }
}

class _IOSScreenShareBroadcastMvp extends StatefulWidget {
  const _IOSScreenShareBroadcastMvp();

  @override
  State<_IOSScreenShareBroadcastMvp> createState() =>
      _IOSScreenShareBroadcastMvpState();
}

class _IOSScreenShareBroadcastMvpState
    extends State<_IOSScreenShareBroadcastMvp> {
  bool _opening = false;
  String? _errorText;
  Timer? _broadcastStatusTimer;
  Timer? _voiceCallMetricsTimer;
  Map<String, dynamic>? _broadcastStatus;
  bool _voiceCallActive = false;
  bool _refreshingVoiceCallMetrics = false;
  bool _voiceInputActive = false;
  bool _voiceOutputActive = false;
  double _voiceInputLevel = 0;
  double _voiceOutputLevel = 0;
  int _voiceInputFrames = 0;
  int _voiceOutputFrames = 0;
  int _voiceFramesSent = 0;
  int _voiceFramesReceived = 0;
  DateTime? _voiceCallDetectedAt;
  bool _registeredIdFetched = false;

  @override
  void initState() {
    super.initState();
    _refreshBroadcastStatus();
    _broadcastStatusTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _refreshBroadcastStatus(),
    );
  }

  @override
  void dispose() {
    _broadcastStatusTimer?.cancel();
    _voiceCallMetricsTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshBroadcastStatus() async {
    try {
      final response = await _kqIOSBroadcastChannel
          .invokeMethod<Map<dynamic, dynamic>>('get_broadcast_status');
      if (mounted) {
        final status = response == null
            ? null
            : Map<String, dynamic>.fromEntries(
                response.entries.map(
                  (entry) => MapEntry(entry.key.toString(), entry.value),
                ),
              );
        setState(() {
          _broadcastStatus = status;
        });
        final registrationReady = _broadcastRegistrationReady(status);
        if (!registrationReady) {
          _registeredIdFetched = false;
        } else if (!_registeredIdFetched) {
          _registeredIdFetched = true;
          // The Rust core reads this value from the App Group canonical ID file.
          // Do not copy the extension telemetry ID into the main app state.
          await gFFI.serverModel.fetchID();
        }
      }
    } catch (e) {
      debugPrint('Failed to read iOS broadcast status: $e');
    } finally {
      if (mounted) {
        await _refreshIOSVoiceCallState();
      }
    }
  }

  Future<void> _refreshIOSVoiceCallState() async {
    if (_refreshingVoiceCallMetrics) return;
    _refreshingVoiceCallMetrics = true;
    try {
      final response = await _kqIOSBroadcastChannel
          .invokeMethod<Map<dynamic, dynamic>>('get_ios_voice_call_metrics');
      final metrics = response == null
          ? const <String, dynamic>{}
          : Map<String, dynamic>.fromEntries(response.entries.map(
              (entry) => MapEntry(entry.key.toString(), entry.value),
            ));
      final active = metrics['active'] == true;
      if (!mounted) return;
      if (active && !_voiceCallActive) {
        _voiceCallDetectedAt = DateTime.now();
      } else if (!active) {
        _voiceCallDetectedAt = null;
      }
      setState(() {
        _voiceCallActive = active;
        _voiceInputActive = metrics['inputActive'] == true;
        _voiceOutputActive = metrics['outputActive'] == true;
        _voiceInputLevel = (metrics['inputLevel'] as num?)?.toDouble() ?? 0;
        _voiceOutputLevel = (metrics['outputLevel'] as num?)?.toDouble() ?? 0;
        _voiceInputFrames = (metrics['inputFrames'] as num?)?.toInt() ?? 0;
        _voiceOutputFrames = (metrics['outputFrames'] as num?)?.toInt() ?? 0;
        _voiceFramesSent = (metrics['sentFrames'] as num?)?.toInt() ?? 0;
        _voiceFramesReceived =
            (metrics['receivedFrames'] as num?)?.toInt() ?? 0;
      });
      if (active && _voiceCallMetricsTimer == null) {
        _voiceCallMetricsTimer = Timer.periodic(
          const Duration(milliseconds: 160),
          (_) => _refreshIOSVoiceCallState(),
        );
      } else if (!active && _voiceCallMetricsTimer != null) {
        _voiceCallMetricsTimer?.cancel();
        _voiceCallMetricsTimer = null;
      }
    } on PlatformException catch (error) {
      debugPrint('Failed to read iOS voice call state: $error');
    } finally {
      _refreshingVoiceCallMetrics = false;
    }
  }

  Future<void> _endIOSVoiceCall() async {
    final ended =
        await _kqIOSBroadcastChannel.invokeMethod<bool>('end_ios_voice_call') ??
            false;
    if (!mounted) return;
    if (ended) {
      _voiceCallMetricsTimer?.cancel();
      _voiceCallMetricsTimer = null;
      setState(() {
        _voiceCallActive = false;
        _voiceInputLevel = 0;
        _voiceOutputLevel = 0;
      });
    } else {
      showToast(kqLocaleText(
        zhCn: '语音通话已结束。',
        en: 'The voice call has ended.',
      ));
    }
  }

  String _voiceCallStatusText() {
    final waitingForAudio = _voiceCallDetectedAt != null &&
        DateTime.now().difference(_voiceCallDetectedAt!).inSeconds >= 3 &&
        _voiceInputFrames == 0 &&
        _voiceFramesSent == 0;
    if (waitingForAudio) {
      return kqLocaleText(
        zhCn: '未检测到麦克风声音',
        en: 'No microphone audio',
      );
    }
    if (_voiceInputActive && _voiceInputLevel >= 0.04) {
      return kqLocaleText(zhCn: '正在说话', en: 'Speaking');
    }
    if (_voiceOutputActive && _voiceOutputLevel >= 0.04) {
      return kqLocaleText(zhCn: '对方正在说话', en: 'Peer speaking');
    }
    return kqLocaleText(zhCn: '语音通话中', en: 'Voice call active');
  }

  Widget _buildIOSVoiceCallBar(BuildContext context) {
    final q = KqTheme.of(context);
    final hasAudioFlow = _voiceFramesSent > 0 ||
        _voiceFramesReceived > 0 ||
        _voiceInputFrames > 0 ||
        _voiceOutputFrames > 0;
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: q.surfaceSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: q.line),
      ),
      child: Row(children: [
        _IOSVoiceLevelIndicator(
          level: _voiceInputLevel,
          active: _voiceInputActive,
          color: hasAudioFlow ? q.online : q.primary,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _voiceCallStatusText(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: q.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                kqLocaleText(zhCn: '麦克风已开启', en: 'Microphone on'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: q.muted, fontSize: 11),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Semantics(
          button: true,
          label: kqLocaleText(zhCn: '结束语音通话', en: 'End voice call'),
          child: Material(
            color: q.offline,
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: kqLocaleText(zhCn: '结束语音通话', en: 'End voice call'),
              onPressed: _endIOSVoiceCall,
              constraints: const BoxConstraints.tightFor(width: 44, height: 44),
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.call_end_rounded,
                  color: Colors.white, size: 21),
            ),
          ),
        ),
      ]),
    );
  }

  bool _hasBroadcastHeartbeat([Map<String, dynamic>? status]) {
    status ??= _broadcastStatus;
    if (status == null || status['isFresh'] != true) return false;
    return const <String>{
      'starting',
      'started',
      'capturing',
      'paused',
      'resumed'
    }.contains(status['state']);
  }

  bool _remoteViewAvailable() {
    final remoteViewAvailable = _broadcastStatus?['remoteViewAvailable'];
    return remoteViewAvailable == true;
  }

  bool _broadcastAudioSupported() {
    final audioSupported = _broadcastStatus?['audioSupported'];
    return audioSupported == true;
  }

  bool _broadcastRegistrationReady([Map<String, dynamic>? status]) {
    status ??= _broadcastStatus;
    if (status == null || !_hasBroadcastHeartbeat(status)) return false;
    final registrationState = status['registrationState'];
    return registrationState is num && registrationState.toInt() == 2;
  }

  String? _broadcastFailureText() {
    final status = _broadcastStatus;
    if (status == null) return null;
    final errorCode = (status['errorCode'] as String? ?? '').trim();
    final failed = status['state'] == 'failed' || errorCode.isNotEmpty;
    if (!failed) return null;

    switch (errorCode) {
      case 'app_group_unavailable':
        return _iosShareText(
          zhCn: '屏幕共享启动失败，请重新安装最新版本后再试。',
          zhTw: '螢幕分享啟動失敗，請重新安裝最新版本後再試。',
          en: 'Screen sharing could not start. Reinstall the latest build and try again.',
        );
      case 'server_registration_required':
        return _iosShareText(
          zhCn: '设备暂未完成服务注册，请关闭直播后重新开启。',
          zhTw: '裝置尚未完成服務註冊，請停止直播後重新開啟。',
          en: 'The device has not completed service registration. Stop and start the broadcast again.',
        );
      case 'server_registration_timeout':
        return _iosShareText(
          zhCn: '设备接入服务超时，请检查网络后重新开启直播。',
          zhTw: '裝置接入服務逾時，請檢查網路後重新開啟直播。',
          en: 'Device registration timed out. Check the network and restart the broadcast.',
        );
      case 'pixel_buffer_conversion_failed':
        return _iosShareText(
          zhCn: '屏幕画面初始化失败，请重新开启直播。',
          zhTw: '螢幕畫面初始化失敗，請重新開啟直播。',
          en: 'Screen capture could not initialize. Start the broadcast again.',
        );
      default:
        return _iosShareText(
          zhCn: '屏幕共享启动失败，请关闭直播后重新开启。',
          zhTw: '螢幕分享啟動失敗，請停止直播後重新開啟。',
          en: 'Screen sharing could not start. Stop and start the broadcast again.',
        );
    }
  }

  String _connectionAvailabilityText() {
    final status = _broadcastStatus;
    if (_broadcastFailureText() != null) {
      return _iosShareText(
        zhCn: '暂不可连接',
        zhTw: '暫不可連線',
        en: 'Not available',
      );
    }
    if (status == null || !_hasBroadcastHeartbeat()) {
      return _opening
          ? _iosShareText(
              zhCn: '等待系统确认',
              zhTw: '等待系統確認',
              en: 'Waiting for system confirmation',
            )
          : _iosShareText(
              zhCn: '等待开启',
              zhTw: '等待開啟',
              en: 'Waiting to start',
            );
    }
    if (_remoteViewAvailable()) {
      return _iosShareText(
        zhCn: '正在共享',
        zhTw: '正在分享',
        en: 'Sharing',
      );
    }
    final registrationState = status['registrationState'];
    if (registrationState is num) {
      switch (registrationState.toInt()) {
        case 2:
          if (!_broadcastRegistrationReady()) {
            return _iosShareText(
              zhCn: '正在确认设备标识',
              zhTw: '正在確認裝置識別碼',
              en: 'Confirming device identity',
            );
          }
          return _iosShareText(
            zhCn: '可连接',
            zhTw: '可連線',
            en: 'Sharing started, waiting for another device',
          );
        case 3:
          return _iosShareText(
            zhCn: '暂不可连接',
            zhTw: '暫不可連線',
            en: 'Not available',
          );
        case 4:
          return _iosShareText(
            zhCn: '接入超时',
            zhTw: '接入逾時',
            en: 'Registration timed out',
          );
        case 1:
          return _iosShareText(
            zhCn: '正在接入鲲穹远程',
            zhTw: '正在接入鯤穹遠端',
            en: 'Connecting to Kunqiong Remote',
          );
      }
    }
    return _iosShareText(
      zhCn: '正在接入鲲穹远程',
      zhTw: '正在接入鯤穹遠端',
      en: 'Connecting to Kunqiong Remote',
    );
  }

  Future<void> _openBroadcastPicker() async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _errorText = null;
    });
    try {
      showToast(_iosShareText(
        zhCn: '需要语音通话时，请在系统直播面板打开麦克风。',
        zhTw: '需要語音通話時，請在系統直播面板開啟麥克風。',
        en: 'For voice calls, turn on Microphone in the system broadcast panel.',
      ));
      final opened = await _kqIOSBroadcastChannel
          .invokeMethod<bool>('show_broadcast_picker');
      if (!mounted) return;
      if (opened != true) {
        setState(() {
          _errorText = _iosShareText(
            zhCn: '未能打开系统屏幕共享面板，请确认安装包包含 Broadcast 扩展。',
            zhTw: '未能開啟系統螢幕分享面板，請確認安裝包包含 Broadcast 擴充功能。',
            en: 'Could not open the system screen sharing panel. Check that the build includes the Broadcast extension.',
          );
        });
      }
    } on PlatformException catch (e) {
      debugPrint('Failed to open iOS broadcast picker: $e');
      if (!mounted) return;
      setState(() {
        _errorText = e.code == 'ios_simulator_unavailable'
            ? _iosShareText(
                zhCn: 'iOS 模拟器不支持系统屏幕直播，请连接真机测试。',
                zhTw: 'iOS 模擬器不支援系統螢幕直播，請連接真機測試。',
                en: 'iOS Simulator cannot start system screen sharing. Test on a real iPhone.',
              )
            : _iosShareText(
                zhCn: '暂时无法打开屏幕共享，请重新打开应用后再试。',
                zhTw: '暫時無法開啟螢幕分享，請重新開啟應用程式後再試。',
                en: 'Screen sharing could not be opened. Reopen the app and try again.',
              );
      });
    } catch (e) {
      debugPrint('Failed to open iOS broadcast picker: $e');
      if (!mounted) return;
      setState(() {
        _errorText = _iosShareText(
          zhCn: '暂时无法打开屏幕共享，请重新打开应用后再试。',
          zhTw: '暫時無法開啟螢幕分享，請重新開啟應用程式後再試。',
          en: 'Screen sharing could not be opened. Reopen the app and try again.',
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _opening = false;
        });
        _refreshBroadcastStatus();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final connectionAvailabilityText = _connectionAvailabilityText();
    final broadcastActive = _hasBroadcastHeartbeat();
    final registrationReady = _broadcastRegistrationReady();
    final remoteViewAvailable = _remoteViewAvailable();
    final audioSupported = _broadcastAudioSupported();

    return Semantics(
      label:
          'view-only audioSupported=$audioSupported remoteViewAvailable=$remoteViewAvailable',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 22),
        children: [
          ServerInfo(
            connectionStatusTextOverride: connectionAvailabilityText,
            showDeviceId: registrationReady,
            sharingActionLabel: broadcastActive
                ? _iosShareText(
                    zhCn: remoteViewAvailable ? '正在共享' : '直播已开启',
                    zhTw: remoteViewAvailable ? '正在分享' : '直播已開啟',
                    en: remoteViewAvailable ? 'Sharing' : 'Live',
                  )
                : _iosShareText(
                    zhCn: '开启直播',
                    zhTw: '開啟直播',
                    en: 'Start live',
                  ),
            sharingActionIcon: broadcastActive
                ? Icons.check_circle_outline_rounded
                : Icons.play_circle_outline_rounded,
            onSharingAction:
                _opening || broadcastActive ? null : _openBroadcastPicker,
            sharingErrorText: _broadcastFailureText() ?? _errorText,
          ),
          if (_voiceCallActive) ...[
            const SizedBox(height: 12),
            _buildIOSVoiceCallBar(context),
          ],
        ],
      ),
    );
  }
}

class _IOSVoiceLevelIndicator extends StatelessWidget {
  const _IOSVoiceLevelIndicator({
    required this.level,
    required this.active,
    required this.color,
  });

  final double level;
  final bool active;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final normalized = active ? level.clamp(0.0, 1.0).toDouble() : 0.0;
    final heights = <double>[
      6 + normalized * 8,
      8 + normalized * 15,
      6 + normalized * 11,
    ];
    return SizedBox(
      width: 48,
      height: 44,
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.mic_rounded, color: color, size: 18),
        ),
        const SizedBox(width: 3),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: heights
              .map((height) => AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOut,
                    width: 2,
                    height: height,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ))
              .toList(),
        ),
      ]),
    );
  }
}

// ignore: unused_element
class _IOSScreenShareUnavailable extends StatelessWidget {
  const _IOSScreenShareUnavailable();

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 22),
      children: [
        PaddingCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: q.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.mobile_screen_share_rounded,
                      color: q.primary, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _iosShareText(
                          zhCn: 'iOS 屏幕共享暂不可用',
                          zhTw: 'iOS 螢幕分享暫不可用',
                          en: 'iOS screen sharing is not available yet',
                        ),
                        style: TextStyle(
                          color: q.ink,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _iosShareText(
                          zhCn:
                              '当前安装包没有 iOS 屏幕采集服务，不能作为被控端共享本机屏幕；iPhone 仍可远程连接其他设备。',
                          zhTw:
                              '目前安裝包沒有 iOS 螢幕擷取服務，不能作為被控端分享本機螢幕；iPhone 仍可遠端連線其他裝置。',
                          en: 'This build does not include the iOS screen capture service, so this iPhone cannot share its own screen as a controlled device. You can still connect from iPhone to other devices.',
                        ),
                        style: TextStyle(
                          color: q.muted,
                          fontSize: 13,
                          height: 1.36,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              _IOSShareRequirementNotice(
                text: _iosShareText(
                  zhCn: '要真正支持苹果端屏幕共享，需要接入 ReplayKit Broadcast 扩展并配置对应签名。',
                  zhTw: '要真正支援蘋果端螢幕分享，需要接入 ReplayKit Broadcast 擴充功能並配置對應簽名。',
                  en: 'Real iOS screen sharing requires a ReplayKit Broadcast extension and matching signing setup.',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _IOSShareRequirementNotice extends StatelessWidget {
  const _IOSShareRequirementNotice({
    required this.text,
  });

  final String text;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: q.warning.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: q.warning.withOpacity(0.22)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline_rounded, color: q.warning, size: 19),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: q.ink,
              fontSize: 12,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ]),
    );
  }
}

String _iosShareText({
  required String zhCn,
  required String zhTw,
  required String en,
}) {
  if (!kqUiPrefersChinese()) {
    return translate(en);
  }
  return kqUiPrefersSimplifiedChinese() ? zhCn : zhTw;
}

class ServiceNotRunningNotification extends StatelessWidget {
  ServiceNotRunningNotification({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final serverModel = Provider.of<ServerModel>(context);
    final q = KqTheme.of(context);

    return PaddingCard(
        child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: q.warning.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.play_circle_outline_rounded,
                color: q.warning, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  translate("Service is not running"),
                  style: TextStyle(
                    color: q.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  translate("android_start_service_tip"),
                  style: TextStyle(
                    color: q.muted,
                    fontSize: 12,
                    height: 1.28,
                  ),
                ),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
              icon: const Icon(Icons.play_arrow_rounded),
              onPressed: () {
                if (gFFI.userModel.userName.value.isEmpty &&
                    bind.mainGetLocalOption(key: "show-scam-warning") != "N") {
                  showScamWarning(context, serverModel);
                } else {
                  serverModel.toggleService();
                }
              },
              label: Text(translate("Start service"))),
        )
      ],
    ));
  }
}

class ScamWarningDialog extends StatefulWidget {
  final ServerModel serverModel;

  ScamWarningDialog({required this.serverModel});

  @override
  ScamWarningDialogState createState() => ScamWarningDialogState();
}

class ScamWarningDialogState extends State<ScamWarningDialog> {
  int _countdown = bind.isCustomClient() ? 0 : 12;
  bool show_warning = false;
  late Timer _timer;
  late ServerModel _serverModel;

  @override
  void initState() {
    super.initState();
    _serverModel = widget.serverModel;
    startCountdown();
  }

  void startCountdown() {
    const oneSecond = Duration(seconds: 1);
    _timer = Timer.periodic(oneSecond, (timer) {
      setState(() {
        _countdown--;
        if (_countdown <= 0) {
          timer.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isButtonLocked = _countdown > 0;

    return AlertDialog(
      content: ClipRRect(
        borderRadius: BorderRadius.circular(20.0),
        child: SingleChildScrollView(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [
                  Color(0xffe242bc),
                  Color(0xfff4727c),
                ],
              ),
            ),
            padding: EdgeInsets.all(25.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_sharp,
                      color: Colors.white,
                    ),
                    SizedBox(width: 10),
                    Text(
                      translate("Warning"),
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 20.0,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 20),
                Center(
                  child: Image.asset(
                    'assets/scam.png',
                    width: 180,
                  ),
                ),
                SizedBox(height: 18),
                Text(
                  translate("scam_title"),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 22.0,
                  ),
                ),
                SizedBox(height: 18),
                Text(
                  "${translate("scam_text1")}\n\n${translate("scam_text2")}\n",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16.0,
                  ),
                ),
                Row(
                  children: <Widget>[
                    Checkbox(
                      value: show_warning,
                      onChanged: (value) {
                        setState(() {
                          show_warning = value!;
                        });
                      },
                    ),
                    Text(
                      translate("Don't show again"),
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15.0,
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      constraints: BoxConstraints(maxWidth: 150),
                      child: ElevatedButton(
                        onPressed: isButtonLocked
                            ? null
                            : () {
                                Navigator.of(context).pop();
                                _serverModel.toggleService();
                                if (show_warning) {
                                  bind.mainSetLocalOption(
                                      key: "show-scam-warning", value: "N");
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                        ),
                        child: Text(
                          isButtonLocked
                              ? "${translate("I Agree")} (${_countdown}s)"
                              : translate("I Agree"),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.0,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    SizedBox(width: 15),
                    Container(
                      constraints: BoxConstraints(maxWidth: 150),
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                        ),
                        child: Text(
                          translate("Decline"),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.0,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      contentPadding: EdgeInsets.all(0.0),
    );
  }
}

class ServerInfo extends StatelessWidget {
  ServerInfo({
    Key? key,
    this.connectionStatusTextOverride,
    this.showDeviceId = true,
    this.sharingActionLabel,
    this.sharingActionIcon,
    this.onSharingAction,
    this.sharingErrorText,
  }) : super(key: key);

  final model = gFFI.serverModel;
  final emptyController = TextEditingController(text: "-");
  final String? connectionStatusTextOverride;
  final bool showDeviceId;
  final String? sharingActionLabel;
  final IconData? sharingActionIcon;
  final VoidCallback? onSharingAction;
  final String? sharingErrorText;

  @override
  Widget build(BuildContext context) {
    final serverModel = Provider.of<ServerModel>(context);
    final q = KqTheme.of(context);
    // The App Group ID is the only identity users can rely on. The broadcast
    // status is transport telemetry and must never replace it while ReplayKit
    // starts or stops.
    final displayedDeviceId = model.serverId.value.text;

    void copyToClipboard(String value) {
      Clipboard.setData(ClipboardData(text: value));
      showToast(translate('Copied'));
    }

    Widget ConnectionStateNotification() {
      final Color color;
      final IconData icon;
      final String text;
      if (connectionStatusTextOverride != null) {
        color = q.warning;
        icon = Icons.sync_rounded;
        text = connectionStatusTextOverride!;
      } else if (serverModel.connectStatus == -1) {
        color = q.offline;
        icon = Icons.warning_amber_rounded;
        text = translate('not_ready_status');
      } else if (serverModel.connectStatus == 0) {
        color = q.warning;
        icon = Icons.sync_rounded;
        text = translate('connecting_status');
      } else {
        color = q.online;
        icon = Icons.verified_rounded;
        text = translate('Ready');
      }
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withOpacity(0.24)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ]),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color: q.panelStrong.withOpacity(q.isDark ? 0.8 : 0.95),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: q.line),
        boxShadow: [
          BoxShadow(
            color: q.shadow.withOpacity(q.isDark ? 0.92 : 0.78),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: q.primary.withOpacity(q.isDark ? 0.18 : 0.1),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: q.primary.withOpacity(0.22)),
                ),
                child: Icon(
                  Icons.mobile_screen_share_rounded,
                  color: q.primary,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      translate('Your Device'),
                      style: TextStyle(
                        color: q.ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        height: 1.08,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      translate('Share screen'),
                      style: TextStyle(
                        color: q.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(child: ConnectionStateNotification()),
            ],
          ),
          const SizedBox(height: 14),
          if (showDeviceId) ...[
            _DeviceSecretTile(
              label: translate('ID'),
              value: displayedDeviceId,
              icon: Icons.perm_identity_rounded,
              onCopy: () => copyToClipboard(displayedDeviceId.trim()),
            ),
            const SizedBox(height: 10),
          ],
          _DevicePasswordTile(
            serverModel: serverModel,
            onCopy: serverModel.selectedPasswordCanCopy
                ? () => copyToClipboard(serverModel.selectedPasswordText.trim())
                : null,
            onRefresh: serverModel.selectedPasswordCanRefresh
                ? () => serverModel.refreshSelectedPassword()
                : null,
            onEdit: bind.isDisableSettings()
                ? null
                : () => _showMobileKqPasswordDialog(serverModel),
          ),
          if (sharingActionLabel != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                icon: Icon(
                  sharingActionIcon ?? Icons.mobile_screen_share_rounded,
                  size: 21,
                ),
                label: Text(
                  sharingActionLabel!,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  elevation: onSharingAction == null ? 0 : 3,
                  shadowColor: q.primary.withOpacity(0.26),
                  backgroundColor: onSharingAction == null ? q.line : q.primary,
                  foregroundColor:
                      onSharingAction == null ? q.muted : Colors.white,
                  disabledBackgroundColor: q.line.withOpacity(0.72),
                  disabledForegroundColor: q.muted,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: onSharingAction,
              ),
            ),
          ],
          if (sharingErrorText != null) ...[
            const SizedBox(height: 10),
            _IOSShareRequirementNotice(text: sharingErrorText!),
          ],
        ],
      ),
    );
  }
}

class _DevicePasswordTile extends StatefulWidget {
  const _DevicePasswordTile({
    required this.serverModel,
    required this.onCopy,
    required this.onRefresh,
    required this.onEdit,
  });

  final ServerModel serverModel;
  final VoidCallback? onCopy;
  final VoidCallback? onRefresh;
  final VoidCallback? onEdit;

  @override
  State<_DevicePasswordTile> createState() => _DevicePasswordTileState();
}

class _DevicePasswordTileState extends State<_DevicePasswordTile> {
  bool _revealPassword = false;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    final serverModel = widget.serverModel;
    final actions = [
      _MobilePasswordActionData(
        tooltip: _revealPassword ? '隐藏验证码' : '显示验证码',
        icon: _revealPassword
            ? Icons.visibility_off_outlined
            : Icons.visibility_outlined,
        onPressed: () => setState(() => _revealPassword = !_revealPassword),
      ),
      _MobilePasswordActionData(
        tooltip: translate('Refresh Password'),
        icon: Icons.refresh_rounded,
        onPressed: widget.onRefresh,
      ),
      if (widget.onEdit != null)
        _MobilePasswordActionData(
          tooltip: translate('Change Password'),
          icon: Icons.edit_rounded,
          onPressed: widget.onEdit,
        ),
      _MobilePasswordActionData(
        tooltip: translate('Copy'),
        icon: Icons.copy_outlined,
        onPressed: widget.onCopy,
      ),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
      decoration: BoxDecoration(
        color: q.field.withOpacity(q.isDark ? 0.72 : 0.98),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: q.line),
      ),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: PopupMenuButton<KqPasswordKind>(
                  tooltip: '选择验证码类型',
                  initialValue: serverModel.selectedPasswordKind,
                  onSelected: serverModel.setSelectedPasswordKind,
                  color: q.panelStrong,
                  elevation: 8,
                  shadowColor: q.primary.withOpacity(0.16),
                  offset: const Offset(0, 4),
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: q.line),
                  ),
                  itemBuilder: (context) => KqPasswordKind.values
                      .map(
                        (kind) => PopupMenuItem<KqPasswordKind>(
                          value: kind,
                          height: 42,
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _mobileKqPasswordKindLabel(kind),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: q.ink,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              if (kind == serverModel.selectedPasswordKind)
                                Icon(Icons.check_rounded,
                                    color: q.primary, size: 18),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_outline_rounded,
                          size: 14, color: q.muted),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          serverModel.selectedPasswordLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: q.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.keyboard_arrow_down_rounded,
                          size: 16, color: q.muted),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 5),
              AnimatedBuilder(
                animation: serverModel.selectedPasswordController,
                builder: (context, _) => Text(
                  kqPasswordTextForUi(
                    rawText: serverModel.selectedPasswordText,
                    reveal: _revealPassword,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: q.ink,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _MobilePasswordActionGrid(actions: actions),
      ]),
    );
  }
}

class _MobilePasswordActionData {
  const _MobilePasswordActionData({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
}

class _MobilePasswordActionGrid extends StatelessWidget {
  const _MobilePasswordActionGrid({required this.actions});

  final List<_MobilePasswordActionData> actions;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    final enabledBackground = q.panelStrong.withOpacity(q.isDark ? 0.78 : 0.94);
    final disabledBackground = q.line.withOpacity(q.isDark ? 0.18 : 0.36);
    final disabledColor = q.muted.withOpacity(0.5);

    Widget buildButton(_MobilePasswordActionData action) {
      return Container(
        decoration: BoxDecoration(
          color:
              action.onPressed == null ? disabledBackground : enabledBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: action.onPressed == null
                ? Colors.transparent
                : q.line.withOpacity(0.86),
          ),
        ),
        child: IconButton(
          tooltip: action.tooltip,
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: Icon(
            action.icon,
            color: action.onPressed == null ? disabledColor : q.primary,
            size: 19,
          ),
          onPressed: action.onPressed,
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          buildButton(actions[i]),
        ],
      ],
    );
  }
}

String _mobileKqPasswordKindLabel(KqPasswordKind kind) {
  switch (kind) {
    case KqPasswordKind.oneTime:
      return '一次性验证码';
    case KqPasswordKind.daily:
      return '今日验证码';
    case KqPasswordKind.permanent:
      return '长期验证码';
  }
}

Future<void> _setMobilePasswordDialogPortraitOrientation({
  required bool locked,
}) async {
  if (!isIOS) {
    return;
  }
  try {
    await SystemChrome.setPreferredOrientations(
      locked ? const [DeviceOrientation.portraitUp] : const [],
    );
  } catch (e) {
    debugPrint('Failed to update password dialog orientation: $e');
  }
}

void _showMobileKqPasswordDialog(ServerModel model) {
  final editingKind = model.selectedPasswordKind;
  final isPermanent = editingKind == KqPasswordKind.permanent;
  final lockPortrait = isIOS && isPermanent;
  final title = _mobileKqPasswordKindLabel(editingKind);
  final maxLength = _kqMobileManualVerificationCodeLength;
  final initialPasswordText = model.selectedPasswordCanCopy
      ? model.selectedPasswordText.trim().characters.take(maxLength).join()
      : '';
  final lengthLimiter = LengthLimitingTextInputFormatter(maxLength);
  final controller = TextEditingController(
    text: initialPasswordText,
  );
  final confirmController = TextEditingController(text: '');
  var errMsg = '';
  var confirmErrMsg = '';
  var submitting = false;

  showDialog() async {
    if (lockPortrait) {
      await _setMobilePasswordDialogPortraitOrientation(locked: true);
    }
    try {
      await gFFI.dialogManager.show((setState, close, context) {
        final q = KqTheme.of(context);

        submit() async {
          if (submitting) {
            return;
          }
          setState(() {
            errMsg = '';
            confirmErrMsg = '';
            submitting = true;
          });
          final value = controller.text.trim();
          if (value.isEmpty) {
            setState(() {
              errMsg = '验证码不能为空';
              submitting = false;
            });
            return;
          }
          if (isPermanent && confirmController.text.trim() != value) {
            setState(() {
              confirmErrMsg = translate("The confirmation is not identical.");
              submitting = false;
            });
            return;
          }
          var ok = true;
          if (editingKind == KqPasswordKind.oneTime) {
            await model.setOneTimePassword(value);
          } else if (editingKind == KqPasswordKind.daily) {
            await model.setDailyPassword(value);
          } else {
            ok = await model.setPermanentPasswordPreview(value);
          }
          if (!ok) {
            setState(() {
              errMsg = translate("Failed");
              submitting = false;
            });
            return;
          }
          showToast('已更新$title');
          close();
        }

        return CustomAlertDialog(
          title: _MobileKqPasswordDialogHeader(
            title: title,
            onCancel: close,
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  obscureText: false,
                  decoration: InputDecoration(
                    labelText: title,
                    errorText: errMsg.isEmpty ? null : errMsg,
                  ),
                  enabled: !submitting,
                  maxLength: maxLength,
                  inputFormatters: [lengthLimiter],
                  onChanged: (_) {
                    if (errMsg.isNotEmpty) {
                      setState(() => errMsg = '');
                    }
                  },
                ).workaroundFreezeLinuxMint(),
                if (isPermanent) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: confirmController,
                    obscureText: false,
                    decoration: InputDecoration(
                      labelText: translate('Confirmation'),
                      errorText: confirmErrMsg.isEmpty ? null : confirmErrMsg,
                    ),
                    enabled: !submitting,
                    maxLength: maxLength,
                    inputFormatters: [lengthLimiter],
                    onChanged: (_) {
                      if (confirmErrMsg.isNotEmpty) {
                        setState(() => confirmErrMsg = '');
                      }
                    },
                  ).workaroundFreezeLinuxMint(),
                  const SizedBox(height: 4),
                  Text(
                    '长期验证码会同时更新远程连接使用的长期密码，并在本机可见。',
                    style: TextStyle(
                      color: q.muted,
                      fontSize: 12,
                      height: 1.25,
                    ),
                  ),
                ],
                if (submitting)
                  const LinearProgressIndicator().marginOnly(top: 12),
              ],
            ),
          ),
          actions: [
            _MobileKqPasswordDialogActions(
              submitting: submitting,
              onSubmit: submit,
            ),
          ],
          onSubmit: submitting ? null : submit,
          onCancel: close,
        );
      });
    } finally {
      if (lockPortrait) {
        await _setMobilePasswordDialogPortraitOrientation(locked: false);
      }
    }
  }

  unawaited(showDialog());
}

class _MobileKqPasswordDialogHeader extends StatelessWidget {
  const _MobileKqPasswordDialogHeader({
    required this.title,
    required this.onCancel,
  });

  final String title;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    Widget compactIconButton({
      required String tooltip,
      required IconData icon,
      required Color color,
      required VoidCallback? onPressed,
    }) {
      return IconButton(
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
        iconSize: 22,
        icon: Icon(icon, color: color),
        onPressed: onPressed,
      );
    }

    return Row(
      children: [
        Icon(Icons.key_rounded, color: q.primary, size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '修改$title',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: q.ink,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        compactIconButton(
          tooltip: translate('Close'),
          icon: Icons.close_rounded,
          color: q.muted,
          onPressed: onCancel,
        ),
      ],
    );
  }
}

class _MobileKqPasswordDialogActions extends StatelessWidget {
  const _MobileKqPasswordDialogActions({
    required this.submitting,
    required this.onSubmit,
  });

  final bool submitting;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          dialogButton(
            "OK",
            icon: const Icon(Icons.done_rounded),
            onPressed: submitting ? null : onSubmit,
          ),
        ],
      ),
    );
  }
}

class _DeviceSecretTile extends StatelessWidget {
  const _DeviceSecretTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.onCopy,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 12, 9, 12),
      decoration: BoxDecoration(
        color: q.field.withOpacity(q.isDark ? 0.72 : 0.98),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: q.line),
      ),
      child: Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: q.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: q.primary, size: 20),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: q.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: q.ink,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: q.primary.withOpacity(q.isDark ? 0.16 : 0.08),
            borderRadius: BorderRadius.circular(13),
          ),
          child: IconButton(
            tooltip: translate('Copy'),
            constraints: const BoxConstraints.tightFor(width: 42, height: 42),
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: Icon(Icons.copy_outlined, color: q.primary, size: 20),
            onPressed: onCopy,
          ),
        ),
      ]),
    );
  }
}

class PermissionChecker extends StatefulWidget {
  const PermissionChecker({Key? key}) : super(key: key);

  @override
  State<PermissionChecker> createState() => _PermissionCheckerState();
}

class _PermissionCheckerState extends State<PermissionChecker> {
  bool _isCheckingAll = false;
  bool _showAllPermissions = false;

  Future<void> _toggleInputControl(ServerModel serverModel) async {
    await serverModel.toggleInput();
    if (isAndroid) {
      Future.delayed(const Duration(milliseconds: 800), checkService);
    }
  }

  Future<void> _runAllPermissionSteps({
    required ServerModel serverModel,
    required bool hasAudioPermission,
    required bool hideStopService,
    required bool permissionChangeLocked,
  }) async {
    if (_isCheckingAll) return;
    setState(() => _isCheckingAll = true);
    try {
      if (!serverModel.mediaOk && !hideStopService) {
        final needsScamWarning = gFFI.userModel.userName.value.isEmpty &&
            bind.mainGetLocalOption(key: "show-scam-warning") != "N";
        if (needsScamWarning) {
          showScamWarning(context, serverModel);
          return;
        }
        await serverModel.toggleService();
      }
      if (!serverModel.inputOk) {
        await _toggleInputControl(serverModel);
      }
      if (!permissionChangeLocked && !serverModel.fileOk) {
        await serverModel.toggleFile();
      }
      if (!permissionChangeLocked &&
          hasAudioPermission &&
          !serverModel.audioOk) {
        await serverModel.toggleAudio();
      }
      if (!serverModel.clipboardOk) {
        await serverModel.toggleClipboard();
      }
    } finally {
      if (mounted) {
        setState(() => _isCheckingAll = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final serverModel = Provider.of<ServerModel>(context);
    final q = KqTheme.of(context);
    final hasAudioPermission = androidVersion >= 30;
    final hideStopService = isAndroid &&
        bind.mainGetBuildinOption(key: kOptionHideStopService) == 'Y';
    final allowPermChangeInAcceptWindow = option2bool(
        kOptionEnablePermChangeInAcceptWindow,
        bind.mainGetBuildinOption(
          key: kOptionEnablePermChangeInAcceptWindow,
        ));
    final permissionChangeLocked = isAndroid &&
        serverModel.clients.any((c) => !c.disconnected) &&
        !allowPermChangeInAcceptWindow;
    final permissionItems = [
      _PermissionGuideData(
        title: translate("Screen Capture"),
        description: translate('kq_mobile_screen_capture_permission_tip'),
        icon: Icons.mobile_screen_share_rounded,
        color: q.primary,
        isOk: serverModel.mediaOk,
        enabled: !hideStopService || !serverModel.mediaOk,
        actionLabel: serverModel.mediaOk
            ? translate('Stop service')
            : translate('Enable'),
        enabledActionLabel: translate('Turn off this permission'),
        onPressed: !serverModel.mediaOk &&
                gFFI.userModel.userName.value.isEmpty &&
                bind.mainGetLocalOption(key: "show-scam-warning") != "N"
            ? () => showScamWarning(context, serverModel)
            : serverModel.toggleService,
      ),
      _PermissionGuideData(
        title: translate("Input Control"),
        description: translate('kq_mobile_input_permission_tip'),
        icon: Icons.touch_app_rounded,
        color: q.warning,
        isOk: serverModel.inputOk,
        actionLabel: translate('Enable'),
        enabledActionLabel: translate('Disable this permission'),
        onPressed: () => unawaited(_toggleInputControl(serverModel)),
      ),
      _PermissionGuideData(
        title: translate("Transfer file"),
        description: translate('kq_mobile_file_permission_tip'),
        icon: Icons.folder_copy_outlined,
        color: q.online,
        isOk: serverModel.fileOk,
        enabled: !permissionChangeLocked,
        actionLabel: translate('Enable'),
        enabledActionLabel: translate('Disable this permission'),
        onPressed: serverModel.toggleFile,
      ),
      _PermissionGuideData(
        title: translate("Audio Capture"),
        description: hasAudioPermission
            ? translate('kq_mobile_audio_permission_tip')
            : translate("android_version_audio_tip"),
        icon: Icons.mic_rounded,
        color: const Color(0xFF8E7BFF),
        isOk: hasAudioPermission ? serverModel.audioOk : false,
        enabled: hasAudioPermission && !permissionChangeLocked,
        actionLabel: translate('Enable'),
        enabledActionLabel: translate('Disable this permission'),
        onPressed: serverModel.toggleAudio,
      ),
      _PermissionGuideData(
        title: translate("Enable clipboard"),
        description: translate('kq_mobile_clipboard_permission_tip'),
        icon: Icons.content_paste_rounded,
        color: q.primaryDeep,
        isOk: serverModel.clipboardOk,
        actionLabel: translate('Enable'),
        enabledActionLabel: translate('Disable this permission'),
        onPressed: serverModel.toggleClipboard,
      ),
    ];
    final actionableItems =
        permissionItems.where((item) => item.enabled).toList(growable: false);
    final doneCount = actionableItems.where((item) => item.isOk).length;
    final totalCount = actionableItems.length;
    final progress = totalCount == 0 ? 1.0 : doneCount / totalCount;
    final allReady = totalCount > 0 && doneCount == totalCount;
    final pendingItems = permissionItems
        .where((item) => item.enabled && !item.isOk)
        .toList(growable: false);
    final visibleItems = _showAllPermissions
        ? permissionItems
        : pendingItems.take(3).toList(growable: false);
    final hasHiddenItems = _showAllPermissions ||
        pendingItems.length > visibleItems.length ||
        pendingItems.length < permissionItems.length;
    return PaddingCard(
        title: translate("Permissions"),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _PermissionProgressHeader(
            progress: progress,
            doneCount: doneCount,
            totalCount: totalCount,
            allReady: allReady,
            isChecking: _isCheckingAll,
            onPressed: allReady
                ? null
                : () => _runAllPermissionSteps(
                      serverModel: serverModel,
                      hasAudioPermission: hasAudioPermission,
                      hideStopService: hideStopService,
                      permissionChangeLocked: permissionChangeLocked,
                    ),
          ),
          if (permissionChangeLocked)
            _PermissionNotice(
              icon: Icons.lock_outline_rounded,
              text: translate("android_permission_may_not_change_tip"),
            ).marginOnly(top: 12),
          if (visibleItems.isNotEmpty)
            ...visibleItems.map(
              (item) => _PermissionGuideItem(item: item).marginOnly(top: 10),
            ),
          if (hasHiddenItems)
            _PermissionDetailsToggle(
              expanded: _showAllPermissions,
              pendingCount: pendingItems.length,
              totalCount: permissionItems.length,
              onPressed: () {
                setState(() => _showAllPermissions = !_showAllPermissions);
              },
            ).marginOnly(top: 8),
        ]));
  }
}

class _PermissionGuideData {
  const _PermissionGuideData({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.isOk,
    required this.actionLabel,
    required this.onPressed,
    this.enabledActionLabel,
    this.enabled = true,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final bool isOk;
  final String actionLabel;
  final String? enabledActionLabel;
  final VoidCallback onPressed;
  final bool enabled;
}

class _PermissionProgressHeader extends StatelessWidget {
  const _PermissionProgressHeader({
    required this.progress,
    required this.doneCount,
    required this.totalCount,
    required this.allReady,
    required this.isChecking,
    required this.onPressed,
  });

  final double progress;
  final int doneCount;
  final int totalCount;
  final bool allReady;
  final bool isChecking;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: q.workSurfaceGradient,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: q.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (allReady ? q.online : q.primary).withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              allReady
                  ? Icons.verified_rounded
                  : Icons.admin_panel_settings_rounded,
              color: allReady ? q.online : q.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  allReady
                      ? translate('kq_mobile_permissions_ready')
                      : translate('kq_mobile_permissions_need_setup'),
                  style: TextStyle(
                    color: q.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  translate('kq_mobile_permissions_summary')
                      .replaceAll('%done%', '$doneCount')
                      .replaceAll('%total%', '$totalCount'),
                  style: TextStyle(
                    color: q.muted,
                    fontSize: 12,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 11),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            minHeight: 7,
            backgroundColor: q.line.withOpacity(0.55),
            valueColor: AlwaysStoppedAnimation<Color>(
              allReady ? q.online : q.primary,
            ),
          ),
        ),
        if (!allReady) const SizedBox(height: 12),
        if (!allReady)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: isChecking ? null : onPressed,
              icon: isChecking
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: q.muted,
                      ),
                    )
                  : const Icon(Icons.playlist_add_check_circle_rounded),
              label: Text(translate('kq_mobile_enable_missing_permissions')),
            ),
          ),
      ]),
    );
  }
}

class _PermissionDetailsToggle extends StatelessWidget {
  const _PermissionDetailsToggle({
    required this.expanded,
    required this.pendingCount,
    required this.totalCount,
    required this.onPressed,
  });

  final bool expanded;
  final int pendingCount;
  final int totalCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    final label = expanded ? translate('Hide') : translate('More');
    final countText = pendingCount == 0
        ? translate('Ready')
        : translate('kq_mobile_permissions_summary')
            .replaceAll('%done%', '${totalCount - pendingCount}')
            .replaceAll('%total%', '$totalCount');
    return Row(children: [
      Expanded(
        child: Text(
          countText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: q.muted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      TextButton.icon(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: Icon(
          expanded ? Icons.keyboard_arrow_up_rounded : Icons.tune_rounded,
          size: 18,
        ),
        label: Text(label),
      ),
    ]);
  }
}

class _PermissionNotice extends StatelessWidget {
  const _PermissionNotice({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: q.warning.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: q.warning.withOpacity(0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: q.warning, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: q.ink,
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionGuideItem extends StatelessWidget {
  const _PermissionGuideItem({
    required this.item,
  });

  final _PermissionGuideData item;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    final color = item.enabled ? item.color : q.muted;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: item.enabled ? 1 : 0.62,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: q.surfaceSoft.withOpacity(q.isDark ? 0.56 : 0.76),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: item.isOk ? q.online.withOpacity(0.34) : q.line,
          ),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(item.icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(
                    item.title,
                    style: TextStyle(
                      color: q.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _PermissionStatePill(isOk: item.isOk, enabled: item.enabled),
              ]),
              const SizedBox(height: 6),
              Text(
                item.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: q.muted,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: item.isOk
                    ? TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: item.enabled ? item.onPressed : null,
                        icon: const Icon(Icons.block_rounded, size: 18),
                        label: Text(item.enabledActionLabel ??
                            translate('Disable this permission')),
                      )
                    : OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          minimumSize: const Size(0, 34),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: item.enabled ? item.onPressed : null,
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: Text(item.enabled
                            ? item.actionLabel
                            : translate('Not available')),
                      ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _PermissionStatePill extends StatelessWidget {
  const _PermissionStatePill({
    required this.isOk,
    required this.enabled,
  });

  final bool isOk;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    final color = !enabled
        ? q.muted
        : isOk
            ? q.online
            : q.offline;
    final text = !enabled
        ? translate('Not available')
        : isOk
            ? translate('Enabled')
            : translate('Not enabled');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.24)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}

class ConnectionManager extends StatelessWidget {
  const ConnectionManager({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final serverModel = Provider.of<ServerModel>(context);
    final q = KqTheme.of(context);
    final clients =
        serverModel.clients.where((client) => !client.disconnected).toList();
    if (clients.isEmpty) {
      return PaddingCard(
        title: translate('Current connections'),
        titleIcon: Icon(Icons.link_off_rounded, color: q.muted),
        child: _EmptyConnectionState(),
      );
    }
    return PaddingCard(
      title: translate('Current connections'),
      titleIcon: Icon(Icons.hub_rounded, color: q.primary),
      child: Column(
        children: [
          for (var i = 0; i < clients.length; i++) ...[
            if (i > 0)
              Divider(height: 20, thickness: 1, color: q.line.withOpacity(0.8)),
            _ConnectionClientTile(
              client: clients[i],
              action: clients[i].authorized
                  ? _buildDisconnectButton(context, clients[i])
                  : _buildNewConnectionHint(serverModel, clients[i]),
              prompt: clients[i].authorized
                  ? null
                  : translate("android_new_connection_tip"),
              voiceCallPrompt:
                  clients[i].incomingVoiceCall && !clients[i].inVoiceCall
                      ? _buildNewVoiceCallHint(context, serverModel, clients[i])
                      : const [],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDisconnectButton(BuildContext context, Client client) {
    final q = KqTheme.of(context);
    final disconnectButton = FilledButton.tonalIcon(
      style: FilledButton.styleFrom(
        foregroundColor: q.offline,
        backgroundColor: q.offline.withOpacity(0.1),
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: const Icon(Icons.close_rounded, size: 18),
      onPressed: () {
        bind.cmCloseConnection(connId: client.id);
        gFFI.invokeMethod("cancel_notification", client.id);
      },
      label: Text(translate("Disconnect")),
    );
    final buttons = [disconnectButton];
    if (client.inVoiceCall) {
      buttons.insert(
        0,
        FilledButton.tonalIcon(
          style: FilledButton.styleFrom(
            foregroundColor: q.offline,
            backgroundColor: q.offline.withOpacity(0.1),
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: const Icon(Icons.phone_disabled_rounded, size: 18),
          label: Text(translate("Stop")),
          onPressed: () {
            bind.cmCloseVoiceCall(id: client.id);
            gFFI.invokeMethod("cancel_notification", client.id);
          },
        ),
      );
    }

    if (buttons.length == 1) {
      return disconnectButton;
    } else {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: buttons,
      );
    }
  }

  Widget _buildNewConnectionHint(ServerModel serverModel, Client client) {
    return Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        children: [
          TextButton.icon(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.close_rounded, size: 18),
              label: Text(translate("Dismiss")),
              onPressed: () {
                serverModel.sendLoginResponse(client, false);
              }),
          if (serverModel.approveMode != 'password')
            FilledButton.icon(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: Text(translate("Accept")),
                onPressed: () {
                  serverModel.sendLoginResponse(client, true);
                }),
        ]);
  }

  List<Widget> _buildNewVoiceCallHint(
      BuildContext context, ServerModel serverModel, Client client) {
    final q = KqTheme.of(context);
    return [
      Text(
        translate("android_new_voice_call_tip"),
        style: TextStyle(
          color: q.ink,
          fontSize: 12,
          height: 1.32,
          fontWeight: FontWeight.w700,
        ),
      ).marginOnly(top: 10, bottom: 8),
      Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
        TextButton.icon(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.close_rounded, size: 18),
            label: Text(translate("Dismiss")),
            onPressed: () {
              serverModel.handleVoiceCall(client, false);
            }),
        if (serverModel.approveMode != 'password')
          FilledButton.icon(
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.check_rounded, size: 18),
              label: Text(translate("Accept")),
              onPressed: () {
                serverModel.handleVoiceCall(client, true);
              }),
      ])
    ];
  }
}

class _ConnectionClientTile extends StatelessWidget {
  const _ConnectionClientTile({
    required this.client,
    required this.action,
    required this.voiceCallPrompt,
    this.prompt,
  });

  final Client client;
  final Widget action;
  final String? prompt;
  final List<Widget> voiceCallPrompt;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    final statusColor = client.authorized ? q.online : q.warning;
    final typeIcon = client.isFileTransfer
        ? Icons.folder_rounded
        : Icons.screen_share_rounded;
    final typeText =
        translate(client.isFileTransfer ? "Transfer file" : "Share screen");
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: q.surfaceSoft.withOpacity(q.isDark ? 0.5 : 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: q.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: ClientInfo(client)),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: statusColor.withOpacity(0.24)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(typeIcon, size: 14, color: statusColor),
              const SizedBox(width: 4),
              Text(
                typeText,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ]),
          ),
        ]),
        if (prompt != null)
          _ConnectionPrompt(text: prompt!, color: q.warning)
              .marginOnly(top: 10),
        if (voiceCallPrompt.isNotEmpty) ...voiceCallPrompt,
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: action,
          ),
        ),
      ]),
    );
  }
}

class _ConnectionPrompt extends StatelessWidget {
  const _ConnectionPrompt({
    required this.text,
    required this.color,
  });

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: q.ink,
          fontSize: 12,
          height: 1.35,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EmptyConnectionState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    return Row(children: [
      Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: q.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Icon(Icons.devices_other_rounded, color: q.primary),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          translate('No active connections'),
          style: TextStyle(
            color: q.muted,
            fontSize: 13,
            height: 1.35,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ]);
  }
}

class PaddingCard extends StatelessWidget {
  const PaddingCard({Key? key, required this.child, this.title, this.titleIcon})
      : super(key: key);

  final String? title;
  final Icon? titleIcon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final children = [child];
    final q = KqTheme.of(context);
    if (title != null) {
      children.insert(
          0,
          Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
              child: Row(
                children: [
                  titleIcon?.marginOnly(right: 10) ?? const SizedBox.shrink(),
                  Expanded(
                    child: Text(title!,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: q.ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            )),
                  )
                ],
              )));
    }
    return SizedBox(
        width: double.maxFinite,
        child: Container(
          margin: const EdgeInsets.only(top: 12),
          decoration: BoxDecoration(
            color: q.panelStrong.withOpacity(q.isDark ? 0.78 : 0.92),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: q.line),
            boxShadow: [
              BoxShadow(
                color: q.shadow,
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ));
  }
}

class ClientInfo extends StatelessWidget {
  final Client client;
  ClientInfo(this.client);

  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(children: [
          Row(
            children: [
              Expanded(
                  flex: -1,
                  child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: _buildAvatar(context))),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(client.name, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 8),
                    Text(client.peerId, style: const TextStyle(fontSize: 10))
                  ]))
            ],
          ),
        ]));
  }

  Widget _buildAvatar(BuildContext context) {
    final fallback = CircleAvatar(
      backgroundColor: str2color(client.name,
          Theme.of(context).brightness == Brightness.light ? 255 : 150),
      child: Text(client.name.isNotEmpty ? client.name[0] : '?'),
    );
    return buildAvatarWidget(
          avatar: client.avatar,
          size: 40,
          fallback: fallback,
        ) ??
        fallback;
  }
}

void androidChannelInit() {
  gFFI.setMethodCallHandler((method, arguments) {
    debugPrint("flutter got android msg,$method,$arguments");
    try {
      switch (method) {
        case "start_capture":
          {
            gFFI.dialogManager.dismissAll();
            gFFI.serverModel.updateClientState();
            break;
          }
        case "on_state_changed":
          {
            var name = arguments["name"] as String;
            var value = arguments["value"] as String == "true";
            debugPrint("from jvm:on_state_changed,$name:$value");
            gFFI.serverModel.changeStatue(name, value);
            break;
          }
        case "on_android_permission_result":
          {
            var type = arguments["type"] as String;
            var result = arguments["result"] as bool;
            AndroidPermissionManager.complete(type, result);
            break;
          }
        case "on_media_projection_canceled":
          {
            gFFI.serverModel.stopService();
            break;
          }
        case "msgbox":
          {
            var type = arguments["type"] as String;
            var title = arguments["title"] as String;
            var text = arguments["text"] as String;
            var link = (arguments["link"] ?? '') as String;
            msgBox(gFFI.sessionId, type, title, text, link, gFFI.dialogManager);
            break;
          }
        case "stop_service":
          {
            print(
                "stop_service by kotlin, isStart:${gFFI.serverModel.isStart}");
            if (gFFI.serverModel.isStart) {
              gFFI.serverModel.stopService();
            }
            break;
          }
      }
    } catch (e) {
      debugPrintStack(label: "MethodCallHandler err:$e");
    }
    return "";
  });
}

void showScamWarning(BuildContext context, ServerModel serverModel) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return ScamWarningDialog(serverModel: serverModel);
    },
  );
}
