import 'package:flutter_hbb/models/file_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('classifies destination permission and storage failures', () {
    expect(
      classifyFileTransferFailure('Permission denied (os error 13)'),
      FileTransferFailureKind.permission,
    );
    expect(
      classifyFileTransferFailure('Access is denied. (os error 5)'),
      FileTransferFailureKind.permission,
    );
    expect(
      classifyFileTransferFailure('No space left on device (os error 28)'),
      FileTransferFailureKind.insufficientStorage,
    );
    expect(
      classifyFileTransferFailure('The disk is full. (os error 112)'),
      FileTransferFailureKind.insufficientStorage,
    );
    expect(
      classifyFileTransferFailure('Disk quota exceeded'),
      FileTransferFailureKind.insufficientStorage,
    );
    expect(
      classifyFileTransferFailure('Read-only file system (os error 30)'),
      FileTransferFailureKind.permission,
    );
  });

  test('classifies connection loss without hiding the original transfer state',
      () {
    expect(
      classifyFileTransferFailure(kFileTransferDisconnectedError),
      FileTransferFailureKind.disconnected,
    );
    expect(
      classifyFileTransferFailure('Connection reset by peer'),
      FileTransferFailureKind.disconnected,
    );
    expect(
      classifyFileTransferFailure('skipped'),
      FileTransferFailureKind.none,
    );
  });
}
