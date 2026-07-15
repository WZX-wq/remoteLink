import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS file manager imports documents into its local sandbox', () {
    final page =
        File('lib/mobile/pages/file_manager_page.dart').readAsStringSync();

    expect(page, contains("package:file_picker/file_picker.dart"));
    expect(page, contains('_importFilesFromIOS'));
    expect(page, contains('FilePicker.platform.pickFiles'));
    expect(page, contains('source.copy(destinationPath)'));
    expect(page, contains('currentFileController.refresh()'));
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
