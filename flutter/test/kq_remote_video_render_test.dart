import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/utils/image.dart';
import 'package:flutter_hbb/common/widgets/kq_remote_quality_presentation.dart';
import 'package:flutter_hbb/models/mobile_remote_layout_policy.dart';
import 'package:flutter_hbb/models/remote_toolbar_visibility_policy.dart';
import 'package:flutter_hbb/models/remote_video_quality_policy.dart';
import 'package:flutter_hbb/models/user_model.dart';
import 'package:flutter_hbb/models/video_render_policy.dart';

void main() {
  test('Windows expanded toolbar excludes the performance MenuBar overlay', () {
    expect(
      shouldBuildRemoteToolbarPerformanceMenu(isWindowsPlatform: true),
      isFalse,
    );
    expect(
      shouldBuildRemoteToolbarPerformanceMenu(isWindowsPlatform: false),
      isTrue,
    );

    final source =
        File('lib/desktop/widgets/remote_toolbar.dart').readAsStringSync();
    expect(
      source,
      contains('shouldBuildRemoteToolbarPerformanceMenu('),
    );
  });

  test('desktop video renderer follows native texture availability', () {
    expect(
      shouldUseNativeVideoTexture(
        isDesktopPlatform: true,
        nativeTextureAvailable: true,
      ),
      isTrue,
    );
    expect(
      shouldUseNativeVideoTexture(
        isDesktopPlatform: true,
        nativeTextureAvailable: false,
      ),
      isFalse,
    );
    expect(
      shouldUseNativeVideoTexture(
        isDesktopPlatform: false,
        nativeTextureAvailable: true,
      ),
      isFalse,
    );
  });

  test('first native texture frame is replayed after Flutter presents it', () {
    final model = File('lib/models/model.dart').readAsStringSync();
    final textureModel =
        File('lib/models/desktop_render_texture.dart').readAsStringSync();
    final renderer =
        File('plugins/texture_rgba_renderer/lib/texture_rgba_renderer.dart')
            .readAsStringSync();
    final windowsPlugin = File(
            'plugins/texture_rgba_renderer/windows/texture_rgba_renderer_plugin.cpp')
        .readAsStringSync();

    final textureBranch = model.indexOf(
      '} else if (message is EventToUI_Texture) {',
    );
    final branchEnd = model.indexOf('      }();', textureBranch);
    expect(textureBranch, greaterThanOrEqualTo(0));
    expect(branchEnd, greaterThan(textureBranch));
    final branch = model.substring(textureBranch, branchEnd);

    final finalize = branch.indexOf('await onEvent2UIRgba();');
    final mountedFrame =
        branch.indexOf('await WidgetsBinding.instance.endOfFrame;');
    final replay = branch.indexOf(
      'await textureModel.replayPixelbufferFrame(display);',
    );
    expect(finalize, greaterThanOrEqualTo(0));
    expect(mountedFrame, greaterThan(finalize));
    expect(replay, greaterThan(mountedFrame));
    expect(textureModel, contains('replayPixelbufferFrame(int display)'));
    expect(renderer, contains('Future<bool> markFrameAvailable(int key)'));
    expect(windowsPlugin, contains('"markFrameAvailable"'));
    expect(windowsPlugin, contains('MarkFrameAvailable()'));
  });

  test('basic and member profiles use distinct receiver stream parameters', () {
    expect(
      kqRemoteStreamQuality(highDefinition: false),
      kqStandardRemoteStreamQuality,
    );
    expect(
      kqRemoteStreamQuality(highDefinition: true),
      kqHighDefinitionRemoteStreamQuality,
    );
    expect(kqStandardRemoteStreamQuality, 100);
    expect(kqHighDefinitionRemoteStreamQuality, 150);
    expect(kqStandardRemoteStreamQuality,
        lessThan(kqHighDefinitionRemoteStreamQuality));
    expect(UserModel.freeMaxFps, 30);
    expect(UserModel.memberDefaultFps, 60);
    expect(
      kqRemoteProfileRequiresMembership(highDefinition: false),
      isFalse,
    );
    expect(
      kqRemoteProfileRequiresMembership(highDefinition: true),
      isTrue,
    );
  });

  testWidgets('standard quality is not artificially blurred',
      (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: KqRemoteQualityPresentation(
        streamQuality: kqStandardRemoteStreamQuality,
        isStandardTier: true,
        child: SizedBox(key: Key('standard-video'), width: 40, height: 20),
      ),
    ));

    expect(kqStandardRemoteBlurSigma, 0);
    expect(find.byType(ImageFiltered), findsNothing);
    expect(find.byType(ClipRect), findsNothing);
    expect(find.byType(Stack), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byKey(const Key('standard-video')), findsOneWidget);
  });

  testWidgets('Windows HD quality keeps the video unfiltered', (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: KqRemoteQualityPresentation(
        streamQuality: kqHighDefinitionRemoteStreamQuality,
        isStandardTier: false,
        child: SizedBox(key: Key('hd-video'), width: 40, height: 20),
      ),
    ));

    expect(find.byType(ImageFiltered), findsNothing);
    expect(find.byType(ClipRect), findsNothing);
    expect(find.byKey(const Key('hd-video')), findsOneWidget);
  });

  test('KQ quality tiers never resize frames inside the encoder pipeline', () {
    final videoQos = File('../src/server/video_qos.rs').readAsStringSync();
    final videoService =
        File('../src/server/video_service.rs').readAsStringSync();
    final conversion =
        File('../libs/scrap/src/common/convert.rs').readAsStringSync();
    final frameApi = File('../libs/scrap/src/common/mod.rs').readAsStringSync();
    final yuvHeader =
        File('../libs/scrap/src/bindings/yuv_ffi.h').readAsStringSync();

    expect(videoQos, isNot(contains('KqVideoTier')));
    expect(videoService, isNot(contains('kq_encoded_dimensions')));
    expect(videoService, isNot(contains('KQ video encoder switch')));
    expect(conversion, isNot(contains('convert_to_yuv_with_scale')));
    expect(conversion, isNot(contains('ARGBScale(')));
    expect(frameApi, isNot(contains('scale_data: &mut Vec<u8>')));
    expect(yuvHeader, isNot(contains('scale_argb.h')));
  });

  test('Windows blur stays outside the Android video widget', () {
    final desktop =
        File('lib/desktop/pages/remote_page.dart').readAsStringSync();
    final desktopStart =
        desktop.indexOf('  Widget _applyKqRemoteQualityPresentation(');
    final desktopEnd = desktop.indexOf(
      '  Widget _BuildPaintTextureRender(',
      desktopStart,
    );
    expect(desktopStart, greaterThanOrEqualTo(0));
    expect(desktopEnd, greaterThan(desktopStart));
    final desktopPresentation = desktop.substring(desktopStart, desktopEnd);
    expect(
      desktopPresentation,
      contains('return KqRemoteQualityPresentation('),
    );
    expect(desktopPresentation, contains('remoteCustomQualitySelection'));

    final mobile = File('lib/mobile/pages/remote_page.dart').readAsStringSync();
    final mobileStart =
        mobile.indexOf('class ImagePaint extends StatelessWidget');
    final mobileEnd = mobile.indexOf('class CursorPaint', mobileStart);
    expect(mobileStart, greaterThanOrEqualTo(0));
    expect(mobileEnd, greaterThan(mobileStart));
    final mobileImagePaint = mobile.substring(mobileStart, mobileEnd);
    expect(mobileImagePaint, isNot(contains('KqRemoteQualityPresentation(')));
    expect(mobileImagePaint, isNot(contains('ImageFiltered(')));
    expect(mobileImagePaint, isNot(contains('BackdropFilter(')));
    expect(mobileImagePaint, contains('blurSigma:'));
    expect(mobileImagePaint, contains('remoteResolutionSelection'));
    expect(mobileImagePaint, contains('kqStandardRemoteBlurSigma'));

    expect(
      File('lib/common/widgets/kq_remote_quality_presentation.dart')
          .existsSync(),
      isTrue,
    );
  });

  test('KQ never maps a quality profile to remote display resolution', () {
    final uiSessionInterface =
        File('../src/ui_session_interface.rs').readAsStringSync();

    expect(
      uiSessionInterface,
      isNot(contains('KQ_REMOTE_RESOLUTION_TIER_KEY')),
      reason: '720p and 1080p are compression-quality labels. They must not '
          'select or clamp the controlled computer display resolution.',
    );
    expect(
      uiSessionInterface,
      contains('KQ skips remote display resolution change request'),
    );
  });

  test('KQ Windows remote startup never covers the video scene', () {
    expect(
      shouldShowRemoteConnectionOverlay(
        isWindowsPlatform: true,
        isDesktopPlatform: true,
        isWebPlatform: false,
      ),
      isFalse,
    );
    expect(
      shouldShowRemoteConnectionOverlay(
        isWindowsPlatform: true,
        isDesktopPlatform: false,
        isWebPlatform: false,
      ),
      isTrue,
    );
    expect(
      shouldShowRemoteConnectionOverlay(
        isWindowsPlatform: false,
        isDesktopPlatform: true,
        isWebPlatform: false,
      ),
      isTrue,
    );
  });

  test('KQ Windows keeps the default Flutter renderer', () {
    final runner = File('windows/runner/main.cpp').readAsStringSync();

    expect(runner, isNot(contains('EnableKqSoftwareRendering')));
    expect(runner, isNot(contains('enable-software-rendering=true')));
    expect(runner, isNot(contains('FLUTTER_ENGINE_SWITCHES')));
  });

  test('toolbar visibility changes do not reset the video renderer', () async {
    var toggleCount = 0;
    await toggleRemoteToolbarVisibility(() async {
      toggleCount += 1;
    });
    expect(toggleCount, 1);
  });

  test('remote toolbar auto-collapse depends only on active UI state', () {
    expect(
      shouldAutoCollapseRemoteToolbar(
        isExpanded: true,
        isCursorOverImage: true,
        isDragging: false,
      ),
      isTrue,
    );
    expect(
      shouldAutoCollapseRemoteToolbar(
        isExpanded: false,
        isCursorOverImage: true,
        isDragging: false,
      ),
      isFalse,
    );
    expect(
      shouldAutoCollapseRemoteToolbar(
        isExpanded: true,
        isCursorOverImage: false,
        isDragging: false,
      ),
      isFalse,
    );
    expect(
      shouldAutoCollapseRemoteToolbar(
        isExpanded: true,
        isCursorOverImage: true,
        isDragging: true,
      ),
      isFalse,
    );
  });

  test('remote toolbar has no pin control or persisted pin state', () {
    final source =
        File('lib/desktop/widgets/remote_toolbar.dart').readAsStringSync();
    expect(source, isNot(contains('class _PinMenu')));
    expect(source, isNot(contains('toolbarItems.add(_PinMenu')));
    expect(source, isNot(contains('kOptionRemoteMenubarState')));
    expect(source, isNot(contains('switchPin')));
  });

  test('seven mobile side rail actions fit a compact landscape height', () {
    expect(
      mobileRemoteSideRailContentHeight(itemCount: 7),
      lessThanOrEqualTo(320),
    );
  });

  test('mobile keyboard does not resize or hide the side action rail', () {
    final source = File('lib/mobile/pages/remote_page.dart').readAsStringSync();
    expect(source, contains('resizeToAvoidBottomInset: false'));

    final railStart = source.indexOf('  Widget _remoteSideActionRail()');
    final railEnd = source.indexOf(
      '  Widget _remoteSideActionButton(',
      railStart,
    );
    expect(railStart, greaterThanOrEqualTo(0));
    expect(railEnd, greaterThan(railStart));

    final railSource = source.substring(railStart, railEnd);
    expect(railSource, isNot(contains('keyboardIsVisible ||')));
    expect(railSource, isNot(contains('MediaQuery.of(context)')));
    expect(railSource, contains('top: kMobileRemoteSideRailInset'));
    expect(railSource, contains('bottom: kMobileRemoteSideRailInset'));
    expect(railSource, contains('Align('));
    expect(railSource, contains('SingleChildScrollView('));
  });

  test('mobile rail collapse and expand controls stay above the lower edge',
      () {
    expect(kMobileRemoteToggleButtonYOffset, -72);

    final source = File('lib/mobile/pages/remote_page.dart').readAsStringSync();
    expect(source, contains('kMobileRemoteToggleButtonYOffset'));

    final railStart = source.indexOf('  Widget _remoteSideActionRail()');
    final railEnd = source.indexOf(
      '  Widget _remoteSideActionButton(',
      railStart,
    );
    expect(railStart, greaterThanOrEqualTo(0));
    expect(railEnd, greaterThan(railStart));

    final railSource = source.substring(railStart, railEnd);
    final collapseIndex = railSource.indexOf("zhCn: '收起'");
    final disconnectIndex = railSource.indexOf("zhCn: '断开'");
    expect(collapseIndex, greaterThanOrEqualTo(0));
    expect(disconnectIndex, greaterThan(collapseIndex));
  });

  test('expanded toolbar avoids a physical Material surface', () {
    final source =
        File('lib/desktop/widgets/remote_toolbar.dart').readAsStringSync();
    final methodStart =
        source.indexOf('  Widget _buildToolbar(BuildContext context)');
    final methodEnd = source.indexOf('  ThemeData themeData()', methodStart);

    expect(methodStart, greaterThanOrEqualTo(0));
    expect(methodEnd, greaterThan(methodStart));

    final methodSource = source.substring(methodStart, methodEnd);
    expect(
      methodSource,
      isNot(contains('Material(')),
      reason: 'The expanded Windows toolbar must not add a physical layer over '
          'the continuously painted remote-video surface.',
    );
    expect(methodSource, contains('DecoratedBox('));
  });

  test('Windows remote UI waits for the first canvas paint', () {
    final source = File('lib/models/model.dart').readAsStringSync();
    final branchStart =
        source.indexOf('} else if (message is EventToUI_Rgba) {');
    final branchEnd = source.indexOf(
      '} else if (message is EventToUI_Texture) {',
      branchStart,
    );

    expect(branchStart, greaterThanOrEqualTo(0));
    expect(branchEnd, greaterThan(branchStart));

    final rgbaBranch = source.substring(branchStart, branchEnd);
    expect(
      rgbaBranch,
      contains('imageModel.hasPaintedFrame'),
      reason: 'On Windows remote-desktop sessions, decoded RGBA must not '
          'dismiss the first-frame UI before CustomPaint has presented it.',
    );
  });

  test('remote subwindow startup has a single geometry owner', () {
    final managerSource =
        File('lib/utils/multi_window_manager.dart').readAsStringSync();
    final creatorStart =
        managerSource.indexOf('  Future<int> newSessionWindow(');
    final creatorEnd = managerSource.indexOf(
      '  Future<MultiWindowCallResult> _newSession(',
      creatorStart,
    );
    expect(creatorStart, greaterThanOrEqualTo(0));
    expect(creatorEnd, greaterThan(creatorStart));
    final creatorSource = managerSource.substring(creatorStart, creatorEnd);
    expect(creatorSource, contains('if (type == WindowType.RemoteDesktop)'));

    final remoteCreatorStart =
        creatorSource.indexOf('if (type == WindowType.RemoteDesktop)');
    final remoteCreatorEnd =
        creatorSource.indexOf('} else {', remoteCreatorStart);
    expect(remoteCreatorEnd, greaterThan(remoteCreatorStart));
    final remoteCreator =
        creatorSource.substring(remoteCreatorStart, remoteCreatorEnd);
    expect(remoteCreator, isNot(contains('setFrame(')));
    expect(remoteCreator, isNot(contains('center()')));
    expect(remoteCreator, isNot(contains('show()')));
    expect(remoteCreator, isNot(contains('focus()')));

    final tabSource =
        File('lib/desktop/pages/remote_tab_page.dart').readAsStringSync();
    final constructorStart = tabSource.indexOf(
      '  _ConnectionTabPageState(Map<String, dynamic> params) {',
    );
    final constructorEnd = tabSource.indexOf(
      '    tabController.onRemoved',
      constructorStart,
    );
    expect(constructorStart, greaterThanOrEqualTo(0));
    expect(constructorEnd, greaterThan(constructorStart));
    final constructorSource =
        tabSource.substring(constructorStart, constructorEnd);
    expect(
      constructorSource,
      isNot(contains('tryMoveToScreenAndSetFullscreen(screenRect)')),
    );

    final buildStart = tabSource.indexOf(
      '  Widget build(BuildContext context)',
      constructorStart,
    );
    expect(buildStart, greaterThan(constructorStart));
    final startupSource = tabSource.substring(constructorStart, buildStart);
    expect(
      startupSource,
      isNot(contains('tryMoveToScreenAndSetFullscreen(screenRect)')),
    );
    expect(startupSource, isNot(contains('restoreWindowPosition(')));

    final mainSource = File('lib/main.dart').readAsStringSync();
    final runMultiWindowStart =
        mainSource.indexOf('Future<void> runMultiWindow(');
    expect(
      mainSource,
      matches(
        RegExp(
          r'await runMultiWindow\(\s*argument,\s*kAppTypeDesktopRemote,',
        ),
      ),
    );
    final runAppIndex = mainSource.indexOf('  _runApp(', runMultiWindowStart);
    final restoreIndex = mainSource.indexOf(
      'final useDefaultFrame = await restoreWindowPosition(',
      runMultiWindowStart,
    );
    final setFrameIndex = mainSource.indexOf(
      'await controller.setFrame(',
      runMultiWindowStart,
    );
    final moveIndex = mainSource.indexOf(
      'await tryMoveToScreenAndSetFullscreen(',
      runMultiWindowStart,
    );
    expect(runMultiWindowStart, greaterThanOrEqualTo(0));
    expect(restoreIndex, greaterThan(runMultiWindowStart));
    expect(setFrameIndex, greaterThan(restoreIndex));
    expect(moveIndex, greaterThan(setFrameIndex));
    expect(runAppIndex, greaterThan(moveIndex));

    final firstRemoteCase =
        mainSource.indexOf('    case kAppTypeDesktopRemote:');
    final remoteCaseStart = mainSource.indexOf(
      '    case kAppTypeDesktopRemote:',
      firstRemoteCase + 1,
    );
    final remoteCaseEnd = mainSource.indexOf(
      '    case kAppTypeDesktopFileTransfer:',
      remoteCaseStart,
    );
    final remoteCase = mainSource.substring(remoteCaseStart, remoteCaseEnd);
    expect(
      remoteCase,
      isNot(contains('await WidgetsBinding.instance.endOfFrame;')),
      reason: 'The native remote window must already be visible when Flutter '
          'paints its first software-video scene.',
    );
    expect(remoteCase, contains('await controller.show()'));
    expect(remoteCase, contains('await controller.focus()'));

    final showIndex = remoteCase.indexOf('await controller.show()');
    final focusIndex = remoteCase.indexOf('await controller.focus()');
    expect(remoteCase, isNot(contains('restoreWindowPosition(')));
    expect(remoteCase, isNot(contains('controller.setFrame(')));
    expect(
      remoteCase,
      isNot(contains('tryMoveToScreenAndSetFullscreen(')),
    );
    expect(showIndex, greaterThanOrEqualTo(0));
    expect(focusIndex, greaterThan(showIndex));
    expect(
      RegExp(r'await controller\.show\(\)').allMatches(remoteCase).length,
      1,
    );
    expect(
      RegExp(r'await controller\.focus\(\)').allMatches(remoteCase).length,
      1,
    );
  });

  testWidgets('software frame is painted with visible pixels', (tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    const width = 8;
    const height = 4;
    final recorder = ui.PictureRecorder();
    Canvas(recorder)
      ..drawRect(Rect.fromLTWH(0, 0, width / 2, height.toDouble()),
          Paint()..color = const Color(0xFFFF0000))
      ..drawRect(Rect.fromLTWH(width / 2, 0, width / 2, height.toDouble()),
          Paint()..color = const Color(0xFF00FF00));
    final image = await tester
        .runAsync(() => recorder.endRecording().toImage(width, height));
    expect(image, isNotNull);
    final sourceImage = image!;

    final boundaryKey = GlobalKey();
    var paintCalled = false;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: width.toDouble(),
            height: height.toDouble(),
            child: RepaintBoundary(
              key: boundaryKey,
              child: CustomPaint(
                painter: ImagePainter(
                  image: sourceImage,
                  x: 0,
                  y: 0,
                  scale: 1,
                  onPaint: () => paintCalled = true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(paintCalled, isTrue);

    final boundary = boundaryKey.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    final paintedImage =
        await tester.runAsync(() => boundary.toImage(pixelRatio: 1));
    expect(paintedImage, isNotNull);
    final outputImage = paintedImage!;
    final bytes = await tester.runAsync(
        () => outputImage.toByteData(format: ui.ImageByteFormat.rawRgba));
    expect(bytes, isNotNull);
    final painted = bytes!.buffer.asUint8List();
    expect(painted.sublist(0, 4), equals(<int>[255, 0, 0, 255]));
    final rightPixel = (width - 1) * 4;
    expect(painted.sublist(rightPixel, rightPixel + 4),
        equals(<int>[0, 255, 0, 255]));

    outputImage.dispose();
    sourceImage.dispose();
  });

  testWidgets('Android painter blur keeps video pixels visible',
      (tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    const width = 12;
    const height = 8;
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = const Color(0xFF32B8A6),
    );
    final sourceImage = (await tester
        .runAsync(() => recorder.endRecording().toImage(width, height)))!;
    final boundaryKey = GlobalKey();

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: width.toDouble(),
          height: height.toDouble(),
          child: RepaintBoundary(
            key: boundaryKey,
            child: CustomPaint(
              painter: ImagePainter(
                image: sourceImage,
                x: 0,
                y: 0,
                scale: 1,
                blurSigma: 0.6,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();

    final boundary = boundaryKey.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    final outputImage =
        (await tester.runAsync(() => boundary.toImage(pixelRatio: 1)))!;
    final bytes = (await tester.runAsync(
        () => outputImage.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
    final pixels = bytes.buffer.asUint8List();
    expect(pixels.any((value) => value != 0), isTrue);
    expect(
      List<int>.generate(pixels.length ~/ 4, (index) => pixels[index * 4 + 3])
          .any((alpha) => alpha > 0),
      isTrue,
    );

    outputImage.dispose();
    sourceImage.dispose();
  });

  test('KQ Windows software video uses RawImage instead of CustomPainter', () {
    final source =
        File('lib/desktop/pages/remote_page.dart').readAsStringSync();
    final start = source.indexOf('  Widget _buildScrollbarNonTextureRender(');
    final end = source.indexOf('  void _handleSoftwarePaint(', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final softwareRenderers = source.substring(start, end);
    expect(softwareRenderers, contains('RawImage('));
    expect(softwareRenderers, isNot(contains('CustomPaint(')));
  });

  test('KQ Windows startup overlays are excluded from the remote scene', () {
    final remotePage =
        File('lib/desktop/pages/remote_page.dart').readAsStringSync();
    final model = File('lib/models/model.dart').readAsStringSync();

    expect(remotePage, contains('bool get _shouldShowConnectionOverlay'));
    final overlayPolicyStart =
        remotePage.indexOf('bool get _shouldShowConnectionOverlay');
    final overlayPolicyEnd = remotePage.indexOf(';', overlayPolicyStart);
    final overlayPolicySource =
        remotePage.substring(overlayPolicyStart, overlayPolicyEnd + 1);
    expect(
      overlayPolicySource,
      isNot(contains('appName')),
      reason: 'Branding is initialized asynchronously in the remote window. '
          'The Windows startup overlay decision must use stable platform facts.',
    );
    final connectingGuard =
        remotePage.indexOf('if (_shouldShowConnectionOverlay) {');
    final connectingDialog = remotePage.indexOf(
      ".showLoading(translate('Connecting...')",
      connectingGuard,
    );
    expect(connectingGuard, greaterThanOrEqualTo(0));
    expect(connectingDialog, greaterThan(connectingGuard));

    final firstImageStart = remotePage.indexOf(
      '_ffi.imageModel.addCallbackOnFirstImage',
    );
    final firstImageEnd = remotePage.indexOf(
      '_ffi.canvasModel.initializeEdgeScrollFallback',
      firstImageStart,
    );
    expect(firstImageStart, greaterThanOrEqualTo(0));
    expect(firstImageEnd, greaterThan(firstImageStart));
    final firstImageSource =
        remotePage.substring(firstImageStart, firstImageEnd);
    expect(
      firstImageSource,
      matches(RegExp(
        r'if \(_shouldShowConnectionOverlay\) \{\s+'
        r'showKBLayoutTypeChooserIfNeeded',
      )),
      reason: 'The automatic keyboard chooser uses a window-level Overlay. '
          'On KQ Windows it can leave only its full-screen modal barrier visible.',
    );

    final waitingStart = model.indexOf(
      '  void showConnectedWaitingForImage(',
    );
    final waitingEnd = model.indexOf(
      '  void _showWaitingForImageTimeout(',
      waitingStart,
    );
    expect(waitingStart, greaterThanOrEqualTo(0));
    expect(waitingEnd, greaterThan(waitingStart));
    final waitingSource = model.substring(waitingStart, waitingEnd);
    expect(
      waitingSource,
      contains(
          'final showConnectionOverlay = shouldShowRemoteConnectionOverlay('),
    );
    final waitingGuard = waitingSource.indexOf('if (showConnectionOverlay) {');
    final waitingDialog =
        waitingSource.indexOf('dialogManager.show(', waitingGuard);
    expect(waitingGuard, greaterThanOrEqualTo(0));
    expect(waitingDialog, greaterThan(waitingGuard));
    expect(
      waitingSource,
      contains('waitForImageTimer = Timer('),
      reason: 'Suppressing the Overlay must retain first-frame retry logic.',
    );
    expect(
      waitingSource,
      contains('if (!isKqDesktop) {'),
      reason: 'A slow KQ software first frame must not inject remote mouse '
          'activation while the video pipeline is still starting.',
    );
    expect(
      waitingSource,
      matches(RegExp(
        r'if \(!isKqDesktop\) \{\s+'
        r'waitForImageTimer = Timer\([\s\S]*?'
        r'sessionInputOsPassword',
      )),
    );
    expect(
      waitingSource,
      contains('waitForImageTimeoutTimer = Timer('),
      reason: 'Suppressing the Overlay must retain timeout reporting.',
    );
  });

  test('first remote frame removes every startup dialog barrier', () {
    final remotePage =
        File('lib/desktop/pages/remote_page.dart').readAsStringSync();
    final model = File('lib/models/model.dart').readAsStringSync();

    final callbackStart = remotePage.indexOf(
      '_ffi.imageModel.addCallbackOnFirstImage',
    );
    final callbackEnd = remotePage.indexOf(
      '_ffi.canvasModel.initializeEdgeScrollFallback',
      callbackStart,
    );
    final callbackSource = remotePage.substring(callbackStart, callbackEnd);
    expect(callbackSource, contains('_ffi.dialogManager.dismissAll();'));
    expect(
      callbackSource,
      isNot(contains('clearWaitingForImage(')),
      reason: 'Anonymous login and connecting dialogs also own full-window '
          'barriers, so clearing only the tagged waiting dialog leaves the '
          'decoded video hidden.',
    );

    final firstFrameStart = model.indexOf(
      'if (ffiModel.waitForFirstImage.value == true) {',
    );
    final firstFrameEnd = model.indexOf(
      'for (final cb in imageModel.callbacksOnFirstImage)',
      firstFrameStart,
    );
    final firstFrameSource = model.substring(firstFrameStart, firstFrameEnd);
    expect(firstFrameSource, contains('dialogManager.dismissAll();'));
    expect(firstFrameSource, isNot(contains('clearWaitingForImage(')));
  });

  test('diagnostic build captures decoded and composited first frames', () {
    final source =
        File('lib/desktop/pages/remote_page.dart').readAsStringSync();

    expect(source, contains('final GlobalKey _remoteSceneDiagnosticKey'));
    expect(source, contains('key: _remoteSceneDiagnosticKey'));
    expect(source, contains('as RenderRepaintBoundary'));
    expect(source, contains('ui.ImageByteFormat.png'));
    expect(source, contains('kq-decoded-frame-'));
    expect(source, contains('kq-composited-scene-'));
    expect(source, contains("'scene-capture-saved'"));
  });

  test('first RGBA frame is saved without a GPU readback', () {
    final model = File('lib/models/model.dart').readAsStringSync();
    final helper = File('lib/utils/remote_frame_diagnostic_io.dart');

    final onRgbaStart = model.indexOf(
      'Future<bool> onRgba(int display, Uint8List rgba) async',
    );
    final decodeStart =
        model.indexOf('Future<bool> decodeAndUpdate(', onRgbaStart);
    final onRgbaSource = model.substring(onRgbaStart, decodeStart);
    expect(onRgbaSource, contains('saveRemoteRgbaDiagnostic('));
    expect(helper.existsSync(), isTrue);
    final helperSource = helper.readAsStringSync();
    expect(helperSource, contains('img.Image.fromBytes('));
    expect(helperSource, contains('img.encodePng('));
    expect(helperSource, isNot(contains('ui.Image')));
  });

  test('first software paint finalizes state without rebuilding the scene', () {
    final source =
        File('lib/desktop/pages/remote_page.dart').readAsStringSync();

    expect(source, isNot(contains('FirstFramePresentationBoundary')));
    expect(source, isNot(contains('onFirstSoftwareFramePainted')));
    expect(source, isNot(contains('_presentFirstSoftwareFrame')));

    final handlerStart = source.indexOf('  void _handleSoftwarePaint(');
    final handlerEnd = source.indexOf(
      '  FilterQuality _remoteImageFilterQuality(',
      handlerStart,
    );
    expect(handlerStart, greaterThanOrEqualTo(0));
    expect(handlerEnd, greaterThan(handlerStart));
    final handlerSource = source.substring(handlerStart, handlerEnd);
    expect(
      handlerSource,
      contains('await widget.ffi.onEvent2UIRgba(updateCanvasLayout: false);'),
      reason: 'ImageModel already initializes the software canvas before the '
          'first image is painted. Repeating the layout update after that '
          'paint can replace the valid first scene on Windows.',
    );
    expect(handlerSource, isNot(contains('setState(')));
    expect(handlerSource, isNot(contains('requestRepaint(')));
  });

  test('first frame cancels retry and timeout work on the no-overlay path', () {
    final source = File('lib/models/model.dart').readAsStringSync();
    final handlerStart = source.indexOf(
      '  Future<void> onEvent2UIRgba({bool updateCanvasLayout = true}) async {',
    );
    final handlerEnd = source.indexOf(
      '  /// Login with [password]',
      handlerStart,
    );
    expect(handlerStart, greaterThanOrEqualTo(0));
    expect(handlerEnd, greaterThan(handlerStart));
    final handlerSource = source.substring(handlerStart, handlerEnd);
    final firstFrameBranch =
        handlerSource.indexOf('if (ffiModel.waitForFirstImage.value == true)');
    expect(firstFrameBranch, greaterThanOrEqualTo(0));
    expect(
      handlerSource.indexOf(
        'ffiModel.waitForImageTimer?.cancel();',
        firstFrameBranch,
      ),
      greaterThan(firstFrameBranch),
    );
    expect(
      handlerSource.indexOf(
        'ffiModel.waitForImageTimeoutTimer?.cancel();',
        firstFrameBranch,
      ),
      greaterThan(firstFrameBranch),
    );
  });

  test('software first-frame finalization can skip duplicate canvas layout',
      () {
    final source = File('lib/models/model.dart').readAsStringSync();
    final handlerStart = source.indexOf(
      '  Future<void> onEvent2UIRgba({bool updateCanvasLayout = true}) async {',
    );
    final handlerEnd = source.indexOf(
      '  /// Login with [password]',
      handlerStart,
    );
    expect(handlerStart, greaterThanOrEqualTo(0));
    expect(handlerEnd, greaterThan(handlerStart));
    final handlerSource = source.substring(handlerStart, handlerEnd);
    expect(
      handlerSource,
      matches(RegExp(
        r'if \(updateCanvasLayout\) \{\s+'
        r'await canvasModel\.updateViewStyle\(\);\s+'
        r'await canvasModel\.updateScrollStyle\(\);\s+'
        r'await canvasModel\.initializeEdgeScrollEdgeThickness\(\);',
      )),
    );
  });

  test('first remote session waits for the subwindow first frame', () {
    final managerSource =
        File('lib/utils/multi_window_manager.dart').readAsStringSync();
    final createStart =
        managerSource.indexOf('  Future<int> newSessionWindow(');
    final createEnd = managerSource.indexOf(
      '  Future<MultiWindowCallResult> _newSession(',
      createStart,
    );
    expect(createStart, greaterThanOrEqualTo(0));
    expect(createEnd, greaterThan(createStart));
    final createSource = managerSource.substring(createStart, createEnd);
    expect(
      createSource,
      contains("bootstrapParams['defer_remote_session'] = true"),
    );
    expect(
      createSource,
      matches(RegExp(
        r'DesktopMultiWindow\.createWindow\(bootstrapMessage\)',
      )),
    );
    expect(createSource, isNot(contains('Future.microtask(() async {')));

    final showIndex = createSource.indexOf('await windowController.show()');
    final focusIndex = createSource.indexOf('await windowController.focus()');
    final readyIndex =
        createSource.indexOf('await _waitForRemoteWindowReady(windowId)');
    final sessionIndex = createSource.indexOf('kWindowEventNewRemoteDesktop');
    expect(showIndex, greaterThanOrEqualTo(0));
    expect(focusIndex, greaterThan(showIndex));
    expect(readyIndex, greaterThan(focusIndex));
    expect(sessionIndex, greaterThan(readyIndex));
    expect(createSource, contains('kWindowEventRemoteReady'));

    final tabSource =
        File('lib/desktop/pages/remote_tab_page.dart').readAsStringSync();
    expect(tabSource, contains("params['defer_remote_session'] != true"));
    expect(tabSource, contains('call.method == kWindowEventRemoteReady'));
    expect(
      tabSource,
      contains('await WidgetsBinding.instance.endOfFrame'),
    );

    final mainSource = File('lib/main.dart').readAsStringSync();
    final runStart = mainSource.indexOf('Future<void> runMultiWindow(');
    final runEnd = mainSource.indexOf(
      'void runConnectionManagerScreen()',
      runStart,
    );
    expect(runStart, greaterThanOrEqualTo(0));
    expect(runEnd, greaterThan(runStart));
    final runSource = mainSource.substring(runStart, runEnd);
    expect(
      runSource,
      isNot(contains('await WidgetsBinding.instance.endOfFrame;')),
      reason: 'Showing a remote window must not depend on a frame rendered '
          'while that native window is still hidden.',
    );
  });
}
