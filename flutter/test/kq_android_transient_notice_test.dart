import 'dart:io';

import 'package:flutter_hbb/common/android_transient_notice_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a new Android notice replaces the active notice',
      (tester) async {
    final coordinator = AndroidTransientNoticeCoordinator();
    var firstDismissCount = 0;
    var secondDismissCount = 0;

    coordinator.replace(
      dismiss: () => firstDismissCount += 1,
      timeout: const Duration(seconds: 1),
    );
    coordinator.replace(
      dismiss: () => secondDismissCount += 1,
      timeout: const Duration(seconds: 2),
    );

    expect(firstDismissCount, 1);
    expect(secondDismissCount, 0);

    await tester.pump(const Duration(seconds: 1));
    expect(secondDismissCount, 0,
        reason: 'The cancelled first timer must not dismiss the new notice');

    await tester.pump(const Duration(seconds: 1));
    expect(secondDismissCount, 1);
  });

  test('showToast keeps replacement behavior isolated to Android', () {
    final common = File('lib/common.dart').readAsStringSync();
    final start = common.indexOf('void showToast(String text');
    final end = common.indexOf('// TODO', start);
    final showToastSource = common.substring(start, end);

    expect(showToastSource, contains('if (isAndroid)'));
    expect(
      showToastSource,
      contains('_androidTransientNoticeCoordinator.replace('),
    );
    expect(showToastSource, contains('} else {'));
    expect(showToastSource, contains('Future.delayed(timeout'));
  });
}
