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

    test('today verification code is stored independently from one-time code',
        () {
      final source = File('lib/models/server_model.dart').readAsStringSync();
      final start = source.indexOf('Future<void> setDailyPassword');
      final end = source.indexOf('Future<bool> setPermanentPasswordPreview');

      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final body = source.substring(start, end);

      expect(body, contains('key: kOptionKqDailyPassword, value: value'));
      expect(body, isNot(contains('key: kKqTemporaryPasswordControlKey')));
    });

    test('password writes and background refreshes share one operation queue',
        () {
      final source = File('lib/models/server_model.dart').readAsStringSync();
      final refreshStart = source.indexOf('Future<void> updatePasswordModel()');
      final refreshEnd =
          source.indexOf('Future<void> _updatePasswordModelOnce()');

      expect(source, contains('Future<void> _passwordOperationTail'));
      expect(source, contains('Future<T> _queuePasswordOperation<T>'));
      expect(refreshStart, greaterThanOrEqualTo(0));
      expect(refreshEnd, greaterThan(refreshStart));
      final refreshBody = source.substring(refreshStart, refreshEnd);
      expect(refreshBody, contains('_passwordRefreshQueued'));
      expect(refreshBody, contains('_queuePasswordOperation'));

      for (final signature in [
        'Future<void> setOneTimePassword',
        'Future<void> setDailyPassword',
        'Future<bool> setPermanentPasswordPreview',
        'Future<bool> removePermanentPassword',
      ]) {
        final start = source.indexOf(signature);
        expect(start, greaterThanOrEqualTo(0));
        final end = source.indexOf('\n  }', start);
        expect(end, greaterThan(start));
        expect(
            source.substring(start, end), contains('_queuePasswordOperation'));
      }

      final selectedRefreshStart =
          source.indexOf('Future<void> refreshSelectedPassword');
      final selectedRefreshEnd =
          source.indexOf('Future<T> _queuePasswordOperation');
      expect(selectedRefreshStart, greaterThanOrEqualTo(0));
      expect(selectedRefreshEnd, greaterThan(selectedRefreshStart));
      final selectedRefresh =
          source.substring(selectedRefreshStart, selectedRefreshEnd);
      expect(selectedRefresh, contains('await _queuePasswordOperation'));
      expect(selectedRefresh,
          contains('await bind.mainUpdateTemporaryPassword()'));
    });

    test('a length change rereads the new one-time code before updating UI',
        () {
      final source = File('lib/models/server_model.dart').readAsStringSync();
      final updateStart =
          source.indexOf('Future<void> _updatePasswordModelOnce');
      final lengthRead = source.indexOf(
        'final temporaryPasswordLength =',
        updateStart,
      );
      final regenerate = source.indexOf(
        'await bind.mainUpdateTemporaryPassword();',
        lengthRead,
      );
      final reread = source.indexOf(
        'await bind.mainGetTemporaryPassword(),',
        regenerate,
      );
      final uiUpdate = source.indexOf(
        'final oldPwdText = _serverPasswd.text;',
        updateStart,
      );

      expect(updateStart, greaterThanOrEqualTo(0));
      expect(lengthRead, greaterThan(updateStart));
      expect(regenerate, greaterThan(lengthRead));
      expect(reread, greaterThan(regenerate));
      expect(uiUpdate, greaterThan(reread));
    });

    test('the length dialog uses the queued password transaction', () {
      final dialog = File('lib/mobile/widgets/dialog.dart').readAsStringSync();
      expect(
        dialog,
        contains('await gFFI.serverModel.setTemporaryPasswordLength(newValue)'),
      );
      expect(dialog, isNot(contains('bind.mainUpdateTemporaryPassword()')));
    });
  });
}
