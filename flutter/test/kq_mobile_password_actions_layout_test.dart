import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _section(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  final endIndex = source.indexOf(end, startIndex + start.length);
  expect(startIndex, greaterThanOrEqualTo(0), reason: 'Missing start: $start');
  expect(endIndex, greaterThan(startIndex), reason: 'Missing end: $end');
  return source.substring(startIndex, endIndex);
}

void main() {
  test('mobile password actions stay inline with the code row', () {
    final page = File('lib/mobile/pages/server_page.dart').readAsStringSync();
    final passwordTile = _section(
      page,
      'class _DevicePasswordTileState',
      'String _mobileKqPasswordKindLabel',
    );

    expect(passwordTile, contains('_MobilePasswordActionGrid('));
    expect(passwordTile, contains('child: Row(children: ['));
    expect(
      passwordTile,
      isNot(contains(
          'const SizedBox(height: 12),\n          _MobilePasswordActionGrid(actions: actions),')),
    );
    expect(
      passwordTile,
      isNot(contains('BoxConstraints.tightFor(width: 34, height: 34)')),
    );

    final actionGrid = _section(
      page,
      'class _MobilePasswordActionGrid',
      'String _mobileKqPasswordKindLabel',
    );
    expect(actionGrid, contains('Row('));
    expect(actionGrid, contains('mainAxisAlignment: MainAxisAlignment.end'));
    expect(actionGrid, contains('const SizedBox(width: 6)'));
    expect(actionGrid, isNot(contains('Wrap(')));
    expect(
      actionGrid,
      contains('BoxConstraints.tightFor(width: 40, height: 40)'),
    );
  });
}
