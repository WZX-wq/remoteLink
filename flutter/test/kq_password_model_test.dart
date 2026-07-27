import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/models/server_model.dart';

void main() {
  group('KQ password display', () {
    test('keeps existing one-time code visible when service stop flag is stale',
        () {
      expect(
        kqPasswordTextForDisplay(
          isVisible: true,
          rawText: '123456',
        ),
        '123456',
      );
    });

    test('one-time and today codes can be randomized from the edit dialog', () {
      expect(
          kqPasswordKindSupportsRandomGenerate(KqPasswordKind.oneTime), true);
      expect(kqPasswordKindSupportsRandomGenerate(KqPasswordKind.daily), true);
    });

    test('masks verification code only for UI display', () {
      expect(
        kqPasswordTextForUi(
          rawText: '123456',
          reveal: false,
        ),
        '••••••',
      );
      expect(
        kqPasswordTextForUi(
          rawText: '123456',
          reveal: true,
        ),
        '123456',
      );
      expect(
        kqPasswordTextForUi(
          rawText: '--',
          reveal: false,
        ),
        '--',
      );
    });

    test('normalizes verification codes to the mobile six-character contract',
        () {
      expect(kqNormalizeVerificationCode(' 00DANEYF123 '), '00dane');
      expect(kqNormalizeVerificationCode(' Q75D6R '), 'q75d6r');
      expect(kqNormalizeVerificationCode(''), '');
    });

    test('today verification code also updates the active temporary password',
        () {
      final source = File('lib/models/server_model.dart').readAsStringSync();
      final start = source.indexOf('Future<void> setDailyPassword');
      final end = source.indexOf('Future<bool> setPermanentPasswordPreview');

      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final body = source.substring(start, end);

      expect(body, contains('key: kOptionKqDailyPassword, value: value'));
      expect(body, contains('key: kKqTemporaryPasswordControlKey, value: value'));
    });
  });
}
