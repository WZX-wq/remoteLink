import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/models/input_model.dart';

void main() {
  test('Android effective wheel direction flips both axes exactly once', () {
    expect(applyReverseMouseWheelDelta(3, -7, false), const Point(3, -7));
    expect(applyReverseMouseWheelDelta(3, -7, true), const Point(-3, 7));
  });

  test('Android virtual mouse arrows send explicit opposite wheel steps', () {
    final floatingMouse =
        File('lib/mobile/widgets/floating_mouse.dart').readAsStringSync();

    expect(floatingMouse, contains('onScrollUp: isAndroid'));
    expect(floatingMouse, contains('onScrollDown: isAndroid'));
    expect(floatingMouse, contains('_inputModel.scroll(1)'));
    expect(floatingMouse, contains('_inputModel.scroll(-1)'));
    expect(floatingMouse, contains('onScrollStep.call()'));
    expect(floatingMouse, contains('if (isAndroid) {'));
    expect(
      floatingMouse,
      contains(
          'Starting circular\n      // scrolling here would emit a second'),
    );
  });

  test('Android video recovery is armed only by real remote input', () {
    final ioLoop = File('../src/client/io_loop.rs').readAsStringSync();

    expect(ioLoop, contains('enum AndroidVideoRecoveryDecision'));
    expect(ioLoop, contains('fn decide_android_video_recovery('));
    expect(ioLoop, contains('fn arm_android_video_recovery('));
    expect(ioLoop, contains('fn check_android_video_recovery('));
    expect(ioLoop, contains('fn restart_android_video_thread('));
    expect(ioLoop, contains('self.video_threads.remove(&display)'));
    expect(ioLoop, contains('self.new_video_thread(display)'));
    expect(ioLoop, contains('active.store(false, Ordering::SeqCst)'));
    expect(ioLoop, contains('#[cfg(target_os = "android")]'));
    expect(ioLoop, contains('Android video recovery requested a fresh stream'));
    expect(ioLoop, isNot(contains('self.handler.reconnect(false)')));
  });

  test('Android remote video refresh preserves the active decoder', () {
    final ioLoop = File('../src/client/io_loop.rs').readAsStringSync();

    expect(ioLoop, contains('fn should_reset_decoder_before_video_refresh('));
    expect(
      ioLoop,
      contains(
          'should_reset_decoder_before_video_refresh(cfg!(target_os = "android"))'),
    );
  });

  test('desktop reverse mouse wheel still applies at the Rust event boundary',
      () {
    final sessionInterface =
        File('../src/ui_session_interface.rs').readAsStringSync();

    expect(sessionInterface, contains('fn reverse_scroll_delta('));
    expect(sessionInterface, contains('fn scroll_delta_for_option('));
    expect(sessionInterface,
        contains('scroll_delta_for_option(xy, &reverse_mouse_wheel)'));
    expect(sessionInterface,
        contains('MOUSE_TYPE_WHEEL || event_type == MOUSE_TYPE_TRACKPAD'));
    expect(sessionInterface,
        contains('scroll_delta_for_option((4, -9), "Y"), (-4, 9)'));
  });

  test('Android applies reverse wheel from the live effective Flutter option',
      () {
    final inputModel = File('lib/models/input_model.dart').readAsStringSync();
    final sessionInterface =
        File('../src/ui_session_interface.rs').readAsStringSync();

    expect(
      inputModel,
      contains('bind.sessionGetReverseMouseWheelSync(sessionId: sessionId)'),
    );
    expect(
      inputModel,
      contains('bind.mainGetUserDefaultOption(key: kKeyReverseMouseWheel)'),
    );
    expect(inputModel, contains('applyReverseMouseWheelDelta('));
    expect(
      sessionInterface,
      contains(
          '#[cfg(any(target_os = "android", target_os = "ios"))]\n    fn get_scroll_xy'),
      reason: 'Android reverses once in Flutter; iOS remains unchanged.',
    );
  });

  test('Android wheel events do not use a second Flutter direction cache', () {
    final inputModel = File('lib/models/input_model.dart').readAsStringSync();
    final toolbar = File('lib/common/widgets/toolbar.dart').readAsStringSync();

    expect(inputModel, contains('_sendScrollMouseEvent('));
    expect(inputModel, isNot(contains('_kqAndroidReverseMouseWheel')));
    expect(inputModel, isNot(contains('kqApplyAndroidReverseMouseWheel')));
    expect(
        toolbar, isNot(contains('ffi.inputModel.setReverseMouseWheel(value)')));
  });

  test('Android touch pan stays independent from mouse wheel direction', () {
    final sessionInterface =
        File('../src/ui_session_interface.rs').readAsStringSync();

    expect(
      sessionInterface,
      contains('MOUSE_TYPE_WHEEL || event_type == MOUSE_TYPE_TRACKPAD'),
    );
    expect(
      sessionInterface,
      contains('#[cfg(not(any(target_os = "android", target_os = "ios")))]'),
    );
  });
}
