import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/common/kq_secure_login_credentials.dart';

class _MemoryCredentialStore implements KqSecureLoginCredentialStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

void main() {
  test('remembered password credentials are saved only when enabled', () async {
    final store = _MemoryCredentialStore();
    final credentials = KqSecureLoginCredentials(store: store);

    await credentials.save(
      account: '  13077386092  ',
      password: 'tang123456',
      rememberPassword: true,
    );

    final remembered = await credentials.load();
    expect(remembered.account, '13077386092');
    expect(remembered.password, 'tang123456');
    expect(remembered.rememberPassword, isTrue);
  });

  test('disabling remember password clears the saved password', () async {
    final store = _MemoryCredentialStore();
    final credentials = KqSecureLoginCredentials(store: store);

    await credentials.save(
      account: '13077386092',
      password: 'old-password',
      rememberPassword: true,
    );
    await credentials.save(
      account: '13077386092',
      password: 'new-password',
      rememberPassword: false,
    );

    final remembered = await credentials.load();
    expect(remembered.account, '13077386092');
    expect(remembered.password, isEmpty);
    expect(remembered.rememberPassword, isFalse);
    expect(store.values.values, isNot(contains('new-password')));
  });

  test('empty account or password never creates remembered password state',
      () async {
    final store = _MemoryCredentialStore();
    final credentials = KqSecureLoginCredentials(store: store);

    await credentials.save(
      account: '',
      password: 'secret',
      rememberPassword: true,
    );
    await credentials.save(
      account: '13077386092',
      password: '',
      rememberPassword: true,
    );

    final remembered = await credentials.load();
    expect(remembered.account, '13077386092');
    expect(remembered.password, isEmpty);
    expect(remembered.rememberPassword, isFalse);
  });

  test('account deletion clears remembered login password', () {
    final userModel = File('lib/models/user_model.dart').readAsStringSync();

    expect(userModel, contains('KqSecureLoginCredentials.clearDefault();'));
  });

  test('mobile password login page exposes and persists remember password', () {
    final login = File('lib/common/widgets/login.dart').readAsStringSync();

    expect(login, contains("'Remember password': '记住密码'"));
    expect(login, contains('KqSecureLoginCredentials.loadDefault()'));
    expect(login, contains('rememberPassword: _rememberPassword'));
    expect(login, contains('onRememberPasswordChanged: _setRememberPassword'));
    expect(login, contains('KqSecureLoginCredentials().save('));
  });
}
