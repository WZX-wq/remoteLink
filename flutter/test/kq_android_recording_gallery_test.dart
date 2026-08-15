import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/models/android_recording_gallery.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('kq-recording-gallery-');
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('discovers only new supported non-empty recording files', () async {
    final oldFile = File('${directory.path}/old.mp4');
    await oldFile.writeAsBytes([1, 2, 3]);
    final session =
        await AndroidRecordingGallerySession.capture(directory.path);

    await File('${directory.path}/new.webm').writeAsBytes([4, 5]);
    await File('${directory.path}/empty.mp4').create();
    await File('${directory.path}/note.txt').writeAsString('ignore');

    final discovery = await session.discover();

    expect(discovery.isSafe, isTrue);
    expect(discovery.files, ['${directory.path}/new.webm']);
  });

  test('includes an existing recording file when its identity changed',
      () async {
    final file = File('${directory.path}/segment.mp4');
    await file.writeAsBytes([1]);
    final session =
        await AndroidRecordingGallerySession.capture(directory.path);

    await Future<void>.delayed(const Duration(milliseconds: 5));
    await file.writeAsBytes([1, 2, 3, 4, 5]);

    final discovery = await session.discover();

    expect(discovery.files, [file.path]);
  });

  test('sorts discovered recording files by filename', () async {
    final session =
        await AndroidRecordingGallerySession.capture(directory.path);
    await File('${directory.path}/z.webm').writeAsBytes([1]);
    await File('${directory.path}/a.mp4').writeAsBytes([1]);

    final discovery = await session.discover();

    expect(discovery.files.map((path) => path.split('/').last),
        ['a.mp4', 'z.webm']);
  });

  test('refuses discovery when the baseline snapshot was unavailable',
      () async {
    final missingParent = Directory('${directory.path}/missing/recordings');
    final session = await AndroidRecordingGallerySession.capture(
      missingParent.path,
      createMissingDirectory: false,
    );
    await missingParent.create(recursive: true);
    await File('${missingParent.path}/new.mp4').writeAsBytes([1]);

    final discovery = await session.discover();

    expect(discovery.isSafe, isFalse);
    expect(discovery.files, isEmpty);
  });

  test('settled discovery waits until a recording file stops changing',
      () async {
    final session =
        await AndroidRecordingGallerySession.capture(directory.path);
    final recording = File('${directory.path}/changing.mp4');
    await recording.writeAsBytes([1]);

    final writer = () async {
      await Future<void>.delayed(const Duration(milliseconds: 15));
      await recording.writeAsBytes([1, 2]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await recording.writeAsBytes([1, 2, 3]);
    }();

    final discovery = await session.discoverSettled(
      pollInterval: const Duration(milliseconds: 10),
      stableChecks: 2,
      maxChecks: 12,
    );
    await writer;

    expect(discovery.identities[recording.path]?.size, 3);
  });

  test('settled discovery waits for a delayed recording file to appear',
      () async {
    final session =
        await AndroidRecordingGallerySession.capture(directory.path);
    final recording = File('${directory.path}/delayed.webm');
    final writer = () async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await recording.writeAsBytes([1, 2, 3]);
    }();

    final discovery = await session.discoverSettled(
      pollInterval: const Duration(milliseconds: 10),
      stableChecks: 2,
      maxChecks: 12,
    );
    await writer;

    expect(discovery.isSafe, isTrue);
    expect(discovery.files, [recording.path]);
  });

  test('settled discovery refuses a file that never becomes stable', () async {
    final session =
        await AndroidRecordingGallerySession.capture(directory.path);
    final recording = File('${directory.path}/busy.mp4');
    await recording.writeAsBytes([1]);
    var writes = 1;
    final timer = Timer.periodic(const Duration(milliseconds: 6), (_) {
      writes += 1;
      recording.writeAsBytesSync(List<int>.filled(writes, 1));
    });

    final discovery = await session.discoverSettled(
      pollInterval: const Duration(milliseconds: 10),
      stableChecks: 2,
      maxChecks: 4,
    );
    timer.cancel();

    expect(discovery.isSafe, isFalse);
    expect(discovery.files, isEmpty);
  });

  test('publishes files sequentially and summarizes mixed results', () async {
    final files = [
      File('${directory.path}/a.mp4'),
      File('${directory.path}/b.webm'),
      File('${directory.path}/c.mp4'),
    ];
    for (final file in files) {
      await file.writeAsBytes([1]);
    }
    final calls = <String>[];

    final summary = await publishAndroidRecordings(
      files.map((file) => file.path).toList(),
      (path) async {
        calls.add(path);
        if (path.endsWith('b.webm')) {
          return AndroidRecordingPublishResult.failure(
            sourcePath: path,
            errorCode: 'copy_failed',
          );
        }
        if (path.endsWith('c.mp4')) {
          return AndroidRecordingPublishResult.cleanupWarning(
            sourcePath: path,
            galleryUri: 'content://video/c',
          );
        }
        return AndroidRecordingPublishResult.success(
          galleryUri: 'content://video/a',
        );
      },
    );

    expect(calls, files.map((file) => file.path));
    expect(summary.publishedCount, 2);
    expect(summary.failedCount, 1);
    expect(summary.cleanupWarningCount, 1);
    expect(summary.retainedSourcePaths,
        ['${directory.path}/b.webm', '${directory.path}/c.mp4']);
  });

  test('starts recording before requesting a fresh video frame', () async {
    final calls = <String>[];
    final status = Completer<bool>();
    final transition = Completer<bool>();

    final result = startAndroidRecordingWithFreshFrame(
      statusFuture: status.future,
      transitionFuture: transition.future,
      startRecording: () async {
        calls.add('start');
        status.complete(true);
      },
      refreshVideo: () async => calls.add('refresh'),
    );

    await Future<void>.delayed(Duration.zero);
    expect(calls, ['start']);

    transition.complete(true);
    expect(await result, isTrue);
    expect(calls, ['start', 'refresh']);
  });

  test('publisher invokes the Android gallery channel contract', () async {
    const channel = MethodChannel('mChannel');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return <String, dynamic>{
        'status': 'success',
        'galleryUri': 'content://video/1',
      };
    });

    final result = await publishRecordingThroughAndroidChannel(
      '/private/recording.mp4',
      channel: channel,
    );

    expect(calls.single.method, 'publish_recording_to_gallery');
    expect(calls.single.arguments, '/private/recording.mp4');
    expect(result.status, AndroidRecordingPublishStatus.success);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('Android activity exposes the recording gallery method safely', () {
    final source = File(
      'android/app/src/main/kotlin/com/carriez/flutter_hbb/MainActivity.kt',
    ).readAsStringSync();

    expect(source, contains('PUBLISH_RECORDING_TO_GALLERY'));
    expect(source, contains('RecordingMediaStorePublisher'));
    expect(source, contains('Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q'));
    expect(source, contains('Manifest.permission.WRITE_EXTERNAL_STORAGE'));
    expect(source, contains('result.success(publishResult.toMap())'));
  });

  test('formats success feedback without exposing private paths', () {
    final summary = AndroidRecordingPublishSummary(results: [
      AndroidRecordingPublishResult.success(galleryUri: 'content://video/1'),
      AndroidRecordingPublishResult.success(galleryUri: 'content://video/2'),
    ]);

    final message = androidRecordingGalleryFeedback(
      summary,
      language: RecordingGalleryLanguage.simplifiedChinese,
    );

    expect(message, contains('已保存 2 个录屏文件'));
    expect(message, contains('鲲穹远程桌面'));
    expect(message, isNot(contains('/private')));
  });

  test('formats Android recording started feedback', () {
    expect(
      androidRecordingStartedFeedback(
        RecordingGalleryLanguage.simplifiedChinese,
      ),
      '已开始录屏',
    );
    expect(
      androidRecordingStartedFeedback(
        RecordingGalleryLanguage.traditionalChinese,
      ),
      '已開始錄屏',
    );
    expect(
      androidRecordingStartedFeedback(RecordingGalleryLanguage.english),
      'Recording started',
    );
  });

  test('formats partial failure feedback with retained source paths', () {
    final summary = AndroidRecordingPublishSummary(results: [
      AndroidRecordingPublishResult.success(galleryUri: 'content://video/1'),
      AndroidRecordingPublishResult.failure(
        sourcePath: '/private/failed.webm',
        errorCode: 'copy_failed',
      ),
    ]);

    final message = androidRecordingGalleryFeedback(
      summary,
      language: RecordingGalleryLanguage.english,
    );

    expect(message, contains('1 recording file was saved'));
    expect(message, contains('/private/failed.webm'));
  });

  test('recording model keeps gallery export Android-only', () {
    final source = File('lib/models/model.dart').readAsStringSync();

    expect(source, contains('if (isAndroid)'));
    expect(source, contains('AndroidRecordingGallerySession.capture'));
    expect(source, contains('_ensureAndroidGallerySession'));
    expect(source, contains('publishRecordingThroughAndroidChannel'));
    expect(source, contains('androidRecordingStartedFeedback'));
    expect(source, contains("name == 'recording_transition_complete'"));
    expect(source, contains('_waitForRecordingTransition'));
    expect(source, contains('if (isIOS) return;'));
  });
}
