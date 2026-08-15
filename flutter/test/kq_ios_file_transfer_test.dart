import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS file manager streams picked documents directly to the remote side',
      () {
    final page =
        File('lib/mobile/pages/file_manager_page.dart').readAsStringSync();

    expect(page, contains("package:file_picker/file_picker.dart"));
    expect(page, contains('_pickFilesAndSend'));
    expect(page, contains('FilePicker.pickFiles'));
    expect(page, contains('withData: false'));
    expect(page, contains('SelectedItems(isLocal: true)'));
    expect(
      page,
      contains('sendFiles(selected, model.remoteController.directoryData())'),
    );
    expect(page, isNot(contains('source.copy(destinationPath)')));
    expect(page, contains('currentFileController.refresh()'));
  });

  test('file transfer exposes conflict and recoverable failure states', () {
    final fileModel = File('lib/models/file_model.dart').readAsStringSync();
    final ioLoop = File('../src/client/io_loop.rs').readAsStringSync();
    final model = File('lib/models/model.dart').readAsStringSync();

    expect(
        fileModel, contains('This file exists, skip or overwrite this file?'));
    expect(fileModel, contains('FileTransferFailureKind.permission'));
    expect(fileModel, contains('FileTransferFailureKind.insufficientStorage'));
    expect(fileModel, contains("normalized.contains('os error 28')"));
    expect(fileModel, contains("normalized.contains('os error 112')"));
    expect(fileModel, contains('FileTransferFailureKind.disconnected'));
    expect(fileModel, contains('failActiveTransfers(String error)'));
    expect(
        model, contains('failActiveTransfers(kFileTransferDisconnectedError)'));
    expect(ioLoop, contains('let mut write_error = None;'));
    expect(ioLoop,
        contains('self.handle_job_status(job_id, file_num, Some(err));'));
  });

  test('the Windows controlled endpoint cleans up failed writes', () {
    final connectionManager =
        File('../src/ui_cm_interface.rs').readAsStringSync();

    expect(connectionManager, contains('let write_error ='));
    expect(connectionManager, contains('fs::remove_job(id, write_jobs)'));
    expect(connectionManager, contains('job.remove_download_file()'));
    expect(connectionManager, contains('fs::new_error(id, err, file_num)'));
  });

  test('iOS document directory is visible to the Files app', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();

    expect(plist, contains('<key>UIFileSharingEnabled</key>'));
    expect(plist, contains('<key>LSSupportsOpeningDocumentsInPlace</key>'));
  });

  test('file transfer entry follows the platform capability policy', () {
    final page =
        File('lib/mobile/pages/connection_page.dart').readAsStringSync();

    expect(page, contains('mobilePlatformCapabilities.canTransferFiles'));
  });
}
