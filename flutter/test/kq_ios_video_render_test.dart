import 'dart:io';

import 'package:flutter_hbb/models/video_render_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS software video waits for a real first canvas paint', () {
    bool shouldDefer({
      bool isWindowsPlatform = false,
      bool isIOSPlatform = true,
      bool isRemoteDesktopConnection = true,
      bool waitingForFirstImage = true,
      bool hasPaintedFrame = false,
    }) {
      return shouldDeferSoftwareFirstFrameUntilPaint(
        isWindowsPlatform: isWindowsPlatform,
        isIOSPlatform: isIOSPlatform,
        isRemoteDesktopConnection: isRemoteDesktopConnection,
        waitingForFirstImage: waitingForFirstImage,
        hasPaintedFrame: hasPaintedFrame,
      );
    }

    expect(shouldDefer(), isTrue);
    expect(
      shouldDefer(isWindowsPlatform: true, isIOSPlatform: false),
      isTrue,
    );
    expect(shouldDefer(isIOSPlatform: false), isFalse);
    expect(shouldDefer(waitingForFirstImage: false), isFalse);
    expect(shouldDefer(hasPaintedFrame: true), isFalse);
    expect(shouldDefer(isRemoteDesktopConnection: false), isFalse);
  });

  test('mobile iOS scene fills its viewport and finalizes after paint', () {
    final source = File('lib/mobile/pages/remote_page.dart').readAsStringSync();

    expect(source, contains('void _handleIOSSoftwarePaint(ImageModel model)'));
    expect(source, contains('model.markFramePainted(display)'));
    expect(source, contains('WidgetsBinding.instance.addPostFrameCallback'));
    expect(source,
        contains('await gFFI.onEvent2UIRgba(updateCanvasLayout: false);'));
    expect(source, contains('onPaint: () => onPaint?.call(m)'));
    expect(source, contains('return SizedBox.expand('));
  });

  test('iOS rotation and foreground resume repaint the local canvas only', () {
    final source = File('lib/mobile/pages/remote_page.dart').readAsStringSync();

    expect(source, contains('Timer? _orientationRefreshTimer;'));
    expect(source, contains('bool _wasBackgrounded = false;'));
    final methodStart =
        source.indexOf('void _refreshIOSRemoteVideo(String reason)');
    final methodEnd = source.indexOf('  @override', methodStart);
    expect(methodStart, greaterThanOrEqualTo(0));
    expect(methodEnd, greaterThan(methodStart));
    final method = source.substring(methodStart, methodEnd);
    expect(method, contains('_wasBackgrounded'));
    expect(source, contains('gFFI.imageModel.requestRepaint();'));
    expect(method,
        isNot(contains('sessionRefreshVideo(sessionId, gFFI.ffiModel.pi)')));
    expect(source, contains('_orientationRefreshTimer?.cancel();'));
  });

  test('iOS native RGBA renderer retains the latest frame while Dart decodes',
      () {
    final source = File('../src/flutter.rs').readAsStringSync();

    expect(source, contains('pending_data: Vec<u8>'));
    expect(source, contains('pending_valid: bool'));
    expect(source, contains('fn promote_pending_frame'));
    expect(source,
        contains('KQ software video renderer buffered latest RGBA frame'));
  });
}
