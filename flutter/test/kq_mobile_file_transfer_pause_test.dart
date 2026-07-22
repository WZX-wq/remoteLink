import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'mobile file transfers expose paused jobs with resume and cancel actions',
      () {
    final source =
        File('lib/mobile/pages/file_manager_page.dart').readAsStringSync();

    expect(source, contains('case JobState.paused:'));
    expect(source, contains('title: translate("Paused")'));
    expect(source, contains('tooltip: translate("Resume")'));
    expect(source, contains('model.jobController.resumeJob(activeJob.id)'));
    expect(source, contains('model.jobController.cancelJob(activeJob.id)'));
    expect(source, isNot(contains('// TODO: Handle this case.')));
  });
}
