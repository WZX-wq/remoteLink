import 'android_recording_gallery.dart' show RecordingFileIdentity;

class RecordingSnapshot {
  const RecordingSnapshot({
    required this.isAvailable,
    required this.identities,
  });

  final bool isAvailable;
  final Map<String, RecordingFileIdentity> identities;
}

String absoluteDirectoryPath(String directoryPath) => directoryPath;

Future<RecordingSnapshot> captureRecordingSnapshot(
  String directoryPath, {
  required bool createMissingDirectory,
}) async =>
    const RecordingSnapshot(isAvailable: false, identities: {});
