# Standard Quality Blur Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a clearly visible Gaussian blur to 720p standard video on Windows and Android without restoring overlay-based gray-screen risks.

**Architecture:** A shared single-child presentation widget owns the blur decision and effect. Desktop and mobile video renderers pass their video subtree and current custom stream quality into it; input and control widgets remain outside.

**Tech Stack:** Flutter/Dart, Rust, Flutter widget tests, Flutter 3.24.5, Inno Setup, Android NDK/Gradle

---

### Task 1: Add failing presentation tests

**Files:**
- Modify: `flutter/test/kq_remote_video_render_test.dart`

- [ ] **Step 1: Add tests for the desired widget API and integrations**

```dart
testWidgets('standard quality applies one video-only Gaussian blur',
    (tester) async {
  await tester.pumpWidget(const Directionality(
    textDirection: TextDirection.ltr,
    child: KqRemoteQualityPresentation(
      streamQuality: kqStandardRemoteStreamQuality,
      child: SizedBox(width: 40, height: 20),
    ),
  ));
  expect(kqStandardRemoteBlurSigma, 0.6);
  expect(find.byType(ImageFiltered), findsOneWidget);
  expect(find.byType(ClipRect), findsOneWidget);
  expect(find.byType(Stack), findsNothing);
  expect(find.byType(BackdropFilter), findsNothing);
});

testWidgets('HD quality keeps the video child unfiltered', (tester) async {
  await tester.pumpWidget(const Directionality(
    textDirection: TextDirection.ltr,
    child: KqRemoteQualityPresentation(
      streamQuality: kqHighDefinitionRemoteStreamQuality,
      child: SizedBox(width: 40, height: 20),
    ),
  ));
  expect(find.byType(ImageFiltered), findsNothing);
});
```

- [ ] **Step 2: Run the focused test and verify RED**

```powershell
D:\tools\flutter-3.24.5\bin\flutter.bat test test\kq_remote_video_render_test.dart --plain-name "standard quality applies one video-only Gaussian blur"
```

Expected: compilation fails because `KqRemoteQualityPresentation` and `kqStandardRemoteBlurSigma` do not exist.

### Task 2: Implement the shared presentation widget

**Files:**
- Modify: `flutter/lib/models/remote_video_quality_policy.dart`
- Create: `flutter/lib/common/widgets/kq_remote_quality_presentation.dart`

- [ ] **Step 1: Add the blur constant**

```dart
const double kqStandardRemoteBlurSigma = 0.6;
```

- [ ] **Step 2: Add the single-child presentation component**

```dart
class KqRemoteQualityPresentation extends StatelessWidget {
  const KqRemoteQualityPresentation({
    super.key,
    required this.streamQuality,
    required this.child,
  });

  final int streamQuality;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (streamQuality != kqStandardRemoteStreamQuality) return child;
    return ClipRect(
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: kqStandardRemoteBlurSigma,
          sigmaY: kqStandardRemoteBlurSigma,
          tileMode: TileMode.clamp,
        ),
        child: child,
      ),
    );
  }
}
```

- [ ] **Step 3: Run both widget tests and verify GREEN**

Expected: standard test finds one filter and HD test finds none.

### Task 3: Blur desktop video and bypass Android filtering

**Files:**
- Modify: `flutter/lib/desktop/pages/remote_page.dart`
- Modify: `flutter/lib/mobile/pages/remote_page.dart`
- Modify: `flutter/test/kq_remote_video_render_test.dart`

- [ ] **Step 1: Wrap the existing desktop presentation hook**

```dart
Widget _applyKqRemoteQualityPresentation(Widget child) {
  return KqRemoteQualityPresentation(
    streamQuality: gFFI.userModel.remoteCustomQualitySelection,
    child: child,
  );
}
```

- [ ] **Step 2: Keep mobile `ImagePaint` unfiltered**

```dart
return CustomPaint(
  painter: ImagePainter(...),
);
```

- [ ] **Step 3: Add source tests for both integrations**

Assert desktop contains `KqRemoteQualityPresentation(`, mobile `ImagePaint` contains neither `KqRemoteQualityPresentation(` nor `ImageFiltered(`, and the presentation component source contains no `Stack(`, `ColoredBox(`, or `BackdropFilter(`.

### Task 4: Verify regressions

**Files:**
- Test: `flutter/test/kq_remote_video_render_test.dart`

- [ ] **Step 1: Format the changed Dart files**

```powershell
D:\tools\flutter-3.24.5\bin\dart.bat format lib\models\remote_video_quality_policy.dart lib\common\widgets\kq_remote_quality_presentation.dart lib\desktop\pages\remote_page.dart lib\mobile\pages\remote_page.dart test\kq_remote_video_render_test.dart
```

- [ ] **Step 2: Run the full regression file**

```powershell
D:\tools\flutter-3.24.5\bin\flutter.bat test test\kq_remote_video_render_test.dart
```

Expected: all existing tests plus new blur tests pass.

### Task 5: Overwrite the stable Android package

**Files:**
- Output: `dist/Kunqiong-Remote-Desktop.apk`

- [ ] **Step 1: Build Android ARM64 into the stable name**

```powershell
.\scripts\build-kq-apps.ps1 -Target Android -FlutterSdk D:\tools\flutter-3.24.5 -SkipAndroidNative -SkipFlutterPubGet -UpdateStableNames
```

- [ ] **Step 2: Remove timestamped duplicate APKs**

```powershell
Get-ChildItem .\dist -File -Filter 'Kunqiong-Remote-Desktop-Android-*.apk*' | Remove-Item -Force
```

- [ ] **Step 3: Verify the stable package hash and embedded native library**

Confirm only `Kunqiong-Remote-Desktop.apk` remains for Android delivery and its embedded ARM64 library matches the verified JNI library.
