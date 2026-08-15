import 'dart:io';

import 'android_recording_gallery.dart' show RecordingFileIdentity;

class RecordingSnapshot {
  const RecordingSnapshot({
    required this.isAvailable,
    required this.identities,
  });

  final bool isAvailable;
  final Map<String, RecordingFileIdentity> identities;
}

String absoluteDirectoryPath(String directoryPath) =>
    Directory(directoryPath).absolute.path;

Future<RecordingSnapshot> captureRecordingSnapshot(
  String directoryPath, {
  required bool createMissingDirectory,
}) async {
  final directory = Directory(directoryPath);
  if (!await directory.exists()) {
    if (!createMissingDirectory) {
      return const RecordingSnapshot(isAvailable: false, identities: {});
    }
    await directory.create(recursive: true);
  }
  final identities = <String, RecordingFileIdentity>{};
  await for (final entity in directory.list(followLinks: false)) {
    if (entity is! File || !_isSupportedRecording(entity.path)) continue;
    final stat = await entity.stat();
    if (stat.type != FileSystemEntityType.file) continue;
    identities[entity.absolute.path] = RecordingFileIdentity(
      size: stat.size,
      modifiedMilliseconds: stat.modified.millisecondsSinceEpoch,
    );
  }
  return RecordingSnapshot(isAvailable: true, identities: identities);
}

bool _isSupportedRecording(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.mp4') || lower.endsWith('.webm');
}
