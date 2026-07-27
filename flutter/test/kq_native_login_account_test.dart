import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native mobile password login uses a real login account seed', () {
    final source = File('lib/common/widgets/login.dart').readAsStringSync();

    expect(source, contains("const _kqNativeLoginAccountKey"));
    expect(source, contains('String _initialKqLoginAccount()'));
    expect(
      source,
      isNot(contains(
          "TextEditingController(text: UserModel.getLocalUserInfo()?['name'] ?? '')")),
    );
  });

  test('native mobile password login normalizes phone-looking accounts', () {
    final source = File('lib/common/widgets/login.dart').readAsStringSync();
    final start =
        source.indexOf('  String _normalizeAccountInput(String value)');
    final end = source.indexOf('  bool _isValidPhone', start);

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final normalizer = source.substring(start, end);
    expect(normalizer, contains(r"RegExp(r'[\s-]+')"));
    expect(normalizer, contains('compact'));
    expect(normalizer, contains('_isValidPhone(compact)'));
  });
}
