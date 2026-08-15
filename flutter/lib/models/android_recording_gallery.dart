import 'package:flutter/services.dart';

import 'android_recording_gallery_fs_stub.dart'
    if (dart.library.io) 'android_recording_gallery_fs_io.dart' as recording_fs;

const String kAndroidRecordingGalleryMethod = 'publish_recording_to_gallery';

Future<bool> startAndroidRecordingWithFreshFrame({
  required Future<bool> statusFuture,
  required Future<bool> transitionFuture,
  required Future<void> Function() startRecording,
  required Future<void> Function() refreshVideo,
}) async {
  await startRecording();
  final results = await Future.wait([statusFuture, transitionFuture]);
  final started = results.every((result) => result);
  if (started) {
    await refreshVideo();
  }
  return started;
}

class RecordingFileIdentity {
  const RecordingFileIdentity({
    required this.size,
    required this.modifiedMilliseconds,
  });

  final int size;
  final int modifiedMilliseconds;

  @override
  bool operator ==(Object other) =>
      other is RecordingFileIdentity &&
      size == other.size &&
      modifiedMilliseconds == other.modifiedMilliseconds;

  @override
  int get hashCode => Object.hash(size, modifiedMilliseconds);
}

class RecordingDiscoveryResult {
  const RecordingDiscoveryResult({
    required this.isSafe,
    required this.files,
    this.identities = const {},
  });

  final bool isSafe;
  final List<String> files;
  final Map<String, RecordingFileIdentity> identities;
}

class AndroidRecordingGallerySession {
  AndroidRecordingGallerySession._(
    this.directoryPath,
    this._baseline,
    this._baselineAvailable,
  );

  final String directoryPath;
  final Map<String, RecordingFileIdentity> _baseline;
  final bool _baselineAvailable;

  static Future<AndroidRecordingGallerySession> capture(
    String directoryPath, {
    bool createMissingDirectory = true,
  }) async {
    final absolutePath = recording_fs.absoluteDirectoryPath(directoryPath);
    try {
      final snapshot = await recording_fs.captureRecordingSnapshot(
        absolutePath,
        createMissingDirectory: createMissingDirectory,
      );
      return AndroidRecordingGallerySession._(
        absolutePath,
        snapshot.identities,
        snapshot.isAvailable,
      );
    } catch (_) {
      return AndroidRecordingGallerySession._(
        absolutePath,
        const {},
        false,
      );
    }
  }

  Future<RecordingDiscoveryResult> discover() async {
    if (!_baselineAvailable) {
      return const RecordingDiscoveryResult(isSafe: false, files: []);
    }
    try {
      final snapshot = await recording_fs.captureRecordingSnapshot(
        directoryPath,
        createMissingDirectory: false,
      );
      if (!snapshot.isAvailable) {
        return const RecordingDiscoveryResult(isSafe: false, files: []);
      }
      final current = snapshot.identities;
      final files = <String>[];
      final identities = <String, RecordingFileIdentity>{};
      for (final entry in current.entries) {
        if (entry.value.size <= 0 || _baseline[entry.key] == entry.value) {
          continue;
        }
        files.add(entry.key);
        identities[entry.key] = entry.value;
      }
      files.sort();
      return RecordingDiscoveryResult(
        isSafe: true,
        files: files,
        identities: identities,
      );
    } catch (_) {
      return const RecordingDiscoveryResult(isSafe: false, files: []);
    }
  }

  Future<RecordingDiscoveryResult> discoverSettled({
    Duration pollInterval = const Duration(milliseconds: 200),
    int stableChecks = 3,
    int maxChecks = 15,
  }) async {
    RecordingDiscoveryResult? previous;
    var stableCount = 0;
    var observedFiles = false;
    for (var check = 0; check < maxChecks; check += 1) {
      final current = await discover();
      if (!current.isSafe) return current;
      if (current.identities.isEmpty) {
        previous = current;
        stableCount = 0;
        await Future<void>.delayed(pollInterval);
        continue;
      }
      observedFiles = true;
      if (previous != null &&
          _sameIdentities(previous.identities, current.identities)) {
        stableCount += 1;
        if (stableCount >= stableChecks) return current;
      } else {
        previous = current;
        stableCount = 0;
      }
      await Future<void>.delayed(pollInterval);
    }
    if (!observedFiles && previous != null) {
      return previous;
    }
    return const RecordingDiscoveryResult(isSafe: false, files: []);
  }

  static bool _sameIdentities(
    Map<String, RecordingFileIdentity> left,
    Map<String, RecordingFileIdentity> right,
  ) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (right[entry.key] != entry.value) return false;
    }
    return true;
  }
}

enum AndroidRecordingPublishStatus { success, cleanupWarning, failure }

class AndroidRecordingPublishResult {
  const AndroidRecordingPublishResult._({
    required this.status,
    this.sourcePath = '',
    this.galleryUri = '',
    this.errorCode = '',
  });

  factory AndroidRecordingPublishResult.success({String galleryUri = ''}) =>
      AndroidRecordingPublishResult._(
        status: AndroidRecordingPublishStatus.success,
        galleryUri: galleryUri,
      );

  factory AndroidRecordingPublishResult.cleanupWarning({
    required String sourcePath,
    String galleryUri = '',
  }) =>
      AndroidRecordingPublishResult._(
        status: AndroidRecordingPublishStatus.cleanupWarning,
        sourcePath: sourcePath,
        galleryUri: galleryUri,
        errorCode: 'source_delete_failed',
      );

  factory AndroidRecordingPublishResult.failure({
    required String sourcePath,
    required String errorCode,
  }) =>
      AndroidRecordingPublishResult._(
        status: AndroidRecordingPublishStatus.failure,
        sourcePath: sourcePath,
        errorCode: errorCode,
      );

  factory AndroidRecordingPublishResult.fromMap(
      Map<dynamic, dynamic> value, String sourcePath) {
    switch (value['status']) {
      case 'success':
        return AndroidRecordingPublishResult.success(
          galleryUri: value['galleryUri'] as String? ?? '',
        );
      case 'cleanup_warning':
        return AndroidRecordingPublishResult.cleanupWarning(
          sourcePath: value['sourcePath'] as String? ?? sourcePath,
          galleryUri: value['galleryUri'] as String? ?? '',
        );
      default:
        return AndroidRecordingPublishResult.failure(
          sourcePath: value['sourcePath'] as String? ?? sourcePath,
          errorCode: value['errorCode'] as String? ?? 'publish_failed',
        );
    }
  }

  final AndroidRecordingPublishStatus status;
  final String sourcePath;
  final String galleryUri;
  final String errorCode;
}

class AndroidRecordingPublishSummary {
  const AndroidRecordingPublishSummary({required this.results});

  final List<AndroidRecordingPublishResult> results;

  int get publishedCount => results
      .where((result) => result.status != AndroidRecordingPublishStatus.failure)
      .length;
  int get failedCount => results
      .where((result) => result.status == AndroidRecordingPublishStatus.failure)
      .length;
  int get cleanupWarningCount => results
      .where((result) =>
          result.status == AndroidRecordingPublishStatus.cleanupWarning)
      .length;
  List<String> get retainedSourcePaths => results
      .where((result) => result.sourcePath.isNotEmpty)
      .map((result) => result.sourcePath)
      .toList(growable: false);
}

enum RecordingGalleryLanguage {
  simplifiedChinese,
  traditionalChinese,
  english,
}

String androidRecordingStartedFeedback(RecordingGalleryLanguage language) {
  switch (language) {
    case RecordingGalleryLanguage.simplifiedChinese:
      return '已开始录屏';
    case RecordingGalleryLanguage.traditionalChinese:
      return '已開始錄屏';
    case RecordingGalleryLanguage.english:
      return 'Recording started';
  }
}

String androidRecordingGalleryFeedback(
  AndroidRecordingPublishSummary summary, {
  required RecordingGalleryLanguage language,
}) {
  final retainedPaths = summary.retainedSourcePaths.join('\n');
  final hasFailures = summary.failedCount > 0;
  final hasCleanupWarnings = summary.cleanupWarningCount > 0;
  switch (language) {
    case RecordingGalleryLanguage.simplifiedChinese:
      if (!hasFailures && !hasCleanupWarnings) {
        return '已保存 ${summary.publishedCount} 个录屏文件到系统相册“鲲穹远程桌面”。';
      }
      if (summary.publishedCount == 0) {
        return '录屏未能保存到系统相册，原文件已保留：\n$retainedPaths';
      }
      return '已保存 ${summary.publishedCount} 个录屏文件到系统相册；部分原文件仍保留：\n$retainedPaths';
    case RecordingGalleryLanguage.traditionalChinese:
      if (!hasFailures && !hasCleanupWarnings) {
        return '已儲存 ${summary.publishedCount} 個錄屏檔案到系統相簿「鯤穹遠程桌面」。';
      }
      if (summary.publishedCount == 0) {
        return '錄屏未能儲存到系統相簿，原檔案已保留：\n$retainedPaths';
      }
      return '已儲存 ${summary.publishedCount} 個錄屏檔案到系統相簿；部分原檔案仍保留：\n$retainedPaths';
    case RecordingGalleryLanguage.english:
      final noun = summary.publishedCount == 1 ? 'file was' : 'files were';
      if (!hasFailures && !hasCleanupWarnings) {
        return '${summary.publishedCount} recording $noun saved to the "Kunqiong Remote Desktop" system album.';
      }
      if (summary.publishedCount == 0) {
        return 'The recording could not be saved to the system gallery. The source file was retained:\n$retainedPaths';
      }
      return '${summary.publishedCount} recording $noun saved to the system gallery. Some source files were retained:\n$retainedPaths';
  }
}

typedef AndroidRecordingPublisher = Future<AndroidRecordingPublishResult>
    Function(String sourcePath);

Future<AndroidRecordingPublishSummary> publishAndroidRecordings(
  List<String> files,
  AndroidRecordingPublisher publisher,
) async {
  final results = <AndroidRecordingPublishResult>[];
  for (final file in files) {
    results.add(await publisher(file));
  }
  return AndroidRecordingPublishSummary(results: results);
}

Future<AndroidRecordingPublishResult> publishRecordingThroughAndroidChannel(
  String sourcePath, {
  MethodChannel channel = const MethodChannel('mChannel'),
}) async {
  try {
    final response = await channel.invokeMethod<Map<dynamic, dynamic>>(
      kAndroidRecordingGalleryMethod,
      sourcePath,
    );
    if (response == null) {
      return AndroidRecordingPublishResult.failure(
        sourcePath: sourcePath,
        errorCode: 'empty_result',
      );
    }
    return AndroidRecordingPublishResult.fromMap(response, sourcePath);
  } on PlatformException catch (error) {
    return AndroidRecordingPublishResult.failure(
      sourcePath: sourcePath,
      errorCode: error.code,
    );
  } catch (_) {
    return AndroidRecordingPublishResult.failure(
      sourcePath: sourcePath,
      errorCode: 'channel_failed',
    );
  }
}
