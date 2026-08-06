import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common/shared_state.dart';
import 'package:flutter_hbb/common/widgets/toolbar.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/mobile/widgets/floating_mouse.dart';
import 'package:flutter_hbb/mobile/widgets/gesture_help.dart';
import 'package:flutter_hbb/models/chat_model.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:flutter_svg/svg.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import '../../common.dart';
import '../../common/widgets/overlay.dart';
import '../../common/widgets/dialog.dart';
import '../../common/widgets/remote_input.dart';
import '../../models/input_model.dart';
import '../../models/mobile_remote_layout_policy.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';
import '../../models/user_model.dart';
import '../../utils/image.dart';
import '../widgets/custom_scale_widget.dart';

final initText = '1' * 1024;

// Workaround for Android (default input method, Microsoft SwiftKey keyboard) when using physical keyboard.
// When connecting a physical keyboard, `KeyEvent.physicalKey.usbHidUsage` are wrong is using Microsoft SwiftKey keyboard.
// https://github.com/flutter/flutter/issues/159384
// https://github.com/flutter/flutter/issues/159383
void _disableAndroidSoftKeyboard({bool? isKeyboardVisible}) {
  if (isAndroid) {
    if (isKeyboardVisible != true) {
      // `enable_soft_keyboard` will be set to `true` when clicking the keyboard icon, in `openKeyboard()`.
      gFFI.invokeMethod("enable_soft_keyboard", false);
    }
  }
}

class RemotePage extends StatefulWidget {
  RemotePage(
      {Key? key,
      required this.id,
      this.password,
      this.isSharedPassword,
      this.forceRelay})
      : super(key: key);

  final String id;
  final String? password;
  final bool? isSharedPassword;
  final bool? forceRelay;

  @override
  State<RemotePage> createState() => _RemotePageState(id);
}

class _RemotePageState extends State<RemotePage> with WidgetsBindingObserver {
  static const _iosMethodChannel = MethodChannel('mChannel');
  Timer? _timer;
  bool _showBar = !isWebDesktop;
  bool _showGestureHelp = false;
  String _value = '';
  Orientation? _currentOrientation;
  final _uniqueKey = UniqueKey();
  Timer? _iosKeyboardWorkaroundTimer;
  Timer? _orientationRefreshTimer;
  bool _wasBackgrounded = false;

  final _blockableOverlayState = BlockableOverlayState();

  final keyboardVisibilityController = KeyboardVisibilityController();
  late final StreamSubscription<bool> keyboardSubscription;
  final FocusNode _mobileFocusNode = FocusNode();
  final FocusNode _physicalFocusNode = FocusNode();
  var _showEdit = false; // use soft keyboard

  InputModel get inputModel => gFFI.inputModel;
  SessionID get sessionId => gFFI.sessionId;
  bool get _softKeyboardActive =>
      keyboardVisibilityController.isVisible && _showEdit;

  final TextEditingController _textController =
      TextEditingController(text: initText);

  _RemotePageState(String id) {
    initSharedStates(id);
    gFFI.chatModel.voiceCallStatus.value = VoiceCallStatus.notStarted;
    gFFI.dialogManager.loadMobileActionsOverlayVisible();
  }

  bool get _shouldUseDesktopPeerLandscapeFullscreen {
    if (!isMobile) {
      return false;
    }
    final platform = gFFI.ffiModel.pi.platform;
    return platform == kPeerPlatformWindows ||
        platform == kPeerPlatformMacOS ||
        platform == kPeerPlatformLinux;
  }

  Future<void> _applyDesktopPeerLandscapeFullscreen() async {
    if (!_shouldUseDesktopPeerLandscapeFullscreen) {
      return;
    }
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: []);
  }

  @override
  void initState() {
    super.initState();
    gFFI.ffiModel.updateEventListener(sessionId, widget.id);
    gFFI.start(
      widget.id,
      password: widget.password,
      isSharedPassword: widget.isSharedPassword,
      forceRelay: widget.forceRelay,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
      gFFI.dialogManager
          .showLoading(translate('Connecting...'), onCancel: closeConnection);
    });
    WakelockManager.enable(_uniqueKey);
    _physicalFocusNode.requestFocus();
    gFFI.inputModel.listenToMouse(true);
    gFFI.qualityMonitorModel.checkShowQualityMonitor(sessionId);
    keyboardSubscription =
        keyboardVisibilityController.onChange.listen(onSoftKeyboardChanged);
    gFFI.chatModel
        .changeCurrentKey(MessageKey(widget.id, ChatModel.clientModeID));
    _blockableOverlayState.applyFfi(gFFI);
    gFFI.imageModel.addCallbackOnFirstImage((String peerId) async {
      await kqSaveRememberedMobileConnectPassword(
        id: widget.id,
        password: widget.password,
      );
      await _applyDesktopPeerLandscapeFullscreen();
      gFFI.recordingModel
          .updateStatus(bind.sessionGetIsRecording(sessionId: gFFI.sessionId));
      if (gFFI.recordingModel.start) {
        showToast(translate('Automatically record outgoing sessions'));
      }
      _disableAndroidSoftKeyboard(
          isKeyboardVisible: keyboardVisibilityController.isVisible);
    });
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    // Stop microphone capture before any awaited cleanup can fail or stall.
    gFFI.chatModel.onVoiceCallClosed("End connection");
    _orientationRefreshTimer?.cancel();
    // https://github.com/flutter/flutter/issues/64935
    super.dispose();
    gFFI.dialogManager.hideMobileActionsOverlay(store: false);
    gFFI.inputModel.listenToMouse(false);
    gFFI.imageModel.disposeImage();
    gFFI.cursorModel.disposeImages();
    await gFFI.invokeMethod("enable_soft_keyboard", true);
    _mobileFocusNode.dispose();
    _physicalFocusNode.dispose();
    await gFFI.close();
    _timer?.cancel();
    _iosKeyboardWorkaroundTimer?.cancel();
    gFFI.dialogManager.dismissAll();
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: SystemUiOverlay.values);
    await SystemChrome.setPreferredOrientations([]);
    WakelockManager.disable(_uniqueKey);
    await keyboardSubscription.cancel();
    removeSharedStates(widget.id);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(trySyncClipboard());
      if (_wasBackgrounded) {
        _wasBackgrounded = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _refreshIOSRemoteVideo('app-resumed');
        });
      }
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _wasBackgrounded = true;
    }
  }

  void _refreshIOSRemoteVideo(String reason) {
    if (!isIOS ||
        !mounted ||
        _wasBackgrounded ||
        gFFI.closed ||
        gFFI.ffiModel.pi.isSet.isFalse) {
      return;
    }
    final display = gFFI.ffiModel.pi.currentDisplay;
    platformFFI.logRgbaStage(sessionId, 'ios-video-refresh-$reason', display);
    gFFI.imageModel.requestRepaint();
    unawaited(() async {
      try {
        await sessionRefreshVideo(sessionId, gFFI.ffiModel.pi);
      } catch (error, stackTrace) {
        debugPrint('Failed to refresh iOS remote video after $reason: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }());
  }

  void _scheduleOrientationRefresh(Orientation orientation) {
    if (_currentOrientation == orientation) return;
    _currentOrientation = orientation;
    _orientationRefreshTimer?.cancel();
    _orientationRefreshTimer =
        Timer(const Duration(milliseconds: 200), () async {
      if (!mounted || gFFI.closed) return;
      gFFI.dialogManager.resetMobileActionsOverlay(ffi: gFFI);
      await gFFI.canvasModel.updateViewStyle();
      _refreshIOSRemoteVideo('orientation-changed');
    });
  }

  void _handleIOSSoftwarePaint(ImageModel model) {
    if (!isIOS) return;
    final display = gFFI.ffiModel.pi.currentDisplay;
    if (!model.markFramePainted(display)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || gFFI.closed) return;
      platformFFI.logRgbaStage(sessionId, 'ios-first-frame-after-paint',
          display, model.image?.width ?? 0, model.image?.height ?? 0);
      try {
        await gFFI.onEvent2UIRgba(updateCanvasLayout: false);
      } catch (error, stackTrace) {
        platformFFI.logRgbaStage(
            sessionId, 'ios-first-frame-finalize-error', display);
        debugPrint('Failed to finalize the first iOS remote frame: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    });
  }

  // For client side
  // When swithing from other app to this app, try to sync clipboard.
  Future<void> trySyncClipboard() async {
    if (!isIOS) {
      await gFFI.invokeMethod("try_sync_clipboard");
      return;
    }

    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      if (text == null || text.isEmpty || gFFI.closed) return;
      await bind.sessionSendClipboardText(sessionId: sessionId, text: text);
    } catch (error, stackTrace) {
      debugPrint('Failed to sync iOS foreground clipboard: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  // to-do: It should be better to use transparent color instead of the bgColor.
  // But for now, the transparent color will cause the canvas to be white.
  // I'm sure that the white color is caused by the Overlay widget in BlockableOverlay.
  // But I don't know why and how to fix it.
  Widget emptyOverlay(Color bgColor) => BlockableOverlay(
        /// the Overlay key will be set with _blockableOverlayState in BlockableOverlay
        /// see override build() in [BlockableOverlay]
        state: _blockableOverlayState,
        underlying: Container(
          color: bgColor,
        ),
      );

  void onSoftKeyboardChanged(bool visible) {
    if (!visible) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
      // [pi.version.isNotEmpty] -> check ready or not, avoid login without soft-keyboard
      if (gFFI.chatModel.chatWindowOverlayEntry == null &&
          gFFI.ffiModel.pi.version.isNotEmpty) {
        gFFI.invokeMethod("enable_soft_keyboard", false);
      }

      // Workaround for iOS: physical keyboard input fails after virtual keyboard is hidden
      // https://github.com/flutter/flutter/issues/39900
      // https://github.com/rustdesk/rustdesk/discussions/11843#discussioncomment-13499698 - Virtual keyboard issue
      if (isIOS) {
        _iosKeyboardWorkaroundTimer?.cancel();
        _iosKeyboardWorkaroundTimer = Timer(Duration(milliseconds: 100), () {
          if (!mounted) return;
          _physicalFocusNode.unfocus();
          _iosKeyboardWorkaroundTimer = Timer(Duration(milliseconds: 50), () {
            if (!mounted) return;
            _physicalFocusNode.requestFocus();
          });
        });
      }
    } else {
      _iosKeyboardWorkaroundTimer?.cancel();
      _iosKeyboardWorkaroundTimer = null;
      _timer?.cancel();
      _timer = Timer(kMobileDelaySoftKeyboardFocus, () {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
            overlays: SystemUiOverlay.values);
        _mobileFocusNode.requestFocus();
      });
    }
    // update for Scaffold
    setState(() {});
  }

  void _handleIOSSoftKeyboardInput(String newValue) {
    var oldValue = _value;
    _value = newValue;
    var i = newValue.length - 1;
    for (; i >= 0 && newValue[i] != '1'; --i) {}
    var j = oldValue.length - 1;
    for (; j >= 0 && oldValue[j] != '1'; --j) {}
    if (i < j) j = i;
    var subNewValue = newValue.substring(j + 1);
    var subOldValue = oldValue.substring(j + 1);

    // get common prefix of subNewValue and subOldValue
    var common = 0;
    for (;
        common < subOldValue.length &&
            common < subNewValue.length &&
            subNewValue[common] == subOldValue[common];
        ++common) {}

    // get newStr from subNewValue
    var newStr = "";
    if (subNewValue.length > common) {
      newStr = subNewValue.substring(common);
    }

    // Set the value to the old value and early return if is still composing. (1 && 2)
    // 1. The composing range is valid
    // 2. The new string is shorter than the composing range.
    if (_textController.value.isComposingRangeValid) {
      final composingLength = _textController.value.composing.end -
          _textController.value.composing.start;
      if (composingLength > newStr.length) {
        _value = oldValue;
        return;
      }
    }

    // Delete the different part in the old value.
    for (i = 0; i < subOldValue.length - common; ++i) {
      inputModel.inputKey('VK_BACK');
    }

    // Input the new string.
    if (newStr.length > 1) {
      bind.sessionInputString(sessionId: sessionId, value: newStr);
    } else if (newStr.isNotEmpty) {
      inputChar(newStr);
    }
  }

  void _handleNonIOSSoftKeyboardInput(String newValue) {
    var oldValue = _value;
    _value = newValue;
    if (oldValue.isNotEmpty &&
        newValue.isNotEmpty &&
        oldValue[0] == '1' &&
        newValue[0] != '1') {
      // clipboard
      oldValue = '';
    }
    if (newValue.length == oldValue.length) {
      // ?
    } else if (newValue.length < oldValue.length) {
      final char = 'VK_BACK';
      inputModel.inputKey(char);
    } else {
      final content = newValue.substring(oldValue.length);
      if (content.length > 1) {
        if (oldValue != '' &&
            content.length == 2 &&
            (content == '""' ||
                content == '()' ||
                content == '[]' ||
                content == '<>' ||
                content == "{}" ||
                content == '”“' ||
                content == '《》' ||
                content == '（）' ||
                content == '【】')) {
          // can not only input content[0], because when input ], [ are also auo insert, which cause ] never be input
          bind.sessionInputString(sessionId: sessionId, value: content);
          openKeyboard();
          return;
        }
        bind.sessionInputString(sessionId: sessionId, value: content);
      } else {
        inputChar(content);
      }
    }
  }

  // handle mobile virtual keyboard
  void handleSoftKeyboardInput(String newValue) {
    if (isIOS) {
      _handleIOSSoftKeyboardInput(newValue);
    } else {
      _handleNonIOSSoftKeyboardInput(newValue);
    }
  }

  void inputChar(String char) {
    if (char == '\n') {
      char = 'VK_RETURN';
    } else if (char == ' ') {
      char = 'VK_SPACE';
    }
    inputModel.inputKey(char);
  }

  void openKeyboard() {
    gFFI.invokeMethod("enable_soft_keyboard", true);
    // destroy first, so that our _value trick can work
    _value = initText;
    _textController.text = _value;
    setState(() => _showEdit = false);
    _timer?.cancel();
    _timer = Timer(kMobileDelaySoftKeyboard, () {
      // show now, and sleep a while to requestFocus to
      // make sure edit ready, so that keyboard won't show/hide/show/hide happen
      setState(() => _showEdit = true);
      _timer?.cancel();
      _timer = Timer(kMobileDelaySoftKeyboardFocus, () {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
            overlays: SystemUiOverlay.values);
        _mobileFocusNode.requestFocus();
      });
    });
  }

  Widget _bottomWidget() => _showGestureHelp ? getGestureHelp() : Offstage();

  @override
  Widget build(BuildContext context) {
    final keyboardIsVisible = _softKeyboardActive;
    final showActionButton = !_showBar || keyboardIsVisible || _showGestureHelp;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        clientClose(sessionId, gFFI);
      },
      child: Scaffold(
          resizeToAvoidBottomInset: false,
          // workaround for https://github.com/rustdesk/rustdesk/issues/3131
          floatingActionButtonLocation: FABLocation(
            FloatingActionButtonLocation.endFloat,
            0,
            kMobileRemoteToggleButtonYOffset,
          ),
          floatingActionButton: !showActionButton
              ? null
              : FloatingActionButton(
                  mini: !keyboardIsVisible,
                  child: Icon(
                    (keyboardIsVisible || _showGestureHelp)
                        ? Icons.expand_more
                        : Icons.expand_less,
                    color: Colors.white,
                  ),
                  backgroundColor: MyTheme.accent,
                  onPressed: () {
                    setState(() {
                      if (keyboardIsVisible) {
                        _showEdit = false;
                        gFFI.invokeMethod("enable_soft_keyboard", false);
                        _mobileFocusNode.unfocus();
                        _physicalFocusNode.requestFocus();
                      } else if (_showGestureHelp) {
                        _showGestureHelp = false;
                      } else {
                        _showBar = !_showBar;
                      }
                    });
                  }),
          bottomNavigationBar: Obx(() => Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  gFFI.ffiModel.pi.isSet.isTrue &&
                          gFFI.ffiModel.waitForFirstImage.isTrue
                      ? emptyOverlay(MyTheme.canvasColor)
                      : () {
                          gFFI.ffiModel.tryShowAndroidActionsOverlay();
                          return Offstage();
                        }(),
                  _bottomWidget(),
                  gFFI.ffiModel.pi.isSet.isFalse
                      ? emptyOverlay(MyTheme.canvasColor)
                      : Offstage(),
                ],
              )),
          body: Obx(
            () => getRawPointerAndKeyBody(Overlay(
              initialEntries: [
                OverlayEntry(builder: (context) {
                  return Container(
                    color: kColorCanvas,
                    child: isWebDesktop
                        ? getBodyForDesktopWithListener()
                        : SafeArea(
                            child:
                                OrientationBuilder(builder: (ctx, orientation) {
                              _scheduleOrientationRefresh(orientation);
                              return Container(
                                color: MyTheme.canvasColor,
                                child: RawTouchGestureDetectorRegion(
                                  child: getBodyForMobile(),
                                  ffi: gFFI,
                                ),
                              );
                            }),
                          ),
                  );
                })
              ],
            )),
          )),
    );
  }

  Widget getRawPointerAndKeyBody(Widget child) {
    final ffiModel = Provider.of<FfiModel>(context);
    return RawPointerMouseRegion(
      cursor: ffiModel.keyboard ? SystemMouseCursors.none : MouseCursor.defer,
      inputModel: inputModel,
      // Disable RawKeyFocusScope before the connecting is established.
      // The "Delete" key on the soft keyboard may be grabbed when inputting the password dialog.
      child: gFFI.ffiModel.pi.isSet.isTrue
          ? RawKeyFocusScope(
              focusNode: _physicalFocusNode,
              inputModel: inputModel,
              child: child)
          : child,
    );
  }

  Widget _remoteSideActionRail() {
    if (_softKeyboardActive) {
      return const Offstage();
    }

    final ffiModel = Provider.of<FfiModel>(context);
    if (!_showBar || _showGestureHelp || gFFI.ffiModel.pi.displays.isEmpty) {
      return const Offstage();
    }

    final controls = <Widget>[
      Obx(() => _remoteSideActionButton(
            icon: Icons.chevron_right,
            label: kqLocaleText(zhCn: '收起', en: 'Hide'),
            onPressed: gFFI.ffiModel.waitForFirstImage.isTrue
                ? null
                : () => setState(() => _showBar = !_showBar),
          )),
      _remoteSideActionButton(
        icon: Icons.clear,
        label: kqLocaleText(zhCn: '断开', en: 'End'),
        onPressed: () => clientClose(sessionId, gFFI),
      ),
      _remoteSideActionButton(
        icon: Icons.tv,
        label: kqLocaleText(zhCn: '屏幕', en: 'View'),
        onPressed: () {
          setState(() => _showEdit = false);
          showOptions(context, widget.id, gFFI.dialogManager);
        },
      ),
      if (!isWebDesktop && !ffiModel.viewOnly && ffiModel.keyboard) ...[
        _remoteSideActionButton(
          icon: Icons.keyboard,
          label: kqLocaleText(zhCn: '键盘', en: 'Keys'),
          onPressed: openKeyboard,
        ),
        if (gFFI.ffiModel.isPeerAndroid)
          _remoteSideActionButton(
            icon: Icons.build,
            label: kqLocaleText(zhCn: '操作', en: 'Tools'),
            onPressed: () =>
                gFFI.dialogManager.toggleMobileActionsOverlay(ffi: gFFI),
          )
        else
          _remoteSideActionButton(
            icon: gFFI.ffiModel.touchMode ? Icons.touch_app : Icons.mouse,
            label: gFFI.ffiModel.touchMode
                ? kqLocaleText(zhCn: '手势', en: 'Touch')
                : kqLocaleText(zhCn: '鼠标', en: 'Mouse'),
            onPressed: () =>
                setState(() => _showGestureHelp = !_showGestureHelp),
          ),
      ],
      if (!isWeb)
        futureBuilder(
          future: gFFI.invokeMethod("get_value", "KEY_IS_SUPPORT_VOICE_CALL"),
          hasData: (isSupportVoiceCall) {
            final showVoiceCall = isIOS || (isAndroid && isSupportVoiceCall);
            if (!showVoiceCall) {
              return const SizedBox.shrink();
            }
            return _remoteVoiceCallButton();
          },
        ),
      _remoteSideActionButton(
        icon: Icons.more_vert,
        label: kqLocaleText(zhCn: '更多', en: 'More'),
        onPressed: () {
          setState(() => _showEdit = false);
          showActions(widget.id);
        },
      ),
    ];

    return Positioned(
      right: 12,
      top: kMobileRemoteSideRailInset,
      bottom: kMobileRemoteSideRailInset,
      child: Align(
        alignment: Alignment.topRight,
        child: Material(
          color: const Color(0xCC202124),
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          elevation: 6,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              vertical: kMobileRemoteSideRailContentVerticalPadding,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: controls,
            ),
          ),
        ),
      ),
    );
  }

  Widget _remoteSideActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    Color color = Colors.white,
    Color? backgroundColor,
  }) {
    final effectiveColor = onPressed == null ? Colors.white38 : color;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 4,
        vertical: kMobileRemoteSideRailItemVerticalPadding,
      ),
      child: Material(
        color: backgroundColor ?? Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onPressed,
          child: SizedBox(
            width: 54,
            height: kMobileRemoteSideRailItemHeight,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: effectiveColor, size: 20),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: effectiveColor,
                    fontSize: 10,
                    height: 1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _remoteVoiceCallButton() {
    return Obx(() {
      final status = gFFI.chatModel.voiceCallStatus.value;
      final isWaiting = status == VoiceCallStatus.waitingForResponse;
      final isConnected = status == VoiceCallStatus.connected;
      final isIncoming = status == VoiceCallStatus.incoming;
      final isInVoice = isWaiting || isConnected || isIncoming;
      return _remoteSideActionButton(
        icon: isConnected ? Icons.call_end_rounded : Icons.call_rounded,
        label: isConnected
            ? kqLocaleText(zhCn: '结束', en: 'End')
            : isWaiting
                ? kqLocaleText(zhCn: '等待', en: 'Wait')
                : isIncoming
                    ? kqLocaleText(zhCn: '来电', en: 'Call')
                    : kqLocaleText(zhCn: '语音', en: 'Voice'),
        color: isConnected
            ? Colors.redAccent
            : isWaiting
                ? Colors.amberAccent
                : Colors.white,
        backgroundColor:
            isInVoice ? Colors.white.withValues(alpha: 0.12) : null,
        onPressed: isInVoice ? _endMobileVoiceCall : _requestMobileVoiceCall,
      );
    });
  }

  Future<bool> _ensureMobileVoicePermission() async {
    if (!isIOS) return true;
    try {
      return await _iosMethodChannel.invokeMethod<bool>(
            'request_microphone_permission',
          ) ??
          false;
    } on PlatformException catch (error) {
      debugPrint('Unable to request iOS microphone permission: $error');
      return false;
    }
  }

  Future<void> _requestMobileVoiceCall() async {
    if (!await _ensureMobileVoicePermission()) {
      showToast(
        translate(
          'Microphone is unavailable. Allow microphone access in system settings and try again.',
        ),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _showBar = false;
      _showEdit = false;
    });
    bind.sessionRequestVoiceCall(sessionId: sessionId);
    showToast(
      translate('Voice call started. Waiting for the other side to answer.'),
    );
  }

  void _endMobileVoiceCall() {
    gFFI.chatModel.onVoiceCallClosed('End connection');
    bind.sessionCloseVoiceCall(sessionId: sessionId);
    showToast(translate('End voice call'));
  }

  bool get showCursorPaint =>
      supportsRemoteCursorBroadcast(gFFI.ffiModel.pi) &&
      !gFFI.canvasModel.cursorEmbedded &&
      !gFFI.inputModel.relativeMouseMode.value;

  Widget getBodyForMobile() {
    final keyboardIsVisible = _softKeyboardActive;
    return Container(
        color: MyTheme.canvasColor,
        child: Stack(children: () {
          final paints = [
            ImagePaint(
              ffiModel: gFFI.ffiModel,
              onPaint: _handleIOSSoftwarePaint,
            ),
            Positioned(
              top: 10,
              right: 10,
              child: QualityMonitor(gFFI.qualityMonitorModel),
            ),
            KeyHelpTools(
                keyboardIsVisible: keyboardIsVisible,
                showGestureHelp: _showGestureHelp),
            SizedBox(
              width: 0,
              height: 0,
              child: !_showEdit
                  ? Container()
                  : TextFormField(
                      textInputAction: TextInputAction.newline,
                      autocorrect: false,
                      // Flutter 3.16.9 Android.
                      // `enableSuggestions` causes secure keyboard to be shown.
                      // https://github.com/flutter/flutter/issues/139143
                      // https://github.com/flutter/flutter/issues/146540
                      // enableSuggestions: false,
                      autofocus: true,
                      focusNode: _mobileFocusNode,
                      maxLines: null,
                      controller: _textController,
                      // trick way to make backspace work always
                      keyboardType: TextInputType.multiline,
                      // `onChanged` may be called depending on the input method if this widget is wrapped in
                      // `Focus(onKeyEvent: ..., child: ...)`
                      // For `Backspace` button in the soft keyboard:
                      // en/fr input method:
                      //      1. The button will not trigger `onKeyEvent` if the text field is not empty.
                      //      2. The button will trigger `onKeyEvent` if the text field is empty.
                      // ko/zh/ja input method: the button will trigger `onKeyEvent`
                      //                     and the event will not popup if `KeyEventResult.handled` is returned.
                      onChanged: handleSoftKeyboardInput,
                    ).workaroundFreezeLinuxMint(),
            ),
          ];
          if (showCursorPaint) {
            paints.add(Obx(() => ShowRemoteCursorState.find(widget.id).value
                ? CursorPaint(widget.id)
                : const SizedBox.shrink()));
          }
          paints.add(FloatingMouse(
            ffi: gFFI,
          ));
          paints.add(_remoteSideActionRail());
          return paints;
        }()));
  }

  Widget getBodyForDesktopWithListener() {
    final ffiModel = Provider.of<FfiModel>(context);
    var paints = <Widget>[ImagePaint(ffiModel: ffiModel)];
    if (showCursorPaint) {
      final cursor = bind.sessionGetToggleOptionSync(
          sessionId: sessionId, arg: 'show-remote-cursor');
      if (ffiModel.keyboard || cursor) {
        paints.add(CursorPaint(widget.id));
      }
    }
    return Container(
        color: MyTheme.canvasColor, child: Stack(children: paints));
  }

  List<TTextMenu> _getMobileActionMenus() {
    if (gFFI.ffiModel.pi.platform != kPeerPlatformAndroid ||
        !gFFI.ffiModel.keyboard) {
      return [];
    }
    final enabled = versionCmp(gFFI.ffiModel.pi.version, '1.2.7') >= 0;
    if (!enabled) return [];
    return [
      TTextMenu(
        child: Text(translate('Back')),
        mobileIcon: Icons.arrow_back_rounded,
        onPressed: () => gFFI.inputModel.onMobileBack(),
      ),
      TTextMenu(
        child: Text(translate('Home')),
        mobileIcon: Icons.home_rounded,
        onPressed: () => gFFI.inputModel.onMobileHome(),
      ),
      TTextMenu(
        child: Text(translate('Apps')),
        mobileIcon: Icons.apps_rounded,
        onPressed: () => gFFI.inputModel.onMobileApps(),
      ),
      TTextMenu(
        child: Text(translate('Volume up')),
        mobileIcon: Icons.volume_up_rounded,
        onPressed: () => gFFI.inputModel.onMobileVolumeUp(),
      ),
      TTextMenu(
        child: Text(translate('Volume down')),
        mobileIcon: Icons.volume_down_rounded,
        onPressed: () => gFFI.inputModel.onMobileVolumeDown(),
      ),
      TTextMenu(
        child: Text(translate('Power')),
        mobileIcon: Icons.power_settings_new_rounded,
        onPressed: () => gFFI.inputModel.onMobilePower(),
      ),
    ];
  }

  void showActions(String id) async {
    final mobileActionMenus = _getMobileActionMenus();
    final menus = toolbarControls(context, id, gFFI, includeFingerprint: false)
        .where((menu) => !menu.divider)
        .toList();
    final allMenus = <TTextMenu>[...mobileActionMenus, ...menus];
    final selected = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.72,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 8, 6),
              child: Row(children: [
                Expanded(
                  child: Text(
                    kqLocaleText(zhCn: '更多操作', en: 'More actions'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: translate('Close'),
                  onPressed: () => Navigator.pop(sheetContext),
                  icon: const Icon(Icons.close_rounded),
                ),
              ]),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
                itemCount: allMenus.length,
                separatorBuilder: (_, index) =>
                    index + 1 == mobileActionMenus.length
                        ? const Divider(height: 9)
                        : const SizedBox(height: 1),
                itemBuilder: (_, index) {
                  final menu = allMenus[index];
                  return ListTile(
                    minTileHeight: 52,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    leading: Icon(
                      menu.mobileIcon ?? Icons.tune_rounded,
                      color: theme.colorScheme.primary,
                    ),
                    title: DefaultTextStyle.merge(
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15),
                      child: menu.child,
                    ),
                    trailing: menu.trailingIcon,
                    enabled: menu.onPressed != null,
                    onTap: menu.onPressed == null
                        ? null
                        : () => Navigator.pop(sheetContext, index),
                  );
                },
              ),
            ),
          ]),
        );
      },
    );
    if (selected != null && selected >= 0 && selected < allMenus.length) {
      allMenus[selected].onPressed?.call();
    }
  }

  showChatOptions(String id) async {
    makeTextMenu(String label, Widget icon, VoidCallback onPressed,
            {TextStyle? labelStyle}) =>
        TTextMenu(
          child: Text(translate(label), style: labelStyle),
          trailingIcon: Transform.scale(
            scale: (isDesktop || isWebDesktop) ? 0.8 : 1,
            child: IgnorePointer(
              child: IconButton(
                onPressed: null,
                icon: icon,
              ),
            ),
          ),
          onPressed: onPressed,
        );

    final isInVoice = [
      VoiceCallStatus.waitingForResponse,
      VoiceCallStatus.connected
    ].contains(gFFI.chatModel.voiceCallStatus.value);
    final menus = [
      isInVoice
          ? makeTextMenu(
              'End voice call',
              SvgPicture.asset(
                'assets/call_wait.svg',
                colorFilter:
                    ColorFilter.mode(Colors.redAccent, BlendMode.srcIn),
              ),
              _endMobileVoiceCall,
              labelStyle: TextStyle(color: Colors.redAccent))
          : makeTextMenu(
              'Voice call',
              SvgPicture.asset(
                'assets/call_wait.svg',
                colorFilter: ColorFilter.mode(MyTheme.accent, BlendMode.srcIn),
              ),
              _requestMobileVoiceCall),
    ];

    final menuItems = menus
        .asMap()
        .entries
        .map((e) => PopupMenuItem<int>(child: e.value.getChild(), value: e.key))
        .toList();
    Future.delayed(Duration.zero, () async {
      final size = MediaQuery.of(context).size;
      final x = 120.0;
      final y = size.height;
      var index = await showMenu(
        context: context,
        position: RelativeRect.fromLTRB(x, y, x, y),
        items: menuItems,
        elevation: 8,
      );
      if (index != null && index < menus.length) {
        menus[index].onPressed?.call();
      }
    });
  }

  /// aka changeTouchMode
  BottomAppBar getGestureHelp() {
    return BottomAppBar(
        child: SingleChildScrollView(
            controller: ScrollController(),
            padding: EdgeInsets.symmetric(vertical: 10),
            child: GestureHelp(
              touchMode: gFFI.ffiModel.touchMode,
              onTouchModeChange: (t) {
                gFFI.ffiModel.toggleTouchMode();
                final v = gFFI.ffiModel.touchMode ? 'Y' : 'N';
                bind.mainSetLocalOption(key: kOptionTouchMode, value: v);
              },
              virtualMouseMode: gFFI.ffiModel.virtualMouseMode,
              inputModel: gFFI.inputModel,
            )));
  }

  // * Currently mobile does not enable map mode
  // void changePhysicalKeyboardInputMode() async {
  //   var current = await bind.sessionGetKeyboardMode(id: widget.id) ?? "legacy";
  //   gFFI.dialogManager.show((setState, close) {
  //     void setMode(String? v) async {
  //       await bind.sessionSetKeyboardMode(id: widget.id, value: v ?? "");
  //       setState(() => current = v ?? '');
  //       Future.delayed(Duration(milliseconds: 300), close);
  //     }
  //
  //     return CustomAlertDialog(
  //         title: Text(translate('Physical Keyboard Input Mode')),
  //         content: Column(mainAxisSize: MainAxisSize.min, children: [
  //           getRadio('Legacy mode', 'legacy', current, setMode),
  //           getRadio('Map mode', 'map', current, setMode),
  //         ]));
  //   }, clickMaskDismiss: true);
  // }
}

class KeyHelpTools extends StatefulWidget {
  final bool keyboardIsVisible;
  final bool showGestureHelp;

  /// need to show by external request, etc [keyboardIsVisible] or [changeTouchMode]
  bool get requestShow => keyboardIsVisible || showGestureHelp;

  KeyHelpTools(
      {required this.keyboardIsVisible, required this.showGestureHelp});

  @override
  State<KeyHelpTools> createState() => _KeyHelpToolsState();
}

class _KeyHelpToolsState extends State<KeyHelpTools> {
  var _more = true;
  var _fn = false;
  var _pin = false;
  final _key = GlobalKey();

  InputModel get inputModel => gFFI.inputModel;

  Widget wrap(String text, void Function() onPressed,
      {bool? active, IconData? icon}) {
    final compact = widget.keyboardIsVisible;
    return TextButton(
        style: TextButton.styleFrom(
          minimumSize: compact ? const Size(36, 32) : Size(0, 0),
          padding: EdgeInsets.symmetric(
              vertical: compact ? 7 : 10, horizontal: compact ? 8 : 9.75),
          //adds padding inside the button
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          //limits the touch area to the button area
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(5.0),
          ),
          backgroundColor: active == true ? MyTheme.accent80 : null,
        ),
        child: icon != null
            ? Icon(icon, size: 14, color: Colors.white)
            : Text(translate(text),
                style: TextStyle(
                    color: Colors.white, fontSize: compact ? 10.5 : 11)),
        onPressed: onPressed);
  }

  Widget _compactKeyboardToolbar(List<Widget> children, double space) {
    final rowChildren = <Widget>[];
    for (final child in children) {
      if (rowChildren.isNotEmpty) {
        rowChildren.add(SizedBox(width: space));
      }
      rowChildren.add(child);
    }

    return Container(
      key: _key,
      color: const Color(0xD9111317),
      constraints: const BoxConstraints(minHeight: 40, maxHeight: 54),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: rowChildren,
        ),
      ),
    );
  }

  _updateRect() {
    RenderObject? renderObject = _key.currentContext?.findRenderObject();
    if (renderObject == null) {
      return;
    }
    if (renderObject is RenderBox) {
      final size = renderObject.size;
      Offset pos = renderObject.localToGlobal(Offset.zero);
      gFFI.cursorModel.keyHelpToolsVisibilityChanged(
          Rect.fromLTWH(pos.dx, pos.dy, size.width, size.height),
          widget.keyboardIsVisible);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasModifierOn = inputModel.ctrl ||
        inputModel.alt ||
        inputModel.shift ||
        inputModel.command;

    if (!_pin && !hasModifierOn && !widget.requestShow) {
      gFFI.cursorModel
          .keyHelpToolsVisibilityChanged(null, widget.keyboardIsVisible);
      return Offstage();
    }
    final size = MediaQuery.of(context).size;

    final pi = gFFI.ffiModel.pi;
    final isMac = pi.platform == kPeerPlatformMacOS;
    final isWin = pi.platform == kPeerPlatformWindows;
    final isLinux = pi.platform == kPeerPlatformLinux;
    final modifiers = <Widget>[
      wrap('Ctrl ', () {
        setState(() => inputModel.ctrl = !inputModel.ctrl);
      }, active: inputModel.ctrl),
      wrap(' Alt ', () {
        setState(() => inputModel.alt = !inputModel.alt);
      }, active: inputModel.alt),
      wrap('Shift', () {
        setState(() => inputModel.shift = !inputModel.shift);
      }, active: inputModel.shift),
      wrap(isMac ? ' Cmd ' : ' Win ', () {
        setState(() => inputModel.command = !inputModel.command);
      }, active: inputModel.command),
    ];
    final keys = <Widget>[
      wrap(
          ' Fn ',
          () => setState(
                () {
                  _fn = !_fn;
                  if (_fn) {
                    _more = false;
                  }
                },
              ),
          active: _fn),
      wrap(
          '',
          () => setState(
                () => _pin = !_pin,
              ),
          active: _pin,
          icon: Icons.push_pin),
      wrap(
          ' ... ',
          () => setState(
                () {
                  _more = !_more;
                  if (_more) {
                    _fn = false;
                  }
                },
              ),
          active: _more),
    ];
    final fn = <Widget>[
      SizedBox(width: 9999),
    ];
    for (var i = 1; i <= 12; ++i) {
      final name = 'F$i';
      fn.add(wrap(name, () {
        inputModel.inputKey('VK_$name');
      }));
    }
    final more = <Widget>[
      SizedBox(width: 9999),
      wrap('Esc', () {
        inputModel.inputKey('VK_ESCAPE');
      }),
      wrap('Tab', () {
        inputModel.inputKey('VK_TAB');
      }),
      wrap('Home', () {
        inputModel.inputKey('VK_HOME');
      }),
      wrap('End', () {
        inputModel.inputKey('VK_END');
      }),
      wrap('Ins', () {
        inputModel.inputKey('VK_INSERT');
      }),
      wrap('Del', () {
        inputModel.inputKey('VK_DELETE');
      }),
      wrap('PgUp', () {
        inputModel.inputKey('VK_PRIOR');
      }),
      wrap('PgDn', () {
        inputModel.inputKey('VK_NEXT');
      }),
      // to-do: support PrtScr on Mac
      if (isWin || isLinux)
        wrap('PrtScr', () {
          inputModel.inputKey('VK_SNAPSHOT');
        }),
      if (isWin || isLinux)
        wrap('ScrollLock', () {
          inputModel.inputKey('VK_SCROLL');
        }),
      if (isWin || isLinux)
        wrap('Pause', () {
          inputModel.inputKey('VK_PAUSE');
        }),
      if (isWin || isLinux)
        // Maybe it's better to call it "Menu"
        // https://en.wikipedia.org/wiki/Menu_key
        wrap('Menu', () {
          inputModel.inputKey('Apps');
        }),
      wrap('Enter', () {
        inputModel.inputKey('VK_ENTER');
      }),
      SizedBox(width: 9999),
      wrap('', () {
        inputModel.inputKey('VK_LEFT');
      }, icon: Icons.keyboard_arrow_left),
      wrap('', () {
        inputModel.inputKey('VK_UP');
      }, icon: Icons.keyboard_arrow_up),
      wrap('', () {
        inputModel.inputKey('VK_DOWN');
      }, icon: Icons.keyboard_arrow_down),
      wrap('', () {
        inputModel.inputKey('VK_RIGHT');
      }, icon: Icons.keyboard_arrow_right),
      wrap(isMac ? 'Cmd+C' : 'Ctrl+C', () {
        sendPrompt(isMac, 'VK_C');
      }),
      wrap(isMac ? 'Cmd+V' : 'Ctrl+V', () {
        sendPrompt(isMac, 'VK_V');
      }),
      wrap(isMac ? 'Cmd+S' : 'Ctrl+S', () {
        sendPrompt(isMac, 'VK_S');
      }),
    ];
    final space = size.width > 320 ? 4.0 : 2.0;
    // 500 ms is long enough for this widget to be built!
    Future.delayed(Duration(milliseconds: 500), () {
      _updateRect();
    });
    if (widget.keyboardIsVisible) {
      return _compactKeyboardToolbar(
        <Widget>[
          ...modifiers,
          ...keys,
          if (_fn) ...fn.where((child) => child is! SizedBox),
          if (_more) ...more.where((child) => child is! SizedBox),
        ],
        space,
      );
    }
    return Container(
        key: _key,
        color: Color(0xAA000000),
        padding:
            EdgeInsets.only(top: widget.keyboardIsVisible ? 6 : 4, bottom: 8),
        child: Wrap(
          spacing: space,
          runSpacing: space,
          children: <Widget>[SizedBox(width: 9999)] +
              modifiers +
              keys +
              (_fn ? fn : []) +
              (_more ? more : []),
        ));
  }
}

class ImagePaint extends StatelessWidget {
  final FfiModel ffiModel;
  final ValueChanged<ImageModel>? onPaint;
  ImagePaint({Key? key, required this.ffiModel, this.onPaint})
      : super(key: key);

  FilterQuality _remoteImageFilterQuality(
    double scale, {
    required bool isStandardTier,
  }) {
    if (isStandardTier) {
      return FilterQuality.low;
    }
    if (scale < 1.0) {
      return FilterQuality.high;
    }
    return FilterQuality.medium;
  }

  @override
  Widget build(BuildContext context) {
    final m = Provider.of<ImageModel>(context);
    final c = Provider.of<CanvasModel>(context);
    var s = c.scale;
    if (ffiModel.isPeerLinux) {
      final displays = ffiModel.pi.getCurDisplays();
      if (displays.isNotEmpty) {
        s = s / displays[0].scale;
      }
    }
    final adjust = c.getAdjustY();
    final isStandardTier = gFFI.userModel.remoteResolutionSelection ==
        UserModel.remoteResolution720p;
    return SizedBox.expand(
      child: CustomPaint(
        painter: ImagePainter(
          image: m.image,
          x: c.x / s,
          y: (c.y + adjust) / s,
          scale: s,
          filterQuality: _remoteImageFilterQuality(
            s,
            isStandardTier: isStandardTier,
          ),
          targetWidth: c.getDisplayWidth().toDouble(),
          targetHeight: c.getDisplayHeight().toDouble(),
          onPaint: () => onPaint?.call(m),
        ),
      ),
    );
  }
}

class CursorPaint extends StatelessWidget {
  late final String id;
  CursorPaint(this.id);

  @override
  Widget build(BuildContext context) {
    final m = Provider.of<CursorModel>(context);
    final c = Provider.of<CanvasModel>(context);
    final s = c.scale;
    double hotx = m.hotx;
    double hoty = m.hoty;
    var image = m.image;
    if (image == null) {
      return Offstage();
    }

    final minSize = 12.0;
    double mins =
        minSize / (image.width > image.height ? image.width : image.height);
    double factor = 1.0;
    if (s < mins) {
      factor = s / mins;
    }
    final s2 = s < mins ? mins : s;
    final adjust = c.getAdjustY();
    return CustomPaint(
      painter: ImagePainter(
          image: image,
          x: (m.x - hotx) * factor + c.x / s2,
          y: (m.y - hoty) * factor + (c.y + adjust) / s2,
          scale: s2),
    );
  }
}

void showOptions(
    BuildContext context, String id, OverlayDialogManager dialogManager) async {
  final pi = gFFI.ffiModel.pi;
  final viewStyleRadios = await toolbarViewStyle(context, id, gFFI);
  final imageQualityRadios = await toolbarImageQuality(context, id, gFFI);
  final codecRadios = await toolbarCodec(context, id, gFFI);
  final cursorToggles = await toolbarCursor(context, id, gFFI);
  final displayToggles = await toolbarDisplayToggle(context, id, gFFI);

  var viewStyle =
      viewStyleRadios.isNotEmpty ? viewStyleRadios.first.groupValue : '';
  var imageQuality =
      imageQualityRadios.isNotEmpty ? imageQualityRadios.first.groupValue : '';
  var codec = codecRadios.isNotEmpty ? codecRadios.first.groupValue : '';
  final cursorValues = cursorToggles.map((toggle) => toggle.value).toList();
  final displayValues = displayToggles.map((toggle) => toggle.value).toList();

  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) {
        final theme = Theme.of(sheetContext);
        void closeThen(VoidCallback? action) {
          Navigator.pop(sheetContext);
          if (action != null) {
            Future<void>.delayed(Duration.zero, action);
          }
        }

        final resolution = getResolutionMenu(gFFI, id);
        final virtualDisplayMenu = getVirtualDisplayMenu(gFFI, id);
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.84,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 8, 6),
              child: Row(children: [
                Icon(Icons.monitor_rounded,
                    size: 21, color: theme.colorScheme.primary),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    kqLocaleText(zhCn: '屏幕设置', en: 'Display settings'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: translate('Close'),
                  onPressed: () => Navigator.pop(sheetContext),
                  icon: const Icon(Icons.close_rounded),
                ),
              ]),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (pi.displays.length > 1 &&
                        pi.currentDisplay != kAllDisplayValue)
                      _RemoteOptionSection(
                        title: kqLocaleText(zhCn: '显示器', en: 'Monitor'),
                        icon: Icons.desktop_windows_rounded,
                        child: Wrap(
                          spacing: 8,
                          children: List.generate(pi.displays.length, (index) {
                            final selected = index == pi.currentDisplay;
                            return _RemoteMonitorButton(
                              number: index + 1,
                              selected: selected,
                              onTap: selected
                                  ? null
                                  : () {
                                      openMonitorInTheSameTab(index, gFFI, pi);
                                      Navigator.pop(sheetContext);
                                    },
                            );
                          }),
                        ),
                      ),
                    _RemoteOptionSection(
                      title: kqLocaleText(zhCn: '缩放', en: 'Scale'),
                      icon: Icons.aspect_ratio_rounded,
                      child: Column(children: [
                        _RemoteOptionSegments<String>(
                          options: viewStyleRadios,
                          selected: viewStyle,
                          onSelected: (option) {
                            option.onChanged?.call(option.value);
                            setSheetState(() => viewStyle = option.value);
                          },
                        ),
                        if (viewStyle == kRemoteViewStyleCustom)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: MobileCustomScaleControls(ffi: gFFI),
                          ),
                      ]),
                    ),
                    _RemoteOptionSection(
                      title: kqLocaleText(zhCn: '画质', en: 'Quality'),
                      icon: Icons.high_quality_rounded,
                      child: _RemoteOptionSegments<String>(
                        options: imageQualityRadios,
                        selected: imageQuality,
                        onSelected: (option) {
                          option.onChanged?.call(option.value);
                          setSheetState(() => imageQuality = option.value);
                        },
                      ),
                    ),
                    if (codecRadios.isNotEmpty)
                      _RemoteOptionSection(
                        title: kqLocaleText(zhCn: '编码', en: 'Codec'),
                        icon: Icons.memory_rounded,
                        child: _RemoteOptionSegments<String>(
                          options: codecRadios,
                          selected: codec,
                          onSelected: (option) {
                            option.onChanged?.call(option.value);
                            setSheetState(() => codec = option.value);
                          },
                        ),
                      ),
                    if (cursorToggles.isNotEmpty || displayToggles.isNotEmpty)
                      _RemoteOptionSection(
                        title: kqLocaleText(zhCn: '显示', en: 'Display'),
                        icon: Icons.visibility_rounded,
                        child: Column(children: [
                          for (var index = 0;
                              index < cursorToggles.length;
                              index++)
                            _RemoteOptionToggle(
                              label: cursorToggles[index].child,
                              value: cursorValues[index],
                              onChanged: cursorToggles[index].onChanged == null
                                  ? null
                                  : (value) {
                                      cursorToggles[index]
                                          .onChanged
                                          ?.call(value);
                                      setSheetState(
                                          () => cursorValues[index] = value);
                                    },
                            ),
                          for (var index = 0;
                              index < displayToggles.length;
                              index++)
                            _RemoteOptionToggle(
                              label: displayToggles[index].child,
                              value: displayValues[index],
                              onChanged: displayToggles[index].onChanged == null
                                  ? null
                                  : (value) {
                                      displayToggles[index]
                                          .onChanged
                                          ?.call(value);
                                      setSheetState(
                                          () => displayValues[index] = value);
                                    },
                            ),
                        ]),
                      ),
                    if (resolution != null || virtualDisplayMenu != null)
                      _RemoteOptionSection(
                        title: kqLocaleText(zhCn: '高级', en: 'Advanced'),
                        icon: Icons.tune_rounded,
                        child: Column(children: [
                          if (resolution != null)
                            _RemoteOptionAction(
                              label: resolution.child,
                              onTap: () => closeThen(resolution.onPressed),
                            ),
                          if (virtualDisplayMenu != null)
                            _RemoteOptionAction(
                              label: virtualDisplayMenu.child,
                              onTap: () =>
                                  closeThen(virtualDisplayMenu.onPressed),
                            ),
                        ]),
                      ),
                  ],
                ),
              ),
            ),
          ]),
        );
      },
    ),
  );
  _disableAndroidSoftKeyboard();
}

class _RemoteOptionSection extends StatelessWidget {
  const _RemoteOptionSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 17, color: theme.colorScheme.primary),
          const SizedBox(width: 7),
          Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ]),
        const SizedBox(height: 9),
        child,
        const SizedBox(height: 8),
        Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.55)),
      ]),
    );
  }
}

class _RemoteOptionSegments<T> extends StatelessWidget {
  const _RemoteOptionSegments({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<TRadioMenu<T>> options;
  final T selected;
  final ValueChanged<TRadioMenu<T>> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final columns = options.length <= 3
          ? options.length
          : options.length <= 4
              ? 2
              : 3;
      final width = columns == 0
          ? constraints.maxWidth
          : (constraints.maxWidth - (columns - 1) * 8) / columns;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: options.map((option) {
          final isSelected = option.value == selected;
          final enabled = option.onChanged != null;
          return SizedBox(
            width: width,
            height: 42,
            child: Material(
              color: isSelected
                  ? theme.colorScheme.primary.withValues(alpha: 0.13)
                  : theme.colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: BorderSide(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.dividerColor,
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: enabled ? () => onSelected(option) : null,
                child: Center(
                  child: DefaultTextStyle.merge(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: enabled
                          ? isSelected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface
                          : theme.disabledColor,
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.w800 : FontWeight.w600,
                    ),
                    child: option.child,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      );
    });
  }
}

class _RemoteMonitorButton extends StatelessWidget {
  const _RemoteMonitorButton({
    required this.number,
    required this.selected,
    required this.onTap,
  });

  final int number;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: 46,
      height: 42,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          foregroundColor: selected ? colors.onPrimary : colors.onSurface,
          backgroundColor: selected ? colors.primary : Colors.transparent,
          side: BorderSide(color: selected ? colors.primary : colors.outline),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        child: Text('$number'),
      ),
    );
  }
}

class _RemoteOptionToggle extends StatelessWidget {
  const _RemoteOptionToggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final Widget label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      value: value,
      onChanged: onChanged,
      title: DefaultTextStyle.merge(
        style: const TextStyle(fontSize: 14),
        child: label,
      ),
    );
  }
}

class _RemoteOptionAction extends StatelessWidget {
  const _RemoteOptionAction({required this.label, required this.onTap});

  final Widget label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      title: label,
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

TTextMenu? getVirtualDisplayMenu(FFI ffi, String id) {
  if (!showVirtualDisplayMenu(ffi)) {
    return null;
  }
  return TTextMenu(
    child: Text(translate("Virtual display")),
    onPressed: () {
      ffi.dialogManager.show((setState, close, context) {
        final children = getVirtualDisplayMenuChildren(ffi, id, close);
        return CustomAlertDialog(
          title: Text(translate('Virtual display')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        );
      }, clickMaskDismiss: true, backDismiss: true).then((value) {
        _disableAndroidSoftKeyboard();
      });
    },
  );
}

TTextMenu? getResolutionMenu(FFI ffi, String id) {
  if (appName == '鲲穹远程桌面') {
    return null;
  }
  final ffiModel = ffi.ffiModel;
  final pi = ffiModel.pi;
  final resolutions = pi.resolutions;
  final display = pi.tryGetDisplayIfNotAllDisplay(display: pi.currentDisplay);

  final visible =
      ffiModel.keyboard && (resolutions.length > 1) && display != null;
  if (!visible) return null;

  return TTextMenu(
    child: Text(translate("Resolution")),
    onPressed: () {
      ffi.dialogManager.show((setState, close, context) {
        final children = resolutions.map((e) {
          return getRadio<String>(
            Text('${e.width}x${e.height}'),
            '${e.width}x${e.height}',
            '${display.width}x${display.height}',
            (value) {
              close();
              bind.sessionChangeResolution(
                sessionId: ffi.sessionId,
                display: pi.currentDisplay,
                width: e.width,
                height: e.height,
              );
            },
          );
        }).toList();
        return CustomAlertDialog(
          title: Text(translate('Resolution')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        );
      }, clickMaskDismiss: true, backDismiss: true).then((value) {
        _disableAndroidSoftKeyboard();
      });
    },
  );
}

void sendPrompt(bool isMac, String key) {
  final old = isMac ? gFFI.inputModel.command : gFFI.inputModel.ctrl;
  if (isMac) {
    gFFI.inputModel.command = true;
  } else {
    gFFI.inputModel.ctrl = true;
  }
  gFFI.inputModel.inputKey(key);
  if (isMac) {
    gFFI.inputModel.command = old;
  } else {
    gFFI.inputModel.ctrl = old;
  }
}

class FABLocation extends FloatingActionButtonLocation {
  FloatingActionButtonLocation location;
  double offsetX;
  double offsetY;
  FABLocation(this.location, this.offsetX, this.offsetY);

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry scaffoldGeometry) {
    final offset = location.getOffset(scaffoldGeometry);
    return Offset(offset.dx + offsetX, offset.dy + offsetY);
  }
}
