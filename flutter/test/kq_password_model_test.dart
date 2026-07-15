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
  });
}
