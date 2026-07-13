import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:flutter_hbb/models/state_model.dart';

import '../../consts.dart';
import '../../common/widgets/overlay.dart';
import '../../common/widgets/kq_remote_quality_presentation.dart';
import '../../common/widgets/remote_input.dart';
import '../../common.dart';
import '../../common/widgets/dialog.dart';
import '../../common/widgets/toolbar.dart';
import '../../models/model.dart';
import '../../models/input_model.dart';
import '../../models/platform_model.dart';
import '../../models/user_model.dart';
import '../../models/video_render_policy.dart';
import '../../common/shared_state.dart';
import '../../utils/image.dart';
import '../widgets/remote_toolbar.dart';
import '../widgets/kb_layout_type_chooser.dart';
import '../widgets/tabbar_widget.dart';

import 'package:flutter_hbb/native/custom_cursor.dart'
    if (dart.library.html) 'package:flutter_hbb/web/custom_cursor.dart';

final SimpleWrapper<bool> _firstEnterImage = SimpleWrapper(false);

// Used to skip session close if "move to new window" is clicked.
final Map<String, bool> closeSessionOnDispose = {};

class RemotePage extends StatefulWidget {
  RemotePage({
    Key? key,
    required this.id,
    required this.toolbarState,
    this.sessionId,
    this.tabWindowId,
    this.password,
    this.display,
    this.displays,
    this.tabController,
    this.switchUuid,
    this.forceRelay,
    this.isSharedPassword,
  }) : super(key: key) {
    initSharedStates(id);
  }

  final String id;
  final SessionID? sessionId;
  final int? tabWindowId;
  final int? display;
  final List<int>? displays;
  final String? password;
  final ToolbarState toolbarState;
  final String? switchUuid;
  final bool? forceRelay;
  final bool? isSharedPassword;
  final SimpleWrapper<State<RemotePage>?> _lastState = SimpleWrapper(null);
  final DesktopTabController? tabController;

  FFI get ffi => (_lastState.value! as _RemotePageState)._ffi;

  @override
  State<RemotePage> createState() {
    final state = _RemotePageState(id);
    _lastState.value = state;
    return state;
  }
}

class _RemotePageState extends State<RemotePage>
    with
        AutomaticKeepAliveClientMixin,
        MultiWindowListener,
        TickerProviderStateMixin {
  Timer? _timer;
  String keyboardMode = "legacy";
  bool _isWindowBlur = false;
  final _cursorOverImage = false.obs;
  late RxBool _showRemoteCursor;
  late RxBool _zoomCursor;
  late RxBool _remoteCursorMoved;
  late RxBool _keyboardEnabled;
  final _uniqueKey = UniqueKey();

  var _blockableOverlayState = BlockableOverlayState();

  final FocusNode _rawKeyFocusNode = FocusNode(debugLabel: "rawkeyFocusNode");

  // Debounce timer for pointer lock center updates during window events.
  // Uses kDefaultPointerLockCenterThrottleMs from consts.dart for the duration.
  Timer? _pointerLockCenterDebounceTimer;

  // We need `_instanceIdOnEnterOrLeaveImage4Toolbar` together with `_onEnterOrLeaveImage4Toolbar`
  // to identify the toolbar instance and its callback function.
  int? _instanceIdOnEnterOrLeaveImage4Toolbar;
  Function(bool)? _onEnterOrLeaveImage4Toolbar;

  late FFI _ffi;
  final GlobalKey _remoteSceneDiagnosticKey = GlobalKey();
  bool _remoteSceneDiagnosticStarted = false;

  SessionID get sessionId => _ffi.sessionId;

  bool get _shouldShowConnectionOverlay => shouldShowRemoteConnectionOverlay(
        isWindowsPlatform: isWindows,
        isDesktopPlatform: isDesktop,
        isWebPlatform: isWeb,
      );

  _RemotePageState(String id) {
    _initStates(id);
  }

  void _initStates(String id) {
    _zoomCursor = PeerBoolOption.find(id, kOptionZoomCursor);
    _showRemoteCursor = ShowRemoteCursorState.find(id);
    _keyboardEnabled = KeyboardEnabledState.find(id);
    _remoteCursorMoved = RemoteCursorMovedState.find(id);
  }

  @override
  void initState() {
    super.initState();
    _ffi = FFI(widget.sessionId);
    Get.put<FFI>(_ffi, tag: widget.id);
    _ffi.imageModel.addCallbackOnFirstImage((String peerId) {
      if (DateTime.now().difference(togglePrivacyModeTime) >
          const Duration(milliseconds: 3000)) {
        _ffi.dialogManager.dismissAll();
      }
      _ffi.canvasModel.activateLocalCursor();
      // The chooser is implemented with OverlayDialogManager. RemotePage on
      // KQ Windows intentionally has no page-local Overlay, so auto-opening it
      // during the first-frame callback can leave only a full-window modal
      // barrier visible above an otherwise healthy video scene. The chooser
      // remains available from the toolbar when the user needs it.
      if (_shouldShowConnectionOverlay) {
        showKBLayoutTypeChooserIfNeeded(
            _ffi.ffiModel.pi.platform, _ffi.dialogManager);
      }
      _ffi.recordingModel
          .updateStatus(bind.sessionGetIsRecording(sessionId: _ffi.sessionId));
      _scheduleRemoteSceneDiagnosticCapture();
    });
    _ffi.canvasModel.initializeEdgeScrollFallback(this);
    _ffi.start(
      widget.id,
      password: widget.password,
      isSharedPassword: widget.isSharedPassword,
      switchUuid: widget.switchUuid,
      forceRelay: widget.forceRelay,
      tabWindowId: widget.tabWindowId,
      display: widget.display,
      displays: widget.displays,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
      if (_shouldShowConnectionOverlay) {
        _ffi.dialogManager
            .showLoading(translate('Connecting...'), onCancel: closeConnection);
      }
    });
    WakelockManager.enable(_uniqueKey);

    _ffi.ffiModel.updateEventListener(sessionId, widget.id);
    if (!isWeb) bind.pluginSyncUi(syncTo: kAppTypeDesktopRemote);
    _ffi.qualityMonitorModel.checkShowQualityMonitor(sessionId);
    _ffi.dialogManager.loadMobileActionsOverlayVisible();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Session option should be set after models.dart/FFI.start
      _showRemoteCursor.value = bind.sessionGetToggleOptionSync(
          sessionId: sessionId, arg: 'show-remote-cursor');
      _zoomCursor.value = bind.sessionGetToggleOptionSync(
          sessionId: sessionId, arg: kOptionZoomCursor);
    });
    DesktopMultiWindow.addListener(this);
    // if (!_isCustomCursorInited) {
    //   customCursorController.registerNeedUpdateCursorCallback(
    //       (String? lastKey, String? currentKey) async {
    //     if (_firstEnterImage.value) {
    //       _firstEnterImage.value = false;
    //       return true;
    //     }
    //     return lastKey == null || lastKey != currentKey;
    //   });
    //   _isCustomCursorInited = true;
    // }

    _blockableOverlayState.applyFfi(_ffi);
    // Call onSelected in post frame callback, since we cannot guarantee that the callback will not call setState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.tabController?.onSelected?.call(widget.id);
    });

    // Register callback to cancel debounce timer when relative mouse mode is disabled
    _ffi.inputModel.onRelativeMouseModeDisabled =
        _cancelPointerLockCenterDebounceTimer;
  }

  /// Cancel the pointer lock center debounce timer
  void _cancelPointerLockCenterDebounceTimer() {
    _pointerLockCenterDebounceTimer?.cancel();
    _pointerLockCenterDebounceTimer = null;
  }

  @override
  void onWindowBlur() {
    super.onWindowBlur();
    // On windows, we use `focus` way to handle keyboard better.
    // Now on Linux, there's some rdev issues which will break the input.
    // We disable the `focus` way for non-Windows temporarily.
    if (isWindows) {
      _isWindowBlur = true;
      // unfocus the primary-focus when the whole window is lost focus,
      // and let OS to handle events instead.
      _rawKeyFocusNode.unfocus();
    }
    stateGlobal.isFocused.value = false;

    // When window loses focus, temporarily release relative mouse mode constraints
    // to allow user to interact with other applications normally.
    // The cursor will be re-hidden and re-centered when window regains focus.
    if (_ffi.inputModel.relativeMouseMode.value) {
      _ffi.inputModel.onWindowBlur();
    }
  }

  @override
  void onWindowFocus() {
    super.onWindowFocus();
    // See [onWindowBlur].
    if (isWindows) {
      _isWindowBlur = false;
    }
    stateGlobal.isFocused.value = true;

    // Restore relative mouse mode constraints when window regains focus.
    if (_ffi.inputModel.relativeMouseMode.value) {
      _rawKeyFocusNode.requestFocus();
      _ffi.inputModel.onWindowFocus();
    }
  }

  @override
  void onWindowRestore() {
    super.onWindowRestore();
    // On windows, we use `onWindowRestore` way to handle window restore from
    // a minimized state.
    if (isWindows) {
      _isWindowBlur = false;
    }
    WakelockManager.enable(_uniqueKey);
    // Update pointer lock center when window is restored
    _updatePointerLockCenterIfNeeded();
  }

  // When the window is unminimized, onWindowMaximize or onWindowRestore can be called when the old state was maximized or not.
  @override
  void onWindowMaximize() {
    super.onWindowMaximize();
    WakelockManager.enable(_uniqueKey);
    // Update pointer lock center when window is maximized
    _updatePointerLockCenterIfNeeded();
  }

  @override
  void onWindowResize() {
    super.onWindowResize();
    // Update pointer lock center when window is resized
    _updatePointerLockCenterIfNeeded();
  }

  @override
  void onWindowMove() {
    super.onWindowMove();
    // Update pointer lock center when window is moved
    _updatePointerLockCenterIfNeeded();
  }

  /// Update pointer lock center with debouncing to avoid excessive updates
  /// during rapid window move/resize events.
  void _updatePointerLockCenterIfNeeded() {
    if (!_ffi.inputModel.relativeMouseMode.value) return;

    // Cancel any pending update and schedule a new one (debounce pattern)
    _pointerLockCenterDebounceTimer?.cancel();
    _pointerLockCenterDebounceTimer = Timer(
      const Duration(milliseconds: kDefaultPointerLockCenterThrottleMs),
      () {
        if (!mounted) return;
        if (_ffi.inputModel.relativeMouseMode.value) {
          _ffi.inputModel.updatePointerLockCenter();
        }
      },
    );
  }

  @override
  void onWindowMinimize() {
    super.onWindowMinimize();
    WakelockManager.disable(_uniqueKey);
    // Release cursor constraints when minimized
    if (_ffi.inputModel.relativeMouseMode.value) {
      _ffi.inputModel.onWindowBlur();
    }
  }

  @override
  void onWindowEnterFullScreen() {
    super.onWindowEnterFullScreen();
    if (isMacOS) {
      stateGlobal.setFullscreen(true);
    }
  }

  @override
  void onWindowLeaveFullScreen() {
    super.onWindowLeaveFullScreen();
    if (isMacOS) {
      stateGlobal.setFullscreen(false);
    }
  }

  @override
  Future<void> dispose() async {
    final closeSession = closeSessionOnDispose.remove(widget.id) ?? true;

    // https://github.com/flutter/flutter/issues/64935
    super.dispose();
    debugPrint("REMOTE PAGE dispose session $sessionId ${widget.id}");

    // Defensive cleanup: ensure host system-key propagation is reset even if
    // MouseRegion.onExit never fired (e.g., tab closed while cursor inside).
    if (!isWeb) bind.hostStopSystemKeyPropagate(stopped: true);

    _pointerLockCenterDebounceTimer?.cancel();
    _pointerLockCenterDebounceTimer = null;
    // Clear callback reference to prevent memory leaks and stale references
    _ffi.inputModel.onRelativeMouseModeDisabled = null;
    // Relative mouse mode cleanup is centralized in FFI.close(closeSession: ...).
    _ffi.textureModel.onRemotePageDispose(closeSession);
    if (closeSession) {
      // ensure we leave this session, this is a double check
      _ffi.inputModel.enterOrLeave(false);
    }
    DesktopMultiWindow.removeListener(this);
    _ffi.dialogManager.hideMobileActionsOverlay();
    _ffi.imageModel.disposeImage();
    _ffi.cursorModel.disposeImages();
    _rawKeyFocusNode.dispose();
    await _ffi.close(closeSession: closeSession);
    _timer?.cancel();
    _ffi.dialogManager.dismissAll();
    if (closeSession) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
          overlays: SystemUiOverlay.values);
    }
    WakelockManager.disable(_uniqueKey);
    await Get.delete<FFI>(tag: widget.id);
    removeSharedStates(widget.id);
  }

  Widget buildBody(BuildContext context) {
    remoteToolbar(BuildContext context) => RemoteToolbar(
          id: widget.id,
          ffi: _ffi,
          state: widget.toolbarState,
          onEnterOrLeaveImageSetter: (id, func) {
            _instanceIdOnEnterOrLeaveImage4Toolbar = id;
            _onEnterOrLeaveImage4Toolbar = func;
          },
          onEnterOrLeaveImageCleaner: (id) {
            // If _instanceIdOnEnterOrLeaveImage4Toolbar != id
            // it means `_onEnterOrLeaveImage4Toolbar` is not set or it has been changed to another toolbar.
            if (_instanceIdOnEnterOrLeaveImage4Toolbar == id) {
              _instanceIdOnEnterOrLeaveImage4Toolbar = null;
              _onEnterOrLeaveImage4Toolbar = null;
            }
          },
          setRemoteState: setState,
        );

    bodyWidget() {
      return Stack(
        children: [
          Container(
              color: kColorCanvas,
              child: RawKeyFocusScope(
                  focusNode: _rawKeyFocusNode,
                  onFocusChange: (bool imageFocused) {
                    debugPrint(
                        "onFocusChange(window active:${!_isWindowBlur}) $imageFocused");
                    // See [onWindowBlur].
                    if (isWindows) {
                      if (_isWindowBlur) {
                        imageFocused = false;
                        Future.delayed(Duration.zero, () {
                          _rawKeyFocusNode.unfocus();
                        });
                      }
                      if (imageFocused) {
                        _ffi.inputModel.enterOrLeave(true);
                      } else {
                        _ffi.inputModel.enterOrLeave(false);
                      }
                    }
                  },
                  inputModel: _ffi.inputModel,
                  child: getBodyForDesktop(context))),
          Stack(
            children: [
              if (_ffi.ffiModel.pi.isSet.isTrue &&
                  _ffi.ffiModel.waitForFirstImage.isFalse &&
                  _ffi.ffiModel.isPeerAndroid)
                Obx(() => Offstage(
                      offstage: _ffi
                          .dialogManager.mobileActionsOverlayVisible.isFalse,
                      child: Overlay(initialEntries: [
                        makeMobileActionsOverlayEntry(
                          () => _ffi.dialogManager
                              .setMobileActionsOverlayVisible(false),
                          ffi: _ffi,
                        )
                      ]),
                    )),
              // Hide toolbar when relative mouse mode is active to prevent
              // cursor from escaping to toolbar area.
              Obx(() => _ffi.inputModel.relativeMouseMode.value
                  ? const Offstage()
                  : remoteToolbar(context)),
            ],
          ),
          if (isWindows)
            Positioned.fill(
              child: Obx(() => IgnorePointer(
                    ignoring: !_blockableOverlayState.middleBlocked.value,
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (_) {
                        _blockableOverlayState.onMiddleBlockedClick?.call();
                      },
                      child: const SizedBox.expand(),
                    ),
                  )),
            ),
        ],
      );
    }

    final underlying = Obx(() => bodyWidget());
    return RepaintBoundary(
      key: _remoteSceneDiagnosticKey,
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.background,
        // A second full-window Overlay can hide a valid software-video scene on
        // Windows. Dialogs fall back to the window-level overlay instead.
        body: isWindows
            ? underlying
            : BlockableOverlay(
                underlying: underlying,
                state: _blockableOverlayState,
              ),
      ),
    );
  }

  void _scheduleRemoteSceneDiagnosticCapture() {
    if (!isWindows || _remoteSceneDiagnosticStarted) return;
    _remoteSceneDiagnosticStarted = true;
    Future<void>.delayed(const Duration(milliseconds: 500), () async {
      if (!mounted || _ffi.closed) return;
      final display = _ffi.ffiModel.pi.currentDisplay;
      try {
        await WidgetsBinding.instance.endOfFrame;
        final decoded = _ffi.imageModel.image;
        final boundary = _remoteSceneDiagnosticKey.currentContext
            ?.findRenderObject() as RenderRepaintBoundary?;
        if (decoded == null || boundary == null || boundary.debugNeedsPaint) {
          platformFFI.logRgbaStage(
              _ffi.sessionId, 'scene-capture-not-ready', display);
          return;
        }

        final outputDir = Directory.systemTemp.path;
        final suffix = _ffi.sessionId.toString();
        final decodedBytes =
            await decoded.toByteData(format: ui.ImageByteFormat.png);
        if (decodedBytes != null) {
          final decodedPath = '$outputDir${Platform.pathSeparator}'
              'kq-decoded-frame-$suffix.png';
          await File(decodedPath)
              .writeAsBytes(decodedBytes.buffer.asUint8List(), flush: true);
        }

        final scene = await boundary.toImage(pixelRatio: 1);
        try {
          final sceneBytes =
              await scene.toByteData(format: ui.ImageByteFormat.png);
          if (sceneBytes != null) {
            final scenePath = '$outputDir${Platform.pathSeparator}'
                'kq-composited-scene-$suffix.png';
            await File(scenePath)
                .writeAsBytes(sceneBytes.buffer.asUint8List(), flush: true);
          }
          platformFFI.logRgbaStage(_ffi.sessionId, 'scene-capture-saved',
              display, scene.width, scene.height);
        } finally {
          scene.dispose();
        }
      } catch (error, stackTrace) {
        platformFFI.logRgbaStage(
            _ffi.sessionId, 'scene-capture-error', display);
        debugPrint('Failed to capture remote scene diagnostic: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return WillPopScope(
        onWillPop: () async {
          clientClose(sessionId, _ffi);
          return false;
        },
        child: MultiProvider(providers: [
          ChangeNotifierProvider.value(value: _ffi.ffiModel),
          ChangeNotifierProvider.value(value: _ffi.imageModel),
          ChangeNotifierProvider.value(value: _ffi.cursorModel),
          ChangeNotifierProvider.value(value: _ffi.canvasModel),
          ChangeNotifierProvider.value(value: _ffi.recordingModel),
        ], child: buildBody(context)));
  }

  void enterView(PointerEnterEvent evt) {
    _ffi.canvasModel.rearmEdgeScroll();

    _cursorOverImage.value = true;
    _firstEnterImage.value = true;
    if (_onEnterOrLeaveImage4Toolbar != null) {
      try {
        _onEnterOrLeaveImage4Toolbar!(true);
      } catch (e) {
        //
      }
    }

    // See [onWindowBlur].
    if (!isWindows) {
      if (!_rawKeyFocusNode.hasFocus) {
        _rawKeyFocusNode.requestFocus();
      }
      _ffi.inputModel.enterOrLeave(true);
    }
  }

  void leaveView(PointerExitEvent evt) {
    _ffi.canvasModel.disableEdgeScroll();

    if (_ffi.ffiModel.keyboard) {
      _ffi.inputModel.tryMoveEdgeOnExit(evt.position);
    }

    _cursorOverImage.value = false;
    _firstEnterImage.value = false;
    if (_onEnterOrLeaveImage4Toolbar != null) {
      try {
        _onEnterOrLeaveImage4Toolbar!(false);
      } catch (e) {
        //
      }
    }

    // See [onWindowBlur].
    if (!isWindows) {
      _ffi.inputModel.enterOrLeave(false);
    }
  }

  Widget _buildRawTouchAndPointerRegion(
    Widget child,
    PointerEnterEventListener? onEnter,
    PointerExitEventListener? onExit,
  ) {
    return RawTouchGestureDetectorRegion(
      child: _buildRawPointerMouseRegion(child, onEnter, onExit),
      ffi: _ffi,
    );
  }

  Widget _buildRawPointerMouseRegion(
    Widget child,
    PointerEnterEventListener? onEnter,
    PointerExitEventListener? onExit,
  ) {
    return RawPointerMouseRegion(
      onEnter: onEnter,
      onExit: onExit,
      onPointerDown: (event) {
        // A double check for blur status.
        // Note: If there's an `onPointerDown` event is triggered, `_isWindowBlur` is expected being false.
        // Sometimes the system does not send the necessary focus event to flutter. We should manually
        // handle this inconsistent status by setting `_isWindowBlur` to false. So we can
        // ensure the grab-key thread is running when our users are clicking the remote canvas.
        if (_isWindowBlur) {
          debugPrint(
              "Unexpected status: onPointerDown is triggered while the remote window is in blur status");
          _isWindowBlur = false;
        }
        if (!_rawKeyFocusNode.hasFocus) {
          _rawKeyFocusNode.requestFocus();
        }
      },
      inputModel: _ffi.inputModel,
      child: child,
    );
  }

  Widget getBodyForDesktop(BuildContext context) {
    var paints = <Widget>[
      MouseRegion(
        onEnter: (evt) {
          if (!isWeb) bind.hostStopSystemKeyPropagate(stopped: false);
        },
        onExit: (evt) {
          if (!isWeb) bind.hostStopSystemKeyPropagate(stopped: true);
        },
        child: _ViewStyleUpdater(
          canvasModel: _ffi.canvasModel,
          inputModel: _ffi.inputModel,
          child: Builder(builder: (context) {
            final peerDisplay = CurrentDisplayState.find(widget.id);
            return Obx(
              () => _ffi.ffiModel.pi.isSet.isFalse
                  ? Container(color: Colors.transparent)
                  : Obx(() {
                      _ffi.textureModel.updateCurrentDisplay(peerDisplay.value);
                      return ImagePaint(
                        id: widget.id,
                        zoomCursor: _zoomCursor,
                        cursorOverImage: _cursorOverImage,
                        keyboardEnabled: _keyboardEnabled,
                        remoteCursorMoved: _remoteCursorMoved,
                        listenerBuilder: (child) =>
                            _buildRawTouchAndPointerRegion(
                                child, enterView, leaveView),
                        ffi: _ffi,
                      );
                    }),
            );
          }),
        ),
      )
    ];

    if (!_ffi.canvasModel.cursorEmbedded) {
      paints
          .add(Obx(() => _showRemoteCursor.isFalse || _remoteCursorMoved.isFalse
              ? Offstage()
              : CursorPaint(
                  id: widget.id,
                  zoomCursor: _zoomCursor,
                )));
    }
    paints.add(
      Positioned(
        top: 10,
        right: 10,
        child: _buildRawTouchAndPointerRegion(
            QualityMonitor(_ffi.qualityMonitorModel), null, null),
      ),
    );
    return Stack(
      children: paints,
    );
  }

  @override
  bool get wantKeepAlive => true;
}

/// A widget that tracks the view size and updates CanvasModel.updateViewStyle()
/// and InputModel.updateImageWidgetSize() only when size actually changes.
/// This avoids scheduling post-frame callbacks on every LayoutBuilder rebuild.
class _ViewStyleUpdater extends StatefulWidget {
  final CanvasModel canvasModel;
  final InputModel inputModel;
  final Widget child;

  const _ViewStyleUpdater({
    Key? key,
    required this.canvasModel,
    required this.inputModel,
    required this.child,
  }) : super(key: key);

  @override
  State<_ViewStyleUpdater> createState() => _ViewStyleUpdaterState();
}

class _ViewStyleUpdaterState extends State<_ViewStyleUpdater> {
  Size? _lastSize;
  bool _callbackScheduled = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final maxHeight = constraints.maxHeight;
        // Guard against infinite constraints (e.g., unconstrained ancestor).
        if (!maxWidth.isFinite || !maxHeight.isFinite) {
          return widget.child;
        }
        final newSize = Size(maxWidth, maxHeight);
        if (_lastSize != newSize) {
          _lastSize = newSize;
          widget.canvasModel.setViewportSize(newSize);
          // Schedule the update for after the current frame to avoid setState during build.
          // Use _callbackScheduled flag to prevent accumulating multiple callbacks
          // when size changes rapidly before any callback executes.
          if (!_callbackScheduled) {
            _callbackScheduled = true;
            SchedulerBinding.instance.addPostFrameCallback((_) {
              _callbackScheduled = false;
              final currentSize = _lastSize;
              if (mounted && currentSize != null) {
                widget.canvasModel.updateViewStyle();
                widget.inputModel.updateImageWidgetSize(currentSize);
              }
            });
          }
        }
        return widget.child;
      },
    );
  }
}

class ImagePaint extends StatefulWidget {
  final FFI ffi;
  final String id;
  final RxBool zoomCursor;
  final RxBool cursorOverImage;
  final RxBool keyboardEnabled;
  final RxBool remoteCursorMoved;
  final Widget Function(Widget)? listenerBuilder;

  ImagePaint(
      {Key? key,
      required this.ffi,
      required this.id,
      required this.zoomCursor,
      required this.cursorOverImage,
      required this.keyboardEnabled,
      required this.remoteCursorMoved,
      this.listenerBuilder})
      : super(key: key);

  @override
  State<StatefulWidget> createState() => _ImagePaintState();
}

class _ImagePaintState extends State<ImagePaint> {
  bool _lastRemoteCursorMoved = false;
  bool _loggedFirstTextureLayout = false;
  bool _loggedFirstValidTextureLayout = false;

  String get id => widget.id;
  RxBool get zoomCursor => widget.zoomCursor;
  RxBool get cursorOverImage => widget.cursorOverImage;
  RxBool get keyboardEnabled => widget.keyboardEnabled;
  RxBool get remoteCursorMoved => widget.remoteCursorMoved;
  Widget Function(Widget)? get listenerBuilder => widget.listenerBuilder;

  @override
  Widget build(BuildContext context) {
    final m = Provider.of<ImageModel>(context);
    var c = Provider.of<CanvasModel>(context);
    final s = c.scale;

    bool isViewAdaptive() => c.viewStyle.style == kRemoteViewStyleAdaptive;
    bool isViewOriginal() => c.viewStyle.style == kRemoteViewStyleOriginal;

    mouseRegion({child}) => Obx(() {
          double getCursorScale() {
            var c = Provider.of<CanvasModel>(context);
            var cursorScale = 1.0;
            if (isWindows) {
              // debug win10
              if (zoomCursor.value && isViewAdaptive()) {
                cursorScale = s * c.devicePixelRatio;
              }
            } else {
              if (zoomCursor.value || isViewOriginal()) {
                cursorScale = s;
              }
            }
            return cursorScale;
          }

          return MouseRegion(
              cursor: cursorOverImage.isTrue
                  ? c.cursorEmbedded
                      ? SystemMouseCursors.none
                      // Hide cursor when relative mouse mode is active
                      : widget.ffi.inputModel.relativeMouseMode.value
                          ? SystemMouseCursors.none
                          : keyboardEnabled.isTrue
                              ? (() {
                                  if (remoteCursorMoved.isTrue) {
                                    _lastRemoteCursorMoved = true;
                                    return SystemMouseCursors.none;
                                  } else {
                                    if (_lastRemoteCursorMoved) {
                                      _lastRemoteCursorMoved = false;
                                      _firstEnterImage.value = true;
                                    }
                                    return _buildCustomCursor(
                                        context, getCursorScale());
                                  }
                                }())
                              : _buildDisabledCursor(context, getCursorScale())
                  : MouseCursor.defer,
              onHover: (evt) {},
              child: child);
        });
    if (c.imageOverflow.isTrue && c.scrollStyle != ScrollStyle.scrollauto) {
      final paintWidth = c.getDisplayWidth() * s;
      final paintHeight = c.getDisplayHeight() * s;
      final paintSize = Size(paintWidth, paintHeight);
      final paintWidget = _applyKqRemoteQualityPresentation(
        m.useTextureRender || widget.ffi.ffiModel.pi.forceTextureRender
            ? _BuildPaintTextureRender(
                c, s, Offset.zero, paintSize, isViewOriginal())
            : _buildScrollbarNonTextureRender(m, paintSize, s),
      );
      return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            c.updateScrollPercent();
            return false;
          },
          child: mouseRegion(
            child: Obx(() => _buildCrossScrollbarFromLayout(
                  context,
                  _buildListener(paintWidget),
                  c.size,
                  paintSize,
                  c.scrollHorizontal,
                  c.scrollVertical,
                )),
          ));
    } else {
      if (c.size.width > 0 && c.size.height > 0) {
        final paintWidget = _applyKqRemoteQualityPresentation(
          m.useTextureRender || widget.ffi.ffiModel.pi.forceTextureRender
              ? _BuildPaintTextureRender(
                  c,
                  s,
                  Offset(
                    isLinux ? c.x.toInt().toDouble() : c.x,
                    isLinux ? c.y.toInt().toDouble() : c.y,
                  ),
                  c.size,
                  isViewOriginal())
              : _buildScrollAutoNonTextureRender(m, c, s),
        );
        return mouseRegion(child: _buildListener(paintWidget));
      } else {
        return Container();
      }
    }
  }

  Widget _buildScrollbarNonTextureRender(
      ImageModel m, Size imageSize, double s) {
    return _buildRawSoftwareImage(m, imageSize, 0, 0, s);
  }

  Widget _buildScrollAutoNonTextureRender(
      ImageModel m, CanvasModel c, double s) {
    double sizeScale = s;
    if (widget.ffi.ffiModel.isPeerLinux) {
      final displays = widget.ffi.ffiModel.pi.getCurDisplays();
      if (displays.isNotEmpty) {
        sizeScale = s / displays[0].scale;
      }
    }
    return _buildRawSoftwareImage(
      m,
      c.size,
      c.x / sizeScale,
      c.y / sizeScale,
      sizeScale,
    );
  }

  Widget _buildRawSoftwareImage(
      ImageModel model, Size viewport, double x, double y, double scale) {
    final image = model.image;
    if (image == null || !x.isFinite || !y.isFinite || !scale.isFinite) {
      return SizedBox(width: viewport.width, height: viewport.height);
    }
    _handleSoftwarePaint(model, viewport, scale);
    return SizedBox(
      width: viewport.width,
      height: viewport.height,
      child: ClipRect(
        child: Stack(
          children: [
            Positioned(
              left: x * scale,
              top: y * scale,
              width: image.width * scale,
              height: image.height * scale,
              child: RawImage(
                image: image,
                fit: BoxFit.fill,
                filterQuality: _remoteImageFilterQuality(scale),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleSoftwarePaint(
      ImageModel model, Size paintSize, double paintScale) {
    final display = widget.ffi.ffiModel.pi.currentDisplay;
    final firstPaint = model.markFramePainted(display);
    if (firstPaint) {
      platformFFI.logRgbaStage(widget.ffi.sessionId, 'canvas-paint-size',
          display, paintSize.width.round(), paintSize.height.round());
      platformFFI.logRgbaStage(widget.ffi.sessionId, 'canvas-paint-scale',
          display, paintScale.isFinite ? (paintScale * 10000).round() : 0);
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || widget.ffi.closed) return;
        platformFFI.logRgbaStage(
            widget.ffi.sessionId,
            'first-frame-ui-after-paint',
            display,
            model.image?.width ?? 0,
            model.image?.height ?? 0);
        try {
          await widget.ffi.onEvent2UIRgba(updateCanvasLayout: false);
        } catch (error, stackTrace) {
          platformFFI.logRgbaStage(
              widget.ffi.sessionId, 'first-frame-ui-finalize-error', display);
          debugPrint('Failed to finalize the first remote frame UI: $error');
          debugPrintStack(stackTrace: stackTrace);
        }
      });
    }
  }

  FilterQuality _remoteImageFilterQuality(double scale) {
    if (scale < 1.0) {
      return FilterQuality.high;
    }
    return FilterQuality.medium;
  }

  Widget _applyKqRemoteQualityPresentation(Widget child) {
    return KqRemoteQualityPresentation(
      streamQuality: gFFI.userModel.remoteCustomQualitySelection,
      isStandardTier: gFFI.userModel.remoteResolutionSelection ==
          UserModel.remoteResolution720p,
      child: child,
    );
  }

  Widget _BuildPaintTextureRender(
      CanvasModel c, double s, Offset offset, Size size, bool isViewOriginal) {
    final ffiModel = c.parent.target!.ffiModel;
    final displays = ffiModel.pi.getCurDisplays();
    final children = <Widget>[];
    final rect = ffiModel.rect;
    if (rect == null) {
      return Container();
    }
    final isPeerLinux = ffiModel.isPeerLinux;
    final curDisplay = ffiModel.pi.currentDisplay;
    if (!_loggedFirstTextureLayout) {
      _loggedFirstTextureLayout = true;
      platformFFI.logRgbaStage(widget.ffi.sessionId, 'texture-layout-size',
          curDisplay, size.width.round(), size.height.round());
      platformFFI.logRgbaStage(widget.ffi.sessionId, 'texture-layout-state',
          curDisplay, displays.length, rect.width.round());
    }
    for (var i = 0; i < displays.length; i++) {
      final textureId = widget.ffi.textureModel
          .getTextureId(curDisplay == kAllDisplayValue ? i : curDisplay);
      if (!_loggedFirstValidTextureLayout && textureId.value >= 0) {
        _loggedFirstValidTextureLayout = true;
        platformFFI.logRgbaStage(
            widget.ffi.sessionId,
            'texture-layout-valid-id',
            curDisplay,
            textureId.value,
            (s * 10000).round());
      }
      if (true) {
        // both "textureId.value != -1" and "true" seems ok
        final sizeScale = isPeerLinux ? s / displays[i].scale : s;
        children.add(Positioned(
          left: (displays[i].x - rect.left) * s + offset.dx,
          top: (displays[i].y - rect.top) * s + offset.dy,
          width: displays[i].width * sizeScale,
          height: displays[i].height * sizeScale,
          child: Obx(() => Texture(
                textureId: textureId.value,
                filterQuality: isViewOriginal
                    ? FilterQuality.none
                    : _remoteImageFilterQuality(sizeScale),
              )),
        ));
      }
    }
    return SizedBox(
      width: size.width,
      height: size.height,
      child: Stack(children: children),
    );
  }

  MouseCursor _buildCustomCursor(BuildContext context, double scale) {
    final cursor = Provider.of<CursorModel>(context);
    final cache = cursor.cache ?? preDefaultCursor.cache;
    return buildCursorOfCache(cursor, scale, cache);
  }

  MouseCursor _buildDisabledCursor(BuildContext context, double scale) {
    final cursor = Provider.of<CursorModel>(context);
    final cache = preForbiddenCursor.cache;
    return buildCursorOfCache(cursor, scale, cache);
  }

  Widget _buildCrossScrollbarFromLayout(
    BuildContext context,
    Widget child,
    Size layoutSize,
    Size size,
    ScrollController horizontal,
    ScrollController vertical,
  ) {
    var widget = child;
    if (layoutSize.width < size.width) {
      widget = ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: SingleChildScrollView(
          controller: horizontal,
          scrollDirection: Axis.horizontal,
          physics: cursorOverImage.isTrue
              ? const NeverScrollableScrollPhysics()
              : null,
          child: widget,
        ),
      );
    } else {
      widget = Row(
        children: [
          Container(
            width: ((layoutSize.width - size.width) ~/ 2).toDouble(),
          ),
          widget,
        ],
      );
    }
    if (layoutSize.height < size.height) {
      widget = ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: SingleChildScrollView(
          controller: vertical,
          physics: cursorOverImage.isTrue
              ? const NeverScrollableScrollPhysics()
              : null,
          child: widget,
        ),
      );
    } else {
      widget = Column(
        children: [
          Container(
            height: ((layoutSize.height - size.height) ~/ 2).toDouble(),
          ),
          widget,
        ],
      );
    }
    if (layoutSize.width < size.width) {
      widget = RawScrollbar(
        thickness: kScrollbarThickness,
        thumbColor: Colors.grey,
        controller: horizontal,
        thumbVisibility: false,
        trackVisibility: false,
        notificationPredicate: layoutSize.height < size.height
            ? (notification) => notification.depth == 1
            : defaultScrollNotificationPredicate,
        child: widget,
      );
    }
    if (layoutSize.height < size.height) {
      widget = RawScrollbar(
        thickness: kScrollbarThickness,
        thumbColor: Colors.grey,
        controller: vertical,
        thumbVisibility: false,
        trackVisibility: false,
        child: widget,
      );
    }

    return Container(
      child: widget,
      width: layoutSize.width,
      height: layoutSize.height,
    );
  }

  Widget _buildListener(Widget child) {
    if (listenerBuilder != null) {
      return listenerBuilder!(child);
    } else {
      return child;
    }
  }
}

class CursorPaint extends StatelessWidget {
  final String id;
  final RxBool zoomCursor;

  const CursorPaint({
    Key? key,
    required this.id,
    required this.zoomCursor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final m = Provider.of<CursorModel>(context);
    final c = Provider.of<CanvasModel>(context);
    double hotx = m.hotx;
    double hoty = m.hoty;
    if (m.image == null) {
      if (preDefaultCursor.image != null) {
        hotx = preDefaultCursor.image!.width / 2;
        hoty = preDefaultCursor.image!.height / 2;
      }
    }

    double cx = c.x;
    double cy = c.y;
    if (c.viewStyle.style == kRemoteViewStyleOriginal &&
        c.scrollStyle == ScrollStyle.scrollbar) {
      final rect = c.parent.target!.ffiModel.rect;
      if (rect == null) {
        // unreachable!
        debugPrint('unreachable! The displays rect is null.');
        return Container();
      }
      if (cx < 0) {
        final imageWidth = rect.width * c.scale;
        cx = -imageWidth * c.scrollX;
      }
      if (cy < 0) {
        final imageHeight = rect.height * c.scale;
        cy = -imageHeight * c.scrollY;
      }
    }

    double x = (m.x - hotx) * c.scale + cx;
    double y = (m.y - hoty) * c.scale + cy;
    double scale = 1.0;
    final isViewOriginal = c.viewStyle.style == kRemoteViewStyleOriginal;
    if (zoomCursor.value || isViewOriginal) {
      x = m.x - hotx + cx / c.scale;
      y = m.y - hoty + cy / c.scale;
      scale = c.scale;
    }

    return CustomPaint(
      painter: ImagePainter(
        image: m.image ?? preDefaultCursor.image,
        x: x,
        y: y,
        scale: scale,
      ),
    );
  }
}
