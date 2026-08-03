import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const kKqNativeLoginAccountKey = 'kq-native-login-account';
const _kqNativeLoginPasswordKey = 'kq-native-login-password';
const _kqNativeLoginRememberPasswordKey = 'kq-native-login-remember-password';

class KqRememberedLoginCredentials {
  const KqRememberedLoginCredentials({
    required this.account,
    required this.password,
    required this.rememberPassword,
  });

  final String account;
  final String password;
  final bool rememberPassword;
}

abstract class KqSecureLoginCredentialStore {
  Future<String?> read(String key);

  Future<void> write({required String key, required String value});

  Future<void> delete(String key);
}

class _FlutterSecureLoginCredentialStore
    implements KqSecureLoginCredentialStore {
  const _FlutterSecureLoginCredentialStore();

  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class KqSecureLoginCredentials {
  KqSecureLoginCredentials({
    KqSecureLoginCredentialStore store =
        const _FlutterSecureLoginCredentialStore(),
  }) : _store = store;

  final KqSecureLoginCredentialStore _store;

  static Future<KqRememberedLoginCredentials> loadDefault() =>
      KqSecureLoginCredentials().load();

  static Future<void> clearDefault() => KqSecureLoginCredentials().clear();

  Future<KqRememberedLoginCredentials> load() async {
    final account = (await _store.read(kKqNativeLoginAccountKey) ?? '').trim();
    final remember =
        (await _store.read(_kqNativeLoginRememberPasswordKey) ?? '') == 'Y';
    final password =
        remember ? (await _store.read(_kqNativeLoginPasswordKey) ?? '') : '';
    return KqRememberedLoginCredentials(
      account: account,
      password: password,
      rememberPassword: remember && account.isNotEmpty && password.isNotEmpty,
    );
  }

  Future<void> save({
    required String account,
    required String password,
    required bool rememberPassword,
  }) async {
    final safeAccount = account.trim();
    if (safeAccount.isNotEmpty) {
      await _store.write(key: kKqNativeLoginAccountKey, value: safeAccount);
    } else {
      await _store.delete(kKqNativeLoginAccountKey);
    }

    if (!rememberPassword || safeAccount.isEmpty || password.isEmpty) {
      await _store.delete(_kqNativeLoginPasswordKey);
      await _store.delete(_kqNativeLoginRememberPasswordKey);
      return;
    }

    await _store.write(key: _kqNativeLoginPasswordKey, value: password);
    await _store.write(key: _kqNativeLoginRememberPasswordKey, value: 'Y');
  }

  Future<void> clear() async {
    await _store.delete(kKqNativeLoginAccountKey);
    await _store.delete(_kqNativeLoginPasswordKey);
    await _store.delete(_kqNativeLoginRememberPasswordKey);
  }
}
