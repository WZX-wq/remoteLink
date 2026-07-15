import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _section(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  final endIndex = source.indexOf(end, startIndex + start.length);
  expect(startIndex, greaterThanOrEqualTo(0), reason: 'Missing start: $start');
  expect(endIndex, greaterThan(startIndex), reason: 'Missing end: $end');
  return source.substring(startIndex, endIndex);
}

void main() {
  late String inputModel;
  late String remoteInput;
  late String remotePage;

  setUpAll(() {
    inputModel = File('lib/models/input_model.dart').readAsStringSync();
    remoteInput =
        File('lib/common/widgets/remote_input.dart').readAsStringSync();
    remotePage = File('lib/mobile/pages/remote_page.dart').readAsStringSync();
  });

  test('shared mobile input covers iOS touch mouse scroll and pinch paths', () {
    final gestures = _section(
      remoteInput,
      'class _RawTouchGestureDetectorRegionState',
      'class RawPointerMouseRegion',
    );
    final pointerRegion = _section(
      remoteInput,
      'class RawPointerMouseRegion',
      'class CameraRawPointerMouseRegion',
    );

    expect(gestures, contains('TapGestureRecognizer'));
    expect(gestures, contains('LongPressGestureRecognizer'));
    expect(gestures, contains('HoldTapMoveGestureRecognizer'));
    expect(gestures, contains('onOneFingerPanStart'));
    expect(gestures, contains('onOneFingerPanUpdate'));
    expect(gestures, contains('onOneFingerPanEnd'));
    expect(gestures, contains('onThreeFingerVerticalDragUpdate'));
    expect(gestures, contains('inputModel.scroll(1)'));
    expect(gestures, contains('inputModel.scroll(-1)'));
    expect(gestures, contains('ffi.canvasModel.updateScale'));
    expect(gestures, contains('inputModel.relativeMouseMode.value'));
    expect(gestures, contains('inputModel.sendMobileRelativeMouseMove'));
    expect(pointerRegion, contains('inputModel.onPointerSignalImage'));
    expect(pointerRegion, contains('inputModel.onPointerPanZoomStart'));
    expect(pointerRegion, contains('inputModel.onPointerPanZoomUpdate'));
    expect(pointerRegion, contains('inputModel.onPointerPanZoomEnd'));
  });

  test('iOS Magic Mouse filtering consumes one touch tap sequence', () {
    final magicMouse = _section(
      inputModel,
      '  // iOS Magic Mouse duplicate event detection.',
      '  void onPointUpImage(PointerUpEvent e) {',
    );
    final tapHandlers = _section(
      remoteInput,
      '  onTapDown(TapDownDetails d) async {',
      '  onDoubleTapDown(TapDownDetails d) async {',
    );
    final tapRecognizer = _section(
      remoteInput,
      '      TapGestureRecognizer:',
      '      DoubleTapGestureRecognizer:',
    );

    expect(magicMouse, contains('bool shouldIgnoreTouchTap(ui.Offset pos)'));
    expect(magicMouse, contains('if (!isIOS) return false;'));
    expect(magicMouse, contains('_lastMouseDownTimeMs'));
    expect(magicMouse, contains('_lastMouseDownPos'));
    expect(magicMouse, contains('_shouldIgnoreTouchAfterMouse(nowMs)'));
    expect(magicMouse, contains('const int kTouchAfterMouseWindowMs = 700;'));
    expect(tapHandlers, contains('_ignoreCurrentTouchTap'));
    expect(tapHandlers,
        contains('_ignoreCurrentTouchTap = inputModel.shouldIgnoreTouchTap'));
    expect(tapRecognizer, contains('..onTapCancel = onTapCancel'));

    final doubleTapHandlers = _section(
      remoteInput,
      '  onDoubleTapDown(TapDownDetails d) async {',
      '  onLongPressDown(LongPressDownDetails d) async {',
    );
    expect(doubleTapHandlers, contains('_ignoreCurrentDoubleTap'));
    expect(doubleTapHandlers, contains('inputModel.shouldIgnoreTouchTap'));
  });

  test('long press only releases a left button that it pressed', () {
    final longPressHandlers = _section(
      remoteInput,
      '  onLongPressDown(LongPressDownDetails d) async {',
      '  onDoubleFinerTapDown(TapDownDetails d) async {',
    );

    expect(longPressHandlers, contains('_longPressLeftButtonDown = true'));
    expect(longPressHandlers, contains('_longPressLeftButtonStarting = true'));
    expect(longPressHandlers, contains('_longPressReleasePending = true'));
    expect(longPressHandlers,
        contains('if (_longPressLeftButtonStarting)'));
    expect(longPressHandlers, contains('_longPressLeftButtonDown = false'));
  });

  test('iOS soft hardware and special keyboard paths stay connected', () {
    final hardwareKeyboard = _section(
      inputModel,
      '  KeyEventResult handleKeyEvent(KeyEvent e) {',
      '  /// Send Key Event',
    );
    final softKeyboard = _section(
      remotePage,
      '  void onSoftKeyboardChanged(bool visible) {',
      '  Widget _bottomWidget()',
    );
    final specialKeys = _section(
      remotePage,
      'class _KeyHelpToolsState extends State<KeyHelpTools>',
      'class ImagePaint extends StatelessWidget',
    );

    expect(hardwareKeyboard, contains('if (isIOS)'));
    expect(hardwareKeyboard, contains('isMobileAndMapMode = true;'));
    expect(hardwareKeyboard, contains('newKeyboardMode('));
    expect(softKeyboard, contains('_iosKeyboardWorkaroundTimer'));
    expect(softKeyboard, contains('_physicalFocusNode.requestFocus()'));
    expect(softKeyboard, contains('_handleIOSSoftKeyboardInput(newValue)'));
    expect(softKeyboard, contains('inputModel.inputKey(char)'));
    expect(softKeyboard, contains('else if (newStr.isNotEmpty)'));
    for (final key in <String>[
      'VK_ESCAPE',
      'VK_TAB',
      'VK_HOME',
      'VK_END',
      'VK_INSERT',
      'VK_DELETE',
      'VK_PRIOR',
      'VK_NEXT',
      'VK_ENTER',
      'VK_LEFT',
      'VK_UP',
      'VK_DOWN',
      'VK_RIGHT',
    ]) {
      expect(specialKeys, contains(key));
    }
  });

  test('iOS remote toolbar exposes every supported control', () {
    final rail = _section(
      remotePage,
      '  Widget _remoteSideActionRail() {',
      '  Widget _remoteSideActionButton({',
    );
    final options = _section(
      remotePage,
      'void showOptions(',
      'TTextMenu? getVirtualDisplayMenu(',
    );

    expect(rail, contains('clientClose(sessionId, gFFI)'));
    expect(rail, contains('onPressed: openKeyboard'));
    expect(rail, contains('gFFI.ffiModel.touchMode'));
    expect(rail, contains('_showGestureHelp = !_showGestureHelp'));
    expect(rail, contains('showOptions(context, widget.id'));
    expect(options, contains('toolbarImageQuality(context, id, gFFI)'));
    expect(
      rail,
      contains('isIOS || (isAndroid && isSupportVoiceCall)'),
      reason: 'The voice entry must include iOS instead of being Android-only.',
    );
    expect(rail, contains('showActions(widget.id)'));
  });
}
